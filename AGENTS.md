# AGENTS.md — Prowl

Guidelines for AI coding agents working in this codebase.

---

## 1. Project Overview

Prowl is a Shopify embedded app that monitors product detail pages (PDPs) for broken functionality — missing add-to-cart buttons, JavaScript errors, Liquid template issues, broken images, and performance problems.

**Target users:** Shopify merchants and agencies.

**Core value proposition:** Silent revenue loss detection. PDPs break due to app conflicts, theme changes, or frontend regressions. Merchants often don't notice until revenue drops. Prowl catches these breaks early by scanning pages with a headless browser and alerting merchants before customers are affected.

**Phase 1 (MVP):** Confidence-scored detection with AI visual confirmation (Gemini Flash), purchase funnel testing (deep scans: variant selection → ATC → cart verification → cleanup), daily scanning, email + admin alerts, Polaris UI dashboard. Paid-only at $10/month with a 14-day free trial via the Shopify Billing API.

---

## 2. Architecture Summary

### Stack

| Layer | Technology |
|---|---|
| Backend | Rails 8.1 (Ruby) |
| Database | PostgreSQL (Heroku Postgres Essential-0) |
| Background jobs | Solid Queue (in-process via Puma plugin in production, no Redis) |
| Headless browser | `puppeteer-ruby` gem (~0.45), **Browserless.io** cloud browser in production |
| Shopify integration | `shopify_app` gem (~23.0), embedded app with token-based OAuth |
| Asset pipeline | Propshaft + importmap-rails |
| Frontend framework | Hotwire (Turbo + Stimulus), Shopify Polaris Web Components |
| HTTP client | HTTParty |
| AI analysis | Google Gemini 2.5 Flash (issue confirmation + merchant explanations) |
| Email | `letter_opener` in dev, **Resend** SMTP in production |
| Screenshots | Local `tmp/screenshots/` in dev, **Cloudflare R2** in production |
| Cloud storage | Cloudflare R2 via `aws-sdk-s3` gem (S3-compatible, zero egress fees) |
| Deployment | Heroku (single Basic dyno, web + Solid Queue in-process) |

### Request Flow

1. Merchant installs app via Shopify OAuth (`shopify_app` gem handles the flow).
2. `AfterAuthenticateJob` runs inline after install to bootstrap shop data.
3. Merchant selects up to 3 product pages to monitor (`MAX_MONITORED_PAGES = 3`).
4. `ScheduledScanJob` runs daily at 6am UTC (configured in `config/recurring.yml`).
5. It queues one `ScanPdpJob` per monitored `ProductPage`.
6. `ScanPdpJob` determines scan depth (`:quick` for daily scans, `:deep` for first scan / open critical issues / weekly Monday), then uses `ProductPageScanner` which connects to `BrowserService` (Puppeteer via Browserless in production, local Chrome in dev), navigates to the page, captures data, runs all Tier 1 detectors. Deep scans also run the full purchase funnel test (variant selection → ATC click → cart verification via `/cart.js` → cleanup).
7. Screenshots are uploaded to Cloudflare R2 via `ScreenshotUploader` and the R2 key is stored in `scans.screenshot_url`. Screenshots are **private** — served through `ScreenshotsController` (which scopes to the current shop), never publicly accessible. Files are organized as `{shop-slug}/{product-handle}/scan_{id}_{timestamp}.png`.
8. `ScanPdpJob` delegates to `ScanPipelineService` which orchestrates a 5-step pipeline:
   - **Step 1:** `DetectionService` creates/updates `Issue` records from programmatic detection results. Uses `Issue#merge_new_detection!` for smart escalation/de-escalation.
   - **Step 2:** AI page-level analysis — sends screenshot + programmatic results to Gemini Flash. AI independently identifies ALL issues. New AI-only findings are created with `ai_confirmed: true`.
   - **Step 3:** Per-issue AI analysis — generates merchant explanations and suggested fixes for each issue. High-severity issues get visual confirmation.
   - **Step 4:** `AlertService` sends email/admin notifications for qualifying issues.
   - **Step 5:** Schedules a rescan in 30 minutes for unconfirmed high-severity issues.
9. AI is fail-open throughout — if Gemini fails at any step, programmatic detection and hardcoded descriptions are used.
10. `AlertService` sends alerts for high-severity issues via two paths: (a) AI-confirmed issues alert immediately on first occurrence, (b) non-AI-confirmed issues require 2+ occurrences. Emails include inline screenshots and AI-generated explanations via Resend SMTP.

---

## 3. Key Domain Concepts

