# frozen_string_literal: true

module Detectors
  # LiquidErrorDetector searches the page HTML for Liquid template errors
  # that indicate rendering problems in the Shopify theme.
  #
  # Detection patterns:
  #   - "Liquid error" (runtime errors)
  #   - "Liquid syntax error" (template syntax problems)
  #   - "undefined method" (Liquid object access errors)
  #   - "could not find asset" (missing asset references)
  #   - "Liquid warning" (non-fatal warnings)
  #   - "Translation missing" (i18n issues)
  #   - "No template found" (missing snippet/section)
  #
  class LiquidErrorDetector < BaseDetector
    # Patterns to search for in page HTML
    ERROR_PATTERNS = {
      liquid_error: {
        pattern: /Liquid error(?:\s*:\s*|\s+)([^<\n]{0,200})/i,
        severity: :high,
        label: "Liquid error"
      },
      liquid_syntax_error: {
        pattern: /Liquid syntax error(?:\s*:\s*|\s+)([^<\n]{0,200})/i,
        severity: :high,
        label: "Liquid syntax error"
      },
      undefined_method: {
        pattern: /undefined method\s+['`]([^'`]+)[`']/i,
        severity: :medium,
        label: "Undefined method"
      },
      missing_asset: {
        pattern: /could not find asset\s+['"]?([^'"<\n]{0,200})/i,
        severity: :medium,
        label: "Missing asset"
      },
      liquid_warning: {
        pattern: /Liquid warning(?:\s*:\s*|\s+)([^<\n]{0,200})/i,
        severity: :low,
        label: "Liquid warning"
      },
      translation_missing: {
        pattern: /translation missing:\s*([^<\n]{0,200})/i,
        severity: :low,
        label: "Translation missing"
      },
      no_template: {
        pattern: /No template found\s*(?:for\s+)?([^<\n]{0,200})/i,
        severity: :medium,
        label: "No template found"
      }
    }.freeze

    def check_name
      "liquid_errors"
    end

    private

    def run_detection
      html = page_html

      if html.blank?
        return inconclusive_result("Could not retrieve page HTML for Liquid error detection")
      end

      # Also check via JavaScript to detect errors in rendered vs hidden content
      js_result = evaluate(liquid_error_script)

      found_errors = scan_for_errors(html)
      visible_errors = js_result&.dig("visible_errors") || []

      # Merge JS-detected visible errors
      visible_errors.each do |ve|
        found_errors << {
          type: :visible_liquid_error,
          label: "Visible Liquid error",
          severity: :high,
          match: ve,
          visible: true
        }
      end

      found_errors.uniq! { |e| e[:match] }

      no_errors_found = record_validation(found_errors.empty?)
      no_high_severity = record_validation(found_errors.none? { |e| e[:severity] == :high })
      no_visible_errors = record_validation(visible_errors.empty?)

      if found_errors.empty?
        return pass_result(
          message: "No Liquid template errors detected",
          confidence: 0.9,
          evidence: { errors_found: 0 }
        )
      end

      high_severity = found_errors.select { |e| e[:severity] == :high }
      medium_severity = found_errors.select { |e| e[:severity] == :medium }
      low_severity = found_errors.select { |e| e[:severity] == :low }

      if high_severity.any?
        fail_result(
          message: "#{found_errors.length} Liquid template error(s) detected, #{high_severity.length} critical",
          confidence: confidence_for_liquid_errors(found_errors, visible_errors),
          technical_details: {
            errors: found_errors.first(10).map { |e| { type: e[:label], detail: e[:match].to_s.truncate(200), visible: e[:visible] || false } }
          },
          evidence: {
            total_errors: found_errors.length,
            high_severity_count: high_severity.length,
            medium_severity_count: medium_severity.length,
            low_severity_count: low_severity.length,
            visible_error_count: visible_errors.length
          },
          suggestions: [
            "Check your theme's Liquid templates for syntax errors",
            "Verify all referenced objects and variables exist",
            "Review recent theme changes that may have introduced errors"
          ]
        )
      elsif medium_severity.any?
        warning_result(
          message: "#{found_errors.length} Liquid template issue(s) detected",
          confidence: confidence_for_liquid_errors(found_errors, visible_errors),
          technical_details: {
            errors: found_errors.first(10).map { |e| { type: e[:label], detail: e[:match].to_s.truncate(200) } }
          },
          evidence: {
            total_errors: found_errors.length,
            medium_severity_count: medium_severity.length,
            low_severity_count: low_severity.length
          },
          suggestions: [
            "Review missing assets and templates referenced in your theme"
          ]
        )
      else
        warning_result(
          message: "#{low_severity.length} minor Liquid template warning(s) detected",
          confidence: 0.7,
          technical_details: {
            warnings: low_severity.first(5).map { |e| { type: e[:label], detail: e[:match].to_s.truncate(200) } }
          },
          evidence: {
            total_warnings: low_severity.length
          }
        )
      end
    end

    def scan_for_errors(html)
      found = []

      ERROR_PATTERNS.each do |type, config|
        html.scan(config[:pattern]).each do |match|
          match_text = match.is_a?(Array) ? match.first : match
          found << {
            type: type,
            label: config[:label],
            severity: config[:severity],
            match: match_text.to_s.strip
          }
        end
      end

      found
    end

    def confidence_for_liquid_errors(errors, visible_errors)
      if visible_errors.any?
        0.95 # Very confident when errors are visually apparent
      elsif errors.any? { |e| e[:severity] == :high }
        0.85
      else
        0.75
      end
    end

    def liquid_error_script
      <<~JAVASCRIPT
        () => {
          const body = document.body;
          if (!body) return { visible_errors: [] };

          const walker = document.createTreeWalker(
            body,
            NodeFilter.SHOW_TEXT,
            null,
            false
          );

          const visibleErrors = [];
          let node;

          while (node = walker.nextNode()) {
            const text = node.textContent || '';
            if (text.match(/Liquid error|Liquid syntax error|Translation missing/i)) {
              // Check if this text node is actually visible
              const parent = node.parentElement;
              if (parent) {
                const style = window.getComputedStyle(parent);
                const rect = parent.getBoundingClientRect();
                if (style.display !== 'none' && style.visibility !== 'hidden' && rect.height > 0) {
                  visibleErrors.push(text.trim().substring(0, 200));
                }
              }
            }
          }

          return { visible_errors: visibleErrors.slice(0, 10) };
        }
      JAVASCRIPT
    end
  end
end
