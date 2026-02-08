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

  # Note: set_shop is inherited from AuthenticatedController
  before_action :set_product_page, only: [:show, :destroy, :rescan]
  
  # For embedded apps using token auth, CSRF is handled differently
  protect_from_forgery with: :null_session, only: [:create]

  def index
    # Eager load shop_setting to avoid N+1
    @shop_setting = @shop.shop_setting
    max_pages = @shop_setting&.max_monitored_pages || 5

    # Load product pages once
    @product_pages = @shop.product_pages.order(created_at: :desc).to_a
    @product_pages_count = @product_pages.size

    @can_add_more = @shop.monitored_pages_count < max_pages

    # Preload high severity issue counts in a single query to avoid N+1
    product_page_ids = @product_pages.map(&:id)
    @high_severity_counts = Issue.where(product_page_id: product_page_ids, status: 'open', severity: 'high')
                                  .group(:product_page_id)
                                  .count

    @host = params[:host]
  end

  def show
    @recent_scans = @product_page.scans.recent.limit(10)
    @open_issues = @product_page.open_issues.order(severity: :asc, last_detected_at: :desc)
    @host = params[:host]
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
    @product_page.destroy
    flash[:success] = "#{@product_page.title} removed from monitoring."
    redirect_to product_pages_path(host: params[:host])
  end

  def rescan
    if @product_page.scans.running.any?
      flash[:notice] = "A scan is already in progress for this page."
    else
      ScanPdpJob.perform_later(@product_page.id)
      flash[:success] = "Manual scan started for #{@product_page.title}."
    end

    redirect_to product_page_path(@product_page, host: params[:host])
  end

  private

  # set_shop is inherited from AuthenticatedController

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
end
