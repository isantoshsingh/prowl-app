# frozen_string_literal: true

# ProductPageScanner orchestrates the full scan flow for a product page.
# It manages the BrowserService lifecycle, runs all detectors, captures
# screenshots/HTML, and returns structured results.
#
# This replaces the scanning logic in PdpScannerService while preserving
# the same data capture (screenshots, HTML, errors) and adding the
# new detection engine with confidence scoring.
#
# Usage:
#   scanner = ProductPageScanner.new(product_page)
#   result = scanner.perform
#   # result => { success: bool, scan: Scan, data: Hash, detection_results: Array }
#
class ProductPageScanner
  SCAN_TIMEOUT_SECONDS = 45 unless const_defined?(:SCAN_TIMEOUT_SECONDS)
  DEEP_SCAN_TIMEOUT_SECONDS = 60 unless const_defined?(:DEEP_SCAN_TIMEOUT_SECONDS)

  class ScanError < StandardError; end
  class TimeoutError < ScanError; end

  # Tier 1 detectors - run on every scan
  TIER1_DETECTORS = [
    Detectors::AddToCartDetector,
    Detectors::JavascriptErrorDetector,
    Detectors::LiquidErrorDetector,
    Detectors::PriceVisibilityDetector,
    Detectors::ProductImageDetector
  ].freeze

  attr_reader :product_page, :scan, :browser_service, :detection_results, :scan_depth

  def initialize(product_page, browser_service: nil, scan_depth: :quick)
    @product_page = product_page
    @browser_service = browser_service
    @owns_browser = browser_service.nil?
    @scan_depth = scan_depth.to_sym
    @scan = nil
    @detection_results = []
  end

  # Performs the complete scan and detection flow
  # Returns: { success: bool, scan: Scan, data: Hash, detection_results: Array, error: String }
  def perform
    @scan = product_page.scans.create!(status: "pending", scan_depth: @scan_depth.to_s)
    @scan.start!

    timeout = @scan_depth == :deep ? DEEP_SCAN_TIMEOUT_SECONDS : SCAN_TIMEOUT_SECONDS

    begin
      Timeout.timeout(timeout, TimeoutError, "Scan exceeded #{timeout}s timeout") do
        execute_scan
      end
    rescue TimeoutError => e
      @scan.fail!("Scan timed out after #{SCAN_TIMEOUT_SECONDS} seconds")
      { success: false, scan: @scan, error: e.message, detection_results: [] }
    rescue ScanError => e
      @scan.fail!(e.message)
      { success: false, scan: @scan, error: e.message, detection_results: [] }
    rescue StandardError => e
      @scan.fail!("Unexpected error: #{e.message}")
      Rails.logger.error("[ProductPageScanner] Unexpected error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      { success: false, scan: @scan, error: e.message, detection_results: [] }
    ensure
      close_browser_if_owned
    end
  end

  private

  def execute_scan
    start_browser
    nav_result = navigate_to_page

    unless nav_result[:success]
      error_msg = if nav_result[:password_protected]
        "Store is password-protected. Disable password protection or add Prowl to the allowlist."
      else
        "Navigation failed: #{nav_result[:error]}"
      end
      @scan.fail!(error_msg)
      return { success: false, scan: @scan, error: error_msg, detection_results: [] }
    end

    # Capture page data
    data = capture_page_data

    # Run all detectors
    @detection_results = run_detectors

    # Complete the scan with all captured data
    @scan.complete!(
      screenshot_url: data[:screenshot_url],
      html_snapshot: data[:html_snapshot],
      js_errors: data[:js_errors],
      network_errors: data[:network_errors],
      console_logs: data[:console_logs],
      page_load_time_ms: data[:page_load_time_ms],
      dom_checks_data: serialize_detection_results
    )

    {
      success: true,
      scan: @scan,
      data: data,
      detection_results: @detection_results
    }
  end

  def start_browser
    if @browser_service.nil?
      @browser_service = BrowserService.new
    end

    @browser_service.start unless @browser_service.started?
  end

  def navigate_to_page
    url = product_page.scannable_url
    Rails.logger.info("[ProductPageScanner] Navigating to #{url}")
    @browser_service.navigate_to(url)
  end

  def capture_page_data
    data = {}

    # Screenshot
    screenshot_data = @browser_service.take_screenshot
    data[:screenshot_url] = store_screenshot(screenshot_data) if screenshot_data

    # HTML snapshot (truncated)
    html = @browser_service.page_content
    data[:html_snapshot] = html.truncate(500_000)

    # Captured errors and logs from browser events
    data[:js_errors] = @browser_service.js_errors.map { |e| e.transform_keys(&:to_s) }
    data[:network_errors] = @browser_service.critical_network_errors.map { |e| e.transform_keys(&:to_s) }
    data[:console_logs] = @browser_service.console_logs.first(100).map { |e| e.transform_keys(&:to_s) }
    data[:page_load_time_ms] = @browser_service.page_load_time_ms

    data
  end

  def run_detectors
    results = []

    TIER1_DETECTORS.each do |detector_class|
      begin
        Rails.logger.debug("[ProductPageScanner] Running #{detector_class.name} (depth: #{@scan_depth})")
        # AddToCartDetector needs scan_depth for funnel testing
        detector = if detector_class == Detectors::AddToCartDetector
          detector_class.new(@browser_service, scan_depth: @scan_depth)
        else
          detector_class.new(@browser_service)
        end
        result = detector.perform
        results << result if result
      rescue StandardError => e
        # Individual detector failures should not stop other detectors
        Rails.logger.error("[ProductPageScanner] #{detector_class.name} failed: #{e.message}")
        results << {
          check: detector_class.name.demodulize.underscore.sub("_detector", ""),
          status: "inconclusive",
          confidence: 0.0,
          details: {
            message: "Detection check failed: #{e.message}",
            technical_details: {},
            suggestions: [],
            evidence: {}
          }
        }
      end
    end

    results
  end

  def serialize_detection_results
    @detection_results.to_json
  rescue StandardError
    "[]"
  end

  def store_screenshot(screenshot_data)
    ScreenshotUploader.new.upload(
      screenshot_data,
      @scan.id,
      shop: product_page.shop,
      product_page: product_page
    )
  end

  def close_browser_if_owned
    return unless @owns_browser && @browser_service

    @browser_service.close
  rescue StandardError => e
    Rails.logger.warn("[ProductPageScanner] Error closing browser: #{e.message}")
  end
end
