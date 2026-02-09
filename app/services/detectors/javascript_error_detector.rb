# frozen_string_literal: true

module Detectors
  # JavaScriptErrorDetector analyzes captured JS errors for issues that
  # could impact product page functionality and purchasing flow.
  #
  # Strategy:
  #   1. Filters out known third-party noise (analytics, pixels, chat widgets)
  #   2. Categorizes errors by relevance to purchasing flow
  #   3. Assigns severity based on error type and context
  #   4. Higher confidence when errors relate to cart/product/checkout
  #
  class JavascriptErrorDetector < BaseDetector
    # Patterns to ignore (third-party noise)
    IGNORE_PATTERNS = [
      /google[-_]?analytics/i,
      /googletagmanager/i,
      /gtag/i,
      /gtm\.js/i,
      /facebook/i,
      /fbevents/i,
      /fb\.js/i,
      /hotjar/i,
      /clarity\.ms/i,
      /doubleclick/i,
      /tiktok/i,
      /snapchat/i,
      /pinterest/i,
      /twitter/i,
      /linkedin/i,
      /hubspot/i,
      /intercom/i,
      /zendesk/i,
      /drift/i,
      /crisp/i,
      /tidio/i,
      /livechat/i,
      /favicon/i,
      /recaptcha/i,
      /cookie/i,
      /consent/i,
      /klaviyo/i,
      /mailchimp/i,
      /omnisend/i,
      /privy/i,
      /vitals\.co/i
    ].freeze

    # Patterns that indicate purchase-flow-critical errors
    CRITICAL_PATTERNS = [
      /cart/i,
      /add.?to.?cart/i,
      /checkout/i,
      /product/i,
      /variant/i,
      /price/i,
      /form/i,
      /submit/i,
      /payment/i,
      /shopify/i,
      /buy/i,
      /purchase/i,
      /quantity/i
    ].freeze

    # Patterns that indicate syntax errors (more severe)
    SYNTAX_ERROR_PATTERNS = [
      /SyntaxError/i,
      /ReferenceError/i,
      /TypeError/i,
      /Unexpected token/i,
      /is not defined/i,
      /is not a function/i,
      /Cannot read propert/i,
      /null is not an object/i,
      /undefined is not/i
    ].freeze

    def check_name
      "javascript_errors"
    end

    private

    def run_detection
      all_errors = browser_service.js_errors
      console_errors = browser_service.console_logs.select { |l| l[:type] == "error" }

      # Combine page errors and console errors
      combined_errors = all_errors.map { |e| e[:message].to_s } +
                        console_errors.map { |e| e[:text].to_s }

      # Filter out noise
      filtered_errors = combined_errors.reject { |msg| noise_error?(msg) }

      record_validation(filtered_errors.empty?) # pass if no errors

      if filtered_errors.empty?
        return pass_result(
          message: "No critical JavaScript errors detected",
          confidence: 0.9,
          evidence: {
            total_errors_captured: all_errors.length,
            console_errors_captured: console_errors.length,
            filtered_count: 0
          }
        )
      end

      # Categorize errors
      critical = filtered_errors.select { |msg| critical_error?(msg) }
      syntax = filtered_errors.select { |msg| syntax_error?(msg) }
      other = filtered_errors - critical - syntax

      record_validation(critical.empty?)
      record_validation(syntax.empty?)

      # Determine severity
      if critical.any? || syntax.any?
        severity_errors = (critical + syntax).uniq
        fail_result(
          message: "#{severity_errors.length} critical JavaScript error(s) detected that may affect purchasing",
          confidence: confidence_for_errors(critical, syntax, other),
          technical_details: {
            critical_errors: critical.first(5),
            syntax_errors: syntax.first(5),
            other_errors: other.first(3)
          },
          evidence: {
            total_errors: filtered_errors.length,
            critical_count: critical.length,
            syntax_count: syntax.length,
            other_count: other.length
          },
          suggestions: [
            "Review JavaScript console in browser DevTools for error details",
            "Check if recently installed apps are causing conflicts",
            "Verify theme JavaScript files are loading correctly"
          ]
        )
      else
        warning_result(
          message: "#{other.length} JavaScript error(s) detected (not directly purchase-related)",
          confidence: 0.7,
          technical_details: {
            errors: other.first(5)
          },
          evidence: {
            total_errors: filtered_errors.length,
            critical_count: 0,
            other_count: other.length
          },
          suggestions: [
            "Review these errors to ensure they don't affect customer experience"
          ]
        )
      end
    end

    def noise_error?(message)
      IGNORE_PATTERNS.any? { |pattern| message.match?(pattern) }
    end

    def critical_error?(message)
      CRITICAL_PATTERNS.any? { |pattern| message.match?(pattern) }
    end

    def syntax_error?(message)
      SYNTAX_ERROR_PATTERNS.any? { |pattern| message.match?(pattern) }
    end

    def confidence_for_errors(critical, syntax, other)
      # Higher confidence when we find purchase-critical errors
      if critical.any? && syntax.any?
        0.95
      elsif critical.any?
        0.85
      elsif syntax.any?
        0.8
      else
        0.7
      end
    end
  end
end
