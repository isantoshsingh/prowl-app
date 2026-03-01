#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone script that mirrors the EXACT production scan flow.
# Uses the same classes and code paths as ScanPdpJob → ProductPageScanner → Detectors.
#
# Usage:
#   bin/rails runner test/scripts/funnel_detection_test.rb
#   bin/rails runner test/scripts/funnel_detection_test.rb https://your-store.myshopify.com/products/your-product
#

URL = ARGV[0] || "https://first-shopify-app.myshopify.com/products/organic-cotton-backpack-fair-trade-certified"

puts "=" * 80
puts "  PURCHASE FUNNEL DETECTION TEST (Production Code Paths)"
puts "  URL: #{URL}"
puts "  Time: #{Time.current}"
puts "=" * 80
puts

browser = nil

begin
  # ── Step 1: Launch browser (same as ProductPageScanner#start_browser) ───
  print "1. Launching browser... "
  browser = BrowserService.new
  browser.start
  puts "✅ #{ENV['BROWSERLESS_URL'].present? ? 'Browserless' : 'Local Chrome'}"

  # ── Step 2: Navigate (same as ProductPageScanner#navigate_to_page) ──────
  print "2. Navigating to product page... "
  nav_result = browser.navigate_to(URL)
  unless nav_result[:success]
    puts "❌ #{nav_result[:error]}"
    exit 1
  end
  puts "✅ (status: #{nav_result[:status_code]})"

  # ── Step 3: Run ALL Tier 1 detectors (same as ProductPageScanner#run_detectors) ─
  puts "\n── TIER 1 DETECTORS (Quick Scan) ───────────────────────────────────"

  ProductPageScanner::TIER1_DETECTORS.each do |detector_class|
    detector = if detector_class == Detectors::AddToCartDetector
      detector_class.new(browser, scan_depth: :quick)
    else
      detector_class.new(browser)
    end

    result = detector.perform

    status = result[:status]
    icon = case status
      when "pass" then "✅"
      when "fail" then "❌"
      when "warning" then "⚠️"
      else "❓"
    end

    name = result[:check].ljust(20)
    puts "   #{icon} #{name} conf=#{result[:confidence]}  #{result.dig(:details, :message)}"
  end

  # ── Step 4: Run AddToCartDetector in DEEP mode ──────────────────────────
  puts "\n── ADD TO CART DETECTOR (Deep Scan) ────────────────────────────────"

  # Re-navigate for a clean state (same as a fresh scan)
  browser.navigate_to(URL)
  sleep(2)

  deep_detector = Detectors::AddToCartDetector.new(browser, scan_depth: :deep)
  deep_result = deep_detector.perform

  icon = case deep_result[:status]
    when "pass" then "✅"
    when "fail" then "❌"
    when "warning" then "⚠️"
    else "❓"
  end

  puts "   Status:      #{icon} #{deep_result[:status].upcase}"
  puts "   Confidence:  #{deep_result[:confidence]}"
  puts "   Message:     #{deep_result.dig(:details, :message)}"

  tech = deep_result.dig(:details, :technical_details) || {}
  puts "   Technical:   #{tech.to_json}" if tech.any?

  evidence = deep_result.dig(:details, :evidence) || {}
  puts "   Evidence:    #{evidence.to_json}" if evidence.any?

  suggestions = deep_result.dig(:details, :suggestions) || []
  if suggestions.any?
    puts "   Suggestions:"
    suggestions.each { |s| puts "     • #{s}" }
  end

  # ── Step 5: Simulate DetectionService (same as ScanPdpJob#perform) ──────
  puts "\n── DETECTION SERVICE (Issue Creation Simulation) ────────────────────"

  # Collect all results as the scanner would
  all_results = []

  browser.navigate_to(URL)
  sleep(2)

  ProductPageScanner::TIER1_DETECTORS.each do |detector_class|
    detector = if detector_class == Detectors::AddToCartDetector
      detector_class.new(browser, scan_depth: :deep)
    else
      detector_class.new(browser)
    end
    result = detector.perform
    all_results << result if result
  end

  # Process through DetectionService logic (without DB writes)
  puts "\n   Detection results → Issue mapping:"
  all_results.each do |result|
    check = result[:check] || result["check"]
    status = result[:status] || result["status"]
    confidence = (result[:confidence] || result["confidence"]).to_f

    issue_type = DetectionService::CHECK_TO_ISSUE_TYPE[check]
    severity = DetectionService::CHECK_SEVERITY[check]

    next unless issue_type

    would_create = status == "fail" && confidence >= DetectionService::CONFIDENCE_THRESHOLD
    would_warn = status == "warning" && confidence >= DetectionService::CONFIDENCE_THRESHOLD
    would_resolve = status == "pass"

    action = if would_create
      "🔴 CREATE ISSUE (#{severity})"
    elsif would_warn
      "🟡 CREATE WARNING (low)"
    elsif would_resolve
      "🟢 RESOLVE existing"
    else
      "⚪ NO ACTION (conf=#{confidence} < #{DetectionService::CONFIDENCE_THRESHOLD})"
    end

    puts "   #{check.ljust(20)} → #{issue_type.ljust(25)} #{action}"
  end

  # ── Summary ─────────────────────────────────────────────────────────────
  puts "\n" + "=" * 80
  puts "  SUMMARY"
  puts "=" * 80

  failures = all_results.select { |r| r[:status] == "fail" && (r[:confidence] || 0).to_f >= 0.7 }
  warnings = all_results.select { |r| r[:status] == "warning" && (r[:confidence] || 0).to_f >= 0.7 }
  passes = all_results.select { |r| r[:status] == "pass" }

  puts "  Checks run:  #{all_results.length}"
  puts "  ✅ Passed:   #{passes.length}"
  puts "  ❌ Failed:   #{failures.length}"
  puts "  ⚠️  Warnings: #{warnings.length}"

  if failures.any?
    puts "\n  Issues that would be created in production:"
    failures.each do |r|
      type = DetectionService::CHECK_TO_ISSUE_TYPE[r[:check]]
      sev = DetectionService::CHECK_SEVERITY[r[:check]]
      title = Issue::ISSUE_TYPES.dig(type, :title) || r.dig(:details, :message)
      puts "    🔴 [#{sev&.upcase}] #{title}"
    end
  else
    puts "\n  ✅ No issues detected — page appears healthy"
  end

  puts

rescue StandardError => e
  puts "\n❌ ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
ensure
  if browser
    print "\nClosing browser... "
    browser.close rescue nil
    puts "done."
  end
end
