# Prowl Phase 2 — Implementation Plan

_Last updated: 2026-03-21_

---

## 1. Current State (Phase 1 Baseline)

### What exists and works
- **Scanner engine**: `BrowserService` (puppeteer-ruby) → `ProductPageScanner` → five Tier-1 detectors with confidence scoring
- **Detection pipeline**: `ScanPipelineService` — five steps (programmatic detection → AI page analysis → per-issue AI explanation → alerting → rescan scheduling)
- **AI integration**: Gemini 2.5 Flash for page-level visual analysis + per-issue explanation/confirmation
- **Issues**: 10 issue types defined in `Issue::ISSUE_TYPES`; `missing_add_to_cart`, `atc_not_functional`, `checkout_broken` are all present
- **Cart funnel test**: `AddToCartDetector` Layer 2 (deep scans) already clicks the ATC button and polls `/cart.js` up to 4× to verify item count increases — implemented in `add_to_cart_detector.rb`
- **Alerting**: `AlertService` → `AlertMailer`; batched email per product page per scan; per-scan dedup via unique index on `(shop_id, issue_id, alert_type, scan_id)`; AI-generated merchant explanation + suggested fix included
- **Billing**: Single Shopify recurring charge ("Prowl Monthly", $10/month, 14-day trial) configured in `config/initializers/shopify_app.rb`
- **Page limits**: `Shop::MAX_MONITORED_PAGES = 3` (hardcoded constant in `app/models/shop.rb:14`)
- **Scan scheduling**: `ScheduledScanJob` queues scans for active shops daily; `ScanPdpJob` determines depth (deep on first scan, open critical issues, or Mondays; quick otherwise)
- **scan_frequency**: Column already exists on `shop_settings` (values: `daily`/`weekly`) but **is not wired to the scheduler** — `ProductPage.needs_scan` hardcodes 24 hours regardless of this setting
- **Infrastructure**: PostgreSQL + Solid Queue (no Redis) + Solid Cache; Browserless.io for production Chrome; Cloudflare R2 for screenshots; Resend for email

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

| Plan | Price | Pages | Scan Frequency | Deep Scans |
|------|-------|-------|----------------|------------|
| Starter | $10/month | 10 | Daily | Yes |
| Growth | $29/month | 25 | Twice daily | Yes |
| Pro | $79/month | Unlimited | Every 6 hours | Yes |

These names, prices, and limits are a starting point. The constraint is that Shopify only supports one active recurring charge per app installation — plan changes require cancelling the old charge and creating a new one. Shopify's billing API supports this via `appSubscriptionCreate`.

#### 2A.2 — Shopify billing changes

`config/initializers/shopify_app.rb` currently hardcodes a single `BillingConfiguration`. For multiple plans, remove the single `config.billing` block and instead create a new `BillingPlan` service object that builds the correct `appSubscriptionCreate` GraphQL mutation payload based on the selected plan.

Add a `plan_name` column to `subscriptions` (already exists: `charge_name`). When a merchant selects a plan, call `appSubscriptionCreate` with the appropriate price. After Shopify redirects back, `SubscriptionSyncService#sync` will pick up the new active subscription.

**New service**: `app/services/billing_plan_service.rb`
```ruby
PLANS = {
  "starter" => { price: 10, pages: 10,        interval_hours: 24,  charge_name: "Prowl Starter" },
  "growth"  => { price: 29, pages: 25,        interval_hours: 12,  charge_name: "Prowl Growth"  },
  "pro"     => { price: 79, pages: Float::INFINITY, interval_hours: 6, charge_name: "Prowl Pro" }
}.freeze
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

#### 2C.1 — Fix `ScheduledScanJob` and wire `scan_frequency`

Fix the billing filter bug (see Bug 1 above).

Wire `scan_frequency` from `shop_settings`:
- `daily` → current behavior (24h `needs_scan` window)
- `twice_daily` → 12h window (Growth tier)
- `every_6_hours` → 6h window (Pro tier)

Change `ProductPage.needs_scan` from a hardcoded 24h scope to a shop-aware method, or pass the frequency into the scheduler:

```ruby
# In ScheduledScanJob, replace needs_scan scope with:
pages_to_scan = shop.product_pages.monitoring_enabled
                    .where("last_scanned_at IS NULL OR last_scanned_at < ?",
                           scan_interval(shop).ago)

def scan_interval(shop)
  case shop.shop_setting&.scan_frequency
  when "twice_daily"    then 12.hours
  when "every_6_hours"  then 6.hours
  else                       24.hours
  end
end
```

Add `scan_frequency` values `twice_daily` and `every_6_hours` to `ShopSetting`'s validation inclusion list (currently only allows `daily`/`weekly` — change `weekly` to the new values since weekly is not a Phase 2 use case).

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

## 3. Build Order

The features have dependencies. Build in this sequence:

### Sprint 1 — Billing foundation (do first, everything else depends on it)
1. Implement `BillingPlanService` with three plan definitions
2. Add plan selection UI (`BillingController#plans`, `BillingController#select_plan`)
3. Wire `subscription_plan` from `SubscriptionSyncService` back to `Shop#subscription_plan`
4. Update `Shop#max_monitored_pages` to read from plan definition

