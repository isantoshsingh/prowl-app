# frozen_string_literal: true

require "test_helper"

class DetectionServiceTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  def setup
    @shop = Shop.create!(
      shopify_domain: "detect-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    @product_page = @shop.product_pages.create!(
      shopify_product_id: 123456,
      handle: "test-product",
      title: "Test Product",
      url: "/products/test-product"
    )
  end

  test "should detect JS errors" do
    scan = @product_page.scans.create!(
      status: "completed",
      js_errors: [{ "message" => "Uncaught TypeError: Cannot read property" }]
    )

    service = DetectionService.new(scan)
    issues = service.perform

    assert issues.any? { |i| i.issue_type == "js_error" }
  end

  test "should detect Liquid errors" do
    scan = @product_page.scans.create!(
      status: "completed",
      html_snapshot: "<html><body>Liquid error: undefined</body></html>",
      js_errors: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    assert issues.any? { |i| i.issue_type == "liquid_error" }
  end

  test "should detect slow page load" do
    scan = @product_page.scans.create!(
      status: "completed",
      page_load_time_ms: 6000,
      js_errors: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    assert issues.any? { |i| i.issue_type == "slow_page_load" }
  end

  test "should not create issue for fast page load" do
    scan = @product_page.scans.create!(
      status: "completed",
      page_load_time_ms: 2000,
      html_snapshot: "<html><body>Normal page with name=\"add\"</body></html>",
      js_errors: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    refute issues.any? { |i| i.issue_type == "slow_page_load" }
  end

  test "should update page status based on issues" do
    scan = @product_page.scans.create!(
      status: "completed",
      js_errors: [{ "message" => "Critical error" }]
    )

    DetectionService.new(scan).perform

    @product_page.reload
    assert_includes %w[critical warning], @product_page.status
  end
end
