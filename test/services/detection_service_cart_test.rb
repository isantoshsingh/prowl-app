# frozen_string_literal: true

require "test_helper"

# =============================================================================
# Tests for DetectionService processing of Sprint 2 cart/checkout issue types
#
# Covers:
#   1. price_mismatch detection results are processed correctly
#   2. cart_feedback_missing detection results create appropriate issues
#   3. checkout_broken detection results create high severity issues
#   4. atc_funnel (wrong item) detection results create issues
#   5. Issue::ISSUE_TYPES includes new types
# =============================================================================
class DetectionServiceCartTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  def setup
    @shop = Shop.create!(
      shopify_domain: "cart-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    @product_page = @shop.product_pages.create!(
      shopify_product_id: 123456,
      handle: "test-product",
      title: "Test Product",
      url: "/products/test-product"
    )
  end

  # ---------------------------------------------------------------------------
  # Issue types exist
  # ---------------------------------------------------------------------------

  test "ISSUE_TYPES includes price_mismatch" do
    assert Issue::ISSUE_TYPES.key?("price_mismatch")
    assert_equal "medium", Issue::ISSUE_TYPES["price_mismatch"][:severity]
  end

  test "ISSUE_TYPES includes cart_feedback_missing" do
    assert Issue::ISSUE_TYPES.key?("cart_feedback_missing")
    assert_equal "medium", Issue::ISSUE_TYPES["cart_feedback_missing"][:severity]
  end

  # ---------------------------------------------------------------------------
  # Detection processing
  # ---------------------------------------------------------------------------

  test "processes price_mismatch detection result" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><button name="add">Add</button><span class="price">$29.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: [],
      dom_checks_data: [
        {
          check: "price_visibility",
          status: "pass",
          confidence: 1.0,
          details: { message: "Price visible", technical_details: {}, suggestions: [], evidence: {} }
        },
        {
          check: "price_mismatch",
          status: "fail",
          confidence: 0.9,
          details: {
            message: "Price mismatch: PDP shows $29.99 but cart has $24.99",
            technical_details: { pdp_price_cents: 2999, cart_price_cents: 2499, difference_percent: 16.67 },
            suggestions: [],
            evidence: { pdp_price: "$29.99", cart_price: "$24.99", difference_percent: 16.67 }
          }
        }
      ].to_json
    )

    service = DetectionService.new(scan)
    issues = service.perform

    price_issue = issues.find { |i| i.issue_type == "price_mismatch" }
    assert_not_nil price_issue, "Expected a price_mismatch issue"
    assert_equal "medium", price_issue.severity
    assert_equal "open", price_issue.status
  end

  test "processes cart_feedback warning detection result" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><button name="add">Add</button><span class="price">$29.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: [],
      dom_checks_data: [
        {
          check: "cart_feedback",
          status: "warning",
          confidence: 0.85,
          details: {
            message: "No visible cart feedback",
            technical_details: { feedback_type: "none" },
            suggestions: [],
            evidence: { cart_item_verified: true, feedback_visible: false }
          }
        }
      ].to_json
    )

    service = DetectionService.new(scan)
    issues = service.perform

    feedback_issue = issues.find { |i| i.issue_type == "cart_feedback_missing" }
    assert_not_nil feedback_issue, "Expected a cart_feedback_missing issue"
    assert_equal "low", feedback_issue.severity, "Warning results should create low severity issues"
  end

  test "processes checkout_broken detection result" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><button name="add">Add</button><span class="price">$29.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: [],
      dom_checks_data: [
        {
          check: "checkout",
          status: "fail",
          confidence: 0.9,
          details: {
            message: "Checkout page failed to load",
            technical_details: { redirect_url: "https://store.myshopify.com/cart", error: "timeout" },
            suggestions: [],
            evidence: { redirect_url: "https://store.myshopify.com/cart", error_message: "timeout" }
          }
        }
      ].to_json
    )

    service = DetectionService.new(scan)
    issues = service.perform

    checkout_issue = issues.find { |i| i.issue_type == "checkout_broken" }
    assert_not_nil checkout_issue, "Expected a checkout_broken issue"
    assert_equal "high", checkout_issue.severity
  end

  test "processes atc_funnel wrong item detection result" do
    scan = @product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      page_load_time_ms: 2000,
      html_snapshot: '<html><body><button name="add">Add</button><span class="price">$29.99</span></body></html>',
      js_errors: [],
      network_errors: [],
      console_logs: [],
      dom_checks_data: [
        {
          check: "atc_funnel",
          status: "fail",
          confidence: 0.95,
          details: {
            message: "Cart item verification failed: wrong_item_in_cart",
            technical_details: { expected_product_id: "99999", actual_product_id: "88888" },
            suggestions: [],
            evidence: { reason: "wrong_item_in_cart", expected_product_id: "99999" }
          }
        }
      ].to_json
    )

    service = DetectionService.new(scan)
    issues = service.perform

    atc_issue = issues.find { |i| i.issue_type == "atc_not_functional" }
    assert_not_nil atc_issue, "Expected an atc_not_functional issue"
    assert_equal "high", atc_issue.severity
  end
end
