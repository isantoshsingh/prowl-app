# frozen_string_literal: true

require "test_helper"

# =============================================================================
# Tests for Detectors::AddToCartDetector — Sprint 2 Cart Scanning + Checkout
#
# Covers:
#   1. Free-tier: PDP checks only, cart/checkout skipped
#   2. Monitor-tier deep scan — happy path (full journey)
#   3. ATC click failure
#   4. Wrong item in cart
#   5. No cart feedback (warning)
#   6. Price mismatch detection
#   7. Checkout broken
#   8. Out-of-stock product handling
#   9. Cart cleanup on success and failure
#  10. Price parsing edge cases
# =============================================================================
class AddToCartDetectorTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Builds a configurable browser_service stub for testing without a real browser
  def build_browser_stub(overrides = {})
    defaults = {
      atc_script_result: {
        "button_found" => true,
        "button_visible" => true,
        "button_enabled" => true,
        "button_text" => "Add to Cart",
        "selector_used" => 'form[action*="/cart/add"] button[type="submit"]',
        "form_found" => true,
        "form_valid" => true,
        "form_action" => "/cart/add",
        "has_click_handler" => true,
        "product_unavailable" => false,
        "visibility_details" => { "display" => "block", "visibility" => "visible", "opacity" => "1", "width" => 200, "height" => 40 }
      },
      click_add_to_cart_result: { clicked: true, error: nil, selector: 'form[action*="/cart/add"] button[type="submit"]' },
      cart_before: { item_count: 0, items: [], error: nil },
      cart_after: { item_count: 1, items: [ { "key" => "12345:variant1", "variant_id" => 111, "product_id" => 99999, "title" => "Test Product", "quantity" => 1, "price" => 2999 } ], error: nil },
      verify_cart_result: { verified: true, reason: nil, cart_state: nil, cart_price_cents: 2999 },
      cart_feedback_result: { visible: true, feedback_type: "drawer" },
      checkout_result: { url: "https://checkout.shopify.com/12345", redirected: true, is_shopify_checkout: true, error: nil },
      clear_cart_result: { success: true, error: nil },
      select_variant_result: { selected: true, variant_name: "Small", method: "select" }
    }
    config = defaults.merge(overrides)

    stub = Object.new
    cart_read_count = 0
    cart_before_val = config[:cart_before]
    cart_after_val = config[:cart_after]

    stub.define_singleton_method(:evaluate_script) { |_script, **_opts| config[:atc_script_result] }
    stub.define_singleton_method(:click_add_to_cart) { config[:click_add_to_cart_result] }
    stub.define_singleton_method(:read_cart_state) do
      cart_read_count += 1
      cart_read_count <= 1 ? cart_before_val : cart_after_val
    end
    stub.define_singleton_method(:verify_cart_item) { |_id| config[:verify_cart_result] }
    stub.define_singleton_method(:cart_feedback_visible?) { config[:cart_feedback_result] }
    stub.define_singleton_method(:navigate_to_checkout) { config[:checkout_result] }
    stub.define_singleton_method(:clear_cart_item) { |_key| config[:clear_cart_result] }
    stub.define_singleton_method(:select_first_variant) { config[:select_variant_result] }
    stub.define_singleton_method(:page_content) { "<html><body>Test</body></html>" }

    stub
  end

  def free_shop_stub
    shop = Object.new
    shop.define_singleton_method(:subscription_active?) { false }
    shop.define_singleton_method(:subscription_plan) { nil }
    shop.define_singleton_method(:active_subscription) { nil }
    shop
  end

  def monitor_shop_stub
    shop = Object.new
    shop.define_singleton_method(:subscription_active?) { true }
    shop.define_singleton_method(:subscription_plan) { "Prowl Monitor" }
    shop.define_singleton_method(:active_subscription) { nil }
    shop
  end

  def price_result_stub(price_text = "$29.99")
    {
      check: "price_visibility",
      status: "pass",
      confidence: 1.0,
      details: {
        message: "Product price is visible",
        technical_details: { price_text: price_text },
        evidence: { price_text: price_text },
        suggestions: []
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Suite 1 — Free-tier: PDP only, cart/checkout skipped
  # ---------------------------------------------------------------------------

  test "free-tier deep scan: ATC passes without running cart verification" do
    bs = build_browser_stub
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: free_shop_stub, product_id: 99999
    )

    result = detector.perform

    assert_equal "pass", result[:status]
    assert_includes result.dig(:details, :message), "fully functional"
    # Journey stages should only include PDP
    assert_equal [ "pdp" ], result.dig(:details, :evidence, :journey_stages)
    # No journey results appended (cart/checkout not run)
    assert_empty detector.all_results
  end

  # ---------------------------------------------------------------------------
  # Suite 2 — Monitor-tier deep scan — happy path
  # ---------------------------------------------------------------------------

  test "monitor-tier deep scan happy path: full journey passes" do
    bs = build_browser_stub
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999,
      pdp_price_result: price_result_stub("$29.99")
    )

    result = detector.perform

    assert_equal "pass", result[:status]
    assert_includes result.dig(:details, :message), "fully functional"
    assert_includes result.dig(:details, :evidence, :journey_stages), "cart"
    assert_includes result.dig(:details, :evidence, :journey_stages), "checkout_handoff"
    # Journey results should all be passes (for DetectionService to resolve prior issues)
    journey = detector.all_results
    assert journey.all? { |r| r[:status] == "pass" }, "All journey results should pass on happy path"
    assert journey.any? { |r| r[:check] == "cart_feedback" }, "Expected cart_feedback pass result"
    assert journey.any? { |r| r[:check] == "price_mismatch" }, "Expected price_mismatch pass result"
    assert journey.any? { |r| r[:check] == "checkout" }, "Expected checkout pass result"
  end

  # ---------------------------------------------------------------------------
  # Suite 3 — ATC click failure
  # ---------------------------------------------------------------------------

  test "ATC click failure returns fail result" do
    bs = build_browser_stub(
      click_add_to_cart_result: { clicked: false, error: "No enabled ATC button found", selector: nil }
    )
    detector = Detectors::AddToCartDetector.new(bs, scan_depth: :deep, shop: monitor_shop_stub)

    result = detector.perform

    assert_equal "fail", result[:status]
    assert_includes result.dig(:details, :message), "could not be clicked"
  end

  # ---------------------------------------------------------------------------
  # Suite 4 — Wrong item in cart
  # ---------------------------------------------------------------------------

  test "monitor-tier: wrong item in cart creates atc_funnel issue" do
    bs = build_browser_stub(
      verify_cart_result: {
        verified: false,
        reason: "wrong_item_in_cart",
        expected_product_id: "99999",
        actual_product_id: "88888",
        cart_state: { item_count: 1, items: [] }
      }
    )
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999
    )

    result = detector.perform

    # Primary ATC result passes (item was added)
    assert_equal "pass", result[:status]
    # Journey results contain the cart item verification failure (+ checkout pass)
    journey = detector.all_results
    atc_issue = journey.find { |r| r[:check] == "atc_funnel" }
    assert_not_nil atc_issue
    assert_equal "fail", atc_issue[:status]
    assert_includes atc_issue.dig(:details, :evidence, :reason), "wrong_item_in_cart"
  end

  # ---------------------------------------------------------------------------
  # Suite 5 — No cart feedback (warning)
  # ---------------------------------------------------------------------------

  test "monitor-tier: no cart feedback creates warning" do
    bs = build_browser_stub(
      cart_feedback_result: { visible: false, feedback_type: "none" }
    )
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999
    )

    result = detector.perform

    assert_equal "pass", result[:status]
    journey = detector.all_results
    feedback_issue = journey.find { |r| r[:check] == "cart_feedback" }
    assert_not_nil feedback_issue
    assert_equal "warning", feedback_issue[:status]
    assert_includes feedback_issue.dig(:details, :message), "No visible cart feedback"
  end

  # ---------------------------------------------------------------------------
  # Suite 6 — Price mismatch detection
  # ---------------------------------------------------------------------------

  test "monitor-tier: price mismatch detected when PDP and cart differ by >1%" do
    bs = build_browser_stub(
      verify_cart_result: { verified: true, reason: nil, cart_state: nil, cart_price_cents: 2499 }
    )
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999,
      pdp_price_result: price_result_stub("$29.99")
    )

    result = detector.perform

    assert_equal "pass", result[:status]
    journey = detector.all_results
    price_issue = journey.find { |r| r[:check] == "price_mismatch" }
    assert_not_nil price_issue, "Expected a price_mismatch journey result"
    assert_equal "fail", price_issue[:status]
    assert_includes price_issue.dig(:details, :message), "Price mismatch"
  end

  test "monitor-tier: no price mismatch when prices match within 1%" do
    bs = build_browser_stub(
      verify_cart_result: { verified: true, reason: nil, cart_state: nil, cart_price_cents: 2999 }
    )
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999,
      pdp_price_result: price_result_stub("$29.99")
    )

    result = detector.perform

    assert_equal "pass", result[:status]
    journey = detector.all_results
    price_result = journey.find { |r| r[:check] == "price_mismatch" }
    assert_not_nil price_result, "Expected a price_mismatch pass result for issue resolution"
    assert_equal "pass", price_result[:status]
  end

  test "price mismatch skipped when PDP price not detected" do
    bs = build_browser_stub
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999,
      pdp_price_result: nil
    )

    result = detector.perform

    assert_equal "pass", result[:status]
    journey = detector.all_results
    price_issue = journey.find { |r| r[:check] == "price_mismatch" }
    assert_nil price_issue
  end

  # ---------------------------------------------------------------------------
  # Suite 7 — Checkout broken
  # ---------------------------------------------------------------------------

  test "monitor-tier: checkout broken when redirect fails" do
    bs = build_browser_stub(
      checkout_result: { url: "https://store.myshopify.com/cart", redirected: false, is_shopify_checkout: false, error: "Checkout navigation timed out" }
    )
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999
    )

    result = detector.perform

    assert_equal "pass", result[:status]
    journey = detector.all_results
    checkout_issue = journey.find { |r| r[:check] == "checkout" }
    assert_not_nil checkout_issue
    assert_equal "fail", checkout_issue[:status]
    assert_includes checkout_issue.dig(:details, :message), "Checkout"
  end

  test "monitor-tier: checkout passes when redirected to Shopify checkout" do
    bs = build_browser_stub(
      checkout_result: { url: "https://checkout.shopify.com/12345", redirected: true, is_shopify_checkout: true, error: nil }
    )
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999
    )

    result = detector.perform

    assert_equal "pass", result[:status]
    journey = detector.all_results
    checkout_result = journey.find { |r| r[:check] == "checkout" }
    assert_not_nil checkout_result, "Expected a checkout pass result for issue resolution"
    assert_equal "pass", checkout_result[:status]
  end

  # ---------------------------------------------------------------------------
  # Suite 8 — Out-of-stock product
  # ---------------------------------------------------------------------------

  test "out-of-stock product: passes with sold_out flag, no false positive" do
    bs = build_browser_stub(
      atc_script_result: {
        "button_found" => true,
        "button_visible" => true,
        "button_enabled" => false,
        "button_text" => "Sold Out",
        "selector_used" => 'form[action*="/cart/add"] button[type="submit"]',
        "form_found" => true,
        "form_valid" => true,
        "form_action" => "/cart/add",
        "has_click_handler" => true,
        "product_unavailable" => true,
        "visibility_details" => { "display" => "block", "visibility" => "visible", "opacity" => "1", "width" => 200, "height" => 40 }
      }
    )
    detector = Detectors::AddToCartDetector.new(bs, scan_depth: :deep, shop: monitor_shop_stub)

    result = detector.perform

    assert_equal "pass", result[:status]
    assert result.dig(:details, :technical_details, :sold_out)
  end

  # ---------------------------------------------------------------------------
  # Suite 9 — Cart cleanup
  # ---------------------------------------------------------------------------

  test "cart cleanup runs even when journey checks fail" do
    cleanup_called = false
    bs = build_browser_stub(
      checkout_result: { url: "", redirected: false, is_shopify_checkout: false, error: "Connection refused" }
    )
    original_clear = bs.method(:clear_cart_item)
    bs.define_singleton_method(:clear_cart_item) do |key|
      cleanup_called = true
      original_clear.call(key)
    end

    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999
    )
    detector.perform

    assert cleanup_called, "Cart cleanup should run even when checkout fails"
  end

  test "cart cleanup runs when ATC fails (no item to clean)" do
    cleanup_called = false
    bs = build_browser_stub(
      cart_after: { item_count: 0, items: [], error: nil }
    )
    bs.define_singleton_method(:clear_cart_item) do |key|
      cleanup_called = true
      { success: true, error: nil }
    end

    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999
    )
    detector.perform

    refute cleanup_called, "No cleanup needed when no item was added"
  end

  # ---------------------------------------------------------------------------
  # Suite 10 — Price parsing edge cases
  # ---------------------------------------------------------------------------

  test "parse_price_to_cents handles various formats" do
    bs = build_browser_stub
    detector = Detectors::AddToCartDetector.new(bs, scan_depth: :quick)

    # Access private method via send
    assert_equal 2999, detector.send(:parse_price_to_cents, "$29.99")
    assert_equal 129900, detector.send(:parse_price_to_cents, "$1,299.00")
    assert_equal 2999, detector.send(:parse_price_to_cents, "€29,99")
    assert_equal 2999, detector.send(:parse_price_to_cents, "£29.99")
    assert_equal 129900, detector.send(:parse_price_to_cents, "1299.00")
    assert_nil detector.send(:parse_price_to_cents, nil)
    assert_nil detector.send(:parse_price_to_cents, "")
  end

  # ---------------------------------------------------------------------------
  # Suite 11 — Quick scan does not run funnel test
  # ---------------------------------------------------------------------------

  test "quick scan returns pass without funnel test" do
    bs = build_browser_stub
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :quick, shop: monitor_shop_stub, product_id: 99999
    )

    result = detector.perform

    assert_equal "pass", result[:status]
    assert_equal "quick", result.dig(:details, :evidence, :scan_depth)
    assert_empty detector.all_results
  end

  # ---------------------------------------------------------------------------
  # Suite 12 — Item not added to cart (cart count doesn't increase)
  # ---------------------------------------------------------------------------

  test "deep scan: item not added to cart returns fail" do
    bs = build_browser_stub(
      cart_after: { item_count: 0, items: [], error: nil }
    )
    detector = Detectors::AddToCartDetector.new(
      bs, scan_depth: :deep, shop: monitor_shop_stub, product_id: 99999
    )

    result = detector.perform

    assert_equal "fail", result[:status]
    assert_includes result.dig(:details, :message), "not added to the cart"
  end
end
