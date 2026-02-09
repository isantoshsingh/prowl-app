# Error Detection Engine - Manual Testing Plan

**Version**: 1.0
**Branch**: `claude/error-detection-engine-mLvCd`
**Target Theme**: Horizon (primary), Dawn/Debut/Craft (secondary)

---

## Prerequisites

### Environment Setup
1. Rails development environment running (`bin/rails server`)
2. PostgreSQL running with migrated database (`bin/rails db:migrate`)
3. Chrome/Chromium installed (required by puppeteer-ruby)
4. A Shopify Partner development store with:
   - Silent Profit app installed and authenticated
   - Active billing (trial or paid) on the shop
   - At least 5 products with images, prices, and variants
5. Access to Rails console (`bin/rails console`)

### Test Data Preparation
- **Store A**: Working Horizon theme store with healthy products
- **Store B** (optional): Store with a different theme (Dawn, Debut, or Craft)
- **Product 1**: Normal product with ATC button, images, price, variants
- **Product 2**: Sold-out product (all variants unavailable)
- **Product 3**: Product with only one variant (no variant selector)
- **Product 4**: Product with 10+ variants
- **Product 5**: Product with a single image

---

## Section 1: BrowserService Tests

### 1.1 Browser Launch & Cleanup

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 1.1.1 | Browser starts successfully | In Rails console: `bs = BrowserService.new; bs.start` | `bs.started?` returns `true`, no error logged | |
| 1.1.2 | Browser closes cleanly | `bs.close` | `bs.started?` returns `false`, log shows "[BrowserService] Browser closed" | |
| 1.1.3 | Double-start is idempotent | `bs.start; bs.start` | No error, browser runs once | |
| 1.1.4 | Close without start is safe | `bs = BrowserService.new; bs.close` | No error raised | |
| 1.1.5 | Cleanup on error (ensure block) | Force an error during navigation, then check browser state | Browser is closed, `bs.started?` returns `false` | |

### 1.2 Navigation

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 1.2.1 | Navigate to valid product URL | `bs.start; result = bs.navigate_to("https://{store}.myshopify.com/products/{handle}")` | `result[:success]` is `true`, `result[:status_code]` is 200 | |
| 1.2.2 | Navigate to 404 URL | `result = bs.navigate_to("https://{store}.myshopify.com/products/nonexistent-product-xyz")` | `result[:success]` is `false`, `result[:status_code]` is 404 | |
| 1.2.3 | Navigate to invalid domain | `result = bs.navigate_to("https://this-store-does-not-exist-abc123.myshopify.com/products/test")` | `result[:success]` is `false`, `result[:error]` is present | |
| 1.2.4 | Page load time is recorded | After successful navigation | `bs.page_load_time_ms` is a positive integer (typically 2000-15000) | |
| 1.2.5 | Retry on transient failure | Simulate network issue or navigate to unreliable URL | Logs show retry attempts (up to 2), then succeeds or fails gracefully | |

### 1.3 Password-Protected Store Detection

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 1.3.1 | Detect password-protected store | Enable password protection on dev store, navigate to product URL | `result[:success]` is `false`, `result[:password_protected]` is `true` | |
| 1.3.2 | No false positive on normal store | Navigate to store without password protection | `result[:password_protected]` is `nil` or absent | |

### 1.4 Error Capture

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 1.4.1 | JS errors captured | Navigate to a page with known JS errors (inject via theme editor: `<script>throw new Error("test error")</script>`) | `bs.js_errors` contains entry with matching message | |
| 1.4.2 | Console logs captured | Navigate to any page | `bs.console_logs` is an array, entries have `:type`, `:text`, `:timestamp` keys | |
| 1.4.3 | Network errors captured | Navigate to page with broken resource (e.g., reference non-existent CSS file in theme) | `bs.network_errors` contains entry with URL and failure reason | |
| 1.4.4 | Analytics blocked | Navigate to page with Google Analytics | No requests to `google-analytics.com` in network logs (verify via console or request count) | |
| 1.4.5 | Critical JS errors filtered | After navigation, call `bs.critical_js_errors` | Analytics/pixel/favicon errors excluded from result | |

