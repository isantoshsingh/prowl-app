# Prowl Phase 2 — Implementation Plan

_Last updated: 2026-03-24_

---

## 1. Current State (Phase 1 Baseline)

### What exists and works
- **Scanner engine**: `BrowserService` (puppeteer-ruby) → `ProductPageScanner` → five Tier-1 detectors with confidence scoring
- **Detection pipeline**: `ScanPipelineService` — five steps (programmatic detection → AI page analysis → per-issue AI explanation → alerting → rescan scheduling)
- **AI integration**: Gemini 2.5 Flash for page-level visual analysis + per-issue explanation/confirmation. Currently sends a **single screenshot** per scan.
- **Issues**: 10 issue types defined in `Issue::ISSUE_TYPES`; `missing_add_to_cart`, `atc_not_functional`, `checkout_broken` are all present. `checkout_broken` is disabled (AI-only, no programmatic detector — caused false positives in Phase 1).
- **Cart funnel test**: `AddToCartDetector` Layer 2 (deep scans) already clicks the ATC button and polls `/cart.js` up to 4× to verify item count increases — implemented in `add_to_cart_detector.rb`
- **Screenshots**: Single screenshot captured per scan via `BrowserService#take_screenshot`, uploaded to Cloudflare R2 via `ScreenshotUploader`. Stored as `{shop-slug}/{product-handle}/scan_{id}_{timestamp}.png`. `scans.screenshot_url` stores the R2 key (string column).
- **Alerting**: `AlertService` → `AlertMailer`; batched email per product page per scan; per-scan dedup via unique index on `(shop_id, issue_id, alert_type, scan_id)`; AI-generated merchant explanation + suggested fix included. `AlertMailer#issues_resolved` template exists but is **not wired up**.
- **Billing**: Single Shopify recurring charge ("Prowl Monthly", $10/month, 14-day trial) configured in `config/initializers/shopify_app.rb`. `Subscription` model tracks charge history with fields: `subscription_charge_id`, `charge_name`, `price`, `currency_code`, `trial_days`, `activated_at`, `cancelled_at`. `Shop` caches `subscription_plan` and `subscription_status`.
- **Page limits**: `Shop::MAX_MONITORED_PAGES = 3` (hardcoded constant in `app/models/shop.rb:14`). `ShopSetting#max_monitored_pages` also exists (default: 3) but is not dynamically linked to plan tier.
- **Scan scheduling**: `ScheduledScanJob` queues scans for shops where `subscription_status: "active"` or `billing_exempt: true` (fixed pre-Phase 2); `ScanPdpJob` determines depth (deep on first scan, open critical issues, or Mondays; quick otherwise)
- **scan_frequency**: Column exists on `shop_settings` and is now wired to the scheduler — `ShopSetting#scan_interval` is the single source of truth, used by both `ProductPage#needs_scan?` and `ScheduledScanJob#scan_interval_for`. Currently supports `daily` (24h) and `weekly` (7d). Phase 2 will add `every_4_hours` and `every_6_hours` as valid values for paid tiers.
- **BrowserService checkout methods**: `navigate_to_checkout`, `read_cart_state`, `clear_cart_item` already exist but `navigate_to_checkout` is **not called** in any detector flow. These are ready-to-use building blocks.
- **Infrastructure**: PostgreSQL + Solid Queue (no Redis) + Solid Cache; Browserless.io for production Chrome; Cloudflare R2 for screenshots; Resend for email. Single Heroku Basic dyno (~200MB of 512MB).

### Known bugs to fix before Phase 2 features ship

_No known bugs — the `ScheduledScanJob` billing filter fix has already been merged to main._

### Intentional alert behaviour (not a bug)

`AlertService` fires an alert on every scan that finds an unacknowledged high-severity issue. This is **by design**: merchants receive repeated alerts until they explicitly acknowledge the issue in the dashboard. Acknowledging an issue (`Issue#acknowledge!`) sets `status: "acknowledged"`, which causes `Issue#should_alert?` to return false and stops future alerts.

However, with Phase 2 scan frequencies of every 4–6 hours, this means up to **6 emails per day** for a single unacknowledged issue. The `alert_suppression_hours` setting (Feature 2D.2) is the mechanism to prevent this — merchants choose how often they want to be re-notified about the same persisting issue.

---

## 2. Phase 2 Features

### Feature A — Tiered Billing & Plan Enforcement

**Goal**: Introduce three pricing tiers with different page limits and scan frequencies.

#### 2A.1 — Define the three plans

| Plan | Price | Pages | Scan Frequency | Deep Scans | Multi-Screenshot | Checkout Test | Slack Alerts |
|------|-------|-------|----------------|------------|------------------|---------------|--------------|
| Starter | $10/month | 10 | Daily (24h) | Weekly only (Mondays) | No | No | No |
| Growth | $29/month | 25 | Every 4 hours | Yes (all scans) | Yes | Yes | Yes |
| Pro | $79/month | 100 | Every 6 hours | Yes (all scans) | Yes | Yes | Yes |

**Key pricing decisions:**
- **Starter** inherits the Phase 1 price point ($10) but increases page limit from 3 → 10. Deep scans are limited to weekly (Mondays) to control Browserless.io costs. No access to multi-screenshot funnel capture, checkout testing, or Slack integration.
- **Growth** is the target tier for active merchants who want proactive monitoring. Every-4-hour scans with full deep scan support.
- **Pro** caps at 100 pages (not truly unlimited — see Open Question 1). Every-6-hour scans. Same feature set as Growth but higher page limit.
- All plans include: all 5 Tier-1 detectors, AI visual analysis (Gemini), email alerts, alert suppression settings, scan history dashboard.
- 14-day free trial on all plans (Shopify handles trial billing).

