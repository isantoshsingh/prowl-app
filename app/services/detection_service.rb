# frozen_string_literal: true

# DetectionService analyzes scan results and creates Issue records.
# It uses rule-based detection to identify problems on product pages.
#
# Detection priority (per agent.md):
#   1. Add-to-cart presence & clickability
#   2. Variant selector working
#   3. JS errors on load
#   4. Liquid errors
#   5. Image visibility
#   6. Page load time
#
# Issues only result in alerts after 2 occurrences (to avoid false positives).
#
class DetectionService
  SLOW_PAGE_THRESHOLD_MS = 5000 # 5 seconds

  attr_reader :scan, :detected_issues

  def initialize(scan)
    @scan = scan
    @detected_issues = []
  end

  # Analyzes the scan and creates/updates issues
  # Returns array of Issue records
  def perform
    return [] unless scan.status == "completed"

    # Run all detection rules
    detect_missing_add_to_cart
    detect_variant_selector_issues
    detect_js_errors
    detect_liquid_errors
    detect_missing_images
    detect_missing_price
    detect_slow_page_load

    # Update page status based on detected issues
    scan.product_page.update_status_from_issues!

    detected_issues
  end

  private

  def product_page
    scan.product_page
  end

  def dom_checks
    @dom_checks ||= scan.html_snapshot.present? ? (JSON.parse(scan.html_snapshot.to_s.match(/\A\{.*\}\z/m)&.to_s || "{}") rescue {}) : {}
  end

  # Safely get dom_checks from the scan's stored data
  # Note: In actual implementation, dom_checks would be stored separately
  # For now, we'll check the scan's captured data directly
  def get_dom_check(key)
    # DOM checks are stored in memory during scan - retrieve from serialized data if available
    return nil unless scan.respond_to?(:dom_checks_data)
    scan.dom_checks_data&.dig(key.to_s)
  end

  def detect_missing_add_to_cart
    # Check if ATC button is present and functional
    # We rely on dom_checks captured during scan
    # For simplicity, check if JS errors contain ATC-related issues
    
    js_errors = scan.parsed_js_errors
    atc_error = js_errors.any? { |e| e["message"]&.include?("cart") || e["message"]&.include?("addToCart") }
    
    # Check HTML for ATC button presence
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
          scan_id: scan.id
        }
      )
    else
      # Resolve any existing open issues of this type
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

    # Filter out known non-critical errors
    critical_errors = js_errors.reject do |error|
      msg = error["message"].to_s.downcase
      # Ignore common non-critical errors
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
          errors: critical_errors.first(5), # Limit to first 5
          scan_id: scan.id
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
          scan_id: scan.id
        }
      )
    else
      resolve_existing_issue("liquid_error")
    end
  end

  def detect_missing_images
    network_errors = scan.parsed_network_errors
    
    # Check for failed image requests
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
          scan_id: scan.id
        }
      )
    else
      resolve_existing_issue("missing_images")
    end
  end

  def detect_missing_price
    html = scan.html_snapshot || ""
    
    # Check for price-related elements
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
          scan_id: scan.id
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
    # Look for existing open issue of this type for this page
    existing = product_page.issues.where(issue_type: issue_type, status: ["open", "acknowledged"]).first

    if existing
      # Update occurrence count
      existing.record_occurrence!(scan)
      detected_issues << existing
    else
      # Create new issue
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
  end

  def resolve_existing_issue(issue_type)
    existing = product_page.issues.where(issue_type: issue_type, status: "open").first
    existing&.resolve!
  end
end
