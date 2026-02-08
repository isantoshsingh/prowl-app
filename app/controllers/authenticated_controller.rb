# frozen_string_literal: true

class AuthenticatedController < ApplicationController
  include ShopifyApp::EnsureHasSession
  before_action :set_shop
  before_action :set_host

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
