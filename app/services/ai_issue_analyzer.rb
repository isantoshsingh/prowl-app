# frozen_string_literal: true

# AiIssueAnalyzer uses Google Gemini Flash to analyze detected issues.
#
# Two modes of operation:
#   1. High-severity issues (with screenshot):
#      - Sends screenshot + issue context to Gemini
#      - Returns confirmation, confidence, reasoning, explanation, and suggested fix
#
#   2. Medium/Low-severity issues (text only):
#      - Sends issue context only (no image = cheaper, faster)
#      - Returns explanation and suggested fix
#
# Design principles:
#   - Fail-open: If AI fails, alerts still go through with hardcoded descriptions
#   - Phase 1: AI confirmation is informational only, does NOT gate alerts
#   - Tone: Calm, non-alarming, specific, actionable (matches Prowl UX)
#
# Usage:
#   result = AiIssueAnalyzer.new(scan: scan, issue: issue, product_page: page).perform
#   result[:merchant_explanation]  # Plain-language explanation
#   result[:suggested_fix]         # Actionable steps
#   result[:confirmed]             # true/false (high-severity only)
#
class AiIssueAnalyzer
  # Gemini 2.0 Flash is deprecated (zero free tier). Use 2.5 Flash or newer.
  # Override via GEMINI_MODEL env var if needed (e.g., "gemini-2.5-flash-lite" for cheapest).
  GEMINI_MODEL = ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash")
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/#{GEMINI_MODEL}:generateContent"
  REQUEST_TIMEOUT = 30 # seconds

  def initialize(scan:, issue:, product_page:)
    @scan = scan
    @issue = issue
    @product_page = product_page
    @shop = product_page.shop
  end

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

  # High-severity: send screenshot + context for confirmation + explanation
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

  # Medium/Low: send context only for explanation
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

    # Gemini returns: { candidates: [{ content: { parts: [{ text: "..." }] } }] }
    text = response.dig("candidates", 0, "content", "parts", 0, "text")
    return skip_result("No text in API response") unless text

    # Parse the JSON response from Gemini
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