### 1.5 Helper Methods

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 1.5.1 | evaluate_script returns value | `bs.evaluate_script("() => document.title")` | Returns the page title string | |
| 1.5.2 | evaluate_script handles timeout | `bs.evaluate_script("() => { while(true){} }", timeout_ms: 1000)` | Returns `nil`, log shows timeout warning | |
| 1.5.3 | evaluate_script handles error | `bs.evaluate_script("() => { throw new Error('test') }")` | Returns `nil`, no crash | |
| 1.5.4 | wait_for_selector found | `bs.wait_for_selector("body")` | Returns `true` | |
| 1.5.5 | wait_for_selector timeout | `bs.wait_for_selector("#nonexistent-element-xyz", timeout_ms: 1000)` | Returns `false`, no crash | |
| 1.5.6 | take_screenshot returns data | `data = bs.take_screenshot` | Returns non-nil binary data (PNG), `data.length > 0` | |
| 1.5.7 | page_content returns HTML | `html = bs.page_content` | Returns non-empty string containing `<html` | |

---

## Section 2: Detector Tests

### Setup for Each Detector Test
```ruby
bs = BrowserService.new
bs.start
bs.navigate_to("https://{store}.myshopify.com/products/{handle}")
```

### 2.1 AddToCartDetector

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 2.1.1 | Working ATC button detected | Navigate to normal product page, run `Detectors::AddToCartDetector.new(bs).perform` | `status: "pass"`, `confidence >= 0.8`, `details.evidence.button_found: true` | |
| 2.1.2 | Sold-out product handled | Navigate to sold-out product | `status: "pass"`, `details.technical_details.sold_out: true`, `confidence: 0.9` | |
| 2.1.3 | Hidden ATC button detected | Temporarily hide button via theme CSS (`display: none` on `.product-form__submit`), scan page | `status: "fail"`, `details.evidence.button_visible: false` | |
| 2.1.4 | Missing ATC button detected | Remove ATC button from theme template temporarily, scan page | `status: "fail"`, `confidence >= 0.8`, `details.evidence.button_found: false` | |
| 2.1.5 | Disabled ATC button (not sold out) | Disable button via JS without sold-out text | `status: "warning"` or `"fail"`, `button_enabled: false` | |
| 2.1.6 | Button text validated | Check the `button_text` field in result | Contains recognizable text like "Add to cart" or "Buy now" | |
| 2.1.7 | Form validation | Check `form_valid` and `form_action` fields | `form_valid: true` if form has `/cart/add` action | |
| 2.1.8 | Result structure complete | Inspect full result hash | Has `check: "add_to_cart"`, `status`, `confidence`, `details.message`, `details.technical_details`, `details.suggestions`, `details.evidence` | |

### 2.2 JavaScriptErrorDetector

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 2.2.1 | Clean page - no errors | Navigate to working product page | `status: "pass"`, `confidence: 0.9` | |
| 2.2.2 | Critical JS error detected | Add `<script>throw new TypeError("Cannot read properties of undefined (reading 'cart')")</script>` to theme | `status: "fail"`, critical_count > 0, matches "cart" pattern | |
| 2.2.3 | Syntax error detected | Add `<script>var x = {</script>` to theme | `status: "fail"`, syntax_count > 0 | |
| 2.2.4 | Third-party noise filtered | Verify Google Analytics, Facebook pixel errors are not in filtered results | No analytics-related errors in `critical_errors` or `syntax_errors` | |
| 2.2.5 | Non-critical error = warning | Add `<script>console.error("Some random error")</script>` | `status: "warning"` (error detected but not purchase-critical) | |
| 2.2.6 | Confidence scoring correct | With cart-related + syntax error | `confidence: 0.95` (highest tier) | |
| 2.2.7 | Error count accurate | Inject 3 distinct errors | `evidence.total_errors: 3` | |