These names, prices, and limits are a starting point. The constraint is that Shopify only supports one active recurring charge per app installation — plan changes require cancelling the old charge and creating a new one. Shopify's billing API supports this via `appSubscriptionCreate`.

#### 2A.2 — Shopify billing changes

`config/initializers/shopify_app.rb` currently hardcodes a single `BillingConfiguration`. For multiple plans, remove the single `config.billing` block and instead create a new `BillingPlan` service object that builds the correct `appSubscriptionCreate` GraphQL mutation payload based on the selected plan.

Add a `plan_name` column to `subscriptions` (already exists: `charge_name`). When a merchant selects a plan, call `appSubscriptionCreate` with the appropriate price. After Shopify redirects back, `SubscriptionSyncService#sync` will pick up the new active subscription.

**New service**: `app/services/billing_plan_service.rb`
```ruby
PLANS = {
  "starter" => {
    price: 10, pages: 10, interval_hours: 24,
    charge_name: "Prowl Starter",
    deep_scan_frequency: :weekly,       # Mondays only
    multi_screenshot: false,
    checkout_test: false,
    slack_alerts: false
  },
  "growth"  => {
    price: 29, pages: 25, interval_hours: 4,
    charge_name: "Prowl Growth",
    deep_scan_frequency: :every_scan,   # All scans eligible
    multi_screenshot: true,
    checkout_test: true,
    slack_alerts: true
  },
  "pro"     => {
    price: 79, pages: 100, interval_hours: 6,
    charge_name: "Prowl Pro",
    deep_scan_frequency: :every_scan,
    multi_screenshot: true,
    checkout_test: true,
    slack_alerts: true
  }
}.freeze

def self.feature_available?(plan, feature)
  PLANS.dig(plan, feature) || false
end
```

**Plan feature checks** — gate features in the scanner and alert pipelines:
```ruby
# In ScanPdpJob, when determining scan depth:
def determine_scan_depth(product_page)
  plan = BillingPlanService::PLANS[product_page.shop.subscription_plan] || BillingPlanService::PLANS["starter"]
  return :deep if product_page.scans.none?  # Always deep on first scan
  return :deep if plan[:deep_scan_frequency] == :every_scan
  return :deep if plan[:deep_scan_frequency] == :weekly && Time.current.monday?
  :quick
end
```

#### 2A.3 — Enforce page limits per tier

Replace `Shop::MAX_MONITORED_PAGES = 3` with a dynamic lookup:
```ruby
def max_monitored_pages
  BillingPlanService::PLANS.dig(subscription_plan, :pages) || 3
end
```
`shop.can_add_monitored_page?` already uses `shop_setting.max_monitored_pages`, so update `ShopSetting#max_monitored_pages` to delegate to the shop's plan. Remove the hardcoded `MAX_MONITORED_PAGES` constant or keep it as a fallback default for billing-exempt shops.

#### 2A.4 — Plan selection UI

Add a `/billing/plans` page (new `plans` action on `BillingController`) showing the three plan cards with Polaris `Card` components. The current `BillingController` (`app/controllers/billing_controller.rb`) is 25 lines — extend it with `plans`, `select_plan`, and `cancel` actions.

On install, redirect to plan selection instead of immediately triggering the hardcoded billing flow. After plan approval, `AfterAuthenticateJob` should call `SubscriptionSyncService#sync` and set `shop.subscription_plan` from the returned `charge_name`.

---

### Feature B — Cart Interaction Scanning Improvements

**Goal**: Detect more cart-layer breakage beyond the current ATC click + item count check.

#### What already works (do not re-implement)

`AddToCartDetector` Layer 2 already:
- Selects first available variant via `BrowserService#select_first_variant`
- Clicks the ATC button via `BrowserService#click_add_to_cart`
- Reads `/cart.js` and polls 4× (1s intervals) to verify item count increases
- Cleans up via `BrowserService#clear_cart_item`
- Issues `atc_not_functional` when cart count doesn't increase

`BrowserService` already exposes `read_cart_state`, `clear_cart_item`, and `navigate_to_checkout`. These are building blocks for the new checks.

#### 2B.1 — Cart item correctness verification

After the ATC click succeeds (cart count increased), add a check that the cart item matches the expected product. Read `/cart.js` and verify:
- `cart.items[last].product_id` matches `product_page.shopify_product_id`
- `cart.items[last].price` is a non-zero integer
- `cart.items[last].quantity == 1`

Add a new helper in `BrowserService`:
```ruby
def verify_cart_item(expected_product_id)
  cart = read_cart_state
  last_item = cart.dig("items", -1)
  return false unless last_item
  last_item["product_id"].to_s == expected_product_id.to_s &&
    last_item["price"].to_i > 0
end
```

If item verification fails after a successful click, issue `atc_not_functional` with evidence `{ reason: "wrong_item_in_cart", cart_state: ... }`.

#### 2B.2 — Cart drawer / page opening detection

Some themes open a cart drawer on ATC click. Others navigate to `/cart`. Either way, something visible should happen. Add a post-ATC check in the deep scan funnel:

1. After clicking ATC and confirming cart item count increased, wait up to 2 seconds for either:
   - A cart drawer selector to become visible (common selectors: `[id*="cart-drawer"]`, `[class*="cart-drawer"]`, `[data-cart-drawer]`, `[id*="CartDrawer"]`)
   - A URL change to `/cart`
   - A cart icon/count to update (e.g. `[class*="cart-count"]`)
