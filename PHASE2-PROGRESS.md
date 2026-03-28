# Phase 2 Progress Tracker

This document tracks the progress of the Prowl Phase 2 build (Storefront Conversion Monitor) as defined in `phase2.md`. 
After completing each step, this document will be updated with what was built, test results, and any deviations from the spec.

## Sprint 1: Billing & Onboarding (Week 1)

**Status:** Completed (2026-03-28)
**Branch:** `claude/sprint-1-billing-onboarding-mLKe7`

### Planned Steps
1. **Implement `BillingPlanService`:** Define Free and Monitor ($49) plans.
2. **Update Billing Defaults:** Update `config/initializers/shopify_app.rb` to default to the Free tier.
3. **Plan Comparison UI:** Build the Polaris-based plan comparison page showing Free vs Monitor.
4. **Wire Monitor Plan:** Map selection → `appSubscriptionCreate` (14-day trial) → `SubscriptionSyncService` sync.
5. **Update Onboarding Flow:** Install → land on dashboard (Free) → add products → first scan.
6. **Product Limit Enforcement:** Update limits (Free = 3, Monitor = 5) in controllers.
7. **UI Guidance:** Add copy: "Select different types of products for best coverage" in product selection.

### Completed Work

**Step 1 — BillingPlanService** (`app/services/billing_plan_service.rb` — NEW)
- Defines `PLANS` hash with Free and Monitor tier details (price, max_products, scan_interval_hours, journey_stages, alerts, escalation, on_demand_scan, charge_name).
- Helper methods: `plan_for(shop)`, `plan_name_for(shop)`, `max_products_for(shop)`, `scan_interval_for(shop)`.
- Legacy "Prowl Monthly" ($10) subscribers automatically mapped to Monitor features via `plan_name_for`.

**Step 2 — Billing Defaults** (`config/initializers/shopify_app.rb`)
- Removed hardcoded `config.billing = ShopifyApp::BillingConfiguration.new(...)` ($10/month charge).
- New installs now land directly on the dashboard without an upfront billing approval screen.
- Comment documents that billing is managed via BillingPlanService and BillingController.

**Step 2b — AuthenticatedController** (`app/controllers/authenticated_controller.rb`)
- Removed `has_active_payment?` override that gated all access behind billing.
- Added `sync_subscription_on_charge_callback` as a `before_action` to handle Shopify charge_id callbacks.
- Added `current_plan_name` helper method available to all views.

**Step 2c — AfterAuthenticateJob** (`app/jobs/after_authenticate_job.rb`)
- Added `sync_plan` method that runs after authentication.
- Syncs existing subscriptions from Shopify API (detects legacy $10 and new $49 charges).
- Updates `shop_setting` with plan-appropriate `max_monitored_pages` and `scan_frequency`.

**Step 3 — Plan Comparison UI** (`app/views/billing/plans.html.erb` — NEW)
- Route: `GET /billing/plans` (added to `config/routes.rb`).
- Two side-by-side Polaris cards: Free ($0) and Monitor ($49).
- Free card lists: 3 products, daily scans, PDP monitoring, email alerts, weekly health report.
- Monitor card lists: 5 products, 6-hour scans, full buying journey, alert escalation, on-demand scan, scan history, 14-day free trial.
- "Current plan" badge shown on the active plan.
- CTA: "Start 14-day free trial" button triggers subscribe flow via JS fetch.

**Step 4 — Monitor Plan Billing Flow** (`app/controllers/billing_controller.rb`)
- Added `plans` action for plan comparison page.
- Added `subscribe` action that calls Shopify `appSubscriptionCreate` GraphQL mutation with:
  - name: "Prowl Monitor", price: $49, trialDays: 14, interval: EVERY_30_DAYS.
  - `test: true` in non-production (uses same env var pattern as old config).
- Redirects merchant to Shopify's approval URL.
- On return with `charge_id`, `sync_subscription_on_charge_callback` syncs the subscription.
- `SubscriptionSyncService` updated to call `update_plan_settings` after sync — sets `max_monitored_pages` to 5 and `scan_frequency` to `every_6_hours`.

