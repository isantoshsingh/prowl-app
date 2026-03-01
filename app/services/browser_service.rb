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

  # Launches the browser instance (local) or connects to remote (Browserless)
  # Uses Browserless.io cloud browser when BROWSERLESS_URL is set (production).
  # Falls back to local Chrome launch when not set (development).
  # In production, REFUSES to launch local Chrome (would cause R14 memory crash).
  def start
    return if @started

    retries = 0
    begin
      if ENV["BROWSERLESS_URL"].present?
        # Connect to remote Browserless.io Chrome via WebSocket
        # This uses ~0MB local RAM vs ~350MB for local Chrome
        @browser = Puppeteer.connect(
          browser_ws_endpoint: ENV["BROWSERLESS_URL"]
        )
        @remote_browser = true
        Rails.logger.info("[BrowserService] Connected to remote browser (Browserless)")
      elsif Rails.env.production?
        # NEVER launch local Chrome in production — it uses ~350MB and crashes the dyno
        raise BrowserError, "BROWSERLESS_URL is not set. Cannot launch local Chrome in production (would cause R14 memory crash). Set BROWSERLESS_URL to use Browserless.io."
      else
        # Launch local Chrome for development only
        @browser = Puppeteer.launch(
          headless: @options[:headless],
          args: browser_launch_args
        )
        @remote_browser = false
        Rails.logger.info("[BrowserService] Browser launched locally")
      end
      @started = true
      self
    rescue BrowserError
      raise # Don't retry config errors
    rescue StandardError => e
      if retries < 1
        retries += 1
        Rails.logger.warn("[BrowserService] Browser #{@remote_browser ? 'connection' : 'launch'} failed (attempt #{retries}): #{e.message}, retrying...")
        sleep(1)
        retry
      end
      Rails.logger.error("[BrowserService] Failed to #{ENV['BROWSERLESS_URL'].present? ? 'connect to remote browser' : 'launch browser'} after #{retries + 1} attempts: #{e.message}")
      raise BrowserError, "Failed to start browser: #{e.message}"
    end
  end

  # Closes or disconnects the browser and cleans up resources
  def close
    return unless @started

    begin
      begin
        @page&.close
      rescue StandardError => e
        Rails.logger.debug("[BrowserService] Error closing page: #{e.message}")
      end
      if @remote_browser
        @browser&.disconnect
      else
        @browser&.close
      end
    rescue StandardError => e
      Rails.logger.warn("[BrowserService] Error closing browser: #{e.message}")
    ensure
      @browser = nil
      @page = nil
      @started = false
      Rails.logger.info("[BrowserService] Browser #{@remote_browser ? 'disconnected' : 'closed'}")
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

  # ── Purchase Funnel Interaction Methods ─────────────────────────────────
  # These methods interact with the page to test the full purchase flow.
  # All use Shopify platform conventions (not text) so they're language-independent.

  # Selects the first available variant option on the product page.
  # Strategy: find <select> elements inside variant containers (DOM attributes, not text).
  # Returns: { selected: true/false, variant_name: "value selected", method: "select|radio|swatch|none" }
  def select_first_variant
    ensure_page_loaded!

    result = evaluate_script(<<~JS)
      () => {
        // Strategy 1: <select> inside variant-selects, variant-radios, or product-form
        const selectEl = document.querySelector(
          'variant-selects select, variant-radios select, product-form select[name*="option"], ' +
          'form[action*="/cart/add"] select[name*="option"], product-form select'
        );

        if (selectEl && selectEl.tagName === 'SELECT') {
          const options = Array.from(selectEl.options);
          const available = options.find((opt, i) => i > 0 && !opt.disabled);
          if (available) {
            selectEl.value = available.value;
            selectEl.dispatchEvent(new Event('change', { bubbles: true }));
            return { selected: true, variant_name: available.value, method: 'select' };
          }
        }

        // Strategy 2: Radio buttons inside variant containers
        // Dawn theme uses radios inside variant-selects OR variant-radios
        const radio = document.querySelector(
          'variant-selects input[type="radio"]:not(:checked):not(:disabled), ' +
          'variant-radios input[type="radio"]:not(:checked):not(:disabled), ' +
          '.variant-input-wrapper input[type="radio"]:not(:checked):not(:disabled), ' +
          'product-form input[type="radio"]:not(:checked):not(:disabled), ' +
          'form[action*="/cart/add"] fieldset input[type="radio"]:not(:checked):not(:disabled)'
        );
        if (radio) {
          radio.click();
          radio.dispatchEvent(new Event('change', { bubbles: true }));
          return { selected: true, variant_name: radio.value, method: 'radio' };
        }

        // Strategy 3: Swatch buttons / clickable option elements (custom themes)
        const swatch = document.querySelector(
          '[data-option-value-id]:not(:checked):not(:disabled):not([disabled]), ' +
          '[data-option-value]:not(.is-disabled):not(.disabled):not([disabled]), ' +
          '.swatch-element:not(.soldout) label'
        );
        if (swatch) {
          swatch.click();
          return { selected: true, variant_name: swatch.textContent?.trim() || swatch.value || '', method: 'swatch' };
        }

        // No variant selectors found (might be a simple product with no variants)
        return { selected: false, variant_name: null, method: 'none' };
      }
    JS

    # Wait for DOM to settle after variant selection
    wait_for_network_idle(timeout: 2.0) if result && result["selected"]

    result&.symbolize_keys || { selected: false, variant_name: nil, method: "error" }
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] select_first_variant failed: #{e.message}")
    { selected: false, variant_name: nil, method: "error", error: e.message }
  end

  # Clicks the Add to Cart button.
  # Uses Shopify's standard selectors (form action + button type, not text).
  # Returns: { clicked: true/false, error: nil|string }
  def click_add_to_cart
    ensure_page_loaded!

    # Try selectors in priority order
    selectors = [
      'form[action*="/cart/add"] button[type="submit"]:not([disabled])',
      'product-form button[type="submit"]:not([disabled])',
      'button[name="add"]:not([disabled])',
      '.product-form__submit:not([disabled])'
    ]

    selectors.each do |selector|
      if click(selector)
        Rails.logger.info("[BrowserService] Clicked ATC button: #{selector}")
        wait_for_network_idle(timeout: 3.0) # Wait for cart update (AJAX or page reload)
        return { clicked: true, error: nil, selector: selector }
      end
    end

    { clicked: false, error: "No enabled ATC button found", selector: nil }
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] click_add_to_cart failed: #{e.message}")
    { clicked: false, error: e.message, selector: nil }
  end

  # Reads the current cart state via Shopify's AJAX API.
  # /cart.js is available on every Shopify store regardless of language/theme.
  # Returns: { item_count: int, items: [...], total_price: string }
  def read_cart_state
    ensure_page_loaded!

    result = evaluate_script(<<~JS)
      async () => {
        try {
          const response = await fetch('/cart.js', {
            method: 'GET',
            headers: { 'Accept': 'application/json' }
          });
          if (!response.ok) return { item_count: -1, items: [], error: 'HTTP ' + response.status };
          const cart = await response.json();
          return {
            item_count: cart.item_count || 0,
            items: (cart.items || []).map(i => ({
              key: i.key,
              variant_id: i.variant_id,
              title: i.title,
              quantity: i.quantity,
              price: i.price
            })),
            total_price: cart.total_price,
            error: null
          };
        } catch(e) {
          return { item_count: -1, items: [], error: e.message };
        }
      }
    JS

    result&.symbolize_keys || { item_count: -1, items: [], error: "Script returned nil" }
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] read_cart_state failed: #{e.message}")
    { item_count: -1, items: [], error: e.message }
  end

  # Removes an item from the cart via Shopify's AJAX API.
  # Uses /cart/change.js with quantity 0 to remove.
  # Returns: { success: true/false, error: nil|string }
  def clear_cart_item(line_item_key)
    ensure_page_loaded!

    # Sanitize line_item_key to prevent JS injection — only allow safe characters
    sanitized_key = line_item_key.to_s.gsub(/[^a-zA-Z0-9_:\-]/, "")

    result = evaluate_script(<<~JS)
      async () => {
        try {
          const response = await fetch('/cart/change.js', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: JSON.stringify({ id: #{sanitized_key.to_json}, quantity: 0 })
          });
          if (!response.ok) return { success: false, error: 'HTTP ' + response.status };
          return { success: true, error: null };
        } catch(e) {
          return { success: false, error: e.message };
        }
      }
    JS

    result&.symbolize_keys || { success: false, error: "Script returned nil" }
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] clear_cart_item failed: #{e.message}")
    { success: false, error: e.message }
  end

  # Navigates to /checkout to verify checkout accessibility.
  # Shopify redirects to checkout.shopify.com — we verify the redirect happens.
  # Returns: { url: string, redirected: bool, error: nil|string }
  def navigate_to_checkout
    ensure_page_loaded!

    begin
      @page.goto("/checkout", wait_until: "domcontentloaded", timeout: 10_000)
      current_url = @page.url

      {
        url: current_url,
        redirected: current_url.include?("checkout"),
        is_shopify_checkout: current_url.include?("checkout.shopify.com") || current_url.include?("/checkouts/"),
        error: nil
      }
    rescue Puppeteer::TimeoutError
      # Timeout might mean slow redirect — still capture where we ended up
      current_url = @page.url rescue ""
      {
        url: current_url,
        redirected: current_url.include?("checkout"),
        is_shopify_checkout: current_url.include?("checkout.shopify.com") || current_url.include?("/checkouts/"),
        error: "Checkout navigation timed out"
      }
    end
  rescue StandardError => e
    Rails.logger.warn("[BrowserService] navigate_to_checkout failed: #{e.message}")
    { url: nil, redirected: false, is_shopify_checkout: false, error: e.message }
  end

  private

  # Waits for network activity to settle by polling for idle state.
  # More reliable than fixed sleep — adapts to actual page responsiveness.
  def wait_for_network_idle(timeout: 2.0)
    return unless @page

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep(0.25)
      # Check if there are pending network requests
      idle = @page.evaluate("() => { return document.readyState === 'complete'; }") rescue true
      break if idle
    end
  rescue StandardError => e
    Rails.logger.debug("[BrowserService] wait_for_network_idle error: #{e.message}")
  end

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
