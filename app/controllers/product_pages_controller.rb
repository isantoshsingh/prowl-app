# frozen_string_literal: true

# ProductPagesController manages the product pages being monitored.
# Merchants can:
#   - View monitored pages
#   - Add new pages (up to 5) using Shopify Resource Picker
#   - Remove pages from monitoring
#   - Trigger manual rescans
#
class ProductPagesController < AuthenticatedController
  include ShopifyApp::EmbeddedApp

  before_action :set_shop
  before_action :set_product_page, only: [:show, :destroy, :rescan]
  
  # For embedded apps using token auth, CSRF is handled differently
  protect_from_forgery with: :null_session, only: [:create]

  def index
    @product_pages = @shop.product_pages.order(created_at: :desc)
    @can_add_more = @shop.can_add_monitored_page?
    @host = params[:host]

    respond_to do |format|
      format.html { render layout: "react_app" }
      format.json do
        render json: {
          product_pages: @product_pages.map { |pp| product_page_json(pp) },
          can_add_more: @can_add_more,
          max_pages: @shop.shop_setting&.max_monitored_pages || 5
        }
      end
    end
  end

  def show
    @recent_scans = @product_page.scans.recent.limit(10)
    @open_issues = @product_page.open_issues.order(severity: :asc, last_detected_at: :desc)
    @host = params[:host]

    respond_to do |format|
      format.html { render layout: "react_app" }
      format.json do
        render json: product_page_json(@product_page, include_details: true)
      end
    end
  end

  def new
    unless @shop.can_add_monitored_page?
      flash[:error] = "You've reached the maximum of #{@shop.shop_setting.max_monitored_pages} monitored pages."
      redirect_to product_pages_path(host: params[:host])
      return
    end

    # Data for the Resource Picker
    max_pages = @shop.shop_setting&.max_monitored_pages || 5
    current_count = @shop.monitored_pages_count
    @remaining_slots = max_pages - current_count

    # Already monitored product IDs (numeric and GID format for filtering)
    @monitored_product_ids = @shop.product_pages.pluck(:shopify_product_id)
    @monitored_product_gids = @monitored_product_ids.map { |id| "gid://shopify/Product/#{id}" }

    @host = params[:host]

    respond_to do |format|
      format.html { render layout: "react_app" }
      format.json do
        render json: {
          remaining_slots: @remaining_slots,
          max_pages: max_pages,
          current_count: current_count,
          monitored_product_ids: @monitored_product_ids
        }
      end
    end
  end

  def create
    Rails.logger.info("[ProductPagesController#create] Received params: #{params.to_unsafe_h.except(:authenticity_token)}")
    
    # Handle multiple products from Resource Picker
    products_params = params[:products]

    if products_params.blank?
      Rails.logger.info("[ProductPagesController#create] No products param, checking for single product")
      # Fallback: single product (legacy support)
      create_single_product
      return
    end

    Rails.logger.info("[ProductPagesController#create] Processing #{products_params.keys.count} products")

    # Multiple products from Resource Picker
    created_count = 0
    skipped_count = 0
    errors = []
    created_products = []

    products_params.each do |_index, product_data|
      Rails.logger.info("[ProductPagesController#create] Processing product: #{product_data}")
      
      unless @shop.can_add_monitored_page?
        Rails.logger.warn("[ProductPagesController#create] Max pages reached, stopping")
        break
      end

      product_id = product_data[:shopify_product_id].to_i
      handle = product_data[:handle]
      title = product_data[:title]

      # Skip if already monitored
      if @shop.product_pages.exists?(shopify_product_id: product_id)
        Rails.logger.info("[ProductPagesController#create] Product #{product_id} already monitored, skipping")
        skipped_count += 1
        next
      end

      product_page = @shop.product_pages.build(
        shopify_product_id: product_id,
        handle: handle,
        title: title,
        url: "/products/#{handle}",
        monitoring_enabled: true,
        status: "pending"
      )

      if product_page.save
        Rails.logger.info("[ProductPagesController#create] Created product page #{product_page.id} for #{title}")
        # Queue initial scan
        ScanPdpJob.perform_later(product_page.id)
        created_count += 1
        created_products << { id: product_page.id, title: title }
      else
        Rails.logger.error("[ProductPagesController#create] Failed to save: #{product_page.errors.full_messages}")
        errors << "#{title}: #{product_page.errors.full_messages.join(', ')}"
      end
    end

    # Build response
    respond_to do |format|
      format.html do
        if created_count > 0
          flash[:success] = "Added #{created_count} product#{created_count > 1 ? 's' : ''} to monitoring. First scans starting now."
        end

        if skipped_count > 0
          flash[:notice] = "#{skipped_count} product#{skipped_count > 1 ? 's were' : ' was'} already being monitored."
        end

        if errors.any?
          flash[:error] = "Some products could not be added: #{errors.join('; ')}"
        end

        redirect_to product_pages_path(host: params[:host])
      end

      format.json do
        render json: {
          success: true,
          created_count: created_count,
          skipped_count: skipped_count,
          errors: errors,
          created_products: created_products
        }, status: created_count > 0 ? :created : :ok
      end

      format.any do
        # Default to HTML redirect for form submissions
        if created_count > 0
          flash[:success] = "Added #{created_count} product#{created_count > 1 ? 's' : ''} to monitoring. First scans starting now."
        end

        if skipped_count > 0
          flash[:notice] = "#{skipped_count} product#{skipped_count > 1 ? 's were' : ' was'} already being monitored."
        end

        if errors.any?
          flash[:error] = "Some products could not be added: #{errors.join('; ')}"
        end

        redirect_to product_pages_path(host: params[:host])
      end
    end
  end

  def destroy
    title = @product_page.title
    @product_page.destroy

    respond_to do |format|
      format.html do
        flash[:success] = "#{title} removed from monitoring."
        redirect_to product_pages_path(host: params[:host])
      end
      format.json { render json: { success: true, message: "#{title} removed from monitoring" } }
    end
  end

  def rescan
    if @product_page.scans.running.any?
      respond_to do |format|
        format.html do
          flash[:notice] = "A scan is already in progress for this page."
          redirect_to product_page_path(@product_page, host: params[:host])
        end
        format.json { render json: { success: false, message: "A scan is already in progress" }, status: :unprocessable_entity }
      end
    else
      ScanPdpJob.perform_later(@product_page.id)
      respond_to do |format|
        format.html do
          flash[:success] = "Manual scan started for #{@product_page.title}."
          redirect_to product_page_path(@product_page, host: params[:host])
        end
        format.json { render json: { success: true, message: "Scan queued successfully" } }
      end
    end
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    unless @shop
      redirect_to ShopifyApp.configuration.login_url
    end
  end

  def set_product_page
    @product_page = @shop.product_pages.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Product page not found."
    redirect_to product_pages_path(host: params[:host])
  end

  # Legacy support for single product creation
  def create_single_product
    unless @shop.can_add_monitored_page?
      flash[:error] = "Maximum monitored pages reached"
      redirect_to product_pages_path(host: params[:host])
      return
    end

    product_id = params[:shopify_product_id].to_i
    handle = params[:handle]
    title = params[:title]

    Rails.logger.info("[ProductPagesController#create_single_product] Creating single product: #{title} (#{product_id})")

    product_page = @shop.product_pages.build(
      shopify_product_id: product_id,
      handle: handle,
      title: title,
      url: "/products/#{handle}",
      monitoring_enabled: true,
      status: "pending"
    )

    if product_page.save
      Rails.logger.info("[ProductPagesController#create_single_product] Created product page #{product_page.id}")
      ScanPdpJob.perform_later(product_page.id)
      flash[:success] = "#{title} added to monitoring. First scan starting now."
      redirect_to product_pages_path(host: params[:host])
    else
      Rails.logger.error("[ProductPagesController#create_single_product] Failed: #{product_page.errors.full_messages}")
      flash[:error] = product_page.errors.full_messages.join(", ")
      redirect_to new_product_page_path(host: params[:host])
    end
  end

  def product_page_json(product_page, include_details: false)
    data = {
      id: product_page.id,
      shopify_product_id: product_page.shopify_product_id,
      title: product_page.title,
      handle: product_page.handle,
      url: product_page.url,
      status: product_page.status,
      monitoring_enabled: product_page.monitoring_enabled,
      last_scanned_at: product_page.last_scanned_at&.iso8601,
      created_at: product_page.created_at&.iso8601,
      open_issues_count: product_page.open_issues.count
    }

    if include_details
      data[:issues] = product_page.issues.order(status: :asc, severity: :asc).map do |issue|
        {
          id: issue.id,
          title: issue.title,
          issue_type: issue.issue_type,
          severity: issue.severity,
          status: issue.status,
          occurrence_count: issue.occurrence_count,
          last_detected_at: issue.last_detected_at&.iso8601
        }
      end

      data[:recent_scans] = product_page.scans.recent.limit(10).map do |scan|
        {
          id: scan.id,
          status: scan.status,
          page_load_time_ms: scan.page_load_time_ms,
          completed_at: scan.completed_at&.iso8601,
          created_at: scan.created_at&.iso8601,
          issues_count: scan.issues.count
        }
      end
    end

    data
  end
end
