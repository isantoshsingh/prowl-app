# Prowl Phase 2 — Implementation Plan

_Last updated: 2026-03-26_

---

## 1. The New Product Vision

Prowl is transitioning from a **PDP diagnostic tool** to a **Storefront Conversion Monitor**.
Old positioning: "Prowl scans your product pages for issues." ($10/month)
New positioning: "Prowl monitors your customer's buying journey every day and alerts you the moment something breaks that's costing you sales." ($49–$249/month)

The unit of monitoring is NOT individual product pages. It is **journey stages** and **product configurations**.

---

## 2. New Pricing Tiers & Plan Enforcement

**Goal**: Introduce three pricing tiers with different journey stage coverage and scan frequencies.

### 2.1 — Define the three plans

| Plan | Price | What's Monitored | Scan Frequency | Alerts |
|------|-------|-----------------|----------------|--------|
| Starter | $49/month | Buying stages: PDP + Cart + Checkout handoff, across all auto-detected product configurations | Weekly (168h) | Email |
| Growth | $129/month | Full journey: Homepage + Collections + Search + PDP + Cart + Checkout handoff | Daily (24h) | Email + Slack |
| Pro | $249/month | Same as Growth | Every 4 hours | Email + Slack + Monthly health report PDF |

All tiers include a 14-day free trial.
**Important**: Page count limits are REMOVED. Tiers are differentiated by journey stage coverage and scan frequency.

### 2.2 — Billing Plan Service Updates

Update `BillingPlanService` (`app/services/billing_plan_service.rb`) to reflect the new plans:

```ruby
PLANS = {
  "starter" => { 
    price: 49, 
    journey_stages: [:pdp, :cart, :checkout_handoff],
    interval_hours: 168,  # weekly
    charge_name: "Prowl Starter",
    alerts: [:email]
  },
  "growth" => { 
    price: 129, 
    journey_stages: [:homepage, :collections, :search, :pdp, :cart, :checkout_handoff],
    interval_hours: 24,   # daily
    charge_name: "Prowl Growth",
    alerts: [:email, :slack]
  },
  "pro" => { 
    price: 249, 
    journey_stages: [:homepage, :collections, :search, :pdp, :cart, :checkout_handoff],
    interval_hours: 4,    # every 4 hours
    charge_name: "Prowl Pro",
    alerts: [:email, :slack, :health_report]
  }
}.freeze
```

For Phase 2 launch, only the **Starter tier needs to be fully functional**. Growth and Pro should be visible on the plan selection page (`app/views/billing/plans.html.erb` or similar) but gated as "Coming Soon" with an optional waitlist email capture.

Map existing users: In `SubscriptionSyncService`, if `charge_name` is "Prowl Monthly", map them mapping to Starter tier functionality.

Remove `Shop::MAX_MONITORED_PAGES` constant entirely, as page limits are removed. Update `Shop#can_add_monitored_page?` or replace it if necessary with configuration limit logic instead.

---

## 3. New Monitoring Model: Product Configurations

### The core insight
A "product configuration" is defined as: **product template × variant type**
Examples:
- Default template × single variant
- Default template × multi-variant
- Alternate template × single variant (`product.gift_card.json`)

If a merchant has 200 products all using the same template, Prowl should automatically detect distinct product configurations and monitor one representative product from each.

### 3.1 — Auto-detection flow

Build a new service: `app/services/product_config_detector_service.rb`
This service runs during onboarding and can be manually re-triggered:

1. **Detect product templates**: Read the merchant's theme files via Shopify Asset API. Look for files matching `templates/product*.json` (or `.liquid`).
2. **Find representative products per template**: Use Shopify GraphQL Admin API to query active products. Filter results by `templateSuffix` matching each template. For each template, select:
   - One product where `hasOnlyDefaultVariant: true` (single variant representative)
   - One product where `hasOnlyDefaultVariant: false` AND `totalVariants > 1` (multi-variant representative)
3. **Store as Configurations**: Create or update `ProductPage` records (or a new `MonitoredConfiguration` model) for each distinct configuration.
4. **Present to merchant**: Show the detected configurations in the dashboard.

