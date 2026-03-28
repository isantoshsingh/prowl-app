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
      shopify_status = fetch_subscription_status(existing_pending.subscription_charge_id)

      if shopify_status == "PENDING"
        Rails.logger.info("[BillingController#subscribe] Reusing pending subscription #{existing_pending.id}")
        fullpage_redirect_to(existing_pending.confirmation_url)
        return
      end

      # No longer pending — sync local status and fall through to create a new one
      existing_pending.update!(status: map_shopify_status(shopify_status))
      Rails.logger.info("[BillingController#subscribe] Subscription #{existing_pending.id} updated to '#{existing_pending.status}'")
    end

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

  def shopify_client
    session = ShopifyAPI::Auth::Session.new(
      shop: @shop.shopify_domain,
      access_token: @shop.shopify_token
    )
    ShopifyAPI::Clients::Graphql::Admin.new(session: session)
  end

  # Returns the Shopify status string ("PENDING", "ACTIVE", "DECLINED", etc.)
  # for an existing subscription charge. Returns "EXPIRED" on API failure
  # so a new subscription gets created.
  def fetch_subscription_status(charge_gid)
    query = <<~GRAPHQL
      query($id: ID!) {
        node(id: $id) {
          ... on AppSubscription { status }
        }
      }
    GRAPHQL

    response = shopify_client.query(query: query, variables: { id: charge_gid })
    response.body.dig("data", "node", "status") || "EXPIRED"
  rescue StandardError => e
    Rails.logger.error("[BillingController] Error fetching subscription status: #{e.message}")
    "EXPIRED"
  end

  def map_shopify_status(shopify_status)
    case shopify_status
    when "ACTIVE" then "active"
    when "DECLINED" then "declined"
    when "FROZEN", "CANCELLED" then "cancelled"
    else "expired"
    end
  end

  def create_new_subscription(plan)
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
          appSubscription { id }
          confirmationUrl
          userErrors { field message }
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

    response = shopify_client.query(query: mutation, variables: variables)
    result = response.body.dig("data", "appSubscriptionCreate")

    if result && result["confirmationUrl"].present?
      @shop.subscriptions.create!(
        status: "pending",
        charge_name: plan[:charge_name],
        price: plan[:price],
        currency_code: "USD",
        trial_days: 14,
        subscription_charge_id: result.dig("appSubscription", "id"),
        confirmation_url: result["confirmationUrl"]
      )
      Rails.logger.info("[BillingController#subscribe] New subscription created (pending) for #{@shop.shopify_domain}")

      fullpage_redirect_to(result["confirmationUrl"])
    else
      errors = result&.dig("userErrors")&.map { |e| e["message"] }&.join(", ") || "Unknown error"
      Rails.logger.error("[BillingController#subscribe] Failed: #{errors}")
      flash[:error] = "Could not start subscription. Please try again."
      redirect_to billing_plans_path(host: params[:host])
    end
  end
end