- **Shop** (`app/models/shop.rb`): A Shopify merchant who installed Prowl. Central model that owns all other records. Includes billing state, onboarding progress, and Shopify metadata.

- **ProductPage** (`app/models/product_page.rb`): A PDP URL being monitored. Belongs to a Shop. Has statuses: `pending`, `healthy`, `warning`, `critical`, `error`. Supports soft-delete via `deleted_at`. Each shop can monitor up to 3 pages (`MAX_MONITORED_PAGES = 3`).

- **Scan** (`app/models/scan.rb`): One headless browser run against a ProductPage. Captures screenshot URL (R2 key in production, local path in dev), HTML snapshot, JS errors, network errors, console logs, DOM check data, page load time, `scan_depth` (quick/deep), and `funnel_results` (JSONB). Statuses: `pending`, `running`, `completed`, `failed`. **Important:** `parsed_dom_checks_data` normalizes results to symbol keys via `deep_symbolize_keys` — all downstream consumers (DetectionService, AiIssueAnalyzer) use symbol access.

- **Issue** (`app/models/issue.rb`): A detected problem linked to a ProductPage and the Scan that found it. Has `issue_type`, `severity` (high/medium/low), `status` (open/acknowledged/resolved), `occurrence_count`, and serialized `evidence` JSON. Includes AI analysis columns: `ai_confirmed`, `ai_confidence`, `ai_reasoning`, `ai_explanation`, `ai_suggested_fix`, `ai_verified_at`. The `merchant_explanation` and `merchant_suggested_fix` methods return AI-generated text sanitized via `strip_tags` (with fallback to hardcoded descriptions). `merge_new_detection!` handles escalation/de-escalation/same-severity — returns `self` on escalation/same, `:de_escalated` on de-escalation (caller creates new issue). Two paths to alerting: AI-confirmed issues alert immediately; others require 2+ occurrences. The `alertable` scope includes the `alerts.none?` check to prevent re-alerting.

- **Alert** (`app/models/alert.rb`): A notification sent to a merchant about an Issue. Types: `email`, `admin`. Delivery statuses: `pending`, `sent`, `failed`. Unique DB index on `(shop_id, issue_id, alert_type)` — allows both email and admin alerts per issue. `AlertService` creates the Alert record before sending the email (never the reverse) and handles `RecordNotUnique` for race condition safety.

- **ScanPipelineService** (`app/services/scan_pipeline_service.rb`): Orchestrates the 5-step post-scan pipeline (programmatic detection → AI page analysis → per-issue AI → alerting → conditional rescan). Extracted from `ScanPdpJob` to keep the job thin and each step independently testable. Fail-open: AI failures at any step don't block subsequent steps.

- **Detector** (`app/services/detectors/base_detector.rb`): A module in the detection engine that checks for one class of issue. Returns a standardized result hash: `{ check:, status:, confidence:, details: { message:, technical_details:, suggestions:, evidence: } }`. Status is one of `pass`, `fail`, `warning`, `inconclusive`. Confidence is a float 0.0–1.0.

- **Subscription** (`app/models/subscription.rb`): Tracks Shopify Billing API subscription state. Shops must have active billing (or be `billing_exempt`) to scan.

- **ShopSetting** (`app/models/shop_setting.rb`): Per-shop configuration — alert email, scan frequency, alert toggles, max monitored pages.

---

## 4. Codebase Navigation Guide

### Models
```
app/models/
  shop.rb                  # Central model, Shopify session storage
  product_page.rb          # Monitored PDP URLs (soft-deletable)
  scan.rb                  # Scan run records
  issue.rb                 # Detected problems
  alert.rb                 # Notifications sent
  shop_setting.rb          # Per-shop configuration
  subscription.rb          # Billing state
```

### Scan Orchestration
```
app/services/
  product_page_scanner.rb  # Top-level scan orchestrator — connects browser, runs detectors, saves results
  scan_pipeline_service.rb # 5-step post-scan pipeline (detection → AI → alerts → rescan)
  browser_service.rb       # Puppeteer lifecycle — Browserless (remote) in production, local Chrome in dev
  screenshot_uploader.rb   # Upload/download screenshots to Cloudflare R2 (local tmp/ fallback in dev)
  ai_issue_analyzer.rb     # Gemini Flash AI — page analysis, issue confirmation, merchant explanations
  pdp_scanner_service.rb   # Legacy scanner (kept for reference, replaced by ProductPageScanner)
  detection_service.rb     # Processes detector results into Issue records (symbol keys from parsed_dom_checks_data)
  alert_service.rb         # Sends email/admin alerts for qualifying Issues (create record before sending)
  subscription_sync_service.rb  # Syncs billing state from Shopify API
```