### 3.2 — Re-detection triggers

Re-run `ProductConfigDetectorService`:
- When merchant clicks "Re-scan store setup" in settings (`SettingsController`)
- When a new theme is published (listen to `themes/publish` webhook or check on schedule)

*Do NOT re-detect on every product update.*

---

## 4. Alert Escalation System

Implement escalating alerts instead of simple cooldown/suppression.

### 4.1 — Alert escalation sequence

**Alert 1 — Immediate on first confirmed detection:**
- Full email with: what broke, which product configuration, when detected, AI-generated diagnosis, suggested fix.

**Alert 2 — 24 hours later if still broken AND not acknowledged:**
- Shorter email, more urgent tone. Includes duration.

**Alert 3 — 72 hours later if still broken AND not acknowledged:**
- Revenue impact framing. "This issue has been live for 3 days".

**After Alert 3 — Stop emailing.** Resumes only if issue resolves and recurs, or a new issue occurs.

### 4.2 — Acknowledgment Mechanism

Every alert email includes a signed, one-click "I'm aware of this" link. Clicking it sets `acknowledged_at` and `acknowledged = true`, and stops the escalation sequence. Monitoring continues.

### 4.3 — Data Model Changes

Update `db/schema.rb` via new migration. Add to the `issues` (or `alerts`) table:
```ruby
add_column :issues, :acknowledged, :boolean, default: false, null: false
add_column :issues, :acknowledged_at, :datetime
add_column :issues, :escalation_level, :integer, default: 0, null: false
add_column :issues, :last_alerted_at, :datetime
add_column :issues, :acknowledgment_token, :string

add_index :issues, :acknowledgment_token
```

### 4.4 — Alert Service Logic

In `AlertService` (`app/services/alert_service.rb`):

```ruby
if issue.acknowledged?
  # skip
elsif issue.escalation_level == 0
  # send Alert 1, set escalation_level = 1, set last_alerted_at
elsif issue.escalation_level == 1 && issue.last_alerted_at < 24.hours.ago
  # send Alert 2, set escalation_level = 2, set last_alerted_at
elsif issue.escalation_level == 2 && issue.last_alerted_at < 72.hours.ago
  # send Alert 3, set escalation_level = 3, set last_alerted_at
elsif issue.escalation_level >= 3
  # skip (max alerts reached)
end
```

### 4.5 — "All clear" email

When an issue that was previously detected resolves (product configuration scans clean):
- Send a single "All clear" email.
- Reset `escalation_level` to 0.
- Update `ScanPipelineService` post-scan logic to trigger this email regardless of acknowledgment status.

---

## 5. New Onboarding Flow

Replace the current manual page addition flow with an automated sequence.

### Step 1 — Install + plan selection
Merchant installs → lands on `/billing/plans` showing Starter / Growth (coming soon) / Pro (coming soon) → selects Starter → Shopify billing approval → redirects back.

### Step 2 — Automatic store analysis
Immediately run `ProductConfigDetectorService` in the background. Show a loading state in the UI.

### Step 3 — Review detected configurations
Show merchant the found configurations (template name, variant type, representative product). Allow swapping representatives. "Start monitoring" CTA.

### Step 4 — First scan
Trigger an immediate scan (`ScheduledScanJob` or `ScanPdpJob`) of all detected configurations upon confirmation.

### Step 5 — Ongoing monitoring
Scheduled scans run per plan frequency. 

---

## 6. Cart Scanning + Checkout Handoff

### 6.1 — Cart Verification
`BrowserService#verify_cart_item` — verify correct product/variant in cart.

### 6.2 — Cart Drawer/Feedback
`BrowserService#cart_feedback_visible?` — check if cart drawer or `/cart` page opened.

### 6.3 — Checkout Redirect
Wire `BrowserService#navigate_to_checkout` into `AddToCartDetector` (`app/services/detectors/add_to_cart_detector.rb`) for deep scans to verify successful redirect to the checkout domain. Issue `checkout_broken` if failing.

