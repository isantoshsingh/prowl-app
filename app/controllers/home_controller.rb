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
      redirect_to ShopifyApp.configuration.login_url
      return
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
                        .order(severity: :asc, last_detected_at: :desc)
                        .limit(10)

    @open_issues_count = Issue.joins(:product_page)
                              .where(product_pages: { shop_id: @shop.id })
                              .where(status: "open")
                              .count

    # Recent scans
    @recent_scans = Scan.joins(:product_page)
                        .where(product_pages: { shop_id: @shop.id })
                        .order(created_at: :desc)
                        .limit(5)

    # 7-day scan history for trend chart
    @scan_history = Scan.joins(:product_page)
                        .where(product_pages: { shop_id: @shop.id })
                        .where("scans.created_at >= ?", 7.days.ago)
                        .group("DATE(scans.created_at)")
                        .count

    @host = params[:host]
  end
end
