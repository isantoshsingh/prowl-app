# frozen_string_literal: true

require "test_helper"

class ScheduledScanJobTest < ActiveSupport::TestCase
  self.use_transactional_tests = true

  def setup
    @shop = Shop.create!(
      shopify_domain: "sched-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token",
      billing_exempt: true,
      subscription_status: "active",
      installed: true
    )

    @page = @shop.product_pages.create!(
      shopify_product_id: rand(100_000..999_999),
      handle: "test-product",
      title: "Test Product",
      url: "/products/test-product",
      monitoring_enabled: true,
      status: "pending"
    )

    # Track ScanPdpJob.perform_later calls without using ActiveJob test adapter
    @enqueued_page_ids = []
    ScanPdpJob.define_method(:perform) { |_page_id| } # no-op for perform_now fallback
  end

  private

  def perform_and_collect_enqueued
    enqueued = []
    original_method = ScanPdpJob.method(:perform_later)

    ScanPdpJob.define_singleton_method(:perform_later) do |page_id|
      enqueued << page_id
    end

    ScheduledScanJob.perform_now

    ScanPdpJob.define_singleton_method(:perform_later, &original_method)
    enqueued
  end

  public

  # --- Filtering shops ---

  test "queues scans for installed shops with active subscription" do
    @page.update!(last_scanned_at: 25.hours.ago)

    enqueued = perform_and_collect_enqueued
    assert_includes enqueued, @page.id
  end

  test "queues scans for installed billing-exempt shops" do
    @shop.update!(billing_exempt: true, subscription_status: "none")
    @page.update!(last_scanned_at: 25.hours.ago)

    enqueued = perform_and_collect_enqueued
    assert_includes enqueued, @page.id
  end

  test "skips uninstalled shops" do
    @shop.update!(installed: false)
    @page.update!(last_scanned_at: 25.hours.ago)

    enqueued = perform_and_collect_enqueued
    assert_empty enqueued
  end

  test "skips shops without active billing" do
    @shop.update!(billing_exempt: false, subscription_status: "none")
    @page.update!(last_scanned_at: 25.hours.ago)

    enqueued = perform_and_collect_enqueued
    assert_empty enqueued
  end

  # --- Scan frequency ---

  test "daily frequency queues pages not scanned in 24 hours" do
    @shop.shop_setting.update!(scan_frequency: "daily")
    @page.update!(last_scanned_at: 25.hours.ago)

    enqueued = perform_and_collect_enqueued
    assert_includes enqueued, @page.id
  end

  test "daily frequency skips pages scanned within 24 hours" do
    @shop.shop_setting.update!(scan_frequency: "daily")
    @page.update!(last_scanned_at: 12.hours.ago)

    enqueued = perform_and_collect_enqueued
    assert_empty enqueued
  end

  test "weekly frequency queues pages not scanned in 7 days" do
    @shop.shop_setting.update!(scan_frequency: "weekly")
    @page.update!(last_scanned_at: 8.days.ago)

    enqueued = perform_and_collect_enqueued
    assert_includes enqueued, @page.id
  end

  test "weekly frequency skips pages scanned within 7 days" do
    @shop.shop_setting.update!(scan_frequency: "weekly")
    @page.update!(last_scanned_at: 3.days.ago)

    enqueued = perform_and_collect_enqueued
    assert_empty enqueued
  end

  test "always queues pages never scanned regardless of frequency" do
    @shop.shop_setting.update!(scan_frequency: "weekly")
    @page.update!(last_scanned_at: nil)

    enqueued = perform_and_collect_enqueued
    assert_includes enqueued, @page.id
  end

  # --- Monitoring filter ---

  test "skips pages with monitoring disabled" do
    @page.update!(monitoring_enabled: false, last_scanned_at: 25.hours.ago)

    enqueued = perform_and_collect_enqueued
    assert_empty enqueued
  end
end