### 6.4 — Price Mismatch Detection
Add `price_mismatch` issue type to `Issue::ISSUE_TYPES`. Compare PDP price vs cart price (`PriceVisibilityDetector` result passed into `AddToCartDetector` in `ProductPageScanner`).

---

## 7. Revised Build Order

### Sprint 1 — Billing + Plan Selection (Week 1)
- Implement `BillingPlanService` with 3 plans ($49/$129/$249).
- Build plan selection UI at `/billing/plans`.
- Wire plan selection → `appSubscriptionCreate` → `SubscriptionSyncService` sync.
- Map existing "Prowl Monthly" subscribers to Starter tier automatically.
- Growth and Pro show as "Coming Soon" with waitlist email capture.
- Remove `MAX_MONITORED_PAGES` enforcement.

### Sprint 2 — Product Configuration Auto-Detection + Onboarding (Week 2)
- Build `ProductConfigDetectorService`.
- Build onboarding UI: loading state → configurations review → swap representative → confirm.
- Create/update monitoring records from detected configurations.
- Trigger first scan immediately after onboarding confirmation.

### Sprint 3 — Cart Scanning + Checkout Handoff (Week 3)
- Implement `BrowserService#verify_cart_item` and `BrowserService#cart_feedback_visible?`.
- Wire `navigate_to_checkout` into `AddToCartDetector`.
- Add `price_mismatch` issue type. Pass `PriceVisibilityDetector` result to `AddToCartDetector`.

### Sprint 4 — Alert Escalation System (Week 4)
- Add escalation columns (`acknowledged`, `escalation_level`, `last_alerted_at`, `acknowledgment_token`).
- Implement 3-tier escalation logic in `AlertService`.
- Build endpoint `GET /alerts/:token/acknowledge`.
- Wire "All clear" email (`AlertMailer#issues_resolved`).
- Build alert history page at `/alerts`.

### Sprint 5 — Dashboard Polish + Launch Prep (Week 5)
- Update `HomeController` dashboard to show product configurations instead of isolated pages.
- Add scan history timeline.
- Add "Re-scan store setup" button in settings.
- Update Shopify app store listing.

---

## 8. Risks & Open Questions

### Risk 1 — Product configuration auto-detection accuracy
- Page builder apps (GemPages, Shogun) might use single generic templates for wildly different pages.
- Headless setups lack standard Liquid templates.
- **Mitigation**: Focus on standard Liquid themes for Phase 2. Add a manual override to "add a product to monitor" if auto-detect fails to cover edge cases.

### Risk 2 — Browserless.io cost at new pricing
- Evaluate deep scan costs (which involve checkout navigation). Is $49/month Starter viable for deep scans? 
- **Consideration**: Run quick scans daily, true deep scans weekly.

### Risk 3 — Shopify app review with new pricing
- **Recommendation**: Finish the current review at $10/month. Update pricing immediately after approval, before broad user acquisition.

### Risk 4 — Representative product selection quality
- Detector must avoid hidden or OOS products unless intended.
- **Mitigation**: Filter by `status: active` and `published_at: not null`. Hand off selection confirmation to merchants.

### Risk 5 — Acknowledgment link security
- Do NOT use raw DB lookups. Use `ActiveSupport::MessageVerifier` or `GlobalID`.
- Set token expiry to 7 days. Rate limit the endpoint.

### Risk 6 — Scan scheduling at scale
- Solid Queue concurrency is currently 1.
- **Action Required**: Increase concurrency when higher tiers launch, strictly ensuring Browserless concurrent session quotas are not breached.

### Open Q 1 — Existing $10 subscribers
Provide Starter-level functionality without changing their price. Handled via `charge_name` matching in `BillingPlanService`.

### Open Q 2 — Dashboard experience between scans
Starter runs weekly. The dashboard must show value. Display last scan prominently, expected next scan, and a controlled "Scan Now" button.

### Open Q 3 — Dual-browser confirmation
Deferred to Phase 3. Abstract `BrowserService` heavily so swapping Puppeteer for Playwright will be straightforward.
