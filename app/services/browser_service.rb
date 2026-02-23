# frozen_string_literal: true

# BrowserService manages the Puppeteer browser lifecycle and provides
# a clean interface for the detection engine to interact with pages.
#
# Core responsibilities:
#   - Launch/close browser with appropriate options
#   - Navigate to URLs with retries and configurable timeouts
#   - Capture JS errors, console logs, and network failures during page lifecycle
#   - Provide helper methods for detectors (evaluate JS, wait for elements, etc.)
#   - Handle all errors gracefully without crashing the scan
#
# Usage:
#   browser_service = BrowserService.new
#   browser_service.start
#   browser_service.navigate_to("https://example.com/products/widget")
#   result = browser_service.evaluate_script("() => document.title")
#   browser_service.close
#
class BrowserService
  class BrowserError < StandardError; end
  class NavigationError < BrowserError; end
  class PageLoadError < BrowserError; end
  class ScriptExecutionError < BrowserError; end

  # Configuration defaults
  DEFAULT_VIEWPORT_WIDTH = 1280
  DEFAULT_VIEWPORT_HEIGHT = 800
  DEFAULT_PAGE_TIMEOUT_MS = 15_000
  DEFAULT_ELEMENT_TIMEOUT_MS = 5_000
  DEFAULT_SCRIPT_TIMEOUT_MS = 5_000
  MAX_NAVIGATION_RETRIES = 2
  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  # Resource types to optionally block for performance
  BLOCKABLE_RESOURCE_TYPES = %w[font media].freeze
  BLOCKED_URL_PATTERNS = %w[
    google-analytics.com
    googletagmanager.com
    facebook.net
    hotjar.com
    doubleclick.net
    connect.facebook.net
    analytics
    monorail-edge.shopifysvc.com
    shopifysvc.com
    /api/collect
    favicon.ico
  ].freeze

  attr_reader :browser, :page, :js_errors, :console_logs, :network_errors,
              :network_requests, :page_load_time_ms, :options

  def initialize(options = {})
    @options = default_options.merge(options)
    @browser = nil
    @page = nil
    @js_errors = []
    @console_logs = []
    @network_errors = []
    @network_requests = []
    @page_load_time_ms = nil
    @started = false
  end

  # Launches the browser instance with one retry for transient failures
  def start
    return if @started

    retries = 0
    begin
      @browser = Puppeteer.launch(
        headless: @options[:headless],
        args: browser_launch_args
      )
      @started = true
      Rails.logger.info("[BrowserService] Browser launched")
      self
    rescue StandardError => e
      if retries < 1
        retries += 1
        Rails.logger.warn("[BrowserService] Browser launch failed (attempt #{retries}): #{e.message}, retrying...")
        sleep(1)
        retry
      end
      Rails.logger.error("[BrowserService] Failed to launch browser after #{retries + 1} attempts: #{e.message}")
      raise BrowserError, "Failed to launch browser: #{e.message}"
    end
  end

  # Closes the browser and cleans up resources
  def close
    return unless @started

    begin
      @page&.close rescue nil
      @browser&.close
    rescue StandardError => e
      Rails.logger.warn("[BrowserService] Error closing browser: #{e.message}")
    ensure
      @browser = nil
      @page = nil
      @started = false
      Rails.logger.info("[BrowserService] Browser closed")
    end
  end

  # Navigates to a URL with retry logic and error capture
  # Returns: { success: bool, status_code: int, error: string }
  def navigate_to(url)
    ensure_browser_started!
    reset_page_state!
    setup_new_page

    retries = 0
    last_error = nil

    while retries <= MAX_NAVIGATION_RETRIES
      begin
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        response = @page.goto(url, wait_until: "networkidle2", timeout: @options[:page_timeout_ms])

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @page_load_time_ms = ((end_time - start_time) * 1000).to_i

        # Wait for additional JS execution after network idle
        sleep(1)

        status_code = response&.status || 0

        # Detect password-protected stores
        if password_protected_page?
          return {
            success: false,
            status_code: status_code,
            error: "Store is password-protected",
            password_protected: true
          }
        end

        return {
          success: status_code < 400,
          status_code: status_code,
          error: status_code >= 400 ? "HTTP #{status_code}" : nil
        }
      rescue Puppeteer::TimeoutError
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @page_load_time_ms = ((end_time - start_time) * 1000).to_i

        # Page didn't fully settle but may still be usable - check if content loaded
        if page_has_content?
          Rails.logger.warn("[BrowserService] Navigation timeout for #{url} (attempt #{retries + 1}), continuing with partial load")
          return { success: true, status_code: 0, error: nil, partial_load: true }
        else
          retries += 1
          if retries <= MAX_NAVIGATION_RETRIES
            Rails.logger.warn("[BrowserService] Navigation timeout with no content for #{url} (attempt #{retries}), retrying...")
            sleep(1)
          else
            return { success: false, status_code: 0, error: "Navigation timed out with no content loaded" }
          end
        end
      rescue StandardError => e
        last_error = e
        retries += 1
        if retries <= MAX_NAVIGATION_RETRIES
          Rails.logger.warn("[BrowserService] Navigation failed for #{url} (attempt #{retries}): #{e.message}, retrying...")
          sleep(1)
        end
      end
    end

    Rails.logger.error("[BrowserService] Navigation failed after #{MAX_NAVIGATION_RETRIES + 1} attempts: #{last_error&.message}")
    { success: false, status_code: 0, error: last_error&.message || "Navigation failed" }
  end

  # Evaluates JavaScript in the page context safely
  # Returns the result of the evaluation, or nil on error
  def evaluate_script(script, timeout_ms: nil)
    ensure_page_loaded!
    timeout = timeout_ms || @options[:script_timeout_ms]

    Timeout.timeout(timeout / 1000.0) do
      @page.evaluate(script)
    end
  rescue Timeout::Error
    Rails.logger.warn("[BrowserService] Script evaluation timed out after #{timeout}ms")
    nil
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] Script evaluation error: #{e.message}")
    nil
  end

  # Waits for an element matching selector with timeout
  # Returns true if found, false if timeout
  def wait_for_selector(selector, timeout_ms: nil)
    ensure_page_loaded!
    timeout = timeout_ms || @options[:element_timeout_ms]

    @page.wait_for_selector(selector, timeout: timeout)
    true
  rescue Puppeteer::TimeoutError
    false
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] Error waiting for selector '#{selector}': #{e.message}")
    false
  end

  # Tries multiple selectors and returns the first match
  # Returns: { found: bool, selector: string, element_count: int }
  def find_with_selectors(selectors)
    ensure_page_loaded!

    selectors.each do |selector|
      begin
        elements = @page.query_selector_all(selector)
        if elements.any?
          return { found: true, selector: selector, element_count: elements.length }
        end
      rescue StandardError => e
        Rails.logger.debug("[BrowserService] Selector '#{selector}' failed: #{e.message}")
        next
      end
    end

    { found: false, selector: nil, element_count: 0 }
  end

  # Takes a screenshot of the current page
  # Returns binary PNG data, or nil on error
  def take_screenshot(full_page: false)
    ensure_page_loaded!
    @page.screenshot(type: "png", full_page: full_page)
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] Screenshot failed: #{e.message}")
    nil
  end

  # Returns the current page HTML content
  def page_content
    ensure_page_loaded!
    @page.content
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] Failed to get page content: #{e.message}")
    ""
  end

  # Clicks an element by selector with validation
  # Returns true if click succeeded, false otherwise
  def click(selector)
    ensure_page_loaded!
    @page.click(selector)
    true
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] Click failed on '#{selector}': #{e.message}")
    false
  end

  # Returns captured errors filtered by category
  def critical_js_errors
    @js_errors.reject do |error|
      msg = error[:message].to_s.downcase
      BLOCKED_URL_PATTERNS.any? { |pattern| msg.include?(pattern) } ||
        msg.include?("favicon") ||
        msg.include?("pixel")
    end
  end

  # Returns network errors filtered to critical resources
  def critical_network_errors
    @network_errors.select do |error|
      resource_type = error[:resource_type].to_s.downcase
      url = error[:url].to_s.downcase
      # Focus on critical resources
      %w[document stylesheet script xhr fetch image].include?(resource_type) &&
        BLOCKED_URL_PATTERNS.none? { |pattern| url.include?(pattern) }
    end
  end

  # Checks if the browser is running
  def started?
    @started && @browser
  end

  private

  def default_options
    {
      headless: true,
      viewport_width: DEFAULT_VIEWPORT_WIDTH,
      viewport_height: DEFAULT_VIEWPORT_HEIGHT,
      page_timeout_ms: DEFAULT_PAGE_TIMEOUT_MS,
      element_timeout_ms: DEFAULT_ELEMENT_TIMEOUT_MS,
      script_timeout_ms: DEFAULT_SCRIPT_TIMEOUT_MS,
      block_unnecessary_resources: true,
      user_agent: USER_AGENT
    }
  end

  def browser_launch_args
    args = [
      "--no-sandbox",
      "--disable-setuid-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--disable-software-rasterizer",
      "--js-flags=--max-old-space-size=128",
      "--single-process",
      "--disable-extensions"
    ]

    args << "--window-size=#{@options[:viewport_width]},#{@options[:viewport_height]}"
    args
  end

  def setup_new_page
    @page&.close rescue nil
    @page = @browser.new_page
    configure_page
    setup_event_listeners
    setup_request_interception if @options[:block_unnecessary_resources]
  rescue Puppeteer::Connection::ProtocolError => e
    Rails.logger.warn("[BrowserService] Target closed during page setup: #{e.message}, restarting browser...")
    close
    @started = false
    start
    @page = @browser.new_page
    configure_page
    setup_event_listeners
    setup_request_interception if @options[:block_unnecessary_resources]
  end

  def configure_page
    @page.viewport = Puppeteer::Viewport.new(
      width: @options[:viewport_width],
      height: @options[:viewport_height]
    )
    @page.set_user_agent(@options[:user_agent])
  end

  def setup_event_listeners
    # Capture JS errors (uncaught exceptions)
    @page.on("pageerror") do |error|
      @js_errors << {
        message: error.message.to_s.truncate(1000),
        stack: error.respond_to?(:stack) ? error.stack.to_s.truncate(2000) : nil,
        timestamp: Time.current.iso8601
      }
    end

    # Capture console messages
    @page.on("console") do |msg|
      @console_logs << {
        type: msg.log_type,
        text: msg.text.to_s.truncate(500),
        timestamp: Time.current.iso8601
      }
    end

    # Capture network failures
    @page.on("requestfailed") do |request|
      @network_errors << {
        url: request.url.to_s.truncate(500),
        failure: request.failure&.dig(:errorText) || "Unknown error",
        resource_type: request.resource_type,
        method: request.method,
        timestamp: Time.current.iso8601
      }
    end

    # Track all network requests for analysis
    @page.on("requestfinished") do |request|
      response = request.response
      status = response&.status || 0
      if status >= 400
        @network_errors << {
          url: request.url.to_s.truncate(500),
          failure: "HTTP #{status}",
          resource_type: request.resource_type,
          method: request.method,
          status_code: status,
          timestamp: Time.current.iso8601
        }
      end
    end
  end

  def setup_request_interception
    @page.request_interception = true

    @page.on("request") do |request|
      url = request.url.to_s.downcase

      if should_block_request?(request.resource_type, url)
        request.abort
      else
        request.continue
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] Request interception setup failed: #{e.message}")
  end

  def should_block_request?(resource_type, url)
    return true if BLOCKABLE_RESOURCE_TYPES.include?(resource_type.to_s.downcase)
    BLOCKED_URL_PATTERNS.any? { |pattern| url.include?(pattern) }
  end

  def reset_page_state!
    @js_errors = []
    @console_logs = []
    @network_errors = []
    @network_requests = []
    @page_load_time_ms = nil
  end

  def ensure_browser_started!
    raise BrowserError, "Browser not started. Call #start first." unless started?
  end

  def ensure_page_loaded!
    ensure_browser_started!
    raise PageLoadError, "No page loaded. Call #navigate_to first." unless @page
  end

  # Detects Shopify password-protected storefront pages
  def password_protected_page?
    return false unless @page
    @page.evaluate("() => { return !!document.querySelector('form[action*=\"password\"]') || document.title.toLowerCase().includes('password'); }") rescue false
  end

  # Checks if the page has meaningful content loaded despite timeout
  def page_has_content?
    return false unless @page
    @page.evaluate("() => { return document.body && document.body.innerHTML.length > 500; }") rescue false
  end
end
