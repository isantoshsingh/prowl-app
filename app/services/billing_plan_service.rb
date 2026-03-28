# frozen_string_literal: true

# BillingPlanService defines the two pricing tiers (Free and Monitor)
# and provides helper methods to look up plan details for a given shop.
#
# Legacy "Prowl Monthly" ($10) subscribers are mapped to Monitor features.
#
class BillingPlanService
  PLANS = {
    "free" => {
      price: 0,
      max_products: 3,
      scan_interval_hours: 24,
      journey_stages: [:pdp],
      alerts: [:email],
      escalation: false,
      on_demand_scan: false,
      charge_name: nil
    },
    "monitor" => {
      price: 49,
      max_products: 5,
      scan_interval_hours: 6,
      journey_stages: [:pdp, :cart, :checkout_handoff],
      alerts: [:email],
      escalation: true,
      on_demand_scan: true,
      charge_name: "Prowl Monitor"
    }
  }.freeze

  LEGACY_CHARGE_NAME = "Prowl Monthly"

  # Returns the plan hash for a shop based on its subscription status.
  # Legacy $10 subscribers get Monitor-tier features.
  def self.plan_for(shop)
    PLANS[plan_name_for(shop)]
  end

  # Returns "free" or "monitor" based on the shop's current subscription.
  def self.plan_name_for(shop)
    return "free" unless shop

    # Check for active subscription
    if shop.subscription_active?
      plan = shop.subscription_plan
      return "monitor" if plan == "Prowl Monitor"
      return "monitor" if plan == LEGACY_CHARGE_NAME
    end

    # Check active_subscription association for legacy charges
    if shop.active_subscription&.charge_name == LEGACY_CHARGE_NAME
      return "monitor"
    end

    "free"
  end

  # Returns the max products allowed for this shop's plan
  def self.max_products_for(shop)
    plan_for(shop)[:max_products]
  end

  # Returns the scan interval in hours for this shop's plan
  def self.scan_interval_for(shop)
    plan_for(shop)[:scan_interval_hours]
  end
end
