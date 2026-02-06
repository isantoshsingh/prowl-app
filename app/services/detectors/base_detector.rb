# frozen_string_literal: true

module Detectors
  # BaseDetector provides the foundation for all detection checks.
  # Each detector evaluates a specific aspect of a product page and returns
  # a standardized DetectionResult with confidence scoring.
  #
  # Subclasses must implement:
  #   - #check_name (string identifier for this check)
  #   - #run_detection (performs the actual check, returns raw findings)
  #
  # Result structure:
  #   {
  #     check: "add_to_cart",
  #     status: "pass" | "fail" | "warning" | "inconclusive",
  #     confidence: 0.0..1.0,
  #     details: {
  #       message: "Human-readable description",
  #       technical_details: { ... },
  #       suggestions: [],
  #       evidence: { ... }
  #     }
  #   }
  #
  class BaseDetector
    CONFIDENCE_THRESHOLD = 0.7

    attr_reader :browser_service, :result

    def initialize(browser_service)
      @browser_service = browser_service
      @result = nil
      @validations_passed = 0
      @validations_total = 0
    end

    # Runs the detection check and returns a standardized result hash
    def perform
      @result = run_detection
      @result
    rescue StandardError => e
      Rails.logger.error("[#{self.class.name}] Detection failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      inconclusive_result("Detection check failed: #{e.message}")
    end

    # Returns the string name of this check (e.g., "add_to_cart")
    def check_name
      raise NotImplementedError, "Subclasses must implement #check_name"
    end

    private

    # Subclasses implement this to perform their specific detection logic
    def run_detection
      raise NotImplementedError, "Subclasses must implement #run_detection"
    end

    # Builds a passing result
    def pass_result(message:, confidence: nil, technical_details: {}, evidence: {}, suggestions: [])
      build_result(
        status: "pass",
        message: message,
        confidence: confidence || calculated_confidence,
        technical_details: technical_details,
        evidence: evidence,
        suggestions: suggestions
      )
    end

    # Builds a failing result
    def fail_result(message:, confidence: nil, technical_details: {}, evidence: {}, suggestions: [])
      build_result(
        status: "fail",
        message: message,
        confidence: confidence || calculated_confidence,
        technical_details: technical_details,
        evidence: evidence,
        suggestions: suggestions
      )
    end

    # Builds a warning result
    def warning_result(message:, confidence: nil, technical_details: {}, evidence: {}, suggestions: [])
      build_result(
        status: "warning",
        message: message,
        confidence: confidence || calculated_confidence,
        technical_details: technical_details,
        evidence: evidence,
        suggestions: suggestions
      )
    end

    # Builds an inconclusive result (detector couldn't determine pass/fail)
    def inconclusive_result(message, technical_details: {})
      build_result(
        status: "inconclusive",
        message: message,
        confidence: 0.0,
        technical_details: technical_details,
        evidence: {},
        suggestions: []
      )
    end

    # Records a validation check result for confidence scoring
    def record_validation(passed)
      @validations_total += 1
      @validations_passed += 1 if passed
      passed
    end

    # Calculates confidence based on how many validations passed
    def calculated_confidence
      return 0.0 if @validations_total == 0
      (@validations_passed.to_f / @validations_total).round(2)
    end

    # Safely evaluates JavaScript via the browser service
    def evaluate(script, timeout_ms: nil)
      browser_service.evaluate_script(script, timeout_ms: timeout_ms)
    end

    # Returns the page HTML content
    def page_html
      @page_html ||= browser_service.page_content
    end

    def build_result(status:, message:, confidence:, technical_details:, evidence:, suggestions:)
      {
        check: check_name,
        status: status,
        confidence: confidence,
        details: {
          message: message,
          technical_details: technical_details,
          suggestions: suggestions,
          evidence: evidence
        }
      }
    end
  end
end