2. If none of these appear within 2 seconds but the item IS in the cart via `/cart.js`, treat this as a **warning** (`medium` severity), not a hard failure. It may be an intentional theme design choice.
3. Only escalate to `atc_not_functional` if the cart item count never increased.

Implement as a new `BrowserService#cart_feedback_visible?` method. Call it from `AddToCartDetector#run_funnel_test`.

#### 2B.3 — Checkout navigation test (deep scans only)

`BrowserService#navigate_to_checkout` already exists but is not called in the current detector flow. Wire it into `AddToCartDetector`:
- After confirming item in cart, navigate to `/checkout`
- If response is a redirect to Shopify's checkout domain (`checkout.shopify.com` or `shop.app`), mark as pass
- If page returns 4xx/5xx or contains a visible error, issue `checkout_broken`
- Clean up cart before navigating to checkout (to avoid persisting test items)

This makes `checkout_broken` a programmatically-detected issue rather than AI-only.

#### 2B.4 — Price-in-cart vs. PDP price mismatch (medium severity)

Compare the price from `PriceVisibilityDetector` result against `cart.items[last].price` (in cents). If they differ by more than 1% (to handle currency conversion rounding), issue a new issue type `price_mismatch` at medium severity. Add this to `Issue::ISSUE_TYPES`.

This requires `AddToCartDetector` to accept the price detection result as input. Pass it from `ProductPageScanner` when constructing the detector.

---

### Feature C — Scheduled Scan Pipeline Improvements

**Goal**: Fix the scheduler bug, honor per-shop scan frequency, add scan history log to the dashboard.

#### 2C.1 — Add Phase 2 scan frequency values

`scan_frequency` is fully wired (done pre-Phase 2): `ShopSetting#scan_interval` is the single source of truth, used by both `ProductPage#needs_scan?` and `ScheduledScanJob#scan_interval_for`. Phase 2 only needs to add new cases to that method:

```ruby
# app/models/shop_setting.rb
def scan_interval
  case scan_frequency
  when "every_4_hours" then 4.hours
  when "every_6_hours" then 6.hours
  else                      24.hours  # Starter / default
  end
end
```

Add `every_4_hours` and `every_6_hours` to the `validates :scan_frequency, inclusion:` list. Remove `weekly` — not a Phase 2 use case. Run a data migration to convert any `weekly` records to `daily` first.

`BillingPlanService` sets `shop_setting.scan_frequency` when assigning a plan: `starter` → `daily`, `growth` → `every_4_hours`, `pro` → `every_6_hours`.

When a merchant upgrades their plan, update `shop.shop_setting.scan_frequency` accordingly in `BillingPlanService`.

#### 2C.2 — Fix alert 24-hour suppression

In `AlertService#existing_alert?`, add a 24h window check:
```ruby
def existing_alert?(issue, alert_type)
  # Per-scan dedup (existing)
  return true if Alert.exists?(shop:, issue:, alert_type:, scan:)
  # 24h suppression — don't re-alert for the same issue within 24h
  Alert.where(shop:, issue:, alert_type:, delivery_status: "sent")
       .where("sent_at > ?", 24.hours.ago)
       .exists?
end
```

#### 2C.3 — Scan history log on dashboard

The `scans` table already stores full history. Add a scan history view:

**New route**: `GET /product_pages/:id/scans` (already partially handled by `ScansController`)

**Dashboard changes** in `HomeController`:
- Add a `@recent_scans` instance variable: last 20 scans across all shop pages, eager-loaded with `product_page` and `issues`
- Show a timeline table: page name, scan time, depth, status, issues found, load time in ms

**Per-page history** in `ProductPagesController#show`:
- Already loads recent scans — ensure last 10 scans are shown with status badges and issue counts
- Add sparkline-style status history: last 7 scan results as colored dots (healthy=green, warning=yellow, critical=red, error=grey)

No new models needed. All data is already in `scans` and `issues` tables.

#### 2C.4 — Confirmed-failure scan state

`ScanPipelineService` already schedules a 30-minute rescan for unconfirmed high-severity issues. Extend this:

1. Add a `confirmation_scan` boolean to `ScanPdpJob` invocation (as a keyword arg), passed through to `ProductPageScanner`
2. On completion of a confirmation scan, if the same issue type is still detected, mark the issue `confirmed: true` (this is already partially handled by `ai_confirmed` — use that flag)
3. The existing `should_alert?` logic already handles this: AI-confirmed OR 2+ occurrences

No schema changes required. This is already the behavior — just make sure the rescan triggered by `ScanPipelineService` passes `scan_depth: :deep` so the funnel test runs.

---

### Feature D — Alert System Enhancements

**Goal**: Add alert suppression to prevent flooding at high scan frequencies, add Slack integration, add alert history to dashboard, wire the all-clear email.

#### 2D.1 — Alert history page

Add `GET /alerts` route and `AlertsController#index`:
- List all alerts for the shop, most recent first
- Show: issue type, product page, sent time, delivery status
- Paginate at 50 per page using Rails `limit`/`offset` (no gem needed)
- Filter by: delivery status (pending/sent/failed), alert type (email/admin)

The `alerts` table already has all needed columns.

#### 2D.2 — Per-issue alert suppression

With scans running every 4–6 hours, an unacknowledged high-severity issue would trigger up to 6 emails/day without suppression. Add `alert_suppression_hours` to let merchants control the re-notification frequency independently of how often scans run.

Add column to `shop_settings`:
```ruby
add_column :shop_settings, :alert_suppression_hours, :integer, default: 24, null: false
```

