# frozen_string_literal: true

# AiIssueAnalyzer uses Google Gemini Flash to analyze detected issues.
#
# Three modes of operation:
#
#   1. Page-level analysis (AI as primary detector):
#      - Sends screenshot + programmatic results to Gemini
#      - Returns ALL issues found (AI-detected)
#      - Issues created with ai_confirmed: true → immediate alerting
#
#   2. High-severity issue confirmation (with screenshot):
#      - Sends screenshot + issue context to Gemini
#      - Returns confirmation, confidence, reasoning, explanation, and suggested fix
#
#   3. Medium/Low-severity issues (text only):
#      - Sends issue context only (no image = cheaper, faster)
#      - Returns explanation and suggested fix
#
# Design principles:
#   - Fail-open: If AI fails, programmatic detection still works
#   - AI + code findings are merged and deduplicated
#   - Tone: Calm, non-alarming, specific, actionable (matches Prowl UX)
#
# Usage:
#   # Page-level analysis (primary detection)
#   findings = AiIssueAnalyzer.new(scan: scan, issue: nil, product_page: page).analyze_page(
#     detection_results: [...],
#     screenshot_data: binary_png
#   )
#
#   # Per-issue analysis (confirmation + explanation)
#   result = AiIssueAnalyzer.new(scan: scan, issue: issue, product_page: page).perform
#
class AiIssueAnalyzer
  GEMINI_MODEL = ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash")
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/#{GEMINI_MODEL}:generateContent"
  REQUEST_TIMEOUT = 30 # seconds

  # Maps AI issue types to our Issue model types
  AI_ISSUE_TYPE_MAP = {
    "missing_atc" => "missing_add_to_cart",
    "atc_not_functional" => "atc_not_functional",
    "missing_price" => "missing_price",
    "wrong_price" => "missing_price",
    "broken_images" => "missing_images",
    "missing_images" => "missing_images",
    "checkout_broken" => "checkout_broken",
    "variant_broken" => "variant_selection_broken",
    "layout_broken" => "js_error",
    "error_message" => "js_error"
  }.freeze

  def initialize(scan:, issue:, product_page:)
    @scan = scan
    @issue = issue
    @product_page = product_page
    @shop = product_page.shop
  end

  # ── Mode 1: Page-level analysis (AI as primary detector) ────────────────
  # Sends screenshot to Gemini along with programmatic results.
  # AI independently identifies ALL issues on the page.
  # Returns: { findings: [...], page_healthy: bool, summary: "..." }
  def analyze_page(detection_results: [], screenshot_data: nil)
    return skip_page_result("AI not configured") unless api_key_present?
    return skip_page_result("No screenshot") unless screenshot_data

    screenshot_base64 = Base64.strict_encode64(screenshot_data)
    prompt = build_page_analysis_prompt(detection_results)

    response = call_gemini(prompt, screenshot_base64: screenshot_base64)
    parse_page_response(response, detection_results)
  rescue StandardError => e
    Rails.logger.error("[AiIssueAnalyzer] Page analysis error: #{e.message}")
    skip_page_result("AI page analysis failed: #{e.message}")
  end

  # ── Mode 2 & 3: Per-issue analysis (existing) ──────────────────────────
  def perform
    return skip_result("AI not configured") unless api_key_present?

    if @issue.high_severity? && @scan.screenshot_url.present?
      analyze_with_screenshot
    else
      analyze_text_only
    end
  rescue StandardError => e
    Rails.logger.error("[AiIssueAnalyzer] Error: #{e.message}")
    skip_result("AI analysis failed: #{e.message}")
  end

  private

  # ── Page analysis prompt ────────────────────────────────────────────────
  def build_page_analysis_prompt(detection_results)
    programmatic_summary = detection_results.map do |r|
      check = r[:check] || r["check"]
      status = r[:status] || r["status"]
      message = r.dig(:details, :message) || r.dig("details", "message") || ""
      "  - #{check}: #{status} — #{message}"
    end.join("\n")

    <<~PROMPT
      You are a Shopify store quality analyst. Analyze this product page screenshot and identify ALL issues that could prevent a customer from purchasing.

      Store: #{@shop.shopify_domain}
      Product: #{@product_page.title}

      Our automated checks found:
      #{programmatic_summary}

      Look at the screenshot carefully and identify ANY of these issues:
      1. Is the Add to Cart button visible and usable? Or is it missing/hidden/broken?
      2. Is the product price visible and correct (not $0.00, not missing)?
      3. Are product images loading correctly?
      4. Are there any error messages visible on the page?
      5. Is the layout broken or elements overlapping?
      6. Is there anything else that would prevent a customer from buying?

      IMPORTANT: Be precise. Only report issues you can actually see in the screenshot.
      If everything looks fine, return an empty issues array.

      Respond in JSON format only:
      {
        "issues": [
          {
            "type": "missing_atc|atc_not_functional|missing_price|wrong_price|broken_images|missing_images|checkout_broken|variant_broken|layout_broken|error_message",
            "severity": "high|medium|low",
            "confidence": 0.0-1.0,
            "description": "what you see in the screenshot",
            "merchant_explanation": "plain language for the store owner",
            "suggested_fix": "actionable steps to fix"
          }
        ],
        "page_healthy": true/false,
        "summary": "1-2 sentence summary for the merchant"
      }
    PROMPT
  end

  def parse_page_response(response, detection_results)
    return skip_page_result("Empty API response") unless response

    text = response.dig("candidates", 0, "content", "parts", 0, "text")
    return skip_page_result("No text in API response") unless text

    parsed = JSON.parse(text)
    ai_issues = parsed["issues"] || []

    # Determine which issue types programmatic checks already caught
    programmatic_types = detection_results
      .select { |r| (r[:status] || r["status"]) == "fail" }
      .map { |r| DetectionService::CHECK_TO_ISSUE_TYPE[r[:check] || r["check"]] }
      .compact

    findings = ai_issues.filter_map do |ai_issue|
      our_type = AI_ISSUE_TYPE_MAP[ai_issue["type"]]
      next unless our_type

      confidence = ai_issue["confidence"].to_f
      next if confidence < 0.7

      {
        issue_type: our_type,
        severity: ai_issue["severity"] || "medium",
        confidence: confidence,
        description: ai_issue["description"],
        merchant_explanation: ai_issue["merchant_explanation"],
        suggested_fix: ai_issue["suggested_fix"],
        ai_detected: true,
        new_finding: !programmatic_types.include?(our_type)
      }
    end

    {
      findings: findings,
      page_healthy: parsed["page_healthy"],
      summary: parsed["summary"],
      raw_issues_count: ai_issues.length
    }
  rescue JSON::ParserError => e
    Rails.logger.warn("[AiIssueAnalyzer] Failed to parse page analysis response: #{e.message}")
    skip_page_result("Failed to parse AI response")
  end

  def skip_page_result(reason)
    Rails.logger.info("[AiIssueAnalyzer] Page analysis skipped: #{reason}")
    { findings: [], page_healthy: nil, summary: nil, reason: reason }
  end

  # ── Per-issue methods (existing, unchanged) ─────────────────────────────

  def analyze_with_screenshot
    screenshot_data = download_screenshot
    return analyze_text_only unless screenshot_data

    screenshot_base64 = Base64.strict_encode64(screenshot_data)
    prompt = build_high_severity_prompt

    response = call_gemini(prompt, screenshot_base64: screenshot_base64)
    parse_response(response, with_confirmation: true)
  rescue ScreenshotUploader::UploadError => e
    Rails.logger.warn("[AiIssueAnalyzer] Screenshot download failed: #{e.message}, falling back to text-only")
    analyze_text_only
  end

  def analyze_text_only
    prompt = build_text_only_prompt

    response = call_gemini(prompt)
    parse_response(response, with_confirmation: false)
  end

  def build_high_severity_prompt
    <<~PROMPT
      You are a Shopify store advisor who helps non-technical merchants understand issues with their product pages. Analyze this screenshot of a product page.

      Product: #{@product_page.title}
      Store: #{@shop.shopify_domain}

      A scan detected the following issue:
      - Issue type: #{@issue.issue_type}
      - Title: #{@issue.title}
      - Evidence: #{@issue.evidence.to_json}

      Please provide:

      1. CONFIRMATION: Is this issue visible in the screenshot? (true/false)
      2. CONFIDENCE: How confident are you? (0.0 to 1.0)
      3. REASONING: Brief technical reasoning (1-2 sentences)
      4. MERCHANT EXPLANATION: Explain this issue in simple, non-technical language that a store owner would understand. Be specific about what this means for their customers and sales. 2-3 sentences max. Do not be alarming — be calm and helpful.
      5. SUGGESTED FIX: Provide actionable steps the merchant can take to fix this. Use numbered steps. Keep it simple — assume the merchant is not a developer. Only suggest safe, reversible actions.

      Respond in JSON format only:
      {"confirmed": true/false, "confidence": 0.0-1.0, "reasoning": "...", "merchant_explanation": "...", "suggested_fix": "..."}
    PROMPT
  end

  def build_text_only_prompt
    <<~PROMPT
      You are a Shopify store advisor who helps non-technical merchants understand issues with their product pages.

      Product: #{@product_page.title}
      Store: #{@shop.shopify_domain}

      A scan detected the following issue:
      - Issue type: #{@issue.issue_type}
      - Severity: #{@issue.severity}
      - Title: #{@issue.title}
      - Evidence: #{@issue.evidence.to_json}

      Please provide:

      1. MERCHANT EXPLANATION: Explain this issue in simple, non-technical language that a store owner would understand. Be specific about what this means for their customers and sales. 2-3 sentences max. Do not be alarming — be calm and helpful.
      2. SUGGESTED FIX: Provide actionable steps the merchant can take to fix this. Use numbered steps. Keep it simple — assume the merchant is not a developer. Only suggest safe, reversible actions.

      Respond in JSON format only:
      {"merchant_explanation": "...", "suggested_fix": "..."}
    PROMPT
  end

  def call_gemini(prompt, screenshot_base64: nil)
    parts = [{ text: prompt }]

    if screenshot_base64
      parts << {
        inline_data: {
          mime_type: "image/png",
          data: screenshot_base64
        }
      }
    end

    body = {
      contents: [{
        parts: parts
      }],
      generationConfig: {
        responseMimeType: "application/json"
      }
    }

    response = HTTParty.post(
      GEMINI_URL,
      headers: {
        "Content-Type" => "application/json",
        "x-goog-api-key" => ENV["GEMINI_API_KEY"]
      },
      body: body.to_json,
      timeout: REQUEST_TIMEOUT
    )

    unless response.success?
      Rails.logger.error("[AiIssueAnalyzer] Gemini API error: #{response.code} - #{response.body&.truncate(500)}")
      return nil
    end

    response.parsed_response
  end

  def parse_response(response, with_confirmation:)
    return skip_result("Empty API response") unless response

    text = response.dig("candidates", 0, "content", "parts", 0, "text")
    return skip_result("No text in API response") unless text

    parsed = JSON.parse(text)

    result = {
      merchant_explanation: parsed["merchant_explanation"],
      suggested_fix: parsed["suggested_fix"]
    }

    if with_confirmation
      result[:confirmed] = parsed["confirmed"]
      result[:confidence] = parsed["confidence"]&.to_f
      result[:reasoning] = parsed["reasoning"]
    end

    result
  rescue JSON::ParserError => e
    Rails.logger.warn("[AiIssueAnalyzer] Failed to parse Gemini response: #{e.message}")
    skip_result("Failed to parse AI response")
  end

  def download_screenshot
    ScreenshotUploader.new.download(@scan.screenshot_url)
  rescue StandardError => e
    Rails.logger.warn("[AiIssueAnalyzer] Screenshot download failed: #{e.message}")
    nil
  end

  def api_key_present?
    ENV["GEMINI_API_KEY"].present?
  end

  def skip_result(reason)
    Rails.logger.info("[AiIssueAnalyzer] Skipped: #{reason}")
    { merchant_explanation: nil, suggested_fix: nil, confirmed: nil, confidence: nil, reasoning: reason }
  end
end
