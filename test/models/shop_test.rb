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
end
