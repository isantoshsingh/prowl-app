# frozen_string_literal: true

class AuthenticatedController < ApplicationController
  include ShopifyApp::EmbeddedApp
  include ShopifyApp::EnsureHasSession

  before_action :set_shop
  before_action :set_host
  before_action :sync_subscription_on_charge_callback

  private

  # Set @shop for use across controllers
  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_session&.shop) if current_shopify_session
  end

  # Set @host for use in views (needed for navigation links)
  def set_host
    @host = params[:host]
  end

  # When Shopify redirects back after billing approval with a charge_id,
  # sync the subscription immediately so the shop gets Monitor features.
  def sync_subscription_on_charge_callback
    return unless params[:charge_id].present? && @shop

    Rails.logger.info("[Billing] charge_id=#{params[:charge_id]} received, syncing subscription for #{@shop.shopify_domain}")
    SubscriptionSyncService.new(@shop).sync
  end

  # Returns the current plan name for the shop
  def current_plan_name
    BillingPlanService.plan_name_for(@shop)
  end
  helper_method :current_plan_name
end
