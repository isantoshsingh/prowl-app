# frozen_string_literal: true

# DetectionService analyzes scan results and creates Issue records.
# It processes detection results from the new detector engine (confidence-scored)
# and falls back to legacy rule-based detection when detector results are unavailable.
#
# Detection priority:
#   1. Add-to-cart presence & clickability
#   2. JavaScript errors
#   3. Liquid errors
#   4. Price visibility
#   5. Image visibility
#   6. Variant selector (legacy, kept for compatibility)
#   7. Page load time
#
# Confidence-based filtering:
#   - Only creates issues for detections with confidence >= 0.7
#   - Issues only result in alerts after 2 occurrences (to avoid false positives)
#
class DetectionService
  SLOW_PAGE_THRESHOLD_MS = 5000 # 5 seconds
  CONFIDENCE_THRESHOLD = 0.7

  # Maps detector check names to issue types
  CHECK_TO_ISSUE_TYPE = {
    "add_to_cart" => "missing_add_to_cart",
    "atc_funnel" => "atc_not_functional",
    "checkout" => "checkout_broken",
    "variant_interaction" => "variant_selection_broken",
    "javascript_errors" => "js_error",
    "liquid_errors" => "liquid_error",
    "price_visibility" => "missing_price",
    "product_images" => "missing_images"
  }.freeze

  # Maps detector check names to issue severity
  CHECK_SEVERITY = {
    "add_to_cart" => "high",
    "atc_funnel" => "high",
    "checkout" => "high",
    "variant_interaction" => "high",
    "javascript_errors" => "high",
    "liquid_errors" => "medium",
    "price_visibility" => "high",
    "product_images" => "medium"
  }.freeze

  attr_reader :scan, :detected_issues

  def initialize(scan)
    @scan = scan
    @detected_issues = []
  end

  # Analyzes the scan and creates/updates issues
  # Returns array of Issue records
  def perform
    return [] unless scan.status == "completed"

    detection_results = scan.parsed_dom_checks_data

    if detection_results.any?
      process_detection_results(detection_results)
    else
      run_legacy_detection
    end

    # Always run these legacy checks (not covered by new detectors)
    detect_variant_selector_issues
    detect_slow_page_load

    # Update page status based on detected issues
    scan.product_page.update_status_from_issues!

    detected_issues
  end

  private

  def product_page
    scan.product_page
  end

  # Process structured results from the new detection engine
  def process_detection_results(results)
    results.each do |result|
      check = result["check"] || result[:check]
      status = result["status"] || result[:status]
      confidence = (result["confidence"] || result[:confidence]).to_f
      details = result["details"] || result[:details] || {}

      issue_type = CHECK_TO_ISSUE_TYPE[check]
      next unless issue_type

      message = details["message"] || details[:message] || ""
      evidence = build_evidence(result)

      case status
      when "fail"
        if confidence >= CONFIDENCE_THRESHOLD
          create_or_update_issue(
            issue_type: issue_type,
            severity: CHECK_SEVERITY[check] || "medium",
            title: Issue::ISSUE_TYPES.dig(issue_type, :title) || message.truncate(100),
            description: message,
            evidence: evidence
          )
        else
          Rails.logger.info("[DetectionService] Low confidence #{check} failure (#{confidence}), logging but not creating issue")
        end
      when "warning"
        if confidence >= CONFIDENCE_THRESHOLD
          create_or_update_issue(
            issue_type: issue_type,
            severity: "low",
            title: Issue::ISSUE_TYPES.dig(issue_type, :title) || message.truncate(100),
            description: message,
            evidence: evidence
          )
        end
      when "pass"
        resolve_existing_issue(issue_type)
      when "inconclusive"
        # Don't resolve or create - leave existing state unchanged
        Rails.logger.info("[DetectionService] Inconclusive result for #{check}, skipping")
      end
    end
  end

  def build_evidence(result)
    details = result["details"] || result[:details] || {}
    {
      confidence: result["confidence"] || result[:confidence],
      technical_details: details["technical_details"] || details[:technical_details] || {},
      suggestions: details["suggestions"] || details[:suggestions] || [],
      evidence: details["evidence"] || details[:evidence] || {},
      scan_id: scan.id
    }
  end

  # Legacy detection methods - used when detection engine results are unavailable

  def run_legacy_detection
    detect_missing_add_to_cart
    detect_js_errors
    detect_liquid_errors
    detect_missing_images
    detect_missing_price
  end

  def detect_missing_add_to_cart
    js_errors = scan.parsed_js_errors
    atc_error = js_errors.any? { |e| e["message"]&.include?("cart") || e["message"]&.include?("addToCart") }

    html = scan.html_snapshot || ""
    has_atc = html.include?('name="add"') ||
              html.include?("add-to-cart") ||
              html.include?("AddToCart") ||
              html.include?("product-form__submit")

    if atc_error || !has_atc
      create_or_update_issue(
        issue_type: "missing_add_to_cart",
        severity: "high",
        title: "Add to Cart button may not be working",
        description: "We couldn't verify that the Add to Cart button is functioning. This may prevent customers from making purchases.",
        evidence: {
          has_atc_button: has_atc,
          js_errors_related: atc_error,
          scan_id: scan.id,
          detection_method: "legacy"
        }
      )
    else
      resolve_existing_issue("missing_add_to_cart")
    end
  end

  def detect_variant_selector_issues
    js_errors = scan.parsed_js_errors
    variant_error = js_errors.any? { |e|
      msg = e["message"].to_s.downcase
      msg.include?("variant") || msg.include?("option") || msg.include?("swatch")
    }

    if variant_error
      create_or_update_issue(
        issue_type: "variant_selector_error",
        severity: "high",
        title: "Variant selector may have issues",
        description: "We detected errors that may affect the product variant selector. Customers might have trouble selecting product options.",
        evidence: {
          related_errors: js_errors.select { |e|
            msg = e["message"].to_s.downcase
            msg.include?("variant") || msg.include?("option")
          },
          scan_id: scan.id
        }
      )
    else
      resolve_existing_issue("variant_selector_error")
    end
  end

  def detect_js_errors
    js_errors = scan.parsed_js_errors

    critical_errors = js_errors.reject do |error|
      msg = error["message"].to_s.downcase
      msg.include?("favicon") ||
        msg.include?("analytics") ||
        msg.include?("pixel") ||
        msg.include?("gtm") ||
        msg.include?("hotjar")
    end

    if critical_errors.any?
      create_or_update_issue(
        issue_type: "js_error",
        severity: "high",
        title: "JavaScript errors detected",
        description: "We found JavaScript errors on this page that may affect functionality.",
        evidence: {
          error_count: critical_errors.length,
          errors: critical_errors.first(5),
          scan_id: scan.id,
          detection_method: "legacy"
        }
      )
    else
      resolve_existing_issue("js_error")
    end
  end

  def detect_liquid_errors
    html = scan.html_snapshot || ""

    liquid_errors = []
    liquid_errors << "Liquid error detected" if html.include?("Liquid error")
    liquid_errors << "Translation missing" if html.include?("Translation missing")
    liquid_errors << "No template found" if html.include?("No template found")

    if liquid_errors.any?
      create_or_update_issue(
        issue_type: "liquid_error",
        severity: "medium",
        title: "Liquid template errors detected",
        description: "We found template errors that may cause content to display incorrectly.",
        evidence: {
          errors: liquid_errors,
          scan_id: scan.id,
          detection_method: "legacy"
        }
      )
    else
      resolve_existing_issue("liquid_error")
    end
  end

  def detect_missing_images
    network_errors = scan.parsed_network_errors

    image_failures = network_errors.select do |error|
      type = error["resource_type"].to_s.downcase
      url = error["url"].to_s.downcase
      type == "image" || url.match?(/\.(jpg|jpeg|png|gif|webp|avif)/)
    end

    if image_failures.any?
      create_or_update_issue(
        issue_type: "missing_images",
        severity: "medium",
        title: "Product images may not be loading",
        description: "Some product images failed to load. Customers may not see all product photos.",
        evidence: {
          failed_images: image_failures.first(5).map { |e| e["url"] },
          failure_count: image_failures.length,
          scan_id: scan.id,
          detection_method: "legacy"
        }
      )
    else
      resolve_existing_issue("missing_images")
    end
  end

  def detect_missing_price
    html = scan.html_snapshot || ""

    has_price = html.include?("price") ||
                html.include?("money") ||
                html.match?(/\$[\d,]+\.?\d*/) ||
                html.match?(/€[\d,]+\.?\d*/) ||
                html.match?(/£[\d,]+\.?\d*/)

    unless has_price
      create_or_update_issue(
        issue_type: "missing_price",
        severity: "high",
        title: "Price may not be visible",
        description: "We couldn't find a visible price on this page. Customers may be confused about the cost.",
        evidence: {
          scan_id: scan.id,
          detection_method: "legacy"
        }
      )
    else
      resolve_existing_issue("missing_price")
    end
  end

  def detect_slow_page_load
    load_time = scan.page_load_time_ms || 0

    if load_time > SLOW_PAGE_THRESHOLD_MS
      create_or_update_issue(
        issue_type: "slow_page_load",
        severity: "low",
        title: "Page is loading slowly",
        description: "This page took #{(load_time / 1000.0).round(1)} seconds to load. This may affect customer experience.",
        evidence: {
          load_time_ms: load_time,
          threshold_ms: SLOW_PAGE_THRESHOLD_MS,
          scan_id: scan.id
        }
      )
    else
      resolve_existing_issue("slow_page_load")
    end
  end

  def create_or_update_issue(issue_type:, severity:, title:, description:, evidence:)
    existing = product_page.issues.where(issue_type: issue_type, status: ["open", "acknowledged"]).first

    if existing
      merged_issue = existing.merge_new_detection!(
        scan: scan,
        new_severity: severity,
        new_title: title,
        new_description: description,
        new_evidence: evidence
      )

      if merged_issue
        detected_issues << merged_issue
      else
        # De-escalation occurred (old issue was resolved), so we create a new one for the lower severity
        create_new_issue(issue_type: issue_type, severity: severity, title: title, description: description, evidence: evidence)
      end
    else
      create_new_issue(issue_type: issue_type, severity: severity, title: title, description: description, evidence: evidence)
    end
  end

  def create_new_issue(issue_type:, severity:, title:, description:, evidence:)
    issue = product_page.issues.create!(
      scan: scan,
      issue_type: issue_type,
      severity: severity,
      title: title,
      description: description,
      evidence: evidence,
      occurrence_count: 1,
      first_detected_at: Time.current,
      last_detected_at: Time.current,
      status: "open"
    )
    detected_issues << issue
  end

  def resolve_existing_issue(issue_type)
    product_page.issues.where(issue_type: issue_type, status: ["open", "acknowledged"]).find_each do |issue|
      issue.resolve!
    end
  end
end
