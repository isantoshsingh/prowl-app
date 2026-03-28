# frozen_string_literal: true

# BillingController handles plan display, comparison, and subscription management.
#
# Actions:
#   index     — Current subscription status (existing)
#   plans     — Side-by-side plan comparison page
#   subscribe — Initiates Shopify billing flow for Monitor plan
#
class BillingController < AuthenticatedController

  before_action :set_shop

  def index
    @subscription = @shop.latest_subscription
    @plan_name = BillingPlanService.plan_name_for(@shop)
    @plan = BillingPlanService.plan_for(@shop)
    @host = params[:host]
  end

  def plans
    @plan_name = BillingPlanService.plan_name_for(@shop)
    @host = params[:host]
  end

  def subscribe
    plan = BillingPlanService::PLANS["monitor"]

    session = ShopifyAPI::Auth::Session.new(
      shop: @shop.shopify_domain,
      access_token: @shop.shopify_token
    )

    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    test_mode = !ENV["SHOPIFY_TEST_CHARGES"].nil? ? ["true", "1"].include?(ENV["SHOPIFY_TEST_CHARGES"]) : !Rails.env.production?

    # Build the return URL from the current request (works with Cloudflare tunnels).
    return_url = "#{request.base_url}/?host=#{params[:host]}"

    mutation = <<~GRAPHQL
      mutation appSubscriptionCreate($name: String!, $lineItems: [AppSubscriptionLineItemInput!]!, $returnUrl: URL!, $trialDays: Int, $test: Boolean) {
        appSubscriptionCreate(
          name: $name
          lineItems: $lineItems
          returnUrl: $returnUrl
          trialDays: $trialDays
          test: $test
        ) {
          appSubscription {
            id
          }
          confirmationUrl
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    variables = {
      name: plan[:charge_name],
      returnUrl: return_url,
      trialDays: 14,
      test: test_mode,
      lineItems: [
        {
          plan: {
            appRecurringPricingDetails: {
              price: { amount: plan[:price].to_f, currencyCode: "USD" },
              interval: "EVERY_30_DAYS"
            }
          }
        }
      ]
    }

    response = client.query(query: mutation, variables: variables)
    result = response.body.dig("data", "appSubscriptionCreate")

    if result && result["confirmationUrl"].present?
      # Use fullpage_redirect_to to break out of the Shopify admin iframe
      fullpage_redirect_to(result["confirmationUrl"])
    else
      errors = result&.dig("userErrors")&.map { |e| e["message"] }&.join(", ") || "Unknown error"
      Rails.logger.error("[BillingController#subscribe] Failed to create subscription: #{errors}")
      flash[:error] = "Could not start subscription. Please try again."
      redirect_to billing_plans_path(host: params[:host])
    end
  rescue StandardError => e
    Rails.logger.error("[BillingController#subscribe] Error: #{e.message}")
    flash[:error] = "Something went wrong. Please try again."
    redirect_to billing_plans_path(host: params[:host])
  end

  private

  def set_shop
    @shop = Shop.find_by(shopify_domain: current_shopify_domain)
    unless @shop
      redirect_to ShopifyApp.configuration.login_url
    end
  end
end
