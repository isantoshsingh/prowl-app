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

      # Step 1: Run detection service to create/update Issue records from programmatic results
      detector = DetectionService.new(result[:scan])
      issues = detector.perform

      Rails.logger.info("[ScanPdpJob] Programmatic detection found #{issues.length} issues")

      # Step 2: AI page-level analysis (primary detection)
      # Send screenshot + programmatic results → Gemini finds ALL issues
      ai_page_issues = run_ai_page_analysis(result, product_page, issues)
      issues.concat(ai_page_issues)

      # Step 3: Per-issue AI analysis (explanation + confirmation for remaining issues)
      issues.each do |issue|
        # Skip if AI already provided explanation during page analysis
        next if issue.ai_verified_at.present?

        begin
          ai_result = AiIssueAnalyzer.new(
            scan: result[:scan],
            issue: issue,
            product_page: product_page
          ).perform

          update_attrs = {
            ai_verified_at: Time.current
          }

          if ai_result[:merchant_explanation].present?
            update_attrs[:ai_explanation] = ai_result[:merchant_explanation]
          end
          if ai_result[:suggested_fix].present?
            update_attrs[:ai_suggested_fix] = ai_result[:suggested_fix]
          end

          # High-severity issues get confirmation data
          if issue.high_severity? && ai_result.key?(:confirmed) && !ai_result[:confirmed].nil?
            update_attrs[:ai_confirmed] = ai_result[:confirmed]
            update_attrs[:ai_confidence] = ai_result[:confidence]
            update_attrs[:ai_reasoning] = ai_result[:reasoning]
          end

          issue.update!(update_attrs) if update_attrs.keys.length > 1
        rescue StandardError => e
          Rails.logger.error("[ScanPdpJob] AI analysis failed for issue #{issue.id}: #{e.message}")
        end
      end

      # Step 4: Send alerts for any alertable issues (AI-confirmed = immediate)
      issues.each do |issue|
        issue.reload # Pick up AI updates
        if issue.should_alert?
          begin
            AlertService.new(issue).perform
          rescue StandardError => e
            Rails.logger.error("[ScanPdpJob] AlertService failed for issue #{issue.id}: #{e.message}")
          end
        end
      end

      # Step 5: Schedule rescan only for non-AI-confirmed critical issues
      # AI-confirmed issues already alerted — no need to wait for rescan
      unconfirmed_critical = issues.select { |i| i.high_severity? && i.occurrence_count == 1 && !i.ai_confirmed? }
      if unconfirmed_critical.any?
        Rails.logger.info("[ScanPdpJob] Found #{unconfirmed_critical.length} unconfirmed high severity issue(s). Scheduling rescan in #{RESCAN_DELAY.inspect}.")
        ScanPdpJob.set(wait: RESCAN_DELAY).perform_later(product_page_id)
      end
    else
      Rails.logger.warn("[ScanPdpJob] Scan failed for page #{product_page.id}: #{result[:error]}")
    end
  end

  private

  # Runs AI page-level analysis: sends screenshot to Gemini to find ALL issues.
  # Returns array of Issue records created from AI-only findings.
  def run_ai_page_analysis(result, product_page, existing_issues)
    scan = result[:scan]
    ai_issues = []

    # Download screenshot for AI analysis
    screenshot_data = nil
    if scan.screenshot_url.present?
      begin
        screenshot_data = ScreenshotUploader.new.download(scan.screenshot_url)
      rescue StandardError => e
        Rails.logger.warn("[ScanPdpJob] Screenshot download for AI analysis failed: #{e.message}")
      end
    end

    return ai_issues unless screenshot_data

    # Call AI page analysis
    begin
      analyzer = AiIssueAnalyzer.new(scan: scan, issue: nil, product_page: product_page)
      ai_result = analyzer.analyze_page(
        detection_results: result[:detection_results],
        screenshot_data: screenshot_data
      )

      findings = ai_result[:findings] || []
      Rails.logger.info("[ScanPdpJob] AI page analysis found #{findings.length} issues (#{findings.count { |f| f[:new_finding] }} new)")

      # Store AI summary on the scan
      if ai_result[:summary].present?
        scan.update(funnel_results: (scan.funnel_results || {}).merge(
          "ai_summary" => ai_result[:summary],
          "ai_page_healthy" => ai_result[:page_healthy],
          "ai_findings_count" => findings.length
        ))
      end

      findings.each do |finding|
        # Check if programmatic detection already created this issue
        existing = existing_issues.find { |i| i.issue_type == finding[:issue_type] }

        if existing
          # AI confirms the programmatic finding → apply confirmation
          existing.update!(
            ai_confirmed: true,
            ai_confidence: finding[:confidence],
            ai_reasoning: finding[:description],
            ai_explanation: finding[:merchant_explanation],
            ai_suggested_fix: finding[:suggested_fix],
            ai_verified_at: Time.current
          )
          Rails.logger.info("[ScanPdpJob] AI confirmed programmatic finding: #{finding[:issue_type]}")
        elsif finding[:new_finding]
          # AI found something code missed → create new issue
          issue = product_page.issues.create!(
            scan: scan,
            issue_type: finding[:issue_type],
            severity: finding[:severity],
            title: Issue::ISSUE_TYPES.dig(finding[:issue_type], :title) || finding[:description]&.truncate(100),
            description: finding[:description],
            evidence: {
              ai_detected: true,
              ai_confidence: finding[:confidence],
              scan_id: scan.id
            },
            occurrence_count: 1,
            first_detected_at: Time.current,
            last_detected_at: Time.current,
            status: "open",
            ai_confirmed: true,
            ai_confidence: finding[:confidence],
            ai_reasoning: finding[:description],
            ai_explanation: finding[:merchant_explanation],
            ai_suggested_fix: finding[:suggested_fix],
            ai_verified_at: Time.current
          )
          ai_issues << issue
          Rails.logger.info("[ScanPdpJob] AI detected new issue: #{finding[:issue_type]} (conf: #{finding[:confidence]})")
        end
      end
    rescue StandardError => e
      Rails.logger.error("[ScanPdpJob] AI page analysis failed: #{e.message}")
      # Fail-open: programmatic detection continues to work
    end

    # Update page status if AI issues were created
    product_page.update_status_from_issues! if ai_issues.any?

    ai_issues
  end

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
