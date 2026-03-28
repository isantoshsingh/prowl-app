# Prowl Phase 2: Storefront Conversion Monitor

> **AI Agent Instructions**
> When working on Phase 2 tasks, you MUST:
> 1. Maintain and reference the `PHASE2-PROGRESS.md` file after every completed step to track implementation status.
> 2. Use the `bfs-checker` skill (`.agent/skills/bfs-checker/SKILL.md`) when checking Built for Shopify (BFS) compliance.
> 3. Use the `shopify-polaris-design` skill (`.agent/skills/shopify-polaris-design/SKILL.md`) when building or modifying Shopify Polaris UI components.
> 4. Use the `shopify-app-bridge` skill (`.agent/skills/shopify-app-bridge/SKILL.md`) for embedded app navigation and actions.

---

## Section 1: Current State

Prowl is currently a Shopify embedded app built on Rails 8.1 with PostgreSQL and Solid Queue (`app/jobs/`). It functions as a daily "PDP diagnostic tool" that scans up to 3 manually selected product pages (`app/models/product_page.rb`) for a merchant. 

**Scanning Capabilities:**
Scans are initiated daily by `ScheduledScanJob`. The core scanning logic is managed by `ProductPageScanner`, which launches a headless browser using `BrowserService` (connecting to Browserless.io in production). It runs the following Tier 1 Detectors (`app/services/detectors/`):
- `AddToCartDetector`: Checks if the ATC button is present and clickable.
- `JavascriptErrorDetector`: Captures JS errors on page load.
- `LiquidErrorDetector`: Looks for template rendering errors.
- `PriceVisibilityDetector`: Ensures the price is visible.
- `ProductImageDetector`: Verifies product images load correctly.

**Detection Pipeline:**
After the scan, `ScanPipelineService` orchestrates a 5-step process:
1. `DetectionService` processes the detector results and creates/updates `Issue` records (`app/models/issue.rb`). Only results with a confidence score >= 0.7 (`DetectionService::CONFIDENCE_THRESHOLD`) lead to issue creation.
2. `AiIssueAnalyzer#analyze_page` sends a captured screenshot (stored via Cloudflare R2 using `ScreenshotUploader`) and programmatic results to Gemini 2.5 Flash. It identifies AI-confirmed issues fail-open.
3. `AiIssueAnalyzer` provides per-issue explanations and suggested fixes for merchants.
4. `AlertService` handles alerting. It only sends alerts for High-severity issues via email (`AlertMailer`) or Shopify admin notifications. Immediate alerts are sent for AI-confirmed findings; otherwise, it waits for 2 occurrences.
5. `ScanPdpJob` schedules a rescan in 30 minutes for unconfirmed high-severity issues.

**Known Technical Debt & Observations:**
- **Double Scanning Vulnerability:** `ScanPdpJob` sets concurrency limits, but without rigorous debounce logic, concurrent webhook events/manual triggers could queue duplicate scans.
- **Cart Funnel Interaction:** Methods like `BrowserService#select_first_variant`, `click_add_to_cart`, `read_cart_state`, and `navigate_to_checkout` exist but are not fully wired into a formal "Cart Interaction" or "Checkout Handoff" detector flow used in regular quick scans.

---

## Section 2: Product Vision — Phase 2

Prowl is being repositioned from a "PDP diagnostic tool" to a **Storefront Conversion Monitor**.

**New positioning:** *"Prowl monitors your customer's buying journey and alerts you the moment something breaks that's costing you sales."*

Phase 2 transforms Prowl to:
- Monitor the full buying journey (PDP → cart → checkout handoff), not just product pages.
- Use an escalating alert system that respects merchant attention.
- Offer a "fix-it" service ($199 flat rate) for merchants who want issues resolved by the Prowl team.
- Migrate to run on self-hosted Puppeteer (DigitalOcean droplets) to reduce infrastructure costs and decrease reliance on Browserless.io.

---

## Section 3: Tier Structure

### Free Plan

- **Products monitored:** Up to 3. Selected via Shopify resource picker.
- **Journey stages:** PDP only. Includes variant selection, ATC button presence, price visibility, image loading, JS errors, and Liquid errors.
- **Scan frequency:** Daily (via `config/recurring.yml` & `ScheduledScanJob`).
- **Alerts:** Single email alert per issue detected via `AlertService` with no escalation sequence.
- **Weekly report:** Store health summary email linking to the dashboard, sent every week.
- **Acknowledgment:** One-click acknowledge button in alert emails to mute the issue.
- **On-demand scan:** Disabled.
- **Default plan:** Every merchant starts on Free after installation via `AfterAuthenticateJob`.
- **Guidance:** UI text in `app/views/home/` will guide merchants to select diverse products (e.g., one simple single-variant, one multi-variant).

