# frozen_string_literal: true

# BillingController displays billing/pricing information for the shop.
# Shows subscription status, trial information, or exemption status.
#
class BillingController < AuthenticatedController
  include ShopifyApp::EmbeddedApp

  before_action :set_shop

  def index
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    @subscription = @shop.latest_subscription
    @host = params[:host]
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    unless @shop
      redirect_to ShopifyApp.configuration.login_url
    end
  end
end
