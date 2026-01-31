# frozen_string_literal: true

# DashboardController provides JSON API endpoints for the dashboard.
# This supports any AJAX requests from the Polaris UI.
#
class DashboardController < AuthenticatedController
  include ShopifyApp::EmbeddedApp

  def stats
    shop = current_shop
    return render json: { error: "Shop not found" }, status: :not_found unless shop

    product_pages = shop.product_pages.monitoring_enabled

    render json: {
      total_pages: product_pages.count,
      healthy_pages: product_pages.healthy.count,
      warning_pages: product_pages.warning.count,
      critical_pages: product_pages.critical.count,
      open_issues_count: Issue.joins(:product_page)
                              .where(product_pages: { shop_id: shop.id })
                              .where(status: "open")
                              .count,
      last_scan_at: product_pages.maximum(:last_scanned_at)&.iso8601,
      trial_days_remaining: shop.shop_setting&.trial_days_remaining || 0,
      billing_status: shop.shop_setting&.billing_status || "unknown"
    }
  end

  private

  def current_shop
    @current_shop ||= Shop.find_by(shopify_domain: current_shopify_domain)
  end
end
