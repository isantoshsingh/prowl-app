# frozen_string_literal: true

#  AppUninstalledController handles the app/uninstalled webhook from Shopify.
# This webhook is triggered when a merchant uninstalls the app.
#
class Webhooks::AppUninstalledController < ApplicationController
  include ShopifyApp::WebhookVerification

  def create
    shop_domain = shop_domain_from_headers

    shop = Shop.find_by(shopify_domain: shop_domain)

    unless shop
      Rails.logger.error("[Webhooks::AppUninstalled] Shop not found: #{shop_domain}")
      head :ok
      return
    end

    # Update shop metadata from webhook
    shop.update_from_webhook!(params)
    shop.update!(
      installed: false, 
      uninstalled_at: Time.current,
      subscription_status: 'cancelled'
    )

    # Cancel the current active subscription
    if shop.active_subscription.present?
      shop.active_subscription.cancel!
      Rails.logger.info("[Webhooks::AppUninstalled] Cancelled subscription for #{shop_domain}")
    elsif shop.latest_subscription.present? && shop.latest_subscription.status == 'pending'
      # If there's a pending subscription (trial), mark it as cancelled
      shop.latest_subscription.cancel!
      Rails.logger.info("[Webhooks::AppUninstalled] Cancelled pending subscription for #{shop_domain}")
    end

    Rails.logger.info("[Webhooks::AppUninstalled] App uninstalled for #{shop_domain}")
    head :ok
  rescue StandardError => e
    Rails.logger.error("[Webhooks::AppUninstalled] Error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    head :internal_server_error
  end

  private

  def shop_domain_from_headers
    request.headers['HTTP_X_SHOPIFY_SHOP_DOMAIN'] || params[:shop_domain]
  end
end