**Step 5 — Onboarding Flow**
- No billing gate on install — merchants land on dashboard with Free plan active.
- Dashboard empty state updated: "Add products to start monitoring your store".
- Existing onboarding guide (3 collapsible steps) still works unchanged.
- First scan triggers immediately after product addition (existing behavior, verified).

**Step 6 — Product Limit Enforcement**
- `Shop#can_add_monitored_page?` now delegates to `BillingPlanService.max_products_for(self)` instead of hardcoded `MAX_MONITORED_PAGES`.
- `ShopSetting` validation updated: `max_monitored_pages` allows up to 10 (was capped at 3), `scan_frequency` accepts `every_6_hours`.
- `ProductPagesController#create` shows plan-aware error: "You've reached the maximum of 3 products on your Free plan. Upgrade to Monitor for up to 5 products."
- Product pages index shows warning banner with upgrade link when Free plan limit reached.
- Resource picker toast shows plan-aware message when max slots exhausted.

**Step 7 — UI Guidance**
- Product pages empty state: "For best results, select different types of products — one with a single option (e.g., a poster) and one with multiple options like size and color."
- Remaining slots info shows "Upgrade for more" link for Free plan merchants.

**Additional Work:**

**Upgrade Prompts**
- Dashboard: Polaris info banner for Free plan merchants: "Get full journey monitoring — Upgrade to Monitor ($49/month) for cart + checkout monitoring, 6-hour scans, and alert escalation. [View Plans]".
- Billing index page updated with plan-aware status display and upgrade banner.
- Navigation: "Pricing" link in app nav goes to billing index, which links to plan comparison.

**Scan Frequency** (`app/jobs/scheduled_scan_job.rb`, `config/recurring.yml`)
- `ScheduledScanJob` now uses `BillingPlanService.scan_interval_for(shop)` per shop.
- Free plan: 24-hour interval. Monitor plan: 6-hour interval.
- Recurring job schedule changed from "every day at 6am" to "every hour" so Monitor plan's 6-hour interval is respected.
- Free plan shops are now scanned without requiring an active billing subscription.

**Legacy $10 Subscriber Handling**
- `BillingPlanService.plan_name_for(shop)` checks for `charge_name == "Prowl Monthly"` and returns "monitor".
- Legacy subscribers keep paying $10 but get full Monitor features (5 products, 6-hour scans, full journey, escalation).

### Files Changed (17 total)
- **New:** `app/services/billing_plan_service.rb`, `app/views/billing/plans.html.erb`
- **Modified:** `app/controllers/authenticated_controller.rb`, `app/controllers/billing_controller.rb`, `app/controllers/home_controller.rb`, `app/controllers/product_pages_controller.rb`, `app/jobs/after_authenticate_job.rb`, `app/jobs/scheduled_scan_job.rb`, `app/models/shop.rb`, `app/models/shop_setting.rb`, `app/services/subscription_sync_service.rb`, `app/views/billing/index.html.erb`, `app/views/home/_dashboard.html.erb`, `app/views/product_pages/index.html.erb`, `config/initializers/shopify_app.rb`, `config/recurring.yml`, `config/routes.rb`

### Test Results
- All Ruby syntax checks pass (10/10 files).
- All ERB template compilation checks pass (4/4 views).
- Full test suite could not run (PostgreSQL not available in CI environment) — requires manual verification in dev.

### Deviations from Spec
- **Billing index view (`/pricing`):** Kept as current plan status page rather than replacing with plan comparison. Plan comparison is at `/billing/plans` — the pricing page links to it. This gives merchants both a status view and a comparison view.
- **`ShopSetting.scan_frequency`:** Added `every_6_hours` as a new valid value (was only `daily`/`weekly`). This is stored in the DB so the `scan_interval` method returns the correct duration.
- **No database migration needed:** All changes use existing columns (`subscription_plan`, `subscription_status`, `max_monitored_pages`, `scan_frequency`). The `scan_frequency` value `every_6_hours` is new but the column is a string, so no migration required.