### Monitor Plan — $49/month (14-day free trial)

- **Products monitored:** Up to 5.
- **Journey stages:** Full buying flow (PDP + cart interaction + checkout handoff).
- **Scan frequency:** Every 6 hours (Requires update to `ShopSetting#scan_frequency` and `ScheduledScanJob`).
- **Alerts:** Full 3-tier escalation sequence managed by `AlertService`:
  - Alert 1: Immediate on confirmed detection.
  - Alert 2: 24 hours later if unacknowledged (shorter, high urgency).
  - Alert 3: 72 hours later if unacknowledged (focusing on revenue impact).
  - Post-Alert 3: Persists only as a dashboard banner.
- **Acknowledgment:** Yes — stops escalation sequence.
- **On-demand scan:** Enabled via "Scan Now" button in the dashboard.
- **Historical scan log:** Available on the dashboard.
- **"All clear" email:** Dispatched when a previously detected issue resolves (`status: "resolved"`).

### Fix-it Service — $199 per incident

- **Available to:** Free and Monitor tier users.
- **Pricing:** Flat $199 for standard fixes via Shopify one-time application charge API (`appPurchaseOneTimeCreate`).
- **Access:** Collaborator access requested at the point of service.
- **Resolution target:** 4 business hours.
- **Terms of Service:** A strict TOS checkbox outlining what constitutes a "standard fix" (e.g., excluding theme rebuilds or 3rd party app bugs) to limit liability.
- **Accessed via:** Dedicated Support Portal.

---

## Section 4: Journey Stages — What Gets Scanned

### PDP Stage (Free + Monitor tiers)

This relies on existing logic located in `ProductPageScanner::TIER1_DETECTORS`:
- ATC button present and clickable (`Detectors::AddToCartDetector`).
- Variant selector functioning properly (JS errors tracked by `Detectors::JavascriptErrorDetector` and legacy fallbacks in `DetectionService#detect_variant_selector_issues`).
- Price visibility (`Detectors::PriceVisibilityDetector`).
- Product images loading correctly (`Detectors::ProductImageDetector`).
- No page load JS errors (`Detectors::JavascriptErrorDetector`).
- No Liquid errors (`Detectors::LiquidErrorDetector`).
- Page load performance (`DetectionService#detect_slow_page_load`).

### Cart Interaction Stage (Monitor tier only)

Leveraging `BrowserService` methods:
**Cart Item Verification:**
- Perform ATC click (`click_add_to_cart`), then poll `/cart.js` via `read_cart_state`.
- Verify: added `product_id` matches, item price > 0, quantity increments. 
- *Failure mapping:* Log `atc_not_functional` with evidence `{ reason: "wrong_item_in_cart" }` if cart mismatch occurs.

**Cart Feedback Detection:**
- Add `BrowserService#cart_feedback_visible?` to verify if Cart Drawer DOM changes or URL redirects to `/cart`.
- *Failure mapping:* If cart item exists in `/cart.js` but no visual feedback is triggered within 2 seconds, issue a `warning` status, escalating to failure only if `/cart.js` also fails.

**Price Mismatch Detection:**
- Compare pre-ATC price (from `PriceVisibilityDetector`) against the cart item price (`read_cart_state`).
- *Failure mapping:* Discrepancy > 1% logs a new `price_mismatch` issue defined in `Issue::ISSUE_TYPES` as medium severity.

### Checkout Handoff Stage (Monitor tier only)

- Following a successful cart interaction, call `BrowserService#navigate_to_checkout`.
- Verify response redirection to Shopify checkout domains (`checkout.shopify.com` or `shop.app`).
- *Failure mapping:* HTTP 4xx/5xx or broken page triggers `checkout_broken` (`high` severity).
- Cleanup: Invoke `BrowserService#clear_cart_item` to purge test data.

---

## Section 5: Alert Escalation System

### Data Model Changes
Require a migration for `issues` table:
```ruby
add_column :issues, :acknowledged_at, :datetime
add_column :issues, :escalation_level, :integer, default: 0, null: false
add_column :issues, :last_alerted_at, :datetime
add_column :issues, :acknowledgment_token, :string
add_index :issues, :acknowledgment_token
```

*(Note: `acknowledged_at` already exists, but the others need to be added. `status` is currently used for acknowledgment (`acknowledged`), so we keep that in sync).*

### Escalation Logic in `AlertService`

Refactor `AlertService#perform` and `should_alert?`:
```ruby
def send_escalation_alert(issue)
  return if issue.status == 'acknowledged'

  if issue.escalation_level == 0
    send_alert(issue, level: 1)
    issue.update!(escalation_level: 1, last_alerted_at: Time.current)
  elsif issue.escalation_level == 1 && issue.last_alerted_at < 24.hours.ago
    send_alert(issue, level: 2)
    issue.update!(escalation_level: 2, last_alerted_at: Time.current)
  elsif issue.escalation_level == 2 && issue.last_alerted_at < 72.hours.ago
    send_alert(issue, level: 3)
    issue.update!(escalation_level: 3, last_alerted_at: Time.current)
  end
end
```
Free tier accounts only progress to `escalation_level = 1`.