Update `AlertService#existing_alert?` to check the suppression window:
```ruby
def existing_alert?(issue, alert_type)
  # Per-scan dedup (prevents double-sending within a single scan run)
  return true if Alert.exists?(shop:, issue:, alert_type:, scan:)
  # Suppression window — don't re-alert within the configured hours
  suppression_hours = shop.shop_setting&.alert_suppression_hours || 24
  Alert.where(shop:, issue:, alert_type:, delivery_status: "sent")
       .where("sent_at > ?", suppression_hours.hours.ago)
       .exists?
end
```

Expose in `/settings` as a select: **Every scan** (0h, no suppression), **Every 6 hours**, **Every 12 hours**, **Once per day** (24h, default), **Every 48 hours**. The "Every scan" option is appropriate for low-frequency plans; "Once per day" or higher is the sensible default for the 4–6 hour scan tiers.

#### 2D.3 — Slack webhook alerts

Add `slack_webhook_url` string column to `shop_settings`.

**Migration**:
```ruby
add_column :shop_settings, :slack_webhook_url, :string
```

Create `app/services/slack_alert_service.rb` using `HTTParty` (already in Gemfile):
```ruby
class SlackAlertService
  def initialize(shop, issues, scan:)
    @shop = shop
    @issues = issues
    @scan = scan
  end

  def perform
    return unless @shop.shop_setting&.slack_webhook_url.present?
    payload = build_payload
    HTTParty.post(@shop.shop_setting.slack_webhook_url,
                  body: payload.to_json,
                  headers: { "Content-Type" => "application/json" },
                  timeout: 5)
  end
end
```

Wire into `AlertService#perform` after the email alert block:
```ruby
SlackAlertService.new(shop, alertable, scan:).perform if shop.shop_setting&.slack_webhook_url.present?
```

Slack message format: one Slack Block Kit message per scan, listing all alertable issues with severity emoji and a link to the product page in the Prowl dashboard.

**Settings UI**: Add a "Slack Integration" section to `/settings` with a text input for the webhook URL and a "Send test notification" button (`POST /settings/test_slack`).

#### 2D.4 — "All clear" email when issues resolve

`AlertMailer#issues_resolved` already exists but is never called. Wire it up in `DetectionService` or `ScanPipelineService`: after detection completes, if a page transitions from `critical`/`warning` to `healthy`, send the all-clear email.

Check in `ScanPipelineService#run_programmatic_detection` after `product_page.update_status_from_issues!`:
```ruby
if product_page.status_previously_changed? && product_page.status == "healthy"
  AlertMailer.issues_resolved(product_page.shop, product_page).deliver_later
end
```

---

### Feature E — Multi-Screenshot Funnel Capture

**Goal**: Capture 4 screenshots during deep scans — one at each funnel step — and send all 4 to Gemini in a single API call for comprehensive visual analysis. This dramatically improves AI detection accuracy for cart and checkout issues.

**Gating**: Growth and Pro tiers only (`multi_screenshot: true` in `BillingPlanService`). Starter tier continues with single screenshot.

#### What AI can see with multi-screenshots

| Step | When captured | What AI can detect |
|:-----|:-------------|:-------------------|
| 1. Product page (initial) | After page load, before interaction | Missing ATC, broken layout, wrong price, missing images |
| 2. After variant selection | After `BrowserService#select_first_variant` | ATC button appeared/disappeared, price changed, variant image swap |
| 3. After ATC click | After `BrowserService#click_add_to_cart` | Cart drawer opened, success message, error toast, no visual feedback |
| 4. Cart/checkout page | After `BrowserService#navigate_to_checkout` | Empty cart, checkout loading, payment form visible, error page |

#### 2E.1 — Capture screenshots at each funnel step

Modify `ProductPageScanner#perform` to capture multiple screenshots during deep scans:

```ruby
# app/services/product_page_scanner.rb
def capture_funnel_screenshots
  screenshots = []

  # Step 1: Initial page state (already captured by existing flow)
  screenshots << { step: "product_page", data: browser_service.take_screenshot }

  # Step 2: After variant selection
  browser_service.select_first_variant
  screenshots << { step: "after_variant_selection", data: browser_service.take_screenshot }

  # Step 3: After ATC click
  browser_service.click_add_to_cart
  sleep 1  # Wait for cart drawer/animation
  screenshots << { step: "after_atc_click", data: browser_service.take_screenshot }

  # Step 4: Cart/checkout
  browser_service.navigate_to_checkout
  screenshots << { step: "checkout_page", data: browser_service.take_screenshot }

  screenshots
end
```

#### 2E.2 — Store funnel screenshots in R2

Update `ScreenshotUploader` to support multiple screenshots per scan:

```ruby
# Naming convention: scan_{id}_step_{1-4}.png
def upload_funnel_screenshots(screenshots, scan_id, shop:, product_page:)
  screenshots.map.with_index(1) do |screenshot, index|
    key = "#{shop_slug(shop)}/#{product_page.handle}/scan_#{scan_id}_step_#{index}_#{screenshot[:step]}.png"
    upload_to_r2(screenshot[:data], key)
    { step: screenshot[:step], key: key }
  end
end
```

#### 2E.3 — Schema for funnel screenshots

Use the existing `funnel_results` JSONB column on `scans` (already exists in schema) to store screenshot references:

```ruby
# No migration needed — funnel_results JSONB column already exists
# Store as:
scan.update!(funnel_results: {
  screenshots: [
    { step: "product_page", key: "shop-slug/handle/scan_1_step_1_product_page.png" },
    { step: "after_variant_selection", key: "..." },
    { step: "after_atc_click", key: "..." },
    { step: "checkout_page", key: "..." }
  ],
  cart_state: { ... },  # existing funnel data
  checkout_result: { ... }
})
```

