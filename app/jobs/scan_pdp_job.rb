# frozen_string_literal: true

# ScanPdpJob performs a single PDP scan using the ProductPageScanner.
# This job is queued by ScheduledScanJob for each product page that needs scanning.
#
# The scan flow:
#   1. ProductPageScanner launches BrowserService and navigates to page
#   2. All Tier 1 detectors run with confidence scoring
#   3. DetectionService processes results and creates/updates Issue records
#   4. AlertService sends notifications for alertable issues
#
# Usage:
#   ScanPdpJob.perform_later(product_page_id)
#
class ScanPdpJob < ApplicationJob
  queue_as :scans

  # Retry configuration
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(product_page_id)
    product_page = ProductPage.find(product_page_id)
    shop = product_page.shop

    # Skip if shop doesn't have active billing
    unless shop.billing_active?
      Rails.logger.info("[ScanPdpJob] Skipping scan for shop #{shop.id} - billing not active")
      return
    end

    # Skip if monitoring is disabled for this page
    unless product_page.monitoring_enabled?
      Rails.logger.info("[ScanPdpJob] Skipping scan for page #{product_page.id} - monitoring disabled")
      return
    end

    Rails.logger.info("[ScanPdpJob] Starting scan for product page #{product_page.id} (#{product_page.title})")

    # Perform the scan with detection engine
    scanner = ProductPageScanner.new(product_page)
    result = scanner.perform

    if result[:success]
      Rails.logger.info("[ScanPdpJob] Scan completed for page #{product_page.id} with #{result[:detection_results].length} detection results")

      # Run detection service to create/update Issue records from detection results
      detector = DetectionService.new(result[:scan])
      issues = detector.perform

      Rails.logger.info("[ScanPdpJob] Detection found #{issues.length} issues")

      # Send alerts for any alertable issues
      issues.each do |issue|
        if issue.should_alert?
          begin
            AlertService.new(issue).perform
          rescue StandardError => e
            Rails.logger.error("[ScanPdpJob] AlertService failed for issue #{issue.id}: #{e.message}")
          end
        end
      end
    else
      Rails.logger.warn("[ScanPdpJob] Scan failed for page #{product_page.id}: #{result[:error]}")
    end
  end
end
