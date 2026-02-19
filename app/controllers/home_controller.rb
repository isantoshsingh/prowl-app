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
  include ShopifyApp::EnsureBilling

  def index
    # Use @shop from set_shop callback (already loaded in AuthenticatedController)
    # Only reload if not present (defensive check)
    @shop ||= Shop.find_by(shopify_domain: current_shopify_domain)

    if @shop.nil?
      Rails.logger.error("[HomeController] Shop not found for domain: #{current_shopify_domain}")
      redirect_to ShopifyApp.configuration.login_url
      return
    end

    @host = params[:host]

    # Onboarding state
    @show_onboarding = @shop.show_onboarding?

    if @show_onboarding
      @onboarding_steps = @shop.onboarding_steps
      @onboarding_progress = @shop.onboarding_progress
    end

    load_dashboard_data
  end

  def dismiss_onboarding
    @shop ||= Shop.find_by(shopify_domain: current_shopify_domain)

    if @shop
      @shop.dismiss_onboarding!
    end

    redirect_to root_path(host: params[:host])
  end

  private

  def load_dashboard_data
    # Dashboard metrics - use single GROUP BY query for all status counts
    status_counts = @shop.product_pages
                         .monitoring_enabled
                         .group(:status)
                         .count

    @total_pages = status_counts.values.sum
    @healthy_pages = status_counts["healthy"] || 0
    @warning_pages = status_counts["warning"] || 0
    @critical_pages = status_counts["critical"] || 0

    # Open issues - eager load product_page to prevent N+1
    @open_issues = Issue.includes(:product_page)
                        .joins(:product_page)
                        .where(product_pages: { shop_id: @shop.id })
                        .where(status: "open")
                        .order(severity: :asc, last_detected_at: :desc)
                        .limit(10)

    # Use size on loaded collection instead of separate count query
    @open_issues_count = Issue.joins(:product_page)
                              .where(product_pages: { shop_id: @shop.id })
                              .where(status: "open")
                              .count

    # Recent scans - eager load product_page to prevent N+1
    @recent_scans = Scan.includes(:product_page)
                        .joins(:product_page)
                        .where(product_pages: { shop_id: @shop.id })
                        .order(created_at: :desc)
                        .limit(5)

    # 7-day scan history for trend chart
    @scan_history = Scan.joins(:product_page)
                        .where(product_pages: { shop_id: @shop.id })
                        .where("scans.created_at >= ?", 7.days.ago)
                        .group("DATE(scans.created_at)")
                        .count
  end

  # Override has_active_payment? to implement cache-first logic + sync
  def has_active_payment?(session)
    # Use @shop from set_shop callback if available, otherwise load it
    # This prevents duplicate Shop queries across the request lifecycle
    @shop ||= Shop.find_by(shopify_domain: session.shop)

    # 1. Billing Exempt?
    return true if billing_exempt?

    # 2. Local Cache Active?
    if @shop&.subscription_active?
      Rails.logger.info("[HomeController] Cache hit: Active subscription for #{session.shop}")
      return true
    end

    # 3. Fallback to Shopify API (gem implementation)
    # This query runs against Shopify. If it finds an active subscription:
    api_has_active = super(session)

    if api_has_active
      # 4. Sync local state if API confirms active
      Rails.logger.info("[HomeController] API active, syncing local state for #{session.shop}")
      SubscriptionSyncService.new(@shop).sync
      return true
    end

    # 5. Not active on API -> Gem will redirect
    false
  end
end
