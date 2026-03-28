# Phase 2 Progress Tracker

This document tracks the progress of the Prowl Phase 2 build (Storefront Conversion Monitor) as defined in `phase2.md`. 
After completing each step, this document will be updated with what was built, test results, and any deviations from the spec.

## Sprint 1: Billing & Onboarding (Week 1)

**Status:** Not Started

### Planned Steps
1. **Implement `BillingPlanService`:** Define Free and Monitor ($49) plans.
2. **Update Billing Defaults:** Update `config/initializers/shopify_app.rb` to default to the Free tier.
3. **Plan Comparison UI:** Build the Polaris-based plan comparison page showing Free vs Monitor.
4. **Wire Monitor Plan:** Map selection → `appSubscriptionCreate` (14-day trial) → `SubscriptionSyncService` sync.
5. **Update Onboarding Flow:** Install → land on dashboard (Free) → add products → first scan.
6. **Product Limit Enforcement:** Update limits (Free = 3, Monitor = 5) in controllers.
7. **UI Guidance:** Add copy: "Select different types of products for best coverage" in product selection.

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

*(Waiting for steps to be completed - format below)*

### Format:
**Step:** [Number] - [Description]
**What was built:** [Details]
**Test results:** [Results]
**Deviations:** [Any deviations from the spec]
