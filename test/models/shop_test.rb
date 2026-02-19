# frozen_string_literal: true

require "test_helper"

class ShopTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  test "should create shop with default settings" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    assert shop.persisted?
    assert shop.shop_setting.present?
  end

  test "should check billing active for exempt shops" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token",
      billing_exempt: true
    )

    assert shop.billing_active?
  end

  test "should check billing active for shops with active subscription" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token",
      subscription_status: 'active'
    )

    assert shop.billing_active?
  end

  test "should track monitored pages count" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    assert_equal 0, shop.monitored_pages_count
    assert shop.can_add_monitored_page?
  end

  # Onboarding tests
  test "show_onboarding? returns true for new shop" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    assert shop.show_onboarding?
  end

  test "show_onboarding? returns false after dismissal" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )
    shop.dismiss_onboarding!

    assert_not shop.show_onboarding?
    assert_not_nil shop.onboarding_dismissed_at
  end

  test "onboarding_steps returns 3 steps all incomplete for new shop" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    steps = shop.onboarding_steps
    assert_equal 3, steps.size
    assert_equal [ :add_products, :first_scan, :configure_alerts ], steps.map { |s| s[:key] }
    assert steps.none? { |s| s[:completed] }
  end

  test "onboarding_progress reflects completion count" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    progress = shop.onboarding_progress
    assert_equal 0, progress[:completed]
    assert_equal 3, progress[:total]
  end

  test "onboarding step add_products completes when product page exists" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    shop.product_pages.create!(
      shopify_product_id: 123,
      handle: "test-product",
      title: "Test Product",
      url: "https://#{shop.shopify_domain}/products/test-product",
      monitoring_enabled: true
    )

    steps = shop.onboarding_steps
    assert steps.find { |s| s[:key] == :add_products }[:completed]
  end

  test "onboarding step configure_alerts completes when alert email set" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )
    shop.shop_setting.update!(alert_email: "test@example.com")

    steps = shop.onboarding_steps
    assert steps.find { |s| s[:key] == :configure_alerts }[:completed]
  end

  test "show_onboarding? returns false when all steps completed" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    # Complete step 1: add product
    page = shop.product_pages.create!(
      shopify_product_id: 456,
      handle: "test-product",
      title: "Test Product",
      url: "https://#{shop.shopify_domain}/products/test-product",
      monitoring_enabled: true
    )

    # Complete step 2: run a scan
    Scan.create!(
      product_page: page,
      status: "completed",
      started_at: Time.current,
      completed_at: Time.current
    )

    # Complete step 3: configure alerts
    shop.shop_setting.update!(alert_email: "alerts@example.com")

    assert_not shop.show_onboarding?
    assert shop.onboarding_completed?
  end
end
