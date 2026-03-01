# frozen_string_literal: true

# ScanPipelineService orchestrates the post-scan analysis pipeline.
# Extracted from ScanPdpJob to keep the job thin and each step testable.
#
# Pipeline steps:
#   1. Programmatic detection (DetectionService)
#   2. AI page-level analysis (Gemini screenshot analysis)
#   3. Per-issue AI explanation/confirmation
#   4. Alerting for qualified issues
#   5. Rescan scheduling for unconfirmed critical issues
#
# Design: fail-open — AI failures don't block programmatic detection or alerting.
#
class ScanPipelineService
  RESCAN_DELAY = 30.minutes

  attr_reader :scan, :product_page, :result, :issues

  def initialize(scan_result:, product_page:)
    @result = scan_result
    @scan = scan_result[:scan]
    @product_page = product_page
    @issues = []
  end

  def perform
    run_programmatic_detection
    run_ai_page_analysis
    run_per_issue_ai_analysis
    send_alerts
    schedule_rescan_if_needed

    issues
  end

  private

  # Step 1: Run detection service to create/update Issue records from programmatic results
  def run_programmatic_detection
    detector = DetectionService.new(scan)
    @issues = detector.perform

    Rails.logger.info("[ScanPipeline] Programmatic detection found #{issues.length} issues")
  end

  # Step 2: AI page-level analysis (primary detection)
  # Send screenshot + programmatic results to Gemini to find ALL issues
  def run_ai_page_analysis
    screenshot_data = download_screenshot
    return unless screenshot_data

    analyzer = AiIssueAnalyzer.new(scan: scan, issue: nil, product_page: product_page)
    ai_result = analyzer.analyze_page(
      detection_results: result[:detection_results],
      screenshot_data: screenshot_data
    )

    findings = ai_result[:findings] || []
    Rails.logger.info("[ScanPipeline] AI page analysis found #{findings.length} issues (#{findings.count { |f| f[:new_finding] }} new)")

    store_ai_summary(ai_result) if ai_result[:summary].present?
    process_ai_findings(findings)
  rescue StandardError => e
    Rails.logger.error("[ScanPipeline] AI page analysis failed: #{e.message}")
    # Fail-open: programmatic detection continues to work
  end

  # Step 3: Per-issue AI analysis (explanation + confirmation for remaining issues)
  def run_per_issue_ai_analysis
    issues.each do |issue|
      next if issue.ai_verified_at.present?

      analyze_single_issue(issue)
    end
  end

  # Step 4: Send alerts for any alertable issues (AI-confirmed = immediate)
  def send_alerts
    issues.each do |issue|
      issue.reload
      next unless issue.should_alert?

      begin
        AlertService.new(issue).perform
      rescue StandardError => e
        Rails.logger.error("[ScanPipeline] AlertService failed for issue #{issue.id}: #{e.message}")
      end
    end
  end

  # Step 5: Schedule rescan only for non-AI-confirmed critical issues
  # AI-confirmed issues already alerted — no need to wait for rescan
  def schedule_rescan_if_needed
    unconfirmed_critical = issues.select { |i| i.high_severity? && i.occurrence_count == 1 && !i.ai_confirmed? }
    return unless unconfirmed_critical.any?

    Rails.logger.info("[ScanPipeline] Found #{unconfirmed_critical.length} unconfirmed high severity issue(s). Scheduling rescan in #{RESCAN_DELAY.inspect}.")
    ScanPdpJob.set(wait: RESCAN_DELAY).perform_later(product_page.id)
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  def download_screenshot
    return nil unless scan.screenshot_url.present?

    ScreenshotUploader.new.download(scan.screenshot_url)
  rescue StandardError => e
    Rails.logger.warn("[ScanPipeline] Screenshot download for AI analysis failed: #{e.message}")
    nil
  end

  def store_ai_summary(ai_result)
    scan.update(funnel_results: (scan.funnel_results || {}).merge(
      "ai_summary" => ai_result[:summary],
      "ai_page_healthy" => ai_result[:page_healthy],
      "ai_findings_count" => ai_result[:findings]&.length || 0
    ))
  end

  def process_ai_findings(findings)
    ai_issues = []

    findings.each do |finding|
      existing = issues.find { |i| i.issue_type == finding[:issue_type] }

      if existing
        confirm_existing_issue(existing, finding)
      elsif finding[:new_finding]
        issue = create_ai_detected_issue(finding)
        ai_issues << issue if issue
      end
    end

    issues.concat(ai_issues)
    product_page.update_status_from_issues! if ai_issues.any?
  end

  def confirm_existing_issue(issue, finding)
    issue.update!(
      ai_confirmed: true,
      ai_confidence: finding[:confidence],
      ai_reasoning: finding[:description],
      ai_explanation: finding[:merchant_explanation],
      ai_suggested_fix: finding[:suggested_fix],
      ai_verified_at: Time.current
    )
    Rails.logger.info("[ScanPipeline] AI confirmed programmatic finding: #{finding[:issue_type]}")
  end

  def create_ai_detected_issue(finding)
    product_page.issues.create!(
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
  rescue StandardError => e
    Rails.logger.error("[ScanPipeline] Failed to create AI-detected issue #{finding[:issue_type]}: #{e.message}")
    nil
  end

  def analyze_single_issue(issue)
    ai_result = AiIssueAnalyzer.new(
      scan: scan,
      issue: issue,
      product_page: product_page
    ).perform

    update_attrs = { ai_verified_at: Time.current }

    if ai_result[:merchant_explanation].present?
      update_attrs[:ai_explanation] = ai_result[:merchant_explanation]
    end
    if ai_result[:suggested_fix].present?
      update_attrs[:ai_suggested_fix] = ai_result[:suggested_fix]
    end

    if issue.high_severity? && ai_result.key?(:confirmed) && !ai_result[:confirmed].nil?
      update_attrs[:ai_confirmed] = ai_result[:confirmed]
      update_attrs[:ai_confidence] = ai_result[:confidence]
      update_attrs[:ai_reasoning] = ai_result[:reasoning]
    elsif issue.high_severity? && issue.evidence["confidence"].to_f >= 0.85
      update_attrs[:ai_confirmed] = true
      update_attrs[:ai_confidence] = issue.evidence["confidence"].to_f
      update_attrs[:ai_reasoning] = "Programmatic detection found this issue with #{issue.evidence['confidence']} confidence. AI visual confirmation was unavailable or skipped."
    end

    issue.update!(update_attrs) if update_attrs.keys.length > 1
  rescue StandardError => e
    Rails.logger.error("[ScanPipeline] AI analysis failed for issue #{issue.id}: #{e.message}")
  end
end
