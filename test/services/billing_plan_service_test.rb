# frozen_string_literal: true

require "test_helper"

class BillingPlanServiceTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @shop = Shop.create!(
      shopify_domain: "billing-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )
  end

  # --- plan_name_for ---

  test "returns 'free' for shop with no subscription" do
    assert_equal "free", BillingPlanService.plan_name_for(@shop)
  end

  test "returns 'free' for nil shop" do
    assert_equal "free", BillingPlanService.plan_name_for(nil)
  end

  test "returns 'monitor' for shop with active Prowl Monitor subscription" do
    @shop.update!(subscription_status: "active", subscription_plan: "Prowl Monitor")

    assert_equal "monitor", BillingPlanService.plan_name_for(@shop)
  end

  test "returns 'monitor' for shop with legacy Prowl Monthly subscription" do
    @shop.update!(subscription_status: "active", subscription_plan: "Prowl Monthly")

    assert_equal "monitor", BillingPlanService.plan_name_for(@shop)
  end

  test "returns 'free' for shop with inactive subscription" do
    @shop.update!(subscription_status: "none", subscription_plan: "Prowl Monitor")

    assert_equal "free", BillingPlanService.plan_name_for(@shop)
  end

  # --- max_products_for ---

  test "free plan allows 3 products" do
    assert_equal 3, BillingPlanService.max_products_for(@shop)
  end

  test "monitor plan allows 5 products" do
    @shop.update!(subscription_status: "active", subscription_plan: "Prowl Monitor")

    assert_equal 5, BillingPlanService.max_products_for(@shop)
  end

  # --- scan_interval_for ---

  test "free plan scans every 24 hours" do
    assert_equal 24, BillingPlanService.scan_interval_for(@shop)
  end

  test "monitor plan scans every 6 hours" do
    @shop.update!(subscription_status: "active", subscription_plan: "Prowl Monitor")

    assert_equal 6, BillingPlanService.scan_interval_for(@shop)
  end

  # --- plan_for ---

  test "plan_for returns full plan hash" do
    plan = BillingPlanService.plan_for(@shop)

    assert_equal 0, plan[:price]
    assert_equal 3, plan[:max_products]
    assert_equal 24, plan[:scan_interval_hours]
    assert_equal [:pdp], plan[:journey_stages]
    assert_equal false, plan[:escalation]
    assert_equal false, plan[:on_demand_scan]
  end

  test "monitor plan_for returns full plan hash" do
    @shop.update!(subscription_status: "active", subscription_plan: "Prowl Monitor")
    plan = BillingPlanService.plan_for(@shop)

    assert_equal 49, plan[:price]
    assert_equal 5, plan[:max_products]
    assert_equal 6, plan[:scan_interval_hours]
    assert_equal [:pdp, :cart, :checkout_handoff], plan[:journey_stages]
    assert_equal true, plan[:escalation]
    assert_equal true, plan[:on_demand_scan]
    assert_equal "Prowl Monitor", plan[:charge_name]
  end

  # --- Shop#can_add_monitored_page? integration ---

  test "free shop can add up to 3 pages" do
    assert @shop.can_add_monitored_page?

    3.times do |i|
      @shop.product_pages.create!(
        shopify_product_id: 1000 + i,
        handle: "product-#{i}",
        title: "Product #{i}",
        url: "/products/product-#{i}",
        monitoring_enabled: true
      )
    end

    assert_not @shop.can_add_monitored_page?
  end

  test "monitor shop can add up to 5 pages" do
    @shop.update!(subscription_status: "active", subscription_plan: "Prowl Monitor")

    3.times do |i|
      @shop.product_pages.create!(
        shopify_product_id: 2000 + i,
        handle: "product-#{i}",
        title: "Product #{i}",
        url: "/products/product-#{i}",
        monitoring_enabled: true
      )
    end

    # Still can add more (at 3, limit is 5)
    assert @shop.can_add_monitored_page?

    2.times do |i|
      @shop.product_pages.create!(
        shopify_product_id: 3000 + i,
        handle: "extra-#{i}",
        title: "Extra #{i}",
        url: "/products/extra-#{i}",
        monitoring_enabled: true
      )
    end

    # Now at 5 — limit reached
    assert_not @shop.can_add_monitored_page?
  end

  # --- Legacy subscriber mapping ---

  test "legacy $10 subscriber gets monitor features" do
    @shop.update!(subscription_status: "active", subscription_plan: "Prowl Monthly")

    assert_equal "monitor", BillingPlanService.plan_name_for(@shop)
    assert_equal 5, BillingPlanService.max_products_for(@shop)
    assert_equal 6, BillingPlanService.scan_interval_for(@shop)
  end
end