### Sprint 2 — Cart scanning improvements
1. Add `BrowserService#verify_cart_item` and `BrowserService#cart_feedback_visible?`
2. Wire cart item verification into `AddToCartDetector#run_funnel_test`
3. Wire `navigate_to_checkout` into `AddToCartDetector` for deep scans
4. Add `price_mismatch` issue type to `Issue::ISSUE_TYPES`
5. Pass `PriceVisibilityDetector` result to `AddToCartDetector` in `ProductPageScanner`

### Sprint 3 — Scheduler + scan history
1. Wire `scan_frequency` into `ScheduledScanJob` (replace hardcoded 24h)
2. Update `ShopSetting` validations to support `twice_daily`/`every_6_hours`
3. Add scan history timeline to `HomeController` and `ProductPagesController#show`
4. Add 7-scan sparkline to product page list view
5. Wire `AlertMailer#issues_resolved` in `ScanPipelineService`

### Sprint 4 — Alerts
1. Add `alert_suppression_hours` migration, wire into `AlertService#existing_alert?`, add settings UI
2. Add alert history page (`AlertsController#index`)
3. Add `slack_webhook_url` migration, `SlackAlertService`, settings UI
4. Add "Send test Slack notification" endpoint

---

## 4. Risks & Open Questions

### Risk 1 — Shopify billing plan switching
Shopify's billing API does not allow modifying an active subscription's price. Upgrading/downgrading requires cancelling the current `AppSubscription` and creating a new one. The merchant is charged pro-rata by Shopify. This means:
- `SubscriptionSyncService` must handle the `cancelled` + `pending` transition window during plan changes
- If the merchant closes the approval tab mid-flow, they end up with no active subscription. Add a grace period: if `subscription_status` is `none` and an `active_subscription` existed in the last 30 minutes, still allow access.
- **Question for product**: Should plan downgrades immediately enforce the lower page limit, or give a 7-day grace period to remove pages?

### Risk 2 — Cart interaction false positives on password-protected stores
If a store is password-protected (`shop.password_enabled == true`), the scanner cannot add to cart. `BrowserService` already blocks analytics scripts but doesn't handle the password page redirect. The funnel test will fail with a `missing_add_to_cart` false positive.
- Fix: In `ScanPdpJob`, check `product_page.shop.password_enabled` before deep scan and skip the funnel test, returning `inconclusive` instead.

### Risk 3 — Browserless.io cost at higher scan frequencies
The Growth tier (twice daily) and Pro tier (every 6 hours) will 2× and 4× Browserless.io usage. Deep scans (funnel test + checkout) consume significantly more browser time than quick scans.
- Estimate: Pro tier at every 6 hours + 25 pages = 100 scans/day vs. current ~3 scans/day per shop
- **Concurrency limit**: `ScanPdpJob` is currently limited to 1 concurrent scan (`limits_concurrency to: 1`). With multiple Pro shops, scans will queue. Consider raising the concurrency limit to 2-3 for paid production tiers and ensuring Browserless.io plan supports it.
- **Question**: Should deep scans (funnel + checkout) be gated to the Growth/Pro tiers to control costs?

### Risk 4 — Slack webhook URL validation
Webhooks are user-supplied URLs. Do not make the `POST /settings/test_slack` endpoint a CSRF-free action — keep it protected. Validate that the URL is a valid `https://hooks.slack.com/` URL before storing or calling it to prevent SSRF.

### Risk 5 — `scan_frequency` column migration
`ShopSetting` currently validates `scan_frequency` inclusion in `%w[daily weekly]`. Changing this without a migration first will break existing `weekly` records (if any). Run a migration to update any `weekly` records to `daily` before changing the validation list.

### Open Question 1 — Unlimited pages for Pro tier
`ProductPage.needs_scan` and `ScheduledScanJob` iterate over all pages. "Unlimited" for the Pro tier means no upper bound check, but could mean hundreds of pages for large merchants. The current Solid Queue concurrency limit of 1 will create very long queues.
- Proposed answer: Cap "unlimited" at 100 pages in Phase 2. True unlimited is a Phase 3 concern with horizontal scaling.

### Open Question 2 — What happens to existing shops on the old $10 plan?
When Phase 2 deploys, existing shops have a `charge_name: "Prowl Monthly"` subscription. This should map to the Starter tier.
- In `SubscriptionSyncService`, after syncing, if `charge_name == "Prowl Monthly"` and `subscription_plan` is blank, set `subscription_plan = "starter"`.

### Open Question 3 — `issues_resolved` email timing
The all-clear email should only fire once per recovery event, not on every healthy scan. Check in `ScanPipelineService` that the page was previously `critical` or `warning` before sending the resolved email. Use `product_page.status_previously_changed?` (ActiveRecord dirty tracking) to gate this.