### 2.3 LiquidErrorDetector

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 2.3.1 | Clean page - no errors | Navigate to working page | `status: "pass"`, `confidence: 0.9` | |
| 2.3.2 | Visible Liquid error | Add `{{ nonexistent_variable | filter_that_doesnt_exist }}` to product template (causes "Liquid error" text) | `status: "fail"`, `evidence.visible_error_count >= 1`, `confidence: 0.95` | |
| 2.3.3 | Translation missing detected | Add `{{ 'nonexistent.key' | t }}` to template | `status` is `"fail"` or `"warning"`, error type is "Translation missing" | |
| 2.3.4 | Hidden Liquid error | Add Liquid error inside HTML comment or hidden div | Detected but `visible_error_count: 0`, lower confidence than visible error | |
| 2.3.5 | Multiple error types | Inject both Liquid error and translation missing | Both appear in `technical_details.errors` array | |
| 2.3.6 | Error deduplication | Same error appears twice on page | Only counted once in results | |

### 2.4 PriceVisibilityDetector

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 2.4.1 | Price visible and formatted | Navigate to product with price $29.99 | `status: "pass"`, `evidence.price_text` contains "$29.99", `price_found: true`, `price_visible: true` | |
| 2.4.2 | Hidden price | Hide price via CSS (`display: none` on `.price`) | `status: "fail"`, `evidence.price_visible: false` | |
| 2.4.3 | Missing price element | Remove price element from template | `status: "fail"`, `evidence.price_found: false` | |
| 2.4.4 | Compare-at price detected | Set compare-at price on product (sale pricing) | `evidence.has_compare_at_price: true` or `has_sale_price: true` | |
| 2.4.5 | Multiple currency formats | Test with USD ($), EUR (€), GBP (£) stores | Price format validation passes for all | |
| 2.4.6 | Placeholder price rejected | If price text is "$0.00" or "loading" | `status: "fail"` or `"warning"` | |
| 2.4.7 | Selector fallback works | If primary `.price` selector fails, detector tries other selectors or text-based search | Eventually finds the price via fallback | |

### 2.5 ProductImageDetector

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 2.5.1 | Image present and loaded | Navigate to product with images | `status: "pass"`, `evidence.image_found: true`, `image_loaded: true`, `image_visible: true` | |
| 2.5.2 | Broken image (404 src) | Set image src to non-existent URL in theme | `status: "fail"`, `evidence.is_broken: true` or `image_loaded: false` | |
| 2.5.3 | No image on page | Remove image from product or template | `status: "fail"`, `evidence.image_found: false` | |
| 2.5.4 | Hidden image | Hide image via CSS | `status: "fail"`, `evidence.image_visible: false` | |
| 2.5.5 | Small image warning | Use a tiny image (< 200x200px) | `status: "warning"`, mentions small dimensions | |
| 2.5.6 | Lazy-loaded image | Product with `loading="lazy"` attribute on main image | Image should still be detected after lazy load wait (2s retry) | |
| 2.5.7 | Image dimensions recorded | Check result | `evidence.natural_width` and `natural_height` are positive integers | |
| 2.5.8 | Multiple images counted | Product with gallery (3+ images) | `evidence.total_images >= 3` | |
| 2.5.9 | Network image errors correlated | Image fails to load via network | `evidence.network_image_errors > 0` | |

---

## Section 3: ProductPageScanner (Orchestrator) Tests

### 3.1 Full Scan Flow

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 3.1.1 | Successful scan of working page | `pp = ProductPage.find({id}); scanner = ProductPageScanner.new(pp); result = scanner.perform` | `result[:success]: true`, `result[:scan].status: "completed"`, `result[:detection_results].length: 5` | |
| 3.1.2 | Scan data captured | After successful scan | `result[:data]` contains `:screenshot_url`, `:html_snapshot`, `:js_errors`, `:network_errors`, `:console_logs`, `:page_load_time_ms` | |
| 3.1.3 | Screenshot saved to disk | Check `result[:data][:screenshot_url]` path | File exists at `tmp/screenshots/scan_{id}_{timestamp}.png` | |
| 3.1.4 | HTML snapshot truncated | Check `result[:data][:html_snapshot].length` | Length is <= 500,000 characters | |
| 3.1.5 | Detection results stored in DB | `result[:scan].reload.parsed_dom_checks_data` | Returns array of 5 detection result hashes | |
| 3.1.6 | Console logs limited to 100 | After scanning a noisy page | `result[:data][:console_logs].length <= 100` | |