### Acknowledgment Endpoint
Implement a new controller action `AlertsController#acknowledge` mapped to `GET /alerts/:token/acknowledge`.
Uses `ActiveSupport::MessageVerifier` for the signed URL generated out of `acknowledgment_token`.
Updates issue to `status = 'acknowledged'`. Extends token expiration to 7 days.

### "All Clear" Email & Weekly Report
- **All Clear:** Invoked via `DetectionService#resolve_existing_issue` if the resolved issue previously had a `high` or `medium` severity.
- **Weekly Report:** Create `WeeklyHealthReportJob` iterating over all installed shops, summarizing the week's scan counts and existing issues. Suggests the Monitor plan for Free tier users.

---

## Section 6: Support Portal

### Flow & Location
Served under Prowl's primary domain via a new `SupportPortalController` using magic link auth (`support_tickets.magic_link_token`). Bypasses Shopify OAuth for frictionless mobile access.

### Data Models
Require new migrations:
```ruby
# support_tickets
create_table :support_tickets do |t|
  t.references :shop, null: false, foreign_key: true
  t.references :issue, null: true, foreign_key: true
  t.string :subject
  t.text :message
  t.string :ticket_type # issue_support, general_enquiry, fix_request
  t.string :status      # open, in_progress, resolved, closed
  t.string :magic_link_token
  t.timestamps
end
add_index :support_tickets, :magic_link_token, unique: true

# support_messages
create_table :support_messages do |t|
  t.references :support_ticket, null: false, foreign_key: true
  t.string :sender_type # merchant, admin
  t.text :message
  t.timestamps
end
```

### Fix-it Flow
1. Merchant visits link with pre-loaded context (e.g. `issue.ai_explanation`).
2. Merchant selects "Fix it for me — $199".
3. Displays required terms (TOS checkbox) and Collaborator Access instructions.
4. Redirection to Shopify for `appPurchaseOneTimeCreate` approval checkout.
5. On webhook approval callback (`charg_id`), Santosh gets emailed, and ticket `status` changes to `in_progress`.

---

## Section 7: Onboarding Flow

1. Install via `shopify_app`.
2. App runs `AfterAuthenticateJob` and lands on `HomeController#index` (Dashboard).
3. Defaults to Free plan (`BillingPlanService`).
4. Dashboard banner requests adding properties via Shopify Resource Picker.
5. Limit checks enforced in `ProductPagesController#create` (`shop.shop_setting.max_monitored_pages`).
6. After addition, the first quick scan executes synchronously or queues immmediately.

Upgrade nudges manifest in `WeeklyHealthReportJob` emails, when attempting to add > 3 products, and as sticky dashboard banners.

---

## Section 8: App Settings

Preserve existing `app/models/shop_setting.rb` variables (`email_alerts_enabled`, `admin_alerts_enabled`, `alert_email`).

**New Display Sections in `SettingsController#index`:**
- **Collaborator Access:** Instructions/links for granting access to the Prowl team to proactively fix problems.
- **Plan Management:** Integrates directly with Shopify Billing API to surface differences between Free and Monitor plans.
- **Alert Preferences:** Adjust base alert reception logic.

---

## Section 9: Infrastructure — Self-hosted Puppeteer

**Current implementation:** `BrowserService#start` branches via `ENV["BROWSERLESS_URL"]` to run either via WebSocket on Browserless.io or via `Puppeteer.launch` on local Chrome. 

**Migration to DigitalOcean:**
1. Provision a DigitalOcean droplet (e.g. 2GB RAM / 2 vCPUs) containing a dockerized unmanaged `browserless/chrome` image or an equivalent raw Puppeteer-core WebSocket server.
2. In production, update `ENV["BROWSERLESS_URL"]` to point to the droplet `wss://[DROPLET_IP]:[PORT]`. `BrowserService#start`'s remote condition will connect exactly as it does currently. No structural code rewrite inside Rails `BrowserService` is necessary, only an endpoint change.
3. Recommend keeping `limits_concurrency to: 1` per droplet initially, potentially scaling to `2-3` as memory profiling concludes on a 2GB instance (Chrome memory climbs during JS-heavy Shopify page evaluations).
4. **Fallback mechanism:** If Chrome WS refuses connection, the `start` block's rescues should abort the scan with a `ScanError` gracefully returning `success: false` up to `ProductPageScanner`, suppressing merchant alerts and retrying quietly the next cron cycle.

---

## Section 10: Build Order