## Sprint 2: Cart & Checkout Scanning (Week 2)

**Status:** Not Started

### Planned Steps
1. **Cart Item Verification:** Implement `BrowserService#verify_cart_item` to verify correct product/variant/price in cart after ATC.
2. **Cart Feedback Detection:** Implement `BrowserService#cart_feedback_visible?` to detect cart drawer or page opening.
3. **Checkout Verification:** Wire `navigate_to_checkout` into `AddToCartDetector` or a new funnel detector to verify checkout redirect.
4. **Issue Type Expansion:** Add `price_mismatch` issue type.
5. **Tier Gating:** Gate cart + checkout scanning to Monitor tier only.

## Sprint 3: Alert Escalation & Weekly Report (Week 3)

**Status:** Not Started

### Planned Steps
1. **Database Migrations:** Add escalation columns to the `issues` table.
2. **Escalation Logic:** Implement 3-tier escalation logic in `AlertService`.
3. **Free-tier Alert Logic:** Implement single-alert behavior for Free tier.
4. **Acknowledgment Endpoint:** Build acknowledgment endpoint with signed URLs.
5. **"All Clear" Email:** Wire "All clear" email on issue resolution.
6. **Weekly Report:** Build weekly health report email (mailer + scheduled job).
7. **Free-tier Nudge:** Add upgrade nudge in free-tier weekly report.

## Sprint 4: Support Portal + Fix-It Flow (Week 4)

**Status:** Not Started

### Planned Steps
1. **Support Models:** Scaffold `SupportTickets` and `SupportMessages` models.
2. **Support Portal:** Set up `SupportPortalController` with magic link access on the same domain.
3. **Ticket Creation:** Support ticket creation from alert context (issue pre-loaded) and general enquiry form.
4. **Resolution Flows:** "I'll handle it myself" vs "Fix it for me — $199" Polaris UI flow.
5. **Fix-It Terms:** Fix-it TOS checkbox and terms page.
6. **One-Time Charger:** Shopify one-time charge creation for fix-it ($199).
7. **Collaborator Access Instructions:** Show collaborator access instructions on fix-it page.
8. **Admin Management:** Admin view for managing support tickets.

## Sprint 5: Infrastructure & Launch Prep (Week 5)

**Status:** Not Started

### Planned Steps
1. **Infrastructure Migration:** Spin up DigitalOcean Chrome WS Droplet and update ENV variables.
2. **Connection Update:** Update `BrowserService` connection to point at DigitalOcean droplet.
3. **Stability Testing:** Test scanning reliability on self-hosted infrastructure.
4. **Dashboard Polish:** Dashboard updates: scan history per product, status badges, "Scan Now" button for Monitor.
5. **Settings Polish:** Add collaborator access card, plan management, and alert preferences to Settings page.
6. **App Store Listing:** Update Shopify app store listing: new positioning as "Storefront Conversion Monitor".
7. **Final Testing:** Test across 10-15 real stores with different themes.

---

## Log

### 2026-03-28 — Sprint 1 Complete

**Step:** Sprint 1 (all 7 steps) — Billing + Plan Page + Onboarding
**What was built:** BillingPlanService (Free/Monitor plans), removed hardcoded $10 billing gate, plan comparison page at /billing/plans, Shopify appSubscriptionCreate flow for Monitor ($49/14-day trial), Free plan default onboarding, dynamic product limits, upgrade prompts, plan-based scan frequency, legacy $10 subscriber mapping.
**Test results:** Ruby syntax 10/10 pass, ERB compilation 4/4 pass. Full test suite requires PostgreSQL (not available in environment).
**Deviations:** Plan comparison at /billing/plans (separate from /pricing status page). Added `every_6_hours` scan_frequency value. No DB migration needed — all existing columns.
