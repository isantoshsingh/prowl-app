# frozen_string_literal: true

# ScheduledScanJob runs daily to queue scans for all monitored product pages.
# This job should be scheduled to run once per day via Solid Queue recurring jobs.
#
# Usage:
#   ScheduledScanJob.perform_later
#
class ScheduledScanJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info("[ScheduledScanJob] Starting daily scan scheduling")

    # Find all shops with active billing
    active_shops = Shop.joins(:shop_setting)
                       .where(shop_settings: { billing_status: %w[trial active] })

    scans_queued = 0

    active_shops.find_each do |shop|
      # Check if trial is still valid
      next unless shop.billing_active?

      # Get pages that need scanning
      pages_to_scan = shop.product_pages.needs_scan

      pages_to_scan.find_each do |page|
        ScanPdpJob.perform_later(page.id)
        scans_queued += 1
      end
    end

    Rails.logger.info("[ScheduledScanJob] Queued #{scans_queued} scans for #{active_shops.count} shops")
  end
end
