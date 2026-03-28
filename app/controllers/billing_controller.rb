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

    # Check for an existing pending subscription before creating a new one
    existing_pending = @shop.subscriptions.pending.where(charge_name: plan[:charge_name]).order(created_at: :desc).first

    if existing_pending
      # Check the status of the existing charge via Shopify API
      current_status, confirmation_url = check_subscription_status(existing_pending)

      if current_status == "PENDING" && (confirmation_url || existing_pending.confirmation_url).present?
        # Still pending — reuse it, don't create a duplicate
        Rails.logger.info("[BillingController#subscribe] Reusing pending subscription #{existing_pending.id} for #{@shop.shopify_domain}")
        fullpage_redirect_to(confirmation_url || existing_pending.confirmation_url)
        return
      else
        # No longer pending — update local record to match Shopify's status
        resolved_status = resolve_shopify_status(current_status)
        existing_pending.update!(status: resolved_status)
        Rails.logger.info("[BillingController#subscribe] Existing subscription #{existing_pending.id} status updated to '#{resolved_status}'")
      end
    end

    # Create a new subscription via Shopify API
    create_new_subscription(plan)
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

  # Calls Shopify API to check the current status of an existing subscription charge
  def check_subscription_status(subscription)
    session = ShopifyAPI::Auth::Session.new(
      shop: @shop.shopify_domain,
      access_token: @shop.shopify_token
    )
    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    query = <<~GRAPHQL
      query($id: ID!) {
        node(id: $id) {
          ... on AppSubscription {
            status
            currentPeriodEnd
          }
        }
      }
    GRAPHQL

    response = client.query(query: query, variables: { id: subscription.subscription_charge_id })
    node = response.body.dig("data", "node")

    status = node&.dig("status") || "EXPIRED"
    # Shopify doesn't return confirmationUrl from node query, so we use the stored one
    [status, nil]
  rescue StandardError => e
    Rails.logger.error("[BillingController] Error checking subscription status: #{e.message}")
    # If we can't check, treat as expired so a new one gets created
    ["EXPIRED", nil]
  end

  # Maps Shopify subscription status to our local status values
  def resolve_shopify_status(shopify_status)
    case shopify_status&.upcase
    when "ACTIVE" then "active"
    when "DECLINED" then "declined"
    when "EXPIRED" then "expired"
    when "FROZEN" then "cancelled"
    when "CANCELLED" then "cancelled"
    else "expired"
    end
  end

  def create_new_subscription(plan)
    session = ShopifyAPI::Auth::Session.new(
      shop: @shop.shopify_domain,
      access_token: @shop.shopify_token
    )
    client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

    test_mode = !ENV["SHOPIFY_TEST_CHARGES"].nil? ? ["true", "1"].include?(ENV["SHOPIFY_TEST_CHARGES"]) : !Rails.env.production?

    shopify_host = Base64.strict_encode64("#{@shop.shopify_domain}/admin")
    return_url = "#{request.base_url}/?host=#{shopify_host}"

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
      subscription_gid = result.dig("appSubscription", "id")
      confirmation_url = result["confirmationUrl"]

      @shop.subscriptions.create!(
        status: "pending",
        charge_name: plan[:charge_name],
        price: plan[:price],
        currency_code: "USD",
        trial_days: 14,
        subscription_charge_id: subscription_gid,
        confirmation_url: confirmation_url
      )
      Rails.logger.info("[BillingController#subscribe] Subscription created (pending) for #{@shop.shopify_domain}, charge: #{subscription_gid}")

      fullpage_redirect_to(confirmation_url)
    else
      errors = result&.dig("userErrors")&.map { |e| e["message"] }&.join(", ") || "Unknown error"
      Rails.logger.error("[BillingController#subscribe] Failed to create subscription: #{errors}")
      flash[:error] = "Could not start subscription. Please try again."
      redirect_to billing_plans_path(host: params[:host])
    end
  end
end
