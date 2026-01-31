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
