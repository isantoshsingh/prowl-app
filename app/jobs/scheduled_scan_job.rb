# frozen_string_literal: true

# ScheduledScanJob queues scans for all monitored product pages.
# Runs frequently (every hour) so that Monitor plan shops get 6-hour scans
# while Free plan shops get daily scans. The per-shop interval is determined
# by BillingPlanService.
#
class ScheduledScanJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info("[ScheduledScanJob] Starting scan scheduling")

    # All installed shops can be scanned — Free plan shops are included.
    # Billing-exempt shops and shops with active subscriptions get scanned.
    # Free plan shops (no subscription) also get scanned at their plan interval.
    active_shops = Shop.installed

    scans_queued = 0

    active_shops.find_each do |shop|
      scan_interval = BillingPlanService.scan_interval_for(shop).hours

      pages_to_scan = shop.product_pages.needs_scan_within(scan_interval)

      pages_to_scan.find_each do |page|
        ScanPdpJob.perform_later(page.id)
        scans_queued += 1
      end
    end

    Rails.logger.info("[ScheduledScanJob] Queued #{scans_queued} scans")
  end
end
