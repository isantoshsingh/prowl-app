# frozen_string_literal: true

require "test_helper"

class ProductPageTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  def setup
    @shop = Shop.create!(
      shopify_domain: "pp-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )
  end

  test "should create product page with valid attributes" do
    page = @shop.product_pages.create!(
      shopify_product_id: 123456,
      handle: "test-product",
      title: "Test Product",
      url: "/products/test-product"
    )

    assert page.persisted?
    assert_equal "pending", page.status
    assert page.monitoring_enabled?
  end

  test "should identify pages needing scan" do
    page = @shop.product_pages.create!(
      shopify_product_id: 123456,
      handle: "test-product",
      title: "Test Product",
      url: "/products/test-product"
    )

    assert page.needs_scan?
    assert_includes ProductPage.needs_scan, page
  end

  test "should generate scannable URL" do
    page = @shop.product_pages.create!(
      shopify_product_id: 123456,
      handle: "test-product",
      title: "Test Product",
      url: "/products/test-product"
    )

    assert_equal "https://#{@shop.shopify_domain}/products/test-product", page.scannable_url
  end

  test "needs_scan? returns true for daily frequency after 24 hours" do
    @shop.shop_setting.update!(scan_frequency: "daily")
    page = @shop.product_pages.create!(
      shopify_product_id: 654321,
      handle: "freq-product",
      title: "Freq Product",
      url: "/products/freq-product"
    )

    page.update!(last_scanned_at: 25.hours.ago)
    assert page.needs_scan?

    page.update!(last_scanned_at: 12.hours.ago)
    refute page.needs_scan?
  end

  test "needs_scan? returns true for weekly frequency after 7 days" do
    @shop.shop_setting.update!(scan_frequency: "weekly")
    page = @shop.product_pages.create!(
      shopify_product_id: 654322,
      handle: "weekly-product",
      title: "Weekly Product",
      url: "/products/weekly-product"
    )

    page.update!(last_scanned_at: 8.days.ago)
    assert page.needs_scan?

    page.update!(last_scanned_at: 3.days.ago)
    refute page.needs_scan?
  end

  test "needs_scan_within scope respects the given interval" do
    page = @shop.product_pages.create!(
      shopify_product_id: 654323,
      handle: "scope-product",
      title: "Scope Product",
      url: "/products/scope-product",
      monitoring_enabled: true
    )

    page.update!(last_scanned_at: 3.days.ago)

    # 24-hour interval: should include (3 days > 24 hours)
    assert_includes ProductPage.needs_scan_within(24.hours), page

    # 7-day interval: should exclude (3 days < 7 days)
    refute_includes ProductPage.needs_scan_within(7.days), page

    # Never scanned: always included
    page.update!(last_scanned_at: nil)
    assert_includes ProductPage.needs_scan_within(7.days), page
  end

  test "should enforce unique product per shop" do
    @shop.product_pages.create!(
      shopify_product_id: 123456,
      handle: "test-product",
      title: "Test Product",
      url: "/products/test-product"
    )

    assert_raises ActiveRecord::RecordInvalid do
      @shop.product_pages.create!(
        shopify_product_id: 123456,
        handle: "test-product",
        title: "Test Product",
        url: "/products/test-product"
      )
    end
  end
end
