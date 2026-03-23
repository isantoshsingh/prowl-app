# frozen_string_literal: true

require "test_helper"

class ShopSettingTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  def setup
    @shop = Shop.create!(
      shopify_domain: "setting-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )
    @setting = @shop.shop_setting
  end

  test "scan_interval returns 24 hours for daily frequency" do
    @setting.update!(scan_frequency: "daily")
    assert_equal 24.hours, @setting.scan_interval
  end

  test "scan_interval returns 7 days for weekly frequency" do
    @setting.update!(scan_frequency: "weekly")
    assert_equal 7.days, @setting.scan_interval
  end

  test "defaults scan_frequency to daily" do
    assert_equal "daily", @setting.scan_frequency
    assert_equal 24.hours, @setting.scan_interval
  end
end
