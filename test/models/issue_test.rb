# frozen_string_literal: true

require "test_helper"

class IssueTest < ActiveSupport::TestCase
  # Don't use fixtures for these tests - create fresh data
  self.use_transactional_tests = true

  def setup
    # Use a unique domain for each test to avoid conflicts with fixtures
    @shop = Shop.create!(
      shopify_domain: "issue-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )

    @product_page = @shop.product_pages.create!(
      shopify_product_id: 123456,
      handle: "test-product",
      title: "Test Product",
      url: "/products/test-product"
    )

    @scan = @product_page.scans.create!(status: "completed")
  end

  def teardown
    # Clean up after each test
    @shop&.destroy
  end

  test "should create issue with valid attributes" do
    issue = @product_page.issues.create!(
      scan: @scan,
      issue_type: "missing_add_to_cart",
      severity: "high",
      title: "Test Issue",
      first_detected_at: Time.current,
      last_detected_at: Time.current
    )

    assert issue.persisted?
    assert_equal "open", issue.status
    assert_equal 1, issue.occurrence_count
  end

  test "should not alert on first occurrence" do
    issue = @product_page.issues.create!(
      scan: @scan,
      issue_type: "missing_add_to_cart",
      severity: "high",
      title: "Test Issue",
      first_detected_at: Time.current,
      last_detected_at: Time.current
    )

    refute issue.should_alert?
  end

  test "should alert after two occurrences for high severity" do
    issue = @product_page.issues.create!(
      scan: @scan,
      issue_type: "missing_add_to_cart",
      severity: "high",
      title: "Test Issue",
      occurrence_count: 2,
      first_detected_at: Time.current,
      last_detected_at: Time.current
    )

    assert issue.should_alert?
  end

  test "should not alert for medium severity" do
    issue = @product_page.issues.create!(
      scan: @scan,
      issue_type: "liquid_error",
      severity: "medium",
      title: "Test Issue",
      occurrence_count: 2,
      first_detected_at: Time.current,
      last_detected_at: Time.current
    )

    refute issue.should_alert?
  end

  test "should record occurrence" do
    issue = @product_page.issues.create!(
      scan: @scan,
      issue_type: "missing_add_to_cart",
      severity: "high",
      title: "Test Issue",
      first_detected_at: Time.current,
      last_detected_at: 1.hour.ago
    )

    new_scan = @product_page.scans.create!(status: "completed")
    issue.record_occurrence!(new_scan)

    assert_equal 2, issue.occurrence_count
    assert issue.last_detected_at > 1.minute.ago
  end

  test "should acknowledge issue" do
    issue = @product_page.issues.create!(
      scan: @scan,
      issue_type: "missing_add_to_cart",
      severity: "high",
      title: "Test Issue",
      first_detected_at: Time.current,
      last_detected_at: Time.current
    )

    issue.acknowledge!(by: "merchant@test.com")

    assert_equal "acknowledged", issue.status
    assert issue.acknowledged_at.present?
    assert_equal "merchant@test.com", issue.acknowledged_by
  end
end
