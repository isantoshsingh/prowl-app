# frozen_string_literal: true

# ScansController displays scan history and details.
#
class ScansController < AuthenticatedController
  include ShopifyApp::EmbeddedApp

  before_action :set_shop
  before_action :set_scan, only: [:show]

  def index
    page = (params[:page] || 1).to_i
    per_page = 50

    @scans = Scan.joins(:product_page)
                 .where(product_pages: { shop_id: @shop.id })
                 .includes(:product_page, :issues)
                 .order(created_at: :desc)

    total_count = @scans.count
    @scans = @scans.offset((page - 1) * per_page).limit(per_page)

    @host = params[:host]

    respond_to do |format|
      format.html { render layout: "react_app" }
      format.json do
        render json: {
          scans: @scans.map { |s| scan_json(s) },
          page: page,
          per_page: per_page,
          total_count: total_count,
          has_more: (page * per_page) < total_count
        }
      end
    end
  end

  def show
    @product_page = @scan.product_page
    @issues = @scan.issues.order(severity: :asc)
    @host = params[:host]

    respond_to do |format|
      format.html { render layout: "react_app" }
      format.json { render json: scan_json(@scan, include_details: true) }
    end
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    unless @shop
      redirect_to ShopifyApp.configuration.login_url
    end
  end

  def set_scan
    @scan = Scan.joins(:product_page)
                .where(product_pages: { shop_id: @shop.id })
                .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html do
        flash[:error] = "Scan not found."
        redirect_to scans_path(host: params[:host])
      end
      format.json { render json: { error: "Scan not found" }, status: :not_found }
    end
  end

  def scan_json(scan, include_details: false)
    data = {
      id: scan.id,
      status: scan.status,
      page_load_time_ms: scan.page_load_time_ms,
      error_message: scan.error_message,
      started_at: scan.started_at&.iso8601,
      completed_at: scan.completed_at&.iso8601,
      created_at: scan.created_at&.iso8601,
      issues_count: scan.issues.count,
      product_page: scan.product_page ? {
        id: scan.product_page.id,
        title: scan.product_page.title,
        handle: scan.product_page.handle
      } : nil
    }

    if include_details
      data[:js_errors] = scan.js_errors || []
      data[:network_errors] = scan.network_errors || []
      data[:console_logs] = scan.console_logs || []
      data[:screenshot_url] = scan.screenshot_url
      data[:issues] = scan.issues.order(severity: :asc).map do |issue|
        {
          id: issue.id,
          title: issue.title,
          issue_type: issue.issue_type,
          severity: issue.severity,
          status: issue.status
        }
      end
    end

    data
  end
end