### Detectors
```
app/services/detectors/
  base_detector.rb              # Abstract base — defines result structure, confidence calculation
  add_to_cart_detector.rb       # Checks ATC button presence, visibility, clickability
  javascript_error_detector.rb  # Evaluates captured JS errors for severity
  liquid_error_detector.rb      # Checks for Liquid/template rendering errors
  price_visibility_detector.rb  # Verifies price is visible on the page
  product_image_detector.rb     # Checks product images load correctly
```

### Background Jobs
```
app/jobs/
  scheduled_scan_job.rb     # Runs daily at 6am UTC, queues ScanPdpJob for each monitored page
  scan_pdp_job.rb           # Performs a single page scan — delegates to ScanPipelineService. queue: :scans, retries: 3
  after_authenticate_job.rb # Runs inline after Shopify OAuth install
  shop_redact_job.rb        # GDPR shop data redaction
```

### Shopify Webhooks
```
app/controllers/webhooks/
  app_uninstalled_controller.rb  # Handles app/uninstalled webhook
  shop_update_controller.rb      # Handles shop/update webhook
  compliance_controller.rb       # GDPR: customers_data_request, customers_redact, shop_redact
```

### Controllers
```
app/controllers/
  authenticated_controller.rb  # Base for all authenticated controllers (billing check, session)
  home_controller.rb           # Root — dashboard / App Home Page
  dashboard_controller.rb      # Dashboard stats API endpoint
  product_pages_controller.rb  # CRUD for monitored pages + rescan trigger
  issues_controller.rb         # Issue list + detail + acknowledge action
  scans_controller.rb          # Scan history views
  settings_controller.rb       # Shop settings (alerts, frequency)
  billing_controller.rb        # Pricing page
  screenshots_controller.rb    # Serves private screenshots (R2 in prod, local in dev). Inherits AuthenticatedController, scoped to current shop.
  privacy_controller.rb        # Public privacy policy page
```

### Views
```
app/views/
  home/            # Dashboard / App Home Page (Polaris)
  issues/          # Issue list and detail views
  product_pages/   # Product page management
  scans/           # Scan history
  billing/         # Pricing page
  alert_mailer/    # Email alert templates
  layouts/         # Application layout with Polaris + App Bridge
  privacy/         # Public privacy policy
```

### Configuration
```
config/
  initializers/shopify_app.rb  # Shopify app config (scopes, billing, API version)
  recurring.yml                # Solid Queue recurring job schedules
  queue.yml                    # Solid Queue queue configuration
  solid_queue.yml              # Solid Queue adapter settings
  routes.rb                    # All routes
  database.yml                 # PostgreSQL config
```

### Database
```
db/
  schema.rb          # Current schema (source of truth)
  migrate/           # All migrations
  queue_schema.rb    # Solid Queue tables
  seeds.rb           # Seed data
```

### Rake Tasks
```
lib/tasks/
  shops.rake         # Shop management utilities
```

### Documentation
```
PRD.md           # Product requirements document
ROADMAP.md       # Phase roadmap
SECURITY.md      # Security policy
CHANGELOG.md     # Release changelog
```

---

## 5. Development Principles & Constraints

### Hard Rules

1. **No Redis.** Solid Queue is the job backend. It uses the PostgreSQL database. Do not introduce Redis, Sidekiq, or any other job backend.

2. **Detector result contract.** All detectors must subclass `Detectors::BaseDetector` and return a standardized hash:
   ```ruby
   {
     check: "detector_name",        # string
     status: "pass|fail|warning|inconclusive",
     confidence: 0.0..1.0,          # float
     details: {
       message: "Human-readable description",
       technical_details: { ... },
       suggestions: [],
       evidence: { ... }
     }
   }
   ```

3. **Confidence threshold.** `DetectionService` only creates `Issue` records when `confidence >= 0.7`. Below that threshold, results are logged but ignored. This is defined as `CONFIDENCE_THRESHOLD = 0.7` in both `Detectors::BaseDetector` and `DetectionService`.

4. **Two-path alerting.** `AlertService` only sends notifications for `high` severity issues, via two paths: (a) AI-confirmed issues (`ai_confirmed = true`) alert immediately on first occurrence — high-confidence AI visual confirmation reduces false positives enough to skip the wait; (b) non-AI-confirmed issues require `occurrence_count >= 2` (rescan confirmation). See `Issue#should_alert?`. The `alertable` scope mirrors this logic and includes `alerts.none?` to prevent re-alerting.