### 3.2 Error Handling

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 3.2.1 | Password-protected store | Enable password on store, run scan | `result[:success]: false`, scan status is "failed", error message mentions "password-protected" | |
| 3.2.2 | Invalid URL (404) | Create ProductPage with bogus URL, scan | `result[:success]: false`, scan status "failed", error mentions navigation | |
| 3.2.3 | Scan timeout | Set very slow page or reduce `SCAN_TIMEOUT_SECONDS` for testing | Scan fails with timeout message, browser is closed | |
| 3.2.4 | Individual detector failure | (Requires code modification to force one detector to raise) Verify other 4 detectors still run | `detection_results` has 4 real results + 1 "inconclusive" | |
| 3.2.5 | Browser cleanup on failure | After any failed scan, verify | No orphaned Chrome/Chromium processes (`ps aux | grep chrome`) | |

### 3.3 Browser Reuse

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 3.3.1 | External browser service | Create `BrowserService`, pass to scanner: `ProductPageScanner.new(pp, browser_service: bs)` | Scanner uses existing browser, does NOT close it after scan | |
| 3.3.2 | Owned browser service | `ProductPageScanner.new(pp)` (no browser_service) | Scanner creates and closes its own browser | |

---

## Section 4: DetectionService Tests

### 4.1 New Engine Path (with dom_checks_data)

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 4.1.1 | High-confidence fail creates issue | Run full scan on broken page, then `DetectionService.new(scan).perform` | Issue created with matching `issue_type`, `severity`, `status: "open"` | |
| 4.1.2 | Low-confidence fail does NOT create issue | Manually set `dom_checks_data` with `confidence: 0.5, status: "fail"` on a scan, run detection | No issue created, log shows "Low confidence" message | |
| 4.1.3 | Pass status resolves existing issue | Create an open issue, then run scan with `status: "pass"` for same check | Issue status changed to "resolved" | |
| 4.1.4 | Pass resolves acknowledged issues too | Create an acknowledged issue, then run scan with `status: "pass"` | Issue status changed to "resolved" (not stuck in "acknowledged") | |
| 4.1.5 | Inconclusive leaves state unchanged | Create an open issue, then run scan with `status: "inconclusive"` | Issue remains "open", not resolved or updated | |
| 4.1.6 | Warning creates low-severity issue | Scan with `status: "warning", confidence: 0.8` | Issue created with `severity: "low"` | |
| 4.1.7 | Duplicate prevention | Run two scans that both detect same issue type | Second scan increments `occurrence_count` instead of creating new issue | |

### 4.2 Legacy Fallback Path

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 4.2.1 | Legacy runs when no dom_checks_data | Create scan with `dom_checks_data: nil` (or empty), run detection | Legacy detection methods execute (check logs for "legacy" detection_method in evidence) | |
| 4.2.2 | Variant selector detection works | Scan with JS error containing "variant" in message | `variant_selector_error` issue created | |
| 4.2.3 | Slow page load detection | Scan with `page_load_time_ms: 6000` (above 5000ms threshold) | `slow_page_load` issue created with `severity: "low"` | |
| 4.2.4 | Fast page resolves slow issue | First scan: slow (>5000ms). Second scan: fast (<5000ms) | `slow_page_load` issue is resolved | |

### 4.3 Issue Lifecycle

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 4.3.1 | Issue occurrence count increments | Scan page with same error 3 times | Issue `occurrence_count` is 3, `last_detected_at` updates each time | |
| 4.3.2 | Alert only fires after 2 occurrences | Check `issue.should_alert?` after 1 scan and after 2 scans | `false` after 1st, `true` after 2nd (for high severity open issues) | |
| 4.3.3 | Medium severity never triggers alert | Create medium-severity issue with occurrence_count = 5 | `should_alert?` returns `false` (only high severity alerts) | |
| 4.3.4 | Product page status updates | After scan with high severity issue | `product_page.status` is "critical" | |
| 4.3.5 | Product page becomes healthy | Resolve all issues, run `update_status_from_issues!` | `product_page.status` is "healthy" | |

---

## Section 5: ScanPdpJob Tests

