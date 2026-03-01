# frozen_string_literal: true

require "test_helper"

class ScanPdpJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.use_transactional_tests = true

  def setup
    @shop = Shop.create!(
      shopify_domain: "scan-job-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token",
      billing_exempt: true,
      subscription_status: "active"
    )

    @product_page = @shop.product_pages.create!(
      shopify_product_id: rand(100_000..999_999),
      handle: "test-product",
      title: "Test Product",
      url: "/products/test-product",
      monitoring_enabled: true,
      status: "pending"
    )
  end

  # --- Guard conditions ---

  test "skips scan when billing is not active" do
    @shop.update!(billing_exempt: false, subscription_status: "none")

    assert_no_difference "Scan.count" do
      ScanPdpJob.perform_now(@product_page.id)
    end
  end

  test "skips scan when monitoring is disabled" do
    @product_page.update!(monitoring_enabled: false)

    assert_no_difference "Scan.count" do
      ScanPdpJob.perform_now(@product_page.id)
    end
  end

  test "discards job when product page not found" do
    assert_nothing_raised do
      ScanPdpJob.perform_now(-1)
    end
  end

  # --- Successful scan flow ---

  test "detection service processes a completed scan correctly" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><form action="/cart/add"><button type="submit" name="add">Add to Cart</button></form><span class="price">$19.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    assert_empty issues, "Expected no issues for a well-formed page"
    @product_page.reload
    assert_equal "healthy", @product_page.status
  end

  test "failed scan does not crash detection service" do
    scan = @product_page.scans.create!(
      status: "failed",
      error_message: "Navigation failed"
    )

    service = DetectionService.new(scan)
    issues = service.perform

    assert_empty issues, "Detection should return empty for failed scans"
  end

  # --- Detection integration ---

  test "detection creates issues for JS errors" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      js_errors: [{ "message" => "Uncaught TypeError: Cannot read property 'variant' of undefined" }],
      html_snapshot: '<html><body><form action="/cart/add"><button type="submit" name="add">Add to Cart</button></form><span class="price">$19.99</span></body></html>',
      network_errors: [],
      console_logs: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    js_issue = issues.find { |i| i.issue_type == "js_error" }
    assert_not_nil js_issue, "Expected a js_error issue"
    assert_equal "high", js_issue.severity
    assert_equal "open", js_issue.status

    variant_issue = issues.find { |i| i.issue_type == "variant_selector_error" }
    assert_not_nil variant_issue, "Expected a variant_selector_error issue (JS error mentions 'variant')"
  end

  test "detection creates issue for missing add-to-cart button" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><h1>Product</h1><span class="price">$19.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    atc_issue = issues.find { |i| i.issue_type == "missing_add_to_cart" }
    assert_not_nil atc_issue, "Expected a missing_add_to_cart issue"
    assert_equal "high", atc_issue.severity
  end

  test "detection creates issue for liquid errors in HTML" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body>Liquid error: undefined variable "product.metafield" <button name="add">Add</button><span class="price">$19.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    liquid_issue = issues.find { |i| i.issue_type == "liquid_error" }
    assert_not_nil liquid_issue, "Expected a liquid_error issue"
    assert_equal "medium", liquid_issue.severity
  end

  test "detection creates issue for missing price" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><form action="/cart/add"><button type="submit" name="add">Add</button></form><h1>Widget</h1></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    price_issue = issues.find { |i| i.issue_type == "missing_price" }
    assert_not_nil price_issue, "Expected a missing_price issue"
    assert_equal "high", price_issue.severity
  end

  test "detection creates issue for broken images" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><button name="add">Add</button><span class="price">$19.99</span></body></html>',
      js_errors: [],
      network_errors: [
        { "url" => "https://cdn.shopify.com/product.jpg", "resource_type" => "image", "failure" => "net::ERR_FAILED" }
      ],
      console_logs: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    image_issue = issues.find { |i| i.issue_type == "missing_images" }
    assert_not_nil image_issue, "Expected a missing_images issue"
    assert_equal "medium", image_issue.severity
  end

  test "detection creates issue for slow page load" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 7500,
      html_snapshot: '<html><body><button name="add">Add</button><span class="price">$19.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    slow_issue = issues.find { |i| i.issue_type == "slow_page_load" }
    assert_not_nil slow_issue, "Expected a slow_page_load issue"
    assert_equal "low", slow_issue.severity
  end

  test "no issues created for a healthy page" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 1500,
      html_snapshot: '<html><body><form action="/cart/add"><button type="submit" name="add">Add to Cart</button></form><span class="price">$29.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    service = DetectionService.new(scan)
    issues = service.perform

    assert_empty issues, "Expected no issues for a healthy page"
    @product_page.reload
    assert_equal "healthy", @product_page.status
  end

  # --- Page status updates ---

  test "page status becomes critical with high severity issues" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><h1>Broken</h1></body></html>',
      js_errors: [{ "message" => "Fatal error" }],
      network_errors: [],
      console_logs: []
    )

    DetectionService.new(scan).perform
    @product_page.reload

    assert_equal "critical", @product_page.status
  end

  test "page status becomes warning with only medium severity issues" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body>Translation missing: en.products.title <button name="add">Add</button><span class="price">$19.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    DetectionService.new(scan).perform
    @product_page.reload

    assert_equal "warning", @product_page.status
  end

  # --- Alert threshold ---

  test "alerts only fire after 2 occurrences of high severity issue" do
    # First scan — creates issue with occurrence_count=1
    scan1 = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><h1>No ATC</h1></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    issues1 = DetectionService.new(scan1).perform
    atc_issue = issues1.find { |i| i.issue_type == "missing_add_to_cart" }
    assert_not_nil atc_issue
    assert_equal 1, atc_issue.occurrence_count
    refute atc_issue.should_alert?, "Should NOT alert on first occurrence"

    # Second scan — increments occurrence_count to 2
    scan2 = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><h1>No ATC</h1></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    issues2 = DetectionService.new(scan2).perform
    atc_issue.reload
    assert_equal 2, atc_issue.occurrence_count
    assert atc_issue.should_alert?, "Should alert after 2 occurrences"
  end

  # --- Rescan threshold ---

  test "schedules a delayed rescan when a new high severity issue is found" do
    scan = @product_page.scans.create!(status: "completed", completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><h1>No ATC</h1></body></html>',
      js_errors: [], network_errors: [], console_logs: [])
    scan_result = {
      success: true,
      scan: scan,
      detection_results: [],
      error: nil
    }

    orig_scanner_new = ProductPageScanner.method(:new)
    orig_adapter = ActiveJob::Base.queue_adapter

    begin
      ActiveJob::Base.queue_adapter = :test

      ProductPageScanner.define_singleton_method(:new) do |*args, **kwargs|
        scanner = Object.new
        scanner.define_singleton_method(:perform) { scan_result }
        scanner
      end

      assert_enqueued_with(job: ScanPdpJob, args: [@product_page.id]) do
        ScanPdpJob.perform_now(@product_page.id)
      end
    ensure
      ActiveJob::Base.queue_adapter = orig_adapter
      ProductPageScanner.define_singleton_method(:new, &orig_scanner_new)
    end
  end

  # --- Detection does nothing for non-completed scans ---

  test "detection returns empty for failed scan" do
    scan = @product_page.scans.create!(
      status: "failed",
      error_message: "Timeout"
    )

    service = DetectionService.new(scan)
    issues = service.perform

    assert_empty issues
  end

  test "detection returns empty for pending scan" do
    scan = @product_page.scans.create!(status: "pending")

    service = DetectionService.new(scan)
    issues = service.perform

    assert_empty issues
  end

  # --- Issue resolution on subsequent clean scan ---

  test "existing issues are resolved when subsequent scan is clean" do
    # First scan — create an issue
    scan1 = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><h1>No ATC</h1></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    issues1 = DetectionService.new(scan1).perform
    atc_issue = issues1.find { |i| i.issue_type == "missing_add_to_cart" }
    assert_not_nil atc_issue
    assert_equal "open", atc_issue.status

    # Second scan — clean page, issue should resolve
    scan2 = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 1500,
      html_snapshot: '<html><body><form action="/cart/add"><button type="submit" name="add">Add to Cart</button></form><span class="price">$29.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: []
    )

    DetectionService.new(scan2).perform
    atc_issue.reload
    assert_equal "resolved", atc_issue.status

    @product_page.reload
    assert_equal "healthy", @product_page.status
  end
end
