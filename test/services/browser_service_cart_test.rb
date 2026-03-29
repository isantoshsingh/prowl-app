# frozen_string_literal: true

require "test_helper"

# =============================================================================
# Tests for BrowserService cart verification methods (Sprint 2)
#
# These tests use stubs since real browser interaction is not available in CI.
# Covers: verify_cart_item, cart_feedback_visible?
# =============================================================================
class BrowserServiceCartTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # verify_cart_item
  # ---------------------------------------------------------------------------

  test "verify_cart_item returns verified when product matches" do
    bs = BrowserService.new
    # Stub the internal methods
    bs.instance_variable_set(:@started, true)
    bs.instance_variable_set(:@browser, true) # non-nil to pass started?
    bs.instance_variable_set(:@page, true) # non-nil to pass ensure_page_loaded!

    cart_state = {
      item_count: 1,
      items: [ { "product_id" => 12345, "price" => 2999, "quantity" => 1, "key" => "abc:123" } ],
      error: nil
    }
    bs.define_singleton_method(:read_cart_state) { cart_state }

    result = bs.verify_cart_item(12345)

    assert result[:verified]
    assert_nil result[:reason]
    assert_equal 2999, result[:cart_price_cents]
  end

  test "verify_cart_item fails when product_id doesn't match" do
    bs = BrowserService.new
    bs.instance_variable_set(:@started, true)
    bs.instance_variable_set(:@browser, true)
    bs.instance_variable_set(:@page, true)

    cart_state = {
      item_count: 1,
      items: [ { "product_id" => 99999, "price" => 2999, "quantity" => 1, "key" => "abc:123" } ],
      error: nil
    }
    bs.define_singleton_method(:read_cart_state) { cart_state }

    result = bs.verify_cart_item(12345)

    refute result[:verified]
    assert_equal "wrong_item_in_cart", result[:reason]
    assert_equal "12345", result[:expected_product_id]
    assert_equal "99999", result[:actual_product_id]
  end

  test "verify_cart_item fails when price is zero" do
    bs = BrowserService.new
    bs.instance_variable_set(:@started, true)
    bs.instance_variable_set(:@browser, true)
    bs.instance_variable_set(:@page, true)

    cart_state = {
      item_count: 1,
      items: [ { "product_id" => 12345, "price" => 0, "quantity" => 1, "key" => "abc:123" } ],
      error: nil
    }
    bs.define_singleton_method(:read_cart_state) { cart_state }

    result = bs.verify_cart_item(12345)

    refute result[:verified]
    assert_equal "zero_price", result[:reason]
  end

  test "verify_cart_item fails when quantity is not 1" do
    bs = BrowserService.new
    bs.instance_variable_set(:@started, true)
    bs.instance_variable_set(:@browser, true)
    bs.instance_variable_set(:@page, true)

    cart_state = {
      item_count: 1,
      items: [ { "product_id" => 12345, "price" => 2999, "quantity" => 3, "key" => "abc:123" } ],
      error: nil
    }
    bs.define_singleton_method(:read_cart_state) { cart_state }

    result = bs.verify_cart_item(12345)

    refute result[:verified]
    assert_equal "unexpected_quantity", result[:reason]
  end

  test "verify_cart_item handles empty cart" do
    bs = BrowserService.new
    bs.instance_variable_set(:@started, true)
    bs.instance_variable_set(:@browser, true)
    bs.instance_variable_set(:@page, true)

    cart_state = { item_count: 0, items: [], error: nil }
    bs.define_singleton_method(:read_cart_state) { cart_state }

    result = bs.verify_cart_item(12345)

    refute result[:verified]
    assert_equal "cart_read_failed", result[:reason]
  end

  test "verify_cart_item handles cart read error" do
    bs = BrowserService.new
    bs.instance_variable_set(:@started, true)
    bs.instance_variable_set(:@browser, true)
    bs.instance_variable_set(:@page, true)

    cart_state = { item_count: -1, items: [], error: "HTTP 500" }
    bs.define_singleton_method(:read_cart_state) { cart_state }

    result = bs.verify_cart_item(12345)

    refute result[:verified]
    assert_equal "cart_read_failed", result[:reason]
  end
end
