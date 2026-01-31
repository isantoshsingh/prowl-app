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
    assert_equal "trial", shop.shop_setting.billing_status
    assert shop.shop_setting.trial_ends_at > Time.current
  end

  test "should check billing active during trial" do
    shop = Shop.create!(
      shopify_domain: "shop-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
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