### 5.1 Job Execution

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 5.1.1 | Job runs successfully | `ScanPdpJob.perform_now(product_page.id)` | Scan created with status "completed", detection results stored, issues created/updated | |
| 5.1.2 | Job skips inactive billing | Set `shop_setting.billing_status = "expired"`, run job | Log shows "billing not active", no scan created | |
| 5.1.3 | Job skips disabled monitoring | Set `product_page.monitoring_enabled = false`, run job | Log shows "monitoring disabled", no scan created | |
| 5.1.4 | Job handles scan failure | Use invalid product URL, run job | Log shows "Scan failed", no issues created, no crash | |
| 5.1.5 | AlertService failure doesn't crash job | (Requires mocking or temporarily breaking AlertMailer) Force AlertService to fail | Job completes, log shows AlertService error, but scan and detection complete normally | |
| 5.1.6 | Job retry on StandardError | Kill browser mid-scan | Job retries (up to 3 attempts with polynomial backoff) | |

### 5.2 Job Queue Integration

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 5.2.1 | Job enqueues to correct queue | `ScanPdpJob.perform_later(product_page.id)` | Job appears in `scans` queue in Solid Queue | |
| 5.2.2 | Deleted product page discarded | Delete product page, run job with old ID | Job discarded (ActiveRecord::RecordNotFound), no error | |

---

## Section 6: End-to-End Scenarios

### 6.1 Healthy Product Page

| Step | Action | Verify |
|------|--------|--------|
| 1 | Navigate to Shopify admin, ensure Product 1 is normal (has images, price, ATC, no errors) | Product is accessible |
| 2 | Add Product 1 to monitoring via UI | ProductPage record created, ScanPdpJob enqueued |
| 3 | Wait for scan to complete | Scan record status = "completed" |
| 4 | Check issues | 0 issues created |
| 5 | Check product page status | Status = "healthy" |
| 6 | Check detection results | All 5 detectors returned "pass" |

**Expected**: Zero issues, healthy status, all 5 detectors pass.

### 6.2 Page with Hidden ATC Button

| Step | Action | Verify |
|------|--------|--------|
| 1 | In theme editor, add CSS to hide ATC button: `.product-form__submit { display: none !important; }` | Button hidden on storefront |
| 2 | Trigger rescan for the product | ScanPdpJob runs |
| 3 | Check issues | 1 new issue: type = "missing_add_to_cart", severity = "high" |
| 4 | Check detection result for add_to_cart | `status: "fail"`, `evidence.button_visible: false` |
| 5 | Check product page status | Status = "critical" |
| 6 | Remove the CSS, trigger rescan | Issue resolved, status = "healthy" |

### 6.3 Page with Missing Price

| Step | Action | Verify |
|------|--------|--------|
| 1 | In theme product template, wrap price in `{% comment %}...{% endcomment %}` | Price hidden |
| 2 | Trigger rescan | Scan completes |
| 3 | Check issues | Issue type = "missing_price", severity = "high" |
| 4 | Check detection result for price_visibility | `status: "fail"`, `evidence.price_found: false` |
| 5 | Restore price, rescan | Issue resolved |

### 6.4 Page with Broken Image

| Step | Action | Verify |
|------|--------|--------|
| 1 | Replace main product image src with `https://cdn.shopify.com/nonexistent.jpg` (or delete product images) | Image broken |
| 2 | Trigger rescan | Scan completes |
| 3 | Check issues | Issue type = "missing_images", severity = "medium" |
| 4 | Check detection result for product_images | `status: "fail"`, `evidence.image_loaded: false` or `image_found: false` |
| 5 | Fix image, rescan | Issue resolved |

### 6.5 Page with Visible Liquid Error

| Step | Action | Verify |
|------|--------|--------|
| 1 | Add `{{ product.nonexistent | broken_filter }}` to product template | Visible "Liquid error" on page |
| 2 | Trigger rescan | Scan completes |
| 3 | Check issues | Issue type = "liquid_error", severity = "medium" |
| 4 | Check detection result | `status: "fail"`, `evidence.visible_error_count >= 1`, `confidence >= 0.85` |
| 5 | Remove Liquid error, rescan | Issue resolved |

### 6.6 Password-Protected Store

| Step | Action | Verify |
|------|--------|--------|
| 1 | Enable password protection on store (Shopify admin > Online Store > Preferences) | Storefront shows password page |
| 2 | Trigger rescan | Scan completes |
| 3 | Check scan status | Status = "failed" |
| 4 | Check error message | Contains "password-protected" |
| 5 | Check product page status | Status = "error" |
| 6 | Verify no issues created | 0 new issues from this scan |
| 7 | Verify no crash | App still responsive, no zombie browser processes |

