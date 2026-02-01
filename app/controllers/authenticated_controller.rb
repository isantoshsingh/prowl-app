# frozen_string_literal: true

class AuthenticatedController < ApplicationController
  include ShopifyApp::EnsureHasSession
  include ShopifyApp::EnsureBilling

  # Skip billing check for exempt shops BEFORE charge is created
  skip_before_action :check_billing, if: :billing_exempt?

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
  # Must load shop directly because @shop may not be set yet when check_billing runs
  def billing_exempt?
    return false unless current_shopify_session

    shop = Shop.find_by(shopify_domain: current_shopify_session.shop)
    shop&.billing_exempt? || false
  end
end