5. **Shopify Polaris only.** The UI uses Shopify Polaris Web Components. Do not add Tailwind, Bootstrap, custom CSS frameworks, or React component libraries.

6. **Do not modify billing logic** without explicit instruction. Billing is configured in `config/initializers/shopify_app.rb` and enforced in `AuthenticatedController#has_active_payment?`. Changes to pricing, trial days, or billing flow require explicit approval.

7. **Backward compatibility on data models.** Do not rename or remove columns on `issues`, `scans`, `product_pages`, or `shops` without a migration plan. Existing scans and issues must remain queryable.

8. **Scan timeout budget.** `ProductPageScanner::SCAN_TIMEOUT_SECONDS` is 45s for quick scans, extended to 60s for deep scans (funnel testing). Puppeteer navigation timeout is 15s. Individual detector execution must stay fast — they run in-process, sequentially, after page load.

---

## 6. Testing Conventions

### Framework
- **Minitest** with Rails test helpers (`rails/test_help`).
- Fixtures in `test/fixtures/*.yml` (loaded automatically via `fixtures :all`).
- Tests run in parallel by default (`parallelize(workers: :number_of_processors)`).

### Test locations
```
test/
  test_helper.rb              # Setup, fixtures, parallel config
  models/
    shop_test.rb
    product_page_test.rb
    issue_test.rb
  jobs/
    scan_pdp_job_test.rb
  services/
    detection_service_test.rb
  scripts/
    live_pdp_scan_test.rb     # Integration test against real URLs (not for CI)
    funnel_detection_test.rb  # Manual purchase funnel detection test (not for CI)
  fixtures/
    shops.yml
    product_pages.yml
    scans.yml
    issues.yml
    alerts.yml
    shop_settings.yml
```

### Running tests
```bash
bin/rails test                       # All tests
bin/rails test test/models/          # Model tests only
bin/rails test test/services/        # Service tests only
bin/rails test test/models/issue_test.rb  # Single file
```

### Conventions
- Use fixtures (not factories) — there is no FactoryBot in this project.
- When adding a detector, add a corresponding test in `test/services/`.
- For scan-related tests, mock `BrowserService` rather than launching a real browser.
- `test/scripts/live_pdp_scan_test.rb` and `test/scripts/funnel_detection_test.rb` run against real Shopify stores — do not include in CI.

---

## 7. Common Agent Tasks

### Adding a new detector

1. Create `app/services/detectors/your_detector.rb` subclassing `Detectors::BaseDetector`.
2. Implement `#check_name` (returns a string identifier) and `#run_detection` (performs the check using `browser_service`).
3. Accept `scan_depth:` in `initialize` if the detector behaves differently for quick vs deep scans.
4. Use `pass_result`, `fail_result`, `warning_result`, or `inconclusive_result` to build the return hash.
5. Register the detector in `ProductPageScanner::TIER1_DETECTORS`.
6. Add the check name mapping in `DetectionService::CHECK_TO_ISSUE_TYPE` and `DetectionService::CHECK_SEVERITY`.
7. Add the issue type to `Issue::ISSUE_TYPES` with a title and description.
8. Also add the mapping in `AiIssueAnalyzer::AI_ISSUE_TYPE_MAP` so AI page analysis can confirm/create these issues.
9. Write a test in `test/services/`.

### Adding a new background job

1. Create `app/jobs/your_job.rb` inheriting from `ApplicationJob`.
2. Set `queue_as :default` (or `:scans` for scan-related work).
3. If it should run on a schedule, add an entry to `config/recurring.yml`.
4. For retries, use `retry_on` and `discard_on` as needed.
5. Solid Queue processes jobs from the database — no Redis configuration required.

### Modifying the dashboard UI

1. Views are in `app/views/home/`.
2. Use Shopify Polaris Web Components (imported via `<script>` in the layout).
3. The layout is in `app/views/layouts/` — it loads App Bridge and Polaris.
4. Dashboard stats come from `DashboardController#stats`.
5. Use Stimulus controllers in `app/assets/javascripts/` for interactivity.

### Updating email templates

1. Templates are in `app/views/alert_mailer/`.
2. The mailer is `app/mailers/alert_mailer.rb`. Screenshots are attached inline from R2.
3. Use `@issue.merchant_explanation` (AI-generated with hardcoded fallback) instead of `@issue.description` in templates.
4. In development, emails render in the browser via `letter_opener`.
5. Production uses Resend SMTP — configuration is in `config/environments/production.rb`.

### Modifying the scan pipeline

