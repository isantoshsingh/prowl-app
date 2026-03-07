# frozen_string_literal: true

class AuthenticatedController < ApplicationController
  include ShopifyApp::EmbeddedApp
  include ShopifyApp::EnsureHasSession

  before_action :set_shop
  before_action :set_host

  # Override has_active_payment? to implement cache-first logic + sync.
  # Handles the charge_id callback from Shopify after the merchant approves billing.
  def has_active_payment?(session)
    @shop ||= Shop.find_by(shopify_domain: session.shop)

    # 1. Billing Exempt?
    return true if billing_exempt?

    # 2. If charge_id is present, merchant just approved — sync immediately
    if params[:charge_id].present? && @shop
      Rails.logger.info("[Billing] charge_id=#{params[:charge_id]} received, syncing subscription for #{session.shop}")
      synced = SubscriptionSyncService.new(@shop).sync
      if synced
        Rails.logger.info("[Billing] Subscription synced successfully after charge approval")
        return true
      else
        Rails.logger.warn("[Billing] Subscription sync failed after charge approval, falling back to API check")
      end
    end

    # 3. Local Cache Active?
    if @shop&.subscription_active?
      Rails.logger.info("[Billing] Cache hit: Active subscription for #{session.shop}")
      return true
    end

    # 4. Fallback to Shopify API (gem implementation)
    api_has_active = super(session)

    if api_has_active
      # 5. Sync local state if API confirms active
      Rails.logger.info("[Billing] API active, syncing local state for #{session.shop}")
      SubscriptionSyncService.new(@shop).sync
      return true
    end

    # 6. Not active → Gem will redirect to billing approval
    false
  end

  private

  # Set @shop for use across controllers
  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_session&.shop) if current_shopify_session
  end

  # Set @host for use in views (needed for navigation links)
  def set_host
    @host = params[:host]
  end

  # Check if current shop is exempt from billing
  # Uses @shop from set_shop callback, with fallback to direct load if needed
  def billing_exempt?
    return false unless current_shopify_session

    # Use @shop if already loaded, otherwise load it (and cache for later use)
    @shop ||= Shop.find_by(shopify_domain: current_shopify_session.shop)
    @shop&.billing_exempt? || false
  end
end
