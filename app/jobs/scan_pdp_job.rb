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
#   ScanPdpJob.perform_later(product_page_id, scan_depth: "deep")  # Force deep scan
#
class ScanPdpJob < ApplicationJob
  queue_as :scans

  RESCAN_DELAY = 30.minutes

  # Limit to 1 concurrent scan to prevent memory exhaustion from multiple browser instances
  limits_concurrency to: 1, key: ->(product_page_id, **) { "scan_pdp" }

  # Retry configuration
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(product_page_id, scan_depth: nil)
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

    # Determine scan depth
    depth = (scan_depth || determine_scan_depth(product_page)).to_sym

    Rails.logger.info("[ScanPdpJob] Starting #{depth} scan for product page #{product_page.id} (#{product_page.title})")

    # Perform the scan with detection engine
    scanner = ProductPageScanner.new(product_page, scan_depth: depth)
    result = scanner.perform

    if result[:success]
      Rails.logger.info("[ScanPdpJob] Scan completed for page #{product_page.id} with #{result[:detection_results].length} detection results")

      # Run detection service to create/update Issue records from detection results
      detector = DetectionService.new(result[:scan])
      issues = detector.perform

      Rails.logger.info("[ScanPdpJob] Detection found #{issues.length} issues")

      # AI analysis for all issues (explanation + suggested fix)
      # High-severity also gets visual confirmation via screenshot
      issues.each do |issue|
        begin
          ai_result = AiIssueAnalyzer.new(
            scan: result[:scan],
            issue: issue,
            product_page: product_page
          ).perform

          update_attrs = {
            ai_verified_at: Time.current
          }

          # All issues get explanation and suggested fix
          if ai_result[:merchant_explanation].present?
            update_attrs[:ai_explanation] = ai_result[:merchant_explanation]
          end
          if ai_result[:suggested_fix].present?
            update_attrs[:ai_suggested_fix] = ai_result[:suggested_fix]
          end

          # High-severity issues also get confirmation data
          if issue.high_severity? && ai_result.key?(:confirmed) && !ai_result[:confirmed].nil?
            update_attrs[:ai_confirmed] = ai_result[:confirmed]
            update_attrs[:ai_confidence] = ai_result[:confidence]
            update_attrs[:ai_reasoning] = ai_result[:reasoning]
          end

          issue.update!(update_attrs) if update_attrs.keys.length > 1
        rescue StandardError => e
          Rails.logger.error("[ScanPdpJob] AI analysis failed for issue #{issue.id}: #{e.message}")
          # Fail-open: continue without AI — alerts still work with hardcoded descriptions
        end
      end

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

      # Schedule a quick rescan to confirm new high-severity issues
      new_critical_issues = issues.select { |i| i.high_severity? && i.occurrence_count == 1 }
      if new_critical_issues.any?
        Rails.logger.info("[ScanPdpJob] Found #{new_critical_issues.length} new high severity issue(s). Scheduling rescan in #{RESCAN_DELAY.inspect}.")
        ScanPdpJob.set(wait: RESCAN_DELAY).perform_later(product_page_id)
      end
    else
      Rails.logger.warn("[ScanPdpJob] Scan failed for page #{product_page.id}: #{result[:error]}")
    end
  end

  private

  # Determines scan depth based on context:
  #   :deep  → First scan, open critical issues, Monday (weekly deep), or manual trigger
  #   :quick → Regular daily automated scans
  def determine_scan_depth(product_page)
    if product_page.scans.count == 0
      :deep # First scan ever — do a thorough check
    elsif product_page.issues.where(status: "open", severity: "high").any?
      :deep # Has open critical issues — re-verify thoroughly
    elsif Time.current.monday?
      :deep # Weekly deep scan day
    else
      :quick
    end
  end
end