### 6.7 Sold-Out Product

| Step | Action | Verify |
|------|--------|--------|
| 1 | Set all variants to 0 inventory, track inventory, don't allow oversell | Product shows "Sold out" |
| 2 | Trigger rescan | Scan completes |
| 3 | Check ATC detector result | `status: "pass"`, `technical_details.sold_out: true`, `confidence: 0.9` |
| 4 | Check issues | No `missing_add_to_cart` issue created (disabled button is expected) |

### 6.8 Alert Triggering Flow

| Step | Action | Verify |
|------|--------|--------|
| 1 | Create a broken page (hidden ATC button) | |
| 2 | Scan once | Issue created, `occurrence_count: 1`, `should_alert?: false` |
| 3 | Scan again (same broken state) | `occurrence_count: 2`, `should_alert?: true` |
| 4 | Check alerts table | Alert record created with `alert_type: "email"`, `delivery_status` tracked |
| 5 | Scan a third time | `occurrence_count: 3`, no duplicate alert (alert already exists) |

### 6.9 Issue Resolution Lifecycle

| Step | Action | Verify |
|------|--------|--------|
| 1 | Scan broken page twice (ATC hidden) | Issue: open, occurrence_count: 2 |
| 2 | Acknowledge issue via UI | Issue status = "acknowledged" |
| 3 | Fix the page (restore ATC button) | |
| 4 | Scan again | Issue status = "resolved" (acknowledged issues ARE resolved on pass) |
| 5 | Break the page again | New issue created (fresh occurrence_count: 1) |

---

## Section 7: Performance Tests

### 7.1 Single Page Timing

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 7.1.1 | Single page scan time | Time a single `ProductPageScanner.new(pp).perform` | Completes in < 15 seconds | |
| 7.1.2 | Page load time recorded | Check `scan.page_load_time_ms` | Reasonable value (1000-15000ms) | |

### 7.2 Multi-Page Scan (5 Pages)

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 7.2.1 | 5 pages in sequence with shared browser | See script below | Total time < 60 seconds | |
| 7.2.2 | Per-page average | Calculate average from 5-page run | < 12 seconds per page | |
| 7.2.3 | No browser zombie after batch | After batch completes, `ps aux \| grep chrome` | No orphaned Chrome processes | |

**Multi-page test script:**
```ruby
bs = BrowserService.new
bs.start
start_time = Time.now

pages = ProductPage.monitoring_enabled.limit(5)
pages.each do |pp|
  scanner = ProductPageScanner.new(pp, browser_service: bs)
  result = scanner.perform
  puts "#{pp.title}: #{result[:success] ? 'OK' : 'FAIL'} (#{result[:scan].page_load_time_ms}ms)"
end

bs.close
total = Time.now - start_time
puts "Total: #{total.round(1)}s, Average: #{(total / pages.count).round(1)}s per page"
```

### 7.3 Resource Blocking

| # | Test Case | Steps | Expected Result | Pass/Fail |
|---|-----------|-------|-----------------|-----------|
| 7.3.1 | Fonts blocked | Scan with default settings, check network logs | No font requests in network activity | |
| 7.3.2 | Analytics blocked | Scan with default settings | No Google Analytics, Facebook pixel, Hotjar requests | |
| 7.3.3 | Blocking improves speed | Compare scan time with and without `block_unnecessary_resources: true` vs `false` | Blocking is faster by measurable amount | |

---

## Section 8: Database Verification

### 8.1 Schema Checks

| # | Verify | SQL/Rails Query | Expected |
|---|--------|-----------------|----------|
| 8.1.1 | `dom_checks_data` column exists | `Scan.column_names.include?("dom_checks_data")` | `true` |
| 8.1.2 | Detection results persist | `scan.reload.dom_checks_data` after scan | Non-nil JSON array |
| 8.1.3 | JSON serialization works | `scan.parsed_dom_checks_data` | Returns Ruby array of hashes |
| 8.1.4 | Empty data handled | `Scan.new.parsed_dom_checks_data` | Returns `[]` |

