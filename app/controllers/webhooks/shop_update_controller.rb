# frozen_string_literal: true

# ShopUpdateController handles the shop/update webhook from Shopify.
# This webhook is triggered when shop details change (plan, contact info, settings, etc.)
#
class Webhooks::ShopUpdateController < ApplicationController
  include ShopifyApp::WebhookVerification

  def create
    shop_domain = shop_domain_from_headers

    shop = Shop.find_by(shopify_domain: shop_domain)

    unless shop
      Rails.logger.error("[Webhooks::ShopUpdate] Shop not found: #{shop_domain}")
      head :ok
      return
    end

    # Update shop metadata from webhook
    shop.update_from_webhook!(params)

    Rails.logger.info("[Webhooks::ShopUpdate] Shop metadata updated for #{shop_domain}")
    head :ok
  rescue StandardError => e
    Rails.logger.error("[Webhooks::ShopUpdate] Error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    head :internal_server_error
  end

  private

  def shop_domain_from_headers
    request.headers['HTTP_X_SHOPIFY_SHOP_DOMAIN'] || params[:shop_domain]
  end
end
