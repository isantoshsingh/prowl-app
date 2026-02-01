# frozen_string_literal: true

# AppSubscriptionUpdateController handles the app_subscriptions/update webhook from Shopify.
# This webhook is triggered when a subscription status changes (activated, cancelled, etc.)
#
class Webhooks::AppSubscriptionUpdateController < ApplicationController
  include ShopifyApp::WebhookVerification

  def create
    shop_domain = shop_domain_from_headers
    webhook_data = params.as_json

    shop = Shop.find_by(shopify_domain: shop_domain)

    unless shop
      Rails.logger.error("[Webhooks::AppSubscriptionUpdate] Shop not found: #{shop_domain}")
      head :ok
      return
    end

    # Extract subscription details from webhook
    subscription_id = webhook_data.dig("app_subscription", "id")
    status = webhook_data.dig("app_subscription", "status")
    name = webhook_data.dig("app_subscription", "name")

    Rails.logger.info("[Webhooks::AppSubscriptionUpdate] Received: #{shop_domain} - Status: #{status}")

    # Find or create subscription record
    subscription = shop.subscriptions.find_by(subscription_charge_id: subscription_id)

    if subscription
      # Update existing subscription status
      update_subscription_status(subscription, status)
    else
      # Create new subscription record if it doesn't exist
      create_subscription_from_webhook(shop, webhook_data)
    end

    head :ok
  rescue StandardError => e
    Rails.logger.error("[Webhooks::AppSubscriptionUpdate] Error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    head :internal_server_error
  end

  private

  def shop_domain_from_headers
    request.headers['HTTP_X_SHOPIFY_SHOP_DOMAIN'] || params[:shop_domain]
  end

  def update_subscription_status(subscription, status)
    case status.upcase
    when 'ACTIVE'
      subscription.update!(status: 'active', activated_at: Time.current) unless subscription.active?
      Rails.logger.info("[Webhooks::AppSubscriptionUpdate] Marked subscription as active")
    when 'CANCELLED'
      subscription.cancel! unless subscription.status == 'cancelled'
      Rails.logger.info("[Webhooks::AppSubscriptionUpdate] Marked subscription as cancelled")
    when 'EXPIRED'
      subscription.expire! unless subscription.status == 'expired'
      Rails.logger.info("[Webhooks::AppSubscriptionUpdate] Marked subscription as expired")
    when 'DECLINED'
      subscription.decline! unless subscription.status == 'declined'
      Rails.logger.info("[Webhooks::AppSubscriptionUpdate] Marked subscription as declined")
    else
      Rails.logger.warn("[Webhooks::AppSubscriptionUpdate] Unknown status: #{status}")
    end
  end

  def create_subscription_from_webhook(shop, webhook_data)
    subscription_data = webhook_data["app_subscription"]

    shop.subscriptions.create!(
      subscription_charge_id: subscription_data["id"],
      status: map_shopify_status(subscription_data["status"]),
      charge_name: subscription_data["name"],
      price: subscription_data.dig("line_items", 0, "plan", "pricing_details", "price", "amount"),
      currency_code: subscription_data.dig("line_items", 0, "plan", "pricing_details", "price", "currency_code"),
      trial_days: subscription_data["trial_days"],
      activated_at: subscription_data["status"] == "ACTIVE" ? Time.current : nil
    )

    Rails.logger.info("[Webhooks::AppSubscriptionUpdate] Created subscription from webhook")
  end

  def map_shopify_status(shopify_status)
    case shopify_status.upcase
    when 'ACTIVE' then 'active'
    when 'CANCELLED' then 'cancelled'
    when 'EXPIRED' then 'expired'
    when 'DECLINED' then 'declined'
    when 'PENDING' then 'pending'
    else 'pending'
    end
  end
end