#### 2E.4 — Send all screenshots to Gemini in a single call

Update `AiIssueAnalyzer#analyze_page` to accept multiple screenshots:

```ruby
# app/services/ai_issue_analyzer.rb
def analyze_page(scan, product_page, detection_results)
  screenshots = download_funnel_screenshots(scan)

  if screenshots.length > 1
    # Multi-screenshot analysis — send all as inline_data parts
    image_parts = screenshots.map do |s|
      { inline_data: { mime_type: "image/png", data: Base64.strict_encode64(s[:data]) } }
    end
    prompt = build_multi_screenshot_prompt(detection_results, screenshots.map { |s| s[:step] })
  else
    # Single screenshot (Starter tier or quick scan)
    image_parts = [{ inline_data: { mime_type: "image/png", data: Base64.strict_encode64(screenshots.first[:data]) } }]
    prompt = build_single_screenshot_prompt(detection_results)
  end

  call_gemini(image_parts + [{ text: prompt }])
end
```

**Multi-screenshot prompt** should instruct Gemini: "Here are 4 screenshots showing the purchase flow on this product page. Screenshot 1 shows the initial page load. Screenshot 2 shows the page after variant selection. Screenshot 3 shows the page after clicking Add to Cart. Screenshot 4 shows the cart/checkout page. Analyze each step for issues..."

**Cost note**: One Gemini API call with 4 images is cheaper than 4 separate calls. Gemini 2.5 Flash handles multi-image inputs natively.

---

### Feature F — Checkout Flow Detector

**Goal**: Create a dedicated `CheckoutDetector` that runs during deep scans after ATC succeeds. This re-enables `checkout_broken` as a programmatically-detected issue (disabled in Phase 1 due to AI-only false positives).

**Gating**: Growth and Pro tiers only (`checkout_test: true` in `BillingPlanService`). Starter tier skips checkout detection entirely.

#### 2F.1 — Create `Detectors::CheckoutDetector`

**New file**: `app/services/detectors/checkout_detector.rb`

```ruby
class Detectors::CheckoutDetector < Detectors::BaseDetector
  def check_name
    "checkout_flow"
  end

  def run_detection
    return inconclusive_result("Checkout test requires deep scan") unless scan_depth == :deep
    return inconclusive_result("ATC must succeed first") unless atc_succeeded?

    # Navigate to checkout
    result = browser_service.navigate_to_checkout
    return fail_result("Checkout navigation failed", evidence: result) if result[:error]

    # Verify we reached Shopify checkout
    if result[:is_shopify_checkout]
      pass_result("Checkout page reached successfully", confidence: 0.95)
    elsif result[:redirected]
      warning_result("Checkout redirected to unexpected URL: #{result[:url]}", confidence: 0.7)
    else
      fail_result("Checkout page not reachable", confidence: 0.85, evidence: {
        url: result[:url],
        redirected: result[:redirected]
      })
    end
  end
end
```

#### 2F.2 — Register the detector

1. Add to `ProductPageScanner::TIER1_DETECTORS` (conditionally, only for Growth/Pro):
   ```ruby
   detectors = TIER1_DETECTORS.dup
   if BillingPlanService.feature_available?(shop.subscription_plan, :checkout_test)
     detectors << Detectors::CheckoutDetector
   end
   ```

2. Add mapping in `DetectionService::CHECK_TO_ISSUE_TYPE`:
   ```ruby
   "checkout_flow" => "checkout_broken"
   ```

3. Add severity in `DetectionService::CHECK_SEVERITY`:
   ```ruby
   "checkout_flow" => "high"
   ```

4. `checkout_broken` already exists in `Issue::ISSUE_TYPES` — just needs the AI prompt re-enabled in `AiIssueAnalyzer::AI_ISSUE_TYPE_MAP`.

#### 2F.3 — Detector dependencies

`CheckoutDetector` depends on `AddToCartDetector` having run first (needs item in cart). Options:
- **Option A**: Run `CheckoutDetector` inside `AddToCartDetector#run_funnel_test` after cart verification succeeds. Simpler but couples the detectors.
- **Option B**: Run `CheckoutDetector` as a separate detector in `ProductPageScanner`, passing `atc_succeeded?` from a shared scan context. Cleaner but requires inter-detector state.

**Recommendation**: Option A — keep it in the funnel test flow. The checkout test is logically part of the purchase funnel. `AddToCartDetector` already manages the funnel lifecycle (variant selection → ATC → cart verify → cleanup). Adding checkout navigation after cart verify is natural.

---

### Feature G — Revenue Loss Estimator

**Goal**: Show merchants an estimated revenue impact when issues are detected, making alerts more actionable and creating urgency to fix problems.

#### 2G.1 — Data collection

Shopify's Admin API provides product data including price. When creating/updating a `ProductPage`, store the product's price from the Shopify API:

**Migration**:
```ruby
add_column :product_pages, :product_price_cents, :integer
add_column :product_pages, :currency_code, :string, default: "USD"
```

Populate via `AfterAuthenticateJob` or when a merchant adds a page (the Resource Picker already returns product data).

#### 2G.2 — Estimation logic

Create `app/services/revenue_loss_estimator.rb`:

```ruby
class RevenueLossEstimator
  # Conservative estimate: assume 1% of daily visitors would have purchased
  ESTIMATED_CONVERSION_RATE = 0.01
  # Shopify average: ~500 sessions/day for active stores (adjustable per plan)
  DEFAULT_DAILY_SESSIONS = 500

  def initialize(issue)
    @issue = issue
    @product_page = issue.product_page
  end

  def estimated_daily_loss
    return nil unless @product_page.product_price_cents
    return nil unless high_impact_issue?

    price = @product_page.product_price_cents / 100.0
    lost_sales = DEFAULT_DAILY_SESSIONS * ESTIMATED_CONVERSION_RATE
    (price * lost_sales).round(2)
  end

  def estimated_loss_since_detected
    return nil unless (daily = estimated_daily_loss)
    days = [(@issue.last_detected_at - @issue.first_detected_at).to_f / 1.day, 1].max
    (daily * days).round(2)
  end

  private

  def high_impact_issue?
    %w[missing_add_to_cart atc_not_functional checkout_broken].include?(@issue.issue_type)
  end
end
```

#### 2G.3 — Display in UI and alerts

- **Issue detail page**: Show "Estimated revenue impact: ~$X/day" for high-impact issues
- **Alert emails**: Include estimated loss in `AlertMailer#issues_detected` for high-severity ATC/checkout issues
- **Dashboard**: Show aggregate estimated loss across all open high-severity issues

**Important**: Label estimates clearly as approximate. Use language like "Potential revenue impact" not "Revenue lost". Include a disclaimer that estimates are based on industry averages.

---

### Feature H — Mobile Viewport Scanning

**Goal**: Scan product pages at mobile viewport width to catch mobile-only breakage. Many Shopify themes have responsive issues that only appear on small screens.

**Gating**: Growth and Pro tiers only. Starter gets desktop-only scans (current behavior).

#### 2H.1 — Add mobile viewport to `BrowserService`

```ruby
# app/services/browser_service.rb
DESKTOP_VIEWPORT = { width: 1440, height: 900 }.freeze
MOBILE_VIEWPORT  = { width: 375, height: 812 }.freeze  # iPhone 14 dimensions

def set_viewport(viewport)
  @page.viewport = Puppeteer::Viewport.new(**viewport)
end
```

#### 2H.2 — Dual-viewport scanning in `ProductPageScanner`

For Growth/Pro tiers, run the detection pipeline twice — once at desktop viewport, once at mobile:

```ruby
def perform
  results = { desktop: run_scan_at_viewport(DESKTOP_VIEWPORT) }

  if BillingPlanService.feature_available?(shop.subscription_plan, :mobile_viewport)
    results[:mobile] = run_scan_at_viewport(MOBILE_VIEWPORT)
  end

  merge_results(results)
end
```

#### 2H.3 — New issue type: `mobile_layout_broken`

Add to `Issue::ISSUE_TYPES`:
```ruby
"mobile_layout_broken" => {
  title: "Mobile layout issue",
  description: "The product page has layout or functionality issues on mobile devices."
}
```

Severity: `medium` (unless ATC is missing on mobile — then `high`).

#### 2H.4 — Schema changes

**Migration**:
```ruby
add_column :scans, :viewport, :string, default: "desktop"
```

Store mobile scan results as separate `Scan` records with `viewport: "mobile"`. This keeps the existing scan model clean and allows independent issue tracking per viewport.

#### 2H.5 — Mobile screenshot in R2

Naming: `{shop-slug}/{product-handle}/scan_{id}_mobile_{timestamp}.png`

Send both desktop and mobile screenshots to Gemini for AI analysis when available.

---

## 3. Future Phases (Post-Phase 2)

These items from the roadmap are intentionally deferred past Phase 2. They are listed here for context and to avoid scope creep.

### Phase 3 — Theme Intelligence & App Conflict Detection

- **Theme integrity monitoring**: Diff engine that detects when a theme is published or updated. Compare before/after HTML structure to identify breaking changes. Uses Shopify's `themes/published` webhook.
- **App conflict intelligence**: Track which Shopify apps are installed (via `Shop#shop_json` or Admin API) and correlate app install/uninstall events with issue detection. Build a database of known app conflicts (e.g., "App X breaks ATC on Dawn theme").
- **Screenshot comparison engine**: Compare current scan screenshot against the last healthy screenshot using pixel-diff or perceptual hash. Flag visual regressions even if programmatic detectors pass.
- **Historical trend analysis**: "Your page load time increased 40% this week." Track `page_load_time_ms` over time and alert on significant regressions.

### Phase 4 — Agency & Multi-Store

- **Agency dashboard**: A single view to monitor multiple Shopify stores. Requires a new `Agency` model that `has_many :shops`. Agencies see aggregate health across all their client stores.
- **Multi-store monitoring**: Allow a single merchant to link multiple Shopify stores under one account. Shared billing, unified alert inbox.
- **White-labeled agency reports**: PDF/HTML reports that agencies can share with clients, branded with their logo.

### Phase 5 — Platform Expansion

- **API & webhooks**: REST API for programmatic access to scan results, issues, and alerts. Outgoing webhooks for real-time integration with merchant systems.
- **WhatsApp alerts**: Via Twilio or Meta Business API. Similar architecture to Slack integration but with phone number verification.
- **Auto-fix suggestions**: Generate copy-paste Liquid code fixes. AI already provides `ai_suggested_fix` text; this would extend to actual code snippets merchants can apply.
- **Competitive benchmarking**: Compare a store's PDP against top-performing Shopify stores in the same category.
- **Shopify Plus deep integrations**: Custom checkout extensibility monitoring, Scripts editor compatibility checks.

### Engineering Scale (when needed)

