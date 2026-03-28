# frozen_string_literal: true

require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  setup do
    @shop = Shop.create!(
      shopify_domain: "sub-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token"
    )
  end

  # --- Validations ---

  test "requires status" do
    sub = Subscription.new(shop: @shop)
    assert_not sub.valid?
    assert_includes sub.errors[:status], "can't be blank"
  end

  test "validates status inclusion" do
    sub = Subscription.new(shop: @shop, status: "invalid")
    assert_not sub.valid?
    assert_includes sub.errors[:status], "is not included in the list"
  end

  test "allows all valid statuses" do
    %w[pending active cancelled expired declined].each do |status|
      sub = Subscription.new(shop: @shop, status: status, charge_name: "Test")
      assert sub.valid?, "Expected status '#{status}' to be valid"
    end
  end

  test "enforces uniqueness of subscription_charge_id" do
    Subscription.create!(shop: @shop, status: "pending", subscription_charge_id: "gid://shopify/AppSubscription/123")
    dup = Subscription.new(shop: @shop, status: "pending", subscription_charge_id: "gid://shopify/AppSubscription/123")
    assert_not dup.valid?
  end

  test "allows nil subscription_charge_id" do
    Subscription.create!(shop: @shop, status: "pending", subscription_charge_id: nil)
    another = Subscription.new(shop: @shop, status: "pending", subscription_charge_id: nil)
    assert another.valid?
  end

  # --- Scopes ---

  test "active scope returns only active subscriptions" do
    Subscription.create!(shop: @shop, status: "active", charge_name: "Prowl Monitor")
    Subscription.create!(shop: @shop, status: "pending", charge_name: "Prowl Monitor")

    assert_equal 1, @shop.subscriptions.active.count
    assert_equal "active", @shop.subscriptions.active.first.status
  end

  test "pending scope returns only pending subscriptions" do
    Subscription.create!(shop: @shop, status: "pending", charge_name: "Prowl Monitor")
    Subscription.create!(shop: @shop, status: "active", charge_name: "Prowl Monitor")

    assert_equal 1, @shop.subscriptions.pending.count
    assert_equal "pending", @shop.subscriptions.pending.first.status
  end

  test "pending scope with charge_name filter for dedup lookup" do
    Subscription.create!(shop: @shop, status: "pending", charge_name: "Prowl Monitor")
    Subscription.create!(shop: @shop, status: "pending", charge_name: "Other Plan")

    results = @shop.subscriptions.pending.where(charge_name: "Prowl Monitor")
    assert_equal 1, results.count
    assert_equal "Prowl Monitor", results.first.charge_name
  end

  # --- Instance methods ---

  test "activate! sets status and timestamps" do
    sub = Subscription.create!(shop: @shop, status: "pending")
    sub.activate!("gid://shopify/AppSubscription/456")

    assert_equal "active", sub.status
    assert_equal "gid://shopify/AppSubscription/456", sub.subscription_charge_id
    assert_not_nil sub.activated_at
  end

  test "cancel! sets status and cancelled_at" do
    sub = Subscription.create!(shop: @shop, status: "active")
    sub.cancel!

    assert_equal "cancelled", sub.status
    assert_not_nil sub.cancelled_at
  end

  test "expire! sets status to expired" do
    sub = Subscription.create!(shop: @shop, status: "pending")
    sub.expire!

    assert_equal "expired", sub.status
  end

  test "decline! sets status to declined" do
    sub = Subscription.create!(shop: @shop, status: "pending")
    sub.decline!

    assert_equal "declined", sub.status
  end

  test "active? returns true for active subscriptions" do
    sub = Subscription.new(status: "active")
    assert sub.active?
  end

  test "active? returns false for non-active subscriptions" do
    %w[pending cancelled expired declined].each do |status|
      sub = Subscription.new(status: status)
      assert_not sub.active?, "Expected '#{status}' to not be active"
    end
  end

  # --- Trial ---

  test "in_trial? returns true during trial period" do
    sub = Subscription.create!(
      shop: @shop,
      status: "active",
      trial_days: 14,
      activated_at: 1.day.ago
    )
    assert sub.in_trial?
  end

  test "in_trial? returns false after trial expires" do
    sub = Subscription.create!(
      shop: @shop,
      status: "active",
      trial_days: 14,
      activated_at: 15.days.ago
    )
    assert_not sub.in_trial?
  end

  test "in_trial? returns false without activated_at" do
    sub = Subscription.create!(shop: @shop, status: "pending", trial_days: 14)
    assert_not sub.in_trial?
  end

  test "trial_days_remaining returns correct count" do
    sub = Subscription.create!(
      shop: @shop,
      status: "active",
      trial_days: 14,
      activated_at: 10.days.ago
    )
    assert_equal 4, sub.trial_days_remaining
  end

  test "trial_days_remaining returns 0 when not in trial" do
    sub = Subscription.create!(shop: @shop, status: "pending")
    assert_equal 0, sub.trial_days_remaining
  end

  test "trial_ends_at calculates correctly" do
    activated = 3.days.ago
    sub = Subscription.create!(
      shop: @shop,
      status: "active",
      trial_days: 14,
      activated_at: activated
    )
    assert_in_delta (activated + 14.days).to_f, sub.trial_ends_at.to_f, 1.0
  end

  # --- Dedup pattern (used by BillingController#subscribe) ---

  test "most recent pending subscription is found first" do
    old = Subscription.create!(shop: @shop, status: "pending", charge_name: "Prowl Monitor", created_at: 2.hours.ago)
    recent = Subscription.create!(shop: @shop, status: "pending", charge_name: "Prowl Monitor", created_at: 1.minute.ago)

    found = @shop.subscriptions.pending.where(charge_name: "Prowl Monitor").order(created_at: :desc).first
    assert_equal recent.id, found.id
  end

  test "confirmation_url is stored and retrievable" do
    sub = Subscription.create!(
      shop: @shop,
      status: "pending",
      charge_name: "Prowl Monitor",
      confirmation_url: "https://admin.shopify.com/charges/confirm?id=123"
    )
    sub.reload
    assert_equal "https://admin.shopify.com/charges/confirm?id=123", sub.confirmation_url
  end

  test "updating status from pending to expired allows new subscription" do
    old = Subscription.create!(
      shop: @shop,
      status: "pending",
      charge_name: "Prowl Monitor",
      subscription_charge_id: "gid://shopify/AppSubscription/100"
    )
    old.update!(status: "expired")

    # No more pending subs for this plan
    assert_nil @shop.subscriptions.pending.where(charge_name: "Prowl Monitor").first

    # Can create a new one
    new_sub = Subscription.create!(
      shop: @shop,
      status: "pending",
      charge_name: "Prowl Monitor",
      subscription_charge_id: "gid://shopify/AppSubscription/200"
    )
    assert new_sub.persisted?
  end
end
