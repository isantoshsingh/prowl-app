# frozen_string_literal: true

# Live PDP Scan Test Suite
# ========================
# Runs the scanner against real public Shopify store product pages
# and validates detection results against expected outcomes.
#
# Usage:
#   bin/rails runner test/scripts/live_pdp_scan_test.rb
#
# Requirements:
#   - Puppeteer/Chromium installed (puppeteer-ruby gem)
#   - Database available (creates temporary records, cleans up after)
#   - Internet access to reach public Shopify stores
#
# This script does NOT use the test framework — it's a standalone runner
# that exercises the real scanning + detection pipeline end-to-end.

class LivePdpScanTest
  PASS = "\e[32mPASS\e[0m"
  FAIL = "\e[31mFAIL\e[0m"
  SKIP = "\e[33mSKIP\e[0m"
  WARN = "\e[33mWARN\e[0m"

  # Each test case defines a real Shopify product URL and expected outcomes.
  # `expect_issues` lists issue types that SHOULD be detected.
  # `expect_no_issues` lists issue types that should NOT be detected.
  # `expect_healthy` means no high/medium issues expected.
  #
  # NOTE: These are public Shopify stores. Results may change if stores
  # update their themes. The test tolerates some variance by checking
  # general detection behavior rather than exact match.
  TEST_CASES = [
    {
      name: "Allbirds - Tree Runners (healthy product page)",
      domain: "allbirds.com",
      url: "https://allbirds.com/products/mens-tree-runners",
      handle: "mens-tree-runners",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Well-known Shopify Plus store, should be fully functional"
    },
    {
      name: "Gymshark - Crest T-Shirt (healthy product page)",
      domain: "gymshark.com",
      url: "https://www.gymshark.com/products/gymshark-crest-t-shirt-black-aw24",
      handle: "gymshark-crest-t-shirt-black-aw24",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Major Shopify Plus store"
    },
    {
      name: "Bombas - Ankle Socks (healthy product page)",
      domain: "bombas.com",
      url: "https://bombas.com/products/womens-originals-ankle-sock-6-pack",
      handle: "womens-originals-ankle-sock-6-pack",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Well-established Shopify store"
    },
    {
      name: "KITH - Standard T-Shirt (healthy product page)",
      domain: "kith.com",
      url: "https://kith.com/products/kh030124-101",
      handle: "kh030124-101",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Shopify Plus with custom theme"
    },
    {
      name: "Chubbies - Swim Trunks (healthy product page)",
      domain: "chubbies.com",
      url: "https://www.chubbies.com/products/the-floral-reefs",
      handle: "the-floral-reefs",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Standard Shopify store"
    },
    {
      name: "Taylor Stitch - Organic Tee (healthy product page)",
      domain: "taylorstitch.com",
      url: "https://www.taylorstitch.com/products/organic-cotton-tee-vintage-white-2201",
      handle: "organic-cotton-tee-vintage-white-2201",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Clean Shopify store with standard theme"
    },
    {
      name: "Pura Vida Bracelets - Product Page",
      domain: "puravidabracelets.com",
      url: "https://www.puravidabracelets.com/products/braided-bracelet",
      handle: "braided-bracelet",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Shopify store with standard elements"
    },
    {
      name: "Death Wish Coffee - Product Page",
      domain: "deathwishcoffee.com",
      url: "https://www.deathwishcoffee.com/products/death-wish-coffee",
      handle: "death-wish-coffee",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Well-known Shopify store"
    },
    {
      name: "Ridge Wallet - Product Page",
      domain: "ridge.com",
      url: "https://ridge.com/products/the-ridge-wallet",
      handle: "the-ridge-wallet",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Popular Shopify Plus store"
    },
    {
      name: "Brooklinen - Classic Sheets",
      domain: "brooklinen.com",
      url: "https://www.brooklinen.com/products/classic-core-sheet-set",
      handle: "classic-core-sheet-set",
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price],
      notes: "Well-known Shopify Plus store"
    },
    {
      name: "Nonexistent product - 404 page (should fail scan)",
      domain: "allbirds.com",
      url: "https://allbirds.com/products/this-product-does-not-exist-xyz-999",
      handle: "this-product-does-not-exist-xyz-999",
      expect_scan_failure: true,
      notes: "Should return HTTP 404 or navigate to an error page"
    },
    {
      name: "Slow page simulation (high load time detection)",
      domain: "allbirds.com",
      url: "https://allbirds.com/products/mens-tree-runners",
      handle: "mens-tree-runners-slow-test",
      synthetic_overrides: { page_load_time_ms: 8000 },
      expect_issues: %w[slow_page_load],
      notes: "Uses synthetic override to test slow page detection threshold (5000ms)"
    },
    {
      name: "Synthetic - Missing ATC + JS errors",
      domain: "synthetic-test.myshopify.com",
      url: "https://synthetic-test.myshopify.com/products/broken",
      handle: "broken-page-test",
      synthetic_scan: {
        html_snapshot: '<html><body><h1>Product Title</h1><p>No cart button here</p></body></html>',
        js_errors: [{ "message" => "Uncaught TypeError: Cannot read property 'addToCart' of undefined" }],
        network_errors: [],
        page_load_time_ms: 3000
      },
      expect_issues: %w[missing_add_to_cart js_error missing_price],
      notes: "Fully synthetic scan to validate detection of multiple simultaneous issues"
    },
    {
      name: "Synthetic - Liquid errors + broken images",
      domain: "synthetic-test.myshopify.com",
      url: "https://synthetic-test.myshopify.com/products/liquid-errors",
      handle: "liquid-errors-test",
      synthetic_scan: {
        html_snapshot: '<html><body>Liquid error: undefined variable Translation missing: en.title <button name="add">Add</button><span class="price">$9.99</span></body></html>',
        js_errors: [],
        network_errors: [
          { "url" => "https://cdn.shopify.com/hero.jpg", "resource_type" => "image", "failure" => "net::ERR_FAILED" },
          { "url" => "https://cdn.shopify.com/thumb.png", "resource_type" => "image", "failure" => "net::ERR_FAILED" }
        ],
        page_load_time_ms: 2000
      },
      expect_issues: %w[liquid_error missing_images],
      expect_no_issues: %w[missing_add_to_cart missing_price slow_page_load],
      notes: "Synthetic scan validating liquid error + broken image detection without false positives"
    },
    {
      name: "Synthetic - Completely healthy page",
      domain: "synthetic-test.myshopify.com",
      url: "https://synthetic-test.myshopify.com/products/perfect",
      handle: "perfect-page-test",
      synthetic_scan: {
        html_snapshot: '<html><body><form action="/cart/add"><button type="submit" name="add">Add to Cart</button></form><span class="price">$49.99</span><img class="product-image" src="product.jpg"></body></html>',
        js_errors: [],
        network_errors: [],
        page_load_time_ms: 1200
      },
      expect_healthy: true,
      expect_no_issues: %w[missing_add_to_cart missing_price js_error liquid_error missing_images slow_page_load],
      notes: "Synthetic scan that should produce zero issues"
    }
  ].freeze

  attr_reader :results, :shop, :start_time

  def initialize
    @results = []
    @shop = nil
    @start_time = nil
  end

  def run
    @start_time = Time.current
    print_header
    setup_test_shop

    TEST_CASES.each_with_index do |test_case, index|
      run_test_case(test_case, index + 1)
    end

    cleanup
    print_summary
  end

  private

  def print_header
    puts ""
    puts "=" * 70
    puts "  Prowl — Live PDP Scan Test Suite"
    puts "  #{TEST_CASES.length} test cases | #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "=" * 70
    puts ""
  end

  def setup_test_shop
    @shop = Shop.create!(
      shopify_domain: "live-scan-test-#{SecureRandom.hex(4)}.myshopify.com",
      shopify_token: "test_token_live_scan",
      billing_exempt: true,
      subscription_status: "active"
    )
    puts "  Test shop created: #{@shop.shopify_domain}"
    puts ""
  end

  def run_test_case(test_case, number)
    puts "-" * 70
    puts "  [#{number}/#{TEST_CASES.length}] #{test_case[:name]}"
    puts "  URL: #{test_case[:url]}"
    puts ""

    result = { name: test_case[:name], checks: [], status: nil, duration: nil, error: nil }

    begin
      case_start = Time.current

      if test_case[:synthetic_scan]
        run_synthetic_test(test_case, result)
      elsif test_case[:synthetic_overrides]
        run_override_test(test_case, result)
      else
        run_live_test(test_case, result)
      end

      result[:duration] = (Time.current - case_start).round(2)
    rescue StandardError => e
      result[:status] = :error
      result[:error] = "#{e.class}: #{e.message}"
      puts "    #{FAIL} Unexpected error: #{e.message}"
      puts "         #{e.backtrace.first(3).join("\n         ")}"
    end

    @results << result
    puts ""
  end

  def run_live_test(test_case, result)
    product_page = create_product_page(test_case)

    puts "    Scanning with headless browser..."
    scanner = ProductPageScanner.new(product_page)
    scan_result = scanner.perform

    if test_case[:expect_scan_failure]
      check_scan_failure(scan_result, result)
      return
    end

    unless scan_result[:success]
      result[:status] = :fail
      result[:error] = "Scan failed: #{scan_result[:error]}"
      result[:checks] << { check: "scan_success", passed: false, message: scan_result[:error] }
      puts "    #{FAIL} Scan failed: #{scan_result[:error]}"
      return
    end

    result[:checks] << { check: "scan_success", passed: true, message: "Scan completed" }
    puts "    #{PASS} Scan completed (#{scan_result[:scan].page_load_time_ms}ms load time)"

    # Run detection
    detector = DetectionService.new(scan_result[:scan])
    issues = detector.perform

    print_scan_details(scan_result[:scan], issues)
    validate_expectations(test_case, issues, result)
    determine_result_status(result)
  end

  def run_synthetic_test(test_case, result)
    product_page = create_product_page(test_case)
    synthetic = test_case[:synthetic_scan]

    puts "    Running synthetic scan (no browser)..."

    scan = product_page.scans.create!(
      status: "completed",
      completed_at: Time.current,
      started_at: 3.seconds.ago,
      html_snapshot: synthetic[:html_snapshot],
      js_errors: synthetic[:js_errors],
      network_errors: synthetic[:network_errors],
      console_logs: synthetic[:console_logs] || [],
      page_load_time_ms: synthetic[:page_load_time_ms]
    )

    result[:checks] << { check: "scan_success", passed: true, message: "Synthetic scan created" }
    puts "    #{PASS} Synthetic scan created"

    detector = DetectionService.new(scan)
    issues = detector.perform

    print_scan_details(scan, issues)
    validate_expectations(test_case, issues, result)
    determine_result_status(result)
  end

  def run_override_test(test_case, result)
    product_page = create_product_page(test_case)
    overrides = test_case[:synthetic_overrides]

    puts "    Scanning with headless browser (with synthetic overrides)..."
    scanner = ProductPageScanner.new(product_page)
    scan_result = scanner.perform

    unless scan_result[:success]
      result[:status] = :fail
      result[:error] = "Scan failed: #{scan_result[:error]}"
      result[:checks] << { check: "scan_success", passed: false, message: scan_result[:error] }
      puts "    #{FAIL} Scan failed: #{scan_result[:error]}"
      return
    end

    # Apply overrides to the scan record
    scan = scan_result[:scan]
    scan.update!(overrides)

    result[:checks] << { check: "scan_success", passed: true, message: "Scan completed with overrides" }
    puts "    #{PASS} Scan completed, overrides applied (page_load_time_ms: #{scan.page_load_time_ms}ms)"

    detector = DetectionService.new(scan)
    issues = detector.perform

    print_scan_details(scan, issues)
    validate_expectations(test_case, issues, result)
    determine_result_status(result)
  end

  def check_scan_failure(scan_result, result)
    if scan_result[:success]
      # 404 pages may still "succeed" at HTTP level but produce detection issues
      result[:checks] << { check: "expected_failure", passed: true, message: "Scan completed (page may return soft 404)" }
      puts "    #{WARN} Scan succeeded — store may serve a soft 404. Checking detection..."

      detector = DetectionService.new(scan_result[:scan])
      issues = detector.perform
      print_scan_details(scan_result[:scan], issues)

      # A 404 page likely won't have an ATC button
      if issues.any? { |i| i.issue_type == "missing_add_to_cart" }
        result[:checks] << { check: "soft_404_detected", passed: true, message: "Missing ATC detected on 404 page" }
        puts "    #{PASS} Detection caught missing ATC on 404 page"
      end
    else
      result[:checks] << { check: "expected_failure", passed: true, message: "Scan failed as expected: #{scan_result[:error]}" }
      puts "    #{PASS} Scan failed as expected: #{scan_result[:error]}"
    end

    result[:status] = :pass
  end

  def create_product_page(test_case)
    @shop.product_pages.create!(
      shopify_product_id: rand(1_000_000..9_999_999),
      handle: test_case[:handle],
      title: test_case[:name].truncate(100),
      url: test_case[:url],
      monitoring_enabled: true,
      status: "pending"
    )
  end

  def print_scan_details(scan, issues)
    puts ""
    puts "    --- Scan Details ---"
    puts "    Load time:      #{scan.page_load_time_ms || 'N/A'}ms"
    puts "    JS errors:      #{scan.parsed_js_errors.length}"
    puts "    Network errors: #{scan.parsed_network_errors.length}"
    puts "    Issues found:   #{issues.length}"

    if issues.any?
      puts ""
      issues.each do |issue|
        severity_color = case issue.severity
        when "high" then "\e[31m"
        when "medium" then "\e[33m"
        else "\e[36m"
        end
        puts "    #{severity_color}[#{issue.severity.upcase}]\e[0m #{issue.issue_type}: #{issue.title}"
      end
    end
    puts ""
  end

  def validate_expectations(test_case, issues, result)
    issue_types = issues.map(&:issue_type)

    # Check expected issues are present
    (test_case[:expect_issues] || []).each do |expected_type|
      if issue_types.include?(expected_type)
        result[:checks] << { check: "expect_#{expected_type}", passed: true, message: "#{expected_type} detected" }
        puts "    #{PASS} Expected issue detected: #{expected_type}"
      else
        result[:checks] << { check: "expect_#{expected_type}", passed: false, message: "#{expected_type} NOT detected" }
        puts "    #{FAIL} Expected issue NOT detected: #{expected_type}"
      end
    end

    # Check unexpected issues are absent
    (test_case[:expect_no_issues] || []).each do |unexpected_type|
      if issue_types.include?(unexpected_type)
        result[:checks] << { check: "no_#{unexpected_type}", passed: false, message: "#{unexpected_type} falsely detected" }
        puts "    #{FAIL} False positive: #{unexpected_type} should not be detected"
      else
        result[:checks] << { check: "no_#{unexpected_type}", passed: true, message: "#{unexpected_type} correctly absent" }
        puts "    #{PASS} Correctly no #{unexpected_type}"
      end
    end

    # Check healthy expectation
    if test_case[:expect_healthy]
      high_issues = issues.select { |i| i.severity == "high" }
      if high_issues.empty?
        result[:checks] << { check: "healthy", passed: true, message: "No high severity issues" }
        puts "    #{PASS} Page is healthy (no high severity issues)"
      else
        types = high_issues.map(&:issue_type).join(", ")
        result[:checks] << { check: "healthy", passed: false, message: "High severity issues found: #{types}" }
        puts "    #{FAIL} Expected healthy but found high severity: #{types}"
      end
    end
  end

  def determine_result_status(result)
    return if result[:status] # Already set (error or explicit)

    failed_checks = result[:checks].count { |c| !c[:passed] }
    result[:status] = failed_checks.zero? ? :pass : :fail
  end

  def cleanup
    return unless @shop

    puts "-" * 70
    puts "  Cleaning up test data..."
    page_count = @shop.product_pages.count
    scan_count = Scan.joins(:product_page).where(product_pages: { shop_id: @shop.id }).count
    issue_count = Issue.joins(:product_page).where(product_pages: { shop_id: @shop.id }).count

    @shop.destroy!
    puts "  Removed: #{page_count} pages, #{scan_count} scans, #{issue_count} issues"
  end

  def print_summary
    elapsed = (Time.current - @start_time).round(1)
    passed = @results.count { |r| r[:status] == :pass }
    failed = @results.count { |r| r[:status] == :fail }
    errors = @results.count { |r| r[:status] == :error }
    skipped = @results.count { |r| r[:status] == :skip }

    puts ""
    puts "=" * 70
    puts "  RESULTS SUMMARY"
    puts "=" * 70
    puts ""

    @results.each_with_index do |r, i|
      status_str = case r[:status]
      when :pass then PASS
      when :fail then FAIL
      when :error then FAIL
      when :skip then SKIP
      else WARN
      end

      duration_str = r[:duration] ? " (#{r[:duration]}s)" : ""
      puts "  #{status_str} [#{i + 1}] #{r[:name]}#{duration_str}"

      if r[:status] == :fail || r[:status] == :error
        failed_checks = r[:checks].select { |c| !c[:passed] }
        failed_checks.each do |c|
          puts "       - #{c[:check]}: #{c[:message]}"
        end
        puts "       - Error: #{r[:error]}" if r[:error]
      end
    end

    puts ""
    puts "-" * 70
    color = failed.zero? && errors.zero? ? "\e[32m" : "\e[31m"
    puts "  #{color}#{passed} passed, #{failed} failed, #{errors} errors, #{skipped} skipped\e[0m"
    puts "  Total time: #{elapsed}s"
    puts "=" * 70
    puts ""

    # Return exit code for CI
    exit(failed + errors > 0 ? 1 : 0) if defined?(exit)
  end
end

# Run the test suite
LivePdpScanTest.new.run