- **Scan worker sharding**: Move from single-dyno Solid Queue to multiple worker dynos. Consider Solid Queue's `concurrency_limit` per queue or move to dedicated scan worker processes.
- **Queue prioritization**: High-tier shops (Pro) should have scan priority over Starter. Use separate Solid Queue queues per tier with weighted processing.
- **Browserless.io cost optimization**: Cache page screenshots for unchanged pages (compare HTML hash). Skip re-scanning pages that haven't changed.
- **Horizontal scaling**: Move to Heroku Standard/Performance dynos when scan volume exceeds single-dyno capacity. Target: support 500+ active shops.

---

## 4. Build Order

The features have dependencies. Build in this sequence:

### Sprint 1 — Billing foundation (do first, everything else depends on it)
1. Implement `BillingPlanService` with three plan definitions and feature gating
2. Add plan selection UI (`BillingController#plans`, `BillingController#select_plan`)
3. Wire `subscription_plan` from `SubscriptionSyncService` back to `Shop#subscription_plan`
4. Update `Shop#max_monitored_pages` to read from plan definition
5. Migrate existing "Prowl Monthly" shops to `subscription_plan: "starter"`
6. Update `ScanPdpJob#determine_scan_depth` to respect per-plan deep scan frequency

### Sprint 2 — Cart scanning + Checkout detector
1. Add `BrowserService#verify_cart_item` and `BrowserService#cart_feedback_visible?`
2. Wire cart item verification into `AddToCartDetector#run_funnel_test`
3. Create `Detectors::CheckoutDetector` (Feature F) — wire into `AddToCartDetector` funnel flow
4. Re-enable `checkout_broken` in `AiIssueAnalyzer::AI_ISSUE_TYPE_MAP`
5. Add `price_mismatch` issue type to `Issue::ISSUE_TYPES`
6. Pass `PriceVisibilityDetector` result to `AddToCartDetector` in `ProductPageScanner`
7. Gate checkout test and price mismatch to Growth/Pro tiers

### Sprint 3 — Multi-Screenshot Funnel Capture
1. Update `ProductPageScanner` to capture 4 screenshots at each funnel step during deep scans
2. Update `ScreenshotUploader` to support multiple screenshots per scan (naming: `scan_{id}_step_{N}_{step}.png`)
3. Store screenshot references in `scans.funnel_results` JSONB (no migration needed)
4. Update `AiIssueAnalyzer#analyze_page` to send multiple images to Gemini in a single call
5. Build multi-screenshot Gemini prompt
6. Gate to Growth/Pro tiers via `BillingPlanService.feature_available?`

### Sprint 4 — Scheduler + scan history
1. Add `every_4_hours`/`every_6_hours` to `ShopSetting` validations; remove `weekly`; data-migrate any `weekly` → `daily`
2. Wire new frequency values into `scan_interval`; set `scan_frequency` via `BillingPlanService` on plan assignment
3. Add scan history timeline to `HomeController` and `ProductPagesController#show`
4. Add 7-scan sparkline to product page list view
5. Wire `AlertMailer#issues_resolved` in `ScanPipelineService`

### Sprint 5 — Alerts + Slack
1. Add `alert_suppression_hours` migration, wire into `AlertService#existing_alert?`, add settings UI
2. Add alert history page (`AlertsController#index`)
3. Add `slack_webhook_url` migration, `SlackAlertService`, settings UI (Growth/Pro only)
4. Add "Send test Slack notification" endpoint

### Sprint 6 — Revenue Loss Estimator + Mobile Viewport
1. Add `product_price_cents` and `currency_code` columns to `product_pages`
2. Populate product prices from Shopify API via Resource Picker data
3. Create `RevenueLossEstimator` service; display in issue detail and alert emails
4. Add `viewport` column to `scans`; add `MOBILE_VIEWPORT` to `BrowserService`
5. Implement dual-viewport scanning in `ProductPageScanner` for Growth/Pro
6. Add `mobile_layout_broken` issue type to `Issue::ISSUE_TYPES`

---

## 5. Risks & Open Questions

### Risk 1 — Shopify billing plan switching
Shopify's billing API does not allow modifying an active subscription's price. Upgrading/downgrading requires cancelling the current `AppSubscription` and creating a new one. The merchant is charged pro-rata by Shopify. This means:
- `SubscriptionSyncService` must handle the `cancelled` + `pending` transition window during plan changes
- If the merchant closes the approval tab mid-flow, they end up with no active subscription. Add a grace period: if `subscription_status` is `none` and an `active_subscription` existed in the last 30 minutes, still allow access.
- **Question for product**: Should plan downgrades immediately enforce the lower page limit, or give a 7-day grace period to remove pages?

### Risk 2 — Cart interaction false positives on password-protected stores
If a store is password-protected (`shop.password_enabled == true`), the scanner cannot add to cart. `BrowserService` already blocks analytics scripts but doesn't handle the password page redirect. The funnel test will fail with a `missing_add_to_cart` false positive.
- Fix: In `ScanPdpJob`, check `product_page.shop.password_enabled` before deep scan and skip the funnel test, returning `inconclusive` instead.

### Risk 3 — Browserless.io cost at higher scan frequencies
The Growth tier (every 4h) and Pro tier (every 6h) will significantly increase Browserless.io usage. Deep scans with multi-screenshot capture and checkout testing consume more browser time.
- **Cost estimates per shop per day**:
  - Starter (daily, 10 pages, weekly deep): ~10 quick + ~10 deep/week ≈ 11.4 scans/day avg
  - Growth (every 4h, 25 pages, all deep): 150 scans/day
  - Pro (every 6h, 100 pages, all deep): 400 scans/day