1. The post-scan pipeline lives in `app/services/scan_pipeline_service.rb` (not in the job).
2. `ScanPdpJob` is intentionally thin — it handles billing/monitoring checks, depth selection, and scanner invocation, then delegates to `ScanPipelineService`.
3. Each pipeline step is a separate private method. To add a step, add a method and call it from `#perform` in the correct order.
4. All steps are fail-open by design — wrap AI-dependent code in `rescue StandardError` to avoid blocking programmatic detection.
5. `send_alerts` iterates issues and calls `issue.reload` before `should_alert?` to pick up AI updates from earlier steps.

### Changing scan scheduling logic

1. The cron schedule is in `config/recurring.yml` (currently: daily at 6am UTC).
2. `ScheduledScanJob` selects shops with active billing and pages where `last_scanned_at` is older than 24 hours.
3. Per-shop frequency is stored in `ShopSetting#scan_frequency` but not yet enforced in the scheduler.
4. To change the schedule, edit `config/recurring.yml` and ensure `ScheduledScanJob` respects the per-shop setting.

---

## 8. Infrastructure & Environment Variables

### Production environment variables
```bash
# Cloudflare R2 (screenshot storage)
CLOUDFLARE_R2_ACCESS_KEY_ID=
CLOUDFLARE_R2_SECRET_ACCESS_KEY=
CLOUDFLARE_R2_BUCKET=prowl-screenshots
CLOUDFLARE_R2_ENDPOINT=https://<account_id>.r2.cloudflarestorage.com
CLOUDFLARE_R2_PUBLIC_URL=https://pub-xxxx.r2.dev

# Browserless (cloud browser for scans)
BROWSERLESS_URL=wss://production-sfo.browserless.io?token=YOUR_TOKEN

# Google Gemini (AI issue analysis)
GEMINI_API_KEY=
GEMINI_MODEL=gemini-2.5-flash  # optional override

# Resend (production email)
RESEND_API_KEY=re_xxxxx
```

### Deployment architecture (single dyno)
```
┌─ Heroku Basic Dyno ($7/mo) ──────────────────┐
│  Puma (web server)                            │
│  + Solid Queue (in-process via Puma plugin)   │
│  + HTTP calls to Browserless/R2/Gemini        │
│  Total: ~200MB of 512MB                       │
└───────────────────────────────────────────────┘
```

### R2 screenshot organization
```
prowl-screenshots/
  {shop-slug}/                    ← from shopify_domain minus .myshopify.com
    {product-handle}/             ← from product_page.handle
      scan_{id}_{timestamp}.png
```

---

## 9. What NOT to Do

- **Do not auto-resolve Issues** without merchant confirmation. Issues are resolved only when a subsequent scan no longer detects the problem (handled by `DetectionService#resolve_existing_issue`), or manually by the merchant via acknowledge/resolve.

- **Do not scan pages outside the merchant's own Shopify store.** `ProductPage#scannable_url` constructs URLs using the shop's `shopify_domain`. Do not allow arbitrary URL scanning.

- **Do not store raw HTML of scanned pages long-term.** The `html_snapshot` column on `scans` exists for detection processing only. Screenshots are the permanent evidence artifact.

- **Do not exceed Shopify API rate limits.** The `shopify_app` gem handles throttling for authenticated API calls. When making direct API requests with `HTTParty`, implement backoff.

- **Do not add Redis as a dependency.** Solid Queue handles all background job processing via PostgreSQL. Solid Cache handles caching. There is no Redis in this stack.

- **Do not create Issues with confidence below 0.7.** Low-confidence detections are logged but must not generate Issue records or alerts.

- **Do not send alerts without checking `should_alert?`.** Two paths to alerting: (a) AI-confirmed issues alert immediately on first occurrence, (b) non-AI-confirmed issues require 2+ occurrences. Always use `Issue#should_alert?` — do not hardcode occurrence checks.

- **Do not bypass billing checks.** All authenticated controllers inherit from `AuthenticatedController`, which checks `has_active_payment?`. Scans also verify `shop.billing_active?` before executing.

- **Do not let AI block alerts.** AI is fail-open throughout the pipeline. If Gemini fails, programmatic detection continues, hardcoded descriptions are used, and non-AI-confirmed issues still alert after 2 occurrences. Never make AI availability a prerequisite for alerting.

- **Do not send email before creating the Alert record.** `AlertService` must create the `Alert` record first to prevent duplicate emails if subsequent steps fail. The `create_alert` method handles `RecordNotUnique` for race condition safety.

- **Do not launch local Chrome in production.** `BrowserService` must use `BROWSERLESS_URL` in production to avoid R14 memory errors. Local Chrome is only for development.
