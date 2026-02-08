# frozen_string_literal: true

class SubscriptionSyncService
  def initialize(shop)
    @shop = shop
  end

  # Syncs the local subscription state with Shopify's API
  # Returns true if an active subscription was found and synced
  def sync
    return false unless @shop

    # Skip sync for exempt shops
    if @shop.billing_exempt?
      update_shop_status(nil, 'exempt')
      return true
    end

    subscription_data = fetch_active_subscription_from_shopify

    if subscription_data
      save_subscription(subscription_data)
      true
    else
      # verifying if there is any cancelled logic needed?
      # If no active subscription found, we mark as none unless we want to keep 'cancelled' for history
      # But current requirement is: if active->allow, if not->redirect. 
      # So setting to 'none' causes redirect which is correct.
      update_shop_status(nil, 'none')
      false
    end
  end

  private

  def fetch_active_subscription_from_shopify
    session = ShopifyAPI::Auth::Session.new(
      shop: @shop.shopify_domain,
      access_token: @shop.shopify_token
    )

    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    # Query for active app subscription
    # We look for ANY active subscription.
    query = <<~GRAPHQL
      {
        currentAppInstallation {
          activeSubscriptions {
            id
            name
            status
            test
            trialDays
            createdAt
            lineItems {
              plan {
                pricingDetails {
                  ... on AppRecurringPricing {
                    price {
                      amount
                      currencyCode
                    }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL

    response = client.query(query: query)
    subscriptions = response.body.dig("data", "currentAppInstallation", "activeSubscriptions") || []

    # Prioritize subscriptions that look like ours (if multiple)
    # But generally there should be only one active recurring subscription
    subscriptions.find { |s| s["status"] == "ACTIVE" }
  rescue StandardError => e
    Rails.logger.error("[SubscriptionSyncService] Error fetching from Shopify: #{e.message}")
    nil
  end

  def save_subscription(data)
    # Extract details
    charge_id = data["id"]
    status = data["status"].downcase # 'active'
    name = data["name"]
    trial_days = data["trialDays"]
    
    price_info = data.dig("lineItems", 0, "plan", "pricingDetails", "price")
    amount = price_info&.dig("amount")
    currency = price_info&.dig("currencyCode")

    # Update Subscription Log
    # We find existing by charge_id or create new
    sub = @shop.subscriptions.find_or_initialize_by(subscription_charge_id: charge_id)
    
    is_new_activation = sub.new_record? || sub.status != 'active'

    sub.update!(
      status: status,
      charge_name: name,
      price: amount,
      currency_code: currency,
      trial_days: trial_days,
      # If it's a new record or newly active, set activated_at
      activated_at: (sub.activated_at || Time.current) 
    )

    # Update Shop Cache
    update_shop_status(name, 'active')
  end

  def update_shop_status(plan_name, status)
    @shop.update!(
      subscription_plan: plan_name,
      subscription_status: status
    )
  end
end
