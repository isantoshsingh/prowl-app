# frozen_string_literal: true

# PdpScannerService performs headless browser scans of product pages.
# It uses Puppeteer to load a PDP as a public visitor and capture:
#   - Screenshot
#   - HTML snapshot
#   - JavaScript errors
#   - Network errors
#   - Console logs
#   - Page load time
#
# Timeout: 30 seconds per scan (per PRD requirements)
#
class PdpScannerService
  SCAN_TIMEOUT_SECONDS = 30
  VIEWPORT_WIDTH = 1280
  VIEWPORT_HEIGHT = 800

  class ScanError < StandardError; end
  class TimeoutError < ScanError; end

  attr_reader :product_page, :scan, :results

  def initialize(product_page)
    @product_page = product_page
    @results = {}
  end

  # Performs the scan and returns a hash of results
  # Returns: { success: bool, data: hash, error: string }
  def perform
    @scan = product_page.scans.create!(status: "pending")
    @scan.start!

    begin
      execute_scan
      @scan.complete!(
        screenshot_url: results[:screenshot_url],
        html_snapshot: results[:html_snapshot],
        js_errors: results[:js_errors] || [],
        network_errors: results[:network_errors] || [],
        console_logs: results[:console_logs] || [],
        page_load_time_ms: results[:page_load_time_ms]
      )

      { success: true, scan: @scan, data: results }
    rescue TimeoutError => e
      @scan.fail!("Scan timed out after #{SCAN_TIMEOUT_SECONDS} seconds")
      { success: false, scan: @scan, error: e.message }
    rescue ScanError => e
      @scan.fail!(e.message)
      { success: false, scan: @scan, error: e.message }
    rescue StandardError => e
      @scan.fail!("Unexpected error: #{e.message}")
      Rails.logger.error("[PdpScannerService] Unexpected error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      { success: false, scan: @scan, error: e.message }
    end
  end

  private

  def execute_scan
    url = product_page.scannable_url

    Timeout.timeout(SCAN_TIMEOUT_SECONDS, TimeoutError, "Scan exceeded #{SCAN_TIMEOUT_SECONDS}s timeout") do
      Puppeteer.launch(**launch_options) do |browser|
        page = browser.new_page
        setup_page(page)
        load_page(page, url)
        capture_results(page)
      end
    end
  end

  def setup_page(page)
    @js_errors = []
    @console_logs = []
    @network_errors = []

    # Set viewport
    page.viewport = Puppeteer::Viewport.new(width: VIEWPORT_WIDTH, height: VIEWPORT_HEIGHT)

    # Capture JS errors
    page.on("pageerror") do |error|
      @js_errors << {
        message: error.message,
        timestamp: Time.current.iso8601
      }
    end

    # Capture console messages
    page.on("console") do |msg|
      @console_logs << {
        type: msg.log_type,
        text: msg.text,
        timestamp: Time.current.iso8601
      }
    end

    # Capture network failures
    page.on("requestfailed") do |request|
      @network_errors << {
        url: request.url,
        failure: request.failure&.dig(:errorText) || "Unknown error",
        resource_type: request.resource_type,
        timestamp: Time.current.iso8601
      }
    end
  end

  def load_page(page, url)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      page.goto(url, wait_until: "networkidle2", timeout: (SCAN_TIMEOUT_SECONDS - 5) * 1000)
    rescue Puppeteer::TimeoutError
      # Page didn't reach networkidle, but may still be usable
      Rails.logger.warn("[PdpScannerService] Page load timeout for #{url}, continuing with partial load")
    end

    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @page_load_time_ms = ((end_time - start_time) * 1000).to_i

    # Wait a bit for any remaining JS to execute
    sleep(1)
  end

  def capture_results(page)
    # Capture screenshot
    screenshot_data = page.screenshot(type: "png", full_page: false)
    results[:screenshot_url] = store_screenshot(screenshot_data)

    # Capture HTML (truncated for storage)
    html = page.content
    results[:html_snapshot] = html.truncate(500_000) # Limit to ~500KB

    # Capture collected errors and logs
    results[:js_errors] = @js_errors
    results[:network_errors] = @network_errors
    results[:console_logs] = @console_logs.first(100) # Limit console logs
    results[:page_load_time_ms] = @page_load_time_ms

    # Capture DOM state for detection engine
    results[:dom_checks] = perform_dom_checks(page)
  end

  def perform_dom_checks(page)
    checks = {}

    # Check for Add to Cart button
    checks[:add_to_cart] = page.evaluate(<<~JAVASCRIPT)
      () => {
        const selectors = [
          '[name="add"]',
          'button[type="submit"][name="add"]',
          'form[action*="/cart/add"] button[type="submit"]',
          '.product-form__submit',
          '.add-to-cart',
          '#AddToCart',
          '[data-add-to-cart]',
          'button.shopify-payment-button__button'
        ];
        const button = selectors.map(s => document.querySelector(s)).find(Boolean);
        return {
          found: !!button,
          disabled: button ? button.disabled : null,
          visible: button ? button.offsetParent !== null : null,
          text: button ? button.textContent?.trim().substring(0, 100) : null
        };
      }
    JAVASCRIPT

    # Check for variant selectors
    checks[:variant_selector] = page.evaluate(<<~JAVASCRIPT)
      () => {
        const selectors = [
          '[name*="option"]',
          '.product-form__input',
          '.swatch',
          '[data-option]',
          'select[id*="option"]',
          '[data-variant-option]'
        ];
        const elements = selectors.flatMap(s => Array.from(document.querySelectorAll(s)));
        return {
          found: elements.length > 0,
          count: elements.length
        };
      }
    JAVASCRIPT

    # Check for product images
    checks[:images] = page.evaluate(<<~JAVASCRIPT)
      () => {
        const images = document.querySelectorAll('.product__media img, .product-single__photo img, [data-product-media] img, .product-image img');
        const visibleImages = Array.from(images).filter(img => {
          return img.complete && img.naturalWidth > 0 && img.offsetParent !== null;
        });
        return {
          total: images.length,
          visible: visibleImages.length,
          all_loaded: images.length > 0 && visibleImages.length === images.length
        };
      }
    JAVASCRIPT

    # Check for price
    checks[:price] = page.evaluate(<<~JAVASCRIPT)
      () => {
        const selectors = [
          '.price',
          '.product__price',
          '.product-price',
          '[data-price]',
          '.money',
          '.product-single__price'
        ];
        const priceEl = selectors.map(s => document.querySelector(s)).find(Boolean);
        return {
          found: !!priceEl,
          visible: priceEl ? priceEl.offsetParent !== null : null,
          text: priceEl ? priceEl.textContent?.trim().substring(0, 50) : null
        };
      }
    JAVASCRIPT

    # Check for Liquid errors
    checks[:liquid_errors] = page.evaluate(<<~JAVASCRIPT)
      () => {
        const body = document.body.innerHTML;
        const errors = [];
        if (body.includes('Liquid error')) errors.push('Liquid error detected');
        if (body.includes('Translation missing')) errors.push('Translation missing');
        if (body.includes('No template found')) errors.push('No template found');
        return {
          found: errors.length > 0,
          errors: errors
        };
      }
    JAVASCRIPT

    checks
  end

  def launch_options
    options = {
      headless: true,
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--disable-gpu",
        "--single-process",
        "--js-flags=--max-old-space-size=128",
        "--disable-extensions",
        "--disable-background-networking",
        "--disable-software-rasterizer"
      ]
    }

    chrome_path = Rails.application.config.puppeteer.executable_path
    options[:executable_path] = chrome_path if chrome_path

    options
  end

  def store_screenshot(screenshot_data)
    # In Phase 1, store screenshots locally in tmp directory
    # In production, this would upload to S3 or similar
    filename = "scan_#{@scan.id}_#{Time.current.to_i}.png"
    filepath = Rails.root.join("tmp", "screenshots", filename)

    FileUtils.mkdir_p(File.dirname(filepath))
    File.binwrite(filepath, screenshot_data)

    # Return relative path for now - in production this would be a signed URL
    "/screenshots/#{filename}"
  end
end
