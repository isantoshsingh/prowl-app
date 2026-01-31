# frozen_string_literal: true

# HomeController serves the main dashboard (App Home Page)
# per Shopify App Home Page UX guidelines.
#
# The dashboard shows:
#   - PDP health overview
#   - Recent issues
#   - 7-day trend
#   - Quick actions
#
class HomeController < AuthenticatedController
  include ShopifyApp::EmbeddedApp

  def index
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)

    if @shop.nil?
      Rails.logger.error("[HomeController] Shop not found for domain: #{current_shopify_domain}")
      respond_to do |format|
        format.html { redirect_to ShopifyApp.configuration.login_url }
        format.json { render json: { error: "Shop not found" }, status: :not_found }
      end
      return
    end

    # Check billing status
    unless @shop.billing_active?
      @billing_required = true
      @trial_expired = @shop.shop_setting&.billing_status == "expired"
    end

    # Dashboard metrics
    @product_pages = @shop.product_pages.monitoring_enabled.order(last_scanned_at: :desc)
    @total_pages = @product_pages.count
    @healthy_pages = @product_pages.healthy.count
    @warning_pages = @product_pages.warning.count
    @critical_pages = @product_pages.critical.count

    # Open issues
    @open_issues = Issue.joins(:product_page)
                        .where(product_pages: { shop_id: @shop.id })
                        .where(status: "open")
                        .includes(:product_page)
                        .order(severity: :asc, last_detected_at: :desc)
                        .limit(10)

    @open_issues_count = Issue.joins(:product_page)
                              .where(product_pages: { shop_id: @shop.id })
                              .where(status: "open")
                              .count

    # Recent scans
    @recent_scans = Scan.joins(:product_page)
                        .where(product_pages: { shop_id: @shop.id })
                        .includes(:product_page)
                        .order(created_at: :desc)
                        .limit(5)

    # 7-day scan history for trend chart
    @scan_history = Scan.joins(:product_page)
                        .where(product_pages: { shop_id: @shop.id })
                        .where("scans.created_at >= ?", 7.days.ago)
                        .group("DATE(scans.created_at)")
                        .count

    @host = params[:host]

    respond_to do |format|
      format.html { render layout: "react_app" }
      format.json do
        render json: {
          total_pages: @total_pages,
          healthy_pages: @healthy_pages,
          warning_pages: @warning_pages,
          critical_pages: @critical_pages,
          open_issues_count: @open_issues_count,
          billing_required: @billing_required,
          trial_expired: @trial_expired,
          billing_status: @shop.shop_setting&.billing_status,
          trial_days_remaining: @shop.shop_setting&.trial_days_remaining,
          open_issues: @open_issues.map { |i| issue_json(i) },
          recent_scans: @recent_scans.map { |s| scan_json(s) }
        }
      end
    end
  end

  private

  def issue_json(issue)
    {
      id: issue.id,
      title: issue.title,
      issue_type: issue.issue_type,
      severity: issue.severity,
      status: issue.status,
      occurrence_count: issue.occurrence_count,
      last_detected_at: issue.last_detected_at&.iso8601,
      product_page: issue.product_page ? {
        id: issue.product_page.id,
        title: issue.product_page.title
      } : nil
    }
  end

  def scan_json(scan)
    {
      id: scan.id,
      status: scan.status,
      page_load_time_ms: scan.page_load_time_ms,
      completed_at: scan.completed_at&.iso8601,
      created_at: scan.created_at&.iso8601,
      issues_count: scan.issues.count,
      product_page: scan.product_page ? {
        id: scan.product_page.id,
        title: scan.product_page.title
      } : nil
    }
  end
end
