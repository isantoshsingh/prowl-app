# frozen_string_literal: true

# AfterAuthenticateJob runs after a shop successfully authenticates.
# The shopify_app gem will automatically handle billing before this job runs (if not exempt).
# This job initializes the ShopSetting and Subscription for the newly installed shop.
#
class AfterAuthenticateJob < ApplicationJob
  queue_as :default

  def perform(shop_domain:)
    shop = Shop.find_by(shopify_domain: shop_domain)

    unless shop
      Rails.logger.error("[AfterAuthenticateJob] Shop not found: #{shop_domain}")
      return
    end

    # Create shop settings if they don't exist
    shop.shop_setting || shop.create_shop_setting!

    # Handle subscription creation and activation based on exemption status
    if shop.billing_exempt?
      Rails.logger.info("[AfterAuthenticateJob] Shop #{shop_domain} is exempt from billing")
      # Don't create subscription for exempt shops
    else
      # Create and activate subscription for normal shops
      handle_subscription(shop)
    end

    Rails.logger.info("[AfterAuthenticateJob] Shop settings initialized for #{shop_domain}")
  end

  private

  def handle_subscription(shop)
    # Check if subscription already exists and is active
    return if shop.active_subscription.present?

    # Check if billing was approved by querying Shopify API
    charge_id = fetch_active_charge_id(shop)

    if charge_id
      # Billing was approved - activate subscription
      activate_subscription(shop, charge_id)
    else
      # No active charge yet - create pending subscription (trial period)
      create_trial_subscription(shop)
    end
  end

  def fetch_active_charge_id(shop)
    session = ShopifyAPI::Auth::Session.new(
      shop: shop.shopify_domain,
      access_token: shop.shopify_token
    )

    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    # Query for active app subscription
    query = <<~GRAPHQL
      {
        currentAppInstallation {
          activeSubscriptions {
            id
            name
            status
            trialDays
            createdAt
          }
        }
      }
    GRAPHQL

    response = client.query(query: query)
    subscriptions = response.body.dig("data", "currentAppInstallation", "activeSubscriptions") || []

    # Find the subscription matching our charge name
    active_sub = subscriptions.find { |s| s["name"] == "Silent Profit Monthly" && s["status"] == "ACTIVE" }

    active_sub&.dig("id")
  rescue StandardError => e
    Rails.logger.error("[AfterAuthenticateJob] Error fetching charge: #{e.message}")
    nil
  end

  def activate_subscription(shop, charge_id)
    # Check if subscription already exists
    subscription = shop.latest_subscription
    billing_config = ShopifyApp.configuration.billing

    if subscription&.status == 'pending'
      # Activate existing pending subscription
      subscription.activate!(charge_id)
      Rails.logger.info("[AfterAuthenticateJob] Activated subscription for #{shop.shopify_domain}")
    else
      # Create new active subscription
      shop.subscriptions.create!(
        status: 'active',
        subscription_charge_id: charge_id,
        charge_name: billing_config.charge_name,
        price: billing_config.amount,
        currency_code: billing_config.currency_code,
        trial_days: billing_config.trial_days,
        trial_ends_at: billing_config.trial_days.days.from_now,
        activated_at: Time.current
      )
      Rails.logger.info("[AfterAuthenticateJob] Created active subscription for #{shop.shopify_domain}")
    end
  end

  def create_trial_subscription(shop)
    # Check if there's already a pending subscription
    return if shop.subscriptions.pending.exists?

    billing_config = ShopifyApp.configuration.billing

    # Create new trial subscription
    shop.subscriptions.create!(
      status: 'pending',
      charge_name: billing_config.charge_name,
      price: billing_config.amount,
      currency_code: billing_config.currency_code,
      trial_days: billing_config.trial_days,
      trial_ends_at: billing_config.trial_days.days.from_now
    )

    Rails.logger.info("[AfterAuthenticateJob] Trial subscription created for #{shop.shopify_domain}")
  end
end