### 8.2 Data Integrity

| # | Verify | Check | Expected |
|---|--------|-------|----------|
| 8.2.1 | Scan → ProductPage relationship | `scan.product_page` | Returns correct ProductPage |
| 8.2.2 | Issue → Scan relationship | `issue.scan` | Returns the scan that created it |
| 8.2.3 | Issue evidence contains confidence | `issue.evidence` parsed JSON | Has `confidence` key with float value |
| 8.2.4 | Foreign keys enforced | Try to delete ProductPage with scans | Rails raises error or cascades delete |

---

## Section 9: Theme Compatibility

### 9.1 Horizon Theme (Primary Target)

| # | Test Case | Expected | Pass/Fail |
|---|-----------|----------|-----------|
| 9.1.1 | ATC button found | `product-form button[type="submit"]` selector works | |
| 9.1.2 | Price found | `.price` or `.price__regular` selector works | |
| 9.1.3 | Images found | `product-media img` or `.product__media img` selector works | |
| 9.1.4 | No false positives | All 5 detectors return "pass" on healthy page | |

### 9.2 Dawn Theme (Secondary)

| # | Test Case | Expected | Pass/Fail |
|---|-----------|----------|-----------|
| 9.2.1 | ATC button found | Selectors find Dawn's ATC button pattern | |
| 9.2.2 | Price found | Price selectors locate Dawn's pricing | |
| 9.2.3 | Images found | Image selectors locate Dawn's product images | |
| 9.2.4 | No false positives | All detectors pass on healthy Dawn page | |

### 9.3 Other Themes (If Time Permits)

Test Debut and Craft themes with the same 4 checks above. Document any theme-specific failures.

---

## Section 10: Negative Tests (Things That Should NOT Happen)

| # | Scenario | Verify |
|---|----------|--------|
| 10.1 | Normal product page → no false issues | 0 issues created on healthy page scan |
| 10.2 | Sold-out product → no ATC false positive | No `missing_add_to_cart` issue |
| 10.3 | Analytics JS errors → not flagged | No `js_error` issue from analytics/pixel scripts |
| 10.4 | Low confidence result → no issue | Confidence 0.5 failure creates no issue |
| 10.5 | Single occurrence → no alert | `should_alert?` is `false` after first detection |
| 10.6 | Medium severity → no alert | Medium-severity issues never trigger `should_alert?` |
| 10.7 | Failed scan → no false issues | Scan with status "failed" creates 0 issues |
| 10.8 | Inconclusive → no state change | Inconclusive result doesn't resolve or create issues |

---

## Appendix A: Quick Smoke Test (5 Minutes)

For rapid verification after deployment:

1. **Start a scan**: `ScanPdpJob.perform_now(ProductPage.first.id)` in console
2. **Verify scan completed**: `Scan.last.status` should be `"completed"`
3. **Verify detection results stored**: `Scan.last.parsed_dom_checks_data.length` should be `5`
4. **Verify no false positives on healthy page**: `Issue.where(scan: Scan.last).count` should be `0`
5. **Verify browser cleaned up**: `ps aux | grep -i chrom | grep -v grep` should show no leftover processes

## Appendix B: Rails Console Cheat Sheet

```ruby
# Run a single scan manually
pp = ProductPage.find(ID)
scanner = ProductPageScanner.new(pp)
result = scanner.perform
puts result[:success]
puts result[:detection_results].map { |r| "#{r[:check]}: #{r[:status]} (#{r[:confidence]})" }

# Check detection results stored in DB
scan = Scan.last
scan.parsed_dom_checks_data.each do |r|
  puts "#{r['check']}: #{r['status']} (confidence: #{r['confidence']})"
end

# Check issues for a page
pp.issues.open.each { |i| puts "#{i.issue_type}: #{i.severity} (#{i.occurrence_count}x)" }

# Run detection service manually
ds = DetectionService.new(scan)
issues = ds.perform
issues.each { |i| puts "#{i.issue_type}: #{i.status} (#{i.severity})" }

# Run a single detector
bs = BrowserService.new
bs.start
bs.navigate_to("https://store.myshopify.com/products/handle")
result = Detectors::AddToCartDetector.new(bs).perform
pp result
bs.close
```
