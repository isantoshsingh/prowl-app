# frozen_string_literal: true

# BillingService handles Shopify Billing API integration.
# Silent Profit uses a recurring application charge of $10/month with a 14-day trial.
#
# Billing requirements (per PRD):
#   - $10/month subscription
#   - 14-day free trial
#   - Require billing approval during install
#   - Uninstall if billing rejected
#
class BillingService
  SUBSCRIPTION_NAME = "Silent Profit Monthly"
  SUBSCRIPTION_PRICE = 10.00
  TRIAL_DAYS = 14

  class BillingError < StandardError; end

  attr_reader :shop

  def initialize(shop)
    @shop = shop
  end

  # Creates a recurring application charge
  # Returns the confirmation URL that the merchant must visit to approve
  def create_subscription
    # This would use ShopifyAPI to create a RecurringApplicationCharge
    # For Phase 1, we'll structure the logic but note that actual implementation
    # requires proper API credentials and session management
    
    session = ShopifyAPI::Auth::Session.new(
      shop: shop.shopify_domain,
      access_token: shop.shopify_token
    )

    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    # Create subscription using GraphQL Billing API
    mutation = <<~GRAPHQL
      mutation appSubscriptionCreate($name: String!, $lineItems: [AppSubscriptionLineItemInput!]!, $trialDays: Int!, $returnUrl: URL!) {
        appSubscriptionCreate(
          name: $name,
          returnUrl: $returnUrl,
          trialDays: $trialDays,
          lineItems: $lineItems
        ) {
          userErrors {
            field
            message
          }
          confirmationUrl
          appSubscription {
            id
          }
        }
      }
    GRAPHQL

    variables = {
      name: SUBSCRIPTION_NAME,
      trialDays: TRIAL_DAYS,
      returnUrl: "#{ENV.fetch('HOST', 'https://localhost:3000')}/billing/callback",
      lineItems: [
        {
          plan: {
            appRecurringPricingDetails: {
              price: {
                amount: SUBSCRIPTION_PRICE,
                currencyCode: "USD"
              },
              interval: "EVERY_30_DAYS"
            }
          }
        }
      ]
    }

    response = client.query(query: mutation, variables: variables)
    
    data = response.body.dig("data", "appSubscriptionCreate")
    errors = data&.dig("userErrors") || []

    if errors.any?
      raise BillingError, errors.map { |e| e["message"] }.join(", ")
    end

    data["confirmationUrl"]
  rescue ShopifyAPI::Errors::HttpResponseError => e
    Rails.logger.error("[BillingService] Failed to create subscription: #{e.message}")
    raise BillingError, "Could not create subscription. Please try again."
  end

  # Handles the billing callback after merchant approves/declines
  def handle_callback(charge_id)
    session = ShopifyAPI::Auth::Session.new(
      shop: shop.shopify_domain,
      access_token: shop.shopify_token
    )

    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    # Query subscription status
    query = <<~GRAPHQL
      query getSubscription($id: ID!) {
        node(id: $id) {
          ... on AppSubscription {
            id
            status
            createdAt
            currentPeriodEnd
            trialDays
          }
        }
      }
    GRAPHQL

    response = client.query(query: query, variables: { id: charge_id })
    subscription = response.body.dig("data", "node")

    if subscription && subscription["status"] == "ACTIVE"
      shop.shop_setting.activate_subscription!(charge_id)
      true
    else
      shop.shop_setting.update!(billing_status: "cancelled")
      false
    end
  rescue ShopifyAPI::Errors::HttpResponseError => e
    Rails.logger.error("[BillingService] Failed to verify subscription: #{e.message}")
    false
  end

  # Checks current subscription status
  def subscription_active?
    return true if shop.shop_setting&.trial_active?
    return true if shop.shop_setting&.subscription_active?
    
    # Optionally verify with Shopify API
    false
  end

  # Cancels the subscription
  def cancel_subscription
    return unless shop.shop_setting&.subscription_charge_id

    # Would use Shopify API to cancel
    shop.shop_setting.cancel_subscription!
  end
end