- Multi-screenshot adds ~10s per deep scan (4 screenshot captures + navigation). At 400 scans/day for a Pro shop, that's ~67 extra minutes of browser time.
- **Concurrency limit**: `ScanPdpJob` is currently limited to 1 concurrent scan (`limits_concurrency to: 1`). With multiple Pro shops, scans will queue. Consider raising the concurrency limit to 2-3 for paid production tiers and ensuring Browserless.io plan supports it.
- **Mitigation**: Starter tier gets deep scans weekly only. Quick scans are fast (~15s). This keeps Starter costs close to Phase 1 levels.

### Risk 4 — Slack webhook URL validation
Webhooks are user-supplied URLs. Do not make the `POST /settings/test_slack` endpoint a CSRF-free action — keep it protected. Validate that the URL is a valid `https://hooks.slack.com/` URL before storing or calling it to prevent SSRF.

### Risk 5 — Multi-screenshot scan timeout
Capturing 4 screenshots during a deep scan adds significant time to the scan pipeline. Current `SCAN_TIMEOUT_SECONDS` is 60s for deep scans. With variant selection + ATC + cart verify + checkout navigation + 4 screenshots, the total may exceed 60s.
- **Mitigation**: Increase `SCAN_TIMEOUT_SECONDS` to 90s for deep scans with multi-screenshot enabled. Monitor P95 scan durations after launch.

### Risk 6 — Gemini multi-image token cost
Sending 4 screenshots to Gemini in a single call increases token usage per scan. Gemini 2.5 Flash charges per input token; 4 images ≈ 4× the image token cost of a single screenshot.
- **Mitigation**: Only Growth/Pro tiers use multi-screenshot. The higher plan prices ($29/$79 vs $10) cover the additional AI cost. Monitor Gemini API spend per tier.

### Risk 7 — Mobile viewport scan doubling scan volume
Dual-viewport scanning (desktop + mobile) doubles the scan count for Growth/Pro shops. A Pro shop with 100 pages at every-6-hour frequency would generate 800 scans/day instead of 400.
- **Mitigation**: Run mobile viewport scans at a lower frequency than desktop (e.g., mobile scans once daily even for Pro tier). Or only run mobile scans on deep scan cycles.

### Risk 8 — Revenue loss estimator accuracy
Estimated revenue impact uses industry-average conversion rates. Merchants may take the numbers too literally and panic.
- **Mitigation**: Always display as "Potential impact" with a disclaimer. Use conservative assumptions (1% conversion rate, 500 daily sessions). Consider pulling actual Shopify Analytics data (requires `read_analytics` scope — verify if available in current scopes).

### Open Question 1 — Pro tier page cap
Pro tier caps at 100 pages in Phase 2. "Unlimited" is a Phase 3 concern requiring horizontal scaling. Is 100 pages sufficient for the target Pro customer?

### Open Question 2 — What happens to existing shops on the old $10 plan?
When Phase 2 deploys, existing shops have a `charge_name: "Prowl Monthly"` subscription. This should map to the Starter tier.
- In `SubscriptionSyncService`, after syncing, if `charge_name == "Prowl Monthly"` and `subscription_plan` is blank, set `subscription_plan = "starter"`.
- Existing shops get the Starter tier's expanded 10-page limit (up from 3) as a benefit of the Phase 2 upgrade.

### Open Question 3 — `issues_resolved` email timing
The all-clear email should only fire once per recovery event, not on every healthy scan. Check in `ScanPipelineService` that the page was previously `critical` or `warning` before sending the resolved email. Use `product_page.status_previously_changed?` (ActiveRecord dirty tracking) to gate this.

### Open Question 4 — Plan downgrade grace period
When a merchant downgrades from Growth (25 pages) to Starter (10 pages) but has 20 active pages:
- **Option A**: Immediately disable monitoring on the oldest pages beyond the limit. Notify via email.
- **Option B**: 7-day grace period. Show a banner: "You have 20 pages monitored but your plan allows 10. Please remove pages by [date] or they will be auto-paused."
- **Recommendation**: Option B — less disruptive, gives merchant time to decide which pages to keep.

### Open Question 5 — Mobile scan as separate scan record vs. same record
Two approaches for storing mobile viewport results:
- **Option A**: Separate `Scan` record with `viewport: "mobile"`. Clean separation, independent issue tracking. Doubles scan records.
- **Option B**: Add `mobile_screenshot_url` and `mobile_dom_checks_data` columns to existing `scans`. Single record but schema gets wider.
- **Recommendation**: Option A — separate records. Keeps the model simple. Issues can be scoped to viewport.

---

## 6. Schema Changes Summary

All migrations needed for Phase 2:

```ruby
# Sprint 1 — No migrations (BillingPlanService is code-only; subscription_plan already on shops)

# Sprint 2 — No migrations (checkout_broken issue type already exists)

# Sprint 3 — No migrations (funnel_results JSONB already on scans)

# Sprint 4 — No migrations (scan_frequency column already on shop_settings)

# Sprint 5 — Alert enhancements
add_column :shop_settings, :alert_suppression_hours, :integer, default: 24, null: false
add_column :shop_settings, :slack_webhook_url, :string

# Sprint 6 — Revenue loss + mobile viewport
add_column :product_pages, :product_price_cents, :integer
add_column :product_pages, :currency_code, :string, default: "USD"
add_column :scans, :viewport, :string, default: "desktop"
```

**New issue types to add to `Issue::ISSUE_TYPES`:**
- `price_mismatch` — PDP price differs from cart price (medium severity)
- `mobile_layout_broken` — Mobile viewport layout/functionality issue (medium severity)
- `checkout_broken` — Already exists, just re-enable programmatic detection