*Assumes a 20-25 hours/week cadence. Each sprint delivers usable, deployable features.*

**Sprint 1: Billing & Onboarding (Week 1)**
- Create `BillingPlanService` identifying Free (3 products) vs Monitor (5 products).
- Update `config/initializers/shopify_app.rb` to default to free-tier behavior without an upfront charge screen.
- Overhaul `ProductPagesController` constraints.
- Build the Polaris-based plan comparison UI in `BillingController`.

**Sprint 2: Cart & Checkout Scanning (Week 2)**
- Expand `BrowserService` bridging `cart_feedback_visible?` and `verify_cart_item`.
- Integrate `BrowserService#navigate_to_checkout` within a new `CartFunnelDetector` subclassing `Detectors::BaseDetector`.
- Introduce `price_mismatch` to `Issue::ISSUE_TYPES`.
- Add feature flags checking `shop.plan == 'monitor'` around execution loops in `ProductPageScanner`.

**Sprint 3: Alert Escalation & Weekly Reporting (Week 3)**
- Add `escalation_level`, `last_alerted_at`, and `acknowledgment_token` to `Issue`.
- Redesign `AlertService#perform` logic for staged intervals.
- Establish `AlertsController#acknowledge` with `ActiveSupport::MessageVerifier`.
- Compose and test `WeeklyHealthReportJob` logic + mailer views.
- Rig `DetectionService#resolve_existing_issue` to trigger "All clear" emails.

**Sprint 4: Support Portal + Fix-It App Flow (Week 4)**
- Scaffold `SupportTickets` and `SupportMessages` models.
- Set up `SupportPortalController` authenticated solely via magic link hashes.
- Build "Fix it for me" Polaris interface.
- Scaffold the `appPurchaseOneTimeCreate` GraphQL mutation connection for the $199 fee.

**Sprint 5: Infrastructure & Launch Prep (Week 5)**
- Spin up DigitalOcean Chrome WS Droplet. Update ENV variables.
- Polish dashboard: Add "Scan Now" button for Monitoring tiers, format plan upgrading.
- Ensure staging tests (`test/scripts/live_pdp_scan_test.rb`) span password-protected and headless blocking scenarios robustly.

---

## Section 11: Risks & Open Questions

1. **Self-hosted Puppeteer reliability:** 
   - *Risk:* Memory leaks (Zombie Chrome processes) leading to droplet OOM failure.
   - *Likelihood/Impact:* Medium / High. 
   - *Mitigation:* Employ `pm2` or Docker restart policies mapped to aggressive health checks endpoint. Enforce deep GC sweeps or container restarts every 24h.
2. **Scan cost at scale on free tier:**
   - *Risk:* Infrastructure scales linearly with user base with no revenue injection.
   - *Likelihood/Impact:* High / Medium.
   - *Mitigation:* Pre-compute break-even thresholds based on Fix-it conversion rates. If cost scales unbounded, we must limit Free tier accounts to a lifetime frequency limit (e.g., 60 days) or transition "Daily" scans to "Weekly" scans.
3. **Password-protected stores:** 
   - *Risk:* Puppeteer deadlocks or loops indefinitely.
   - *Likelihood/Impact:* Medium / Low (Already explicitly checked in `BrowserService#password_protected_page?`).
   - *Mitigation:* Ensure `ScanPipelineService` registers this as an inconclusive failure (no issue creation, no alerting).
4. **Shopify storefront bot detection:** 
   - *Risk:* Akamai/Cloudflare flags droplet IP, imposing captchas that Puppeteer cannot bypass.
   - *Likelihood/Impact:* Medium / High.
   - *Mitigation:* Rotating BrightData proxies if needed, and rely strictly on user agent cloaking (`BrowserService#configure_page`).
5. **Fix-it service liability:** 
   - *Risk:* Breaking a theme irreparably during a $199 fix.
   - *Likelihood/Impact:* Low / High.
   - *Mitigation:* Mandatory, undeniable TOS checkmarks isolating Prowl's liability to a refund, combined with enforced strict theme backup procedures prior to any dev edits.
6. **Concurrent Scans on DigitalOcean:**
   - *Risk:* Queue spikes forcing long waits or locking droplets.
   - *Likelihood/Impact:* Medium / Medium.
   - *Mitigation:* `ScanPdpJob` concurrency limit limits node exhaustion. Wait queue handled cleanly by `Solid Queue`'s natural load balancing. Scale droplets horizontally into an array format `wss://droplet1, wss://droplet2` round-robined if adoption scales.
7. **Magic Link Security:**
   - *Risk:* Support portal manipulation via leaked tokens.
   - *Likelihood/Impact:* Low / High.
   - *Mitigation:* `ActiveSupport::MessageVerifier` signature with a hard expiration timestamp combined with rate limiting on the `/support/:token` endpoints.
