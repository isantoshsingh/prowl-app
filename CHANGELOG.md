# Changelog

All notable changes to Prowl are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased] — Detection Reliability + Billing Fixes

### Fixed

- **False positive ATC on Horizon theme**: `wait_for_network_idle` was checking `document.readyState` (always 'complete' after page load), so it returned immediately after ATC click. Now tracks actual network activity via Performance API resource count. Also added cart state polling (up to 4 attempts with 1s delays) in the funnel test to handle themes with async cart updates.
- **False `checkout_broken` from AI over-escalation**: AI was misinterpreting JS errors as checkout failures. Fixed the AI prompt to be explicit about type definitions, added `RELATED_ISSUE_GROUPS` in `ScanPipelineService` to prevent AI from creating duplicate escalated issues when programmatic detection already caught the root cause, and tightened `CRITICAL_PATTERNS` in `JavascriptErrorDetector` (removed overly broad patterns like `/product/i`, `/shopify/i`, `/form/i`).
- **Rescan loader/polling not showing**: Race condition — the Scan record was created inside the job (in `ProductPageScanner`), but the page reloaded before the job started, so `@scanning` was false. Now creates the Scan record in the controller before enqueuing the job, and passes `scan_id` to the scanner. Also fixed `rescan` action using `scans.running` (only "running") instead of checking for both "pending" and "running".
- **AI-only issue types never resolved**: When all detectors passed, `checkout_broken` and `atc_not_functional` were never resolved because no detector directly maps to them. Added `RELATED_RESOLUTION_MAP` so passing detectors also resolve related types (e.g., `missing_add_to_cart` pass resolves `atc_not_functional`).
- **Shopify platform JS errors flagged as critical**: Errors from Shopify's own scripts (shop-js analytics, Web Pixel Manager, shop_events_listener, monorail telemetry) and headless browser noise (`net::ERR_FAILED`, `Failed to fetch`) were not filtered. Added these to `IGNORE_PATTERNS`.
- **Billing redirect loop after charge approval**: `has_active_payment?` didn't process the `charge_id` callback param. After the merchant approved a charge, the local subscription cache was stale, so `check_billing` kept redirecting. Now immediately syncs the subscription via `SubscriptionSyncService` when `charge_id` is present.
- **Stale `subscription_status: 'cancelled'` after reinstall**: The uninstall webhook sets `subscription_status` to 'cancelled', but `reinstall!` didn't reset it. New charge approval couldn't update it because the billing check loop prevented the app from loading. `reinstall!` now resets `subscription_status` to 'none'.

### Changed

- **`checkout_broken` disabled for phase 1**: Removed from `AI_ISSUE_TYPE_MAP` and AI prompt. No programmatic detector exists for it — was AI-only and caused false positives. Will be re-enabled in phase 2 with a proper checkout detector.
- **Timestamps in browser local timezone**: All absolute timestamps (previously server-side UTC via `strftime`) now render as `<time>` elements with ISO 8601 `datetime` attributes, converted to the browser's local timezone via JavaScript. Added `local_time` helper in `ApplicationHelper`.
- **`ProductPageScanner` accepts pre-created scan**: New `scan:` parameter allows passing an existing Scan record instead of always creating one (backward-compatible — creates one if not provided).
- **`ScanPdpJob` accepts `scan_id:`**: Forwards pre-created scan to the scanner. Cleans up the scan record if the job skips (billing inactive, monitoring disabled).

---

## [Unreleased] — Purchase Funnel Detection + AI Visual Confirmation

### Added

- **Purchase funnel testing (deep scan)**: Full end-to-end Add-to-Cart flow verification — select variant, click ATC, verify cart updates via `/cart.js`, cleanup. Controlled by `scan_depth` (`:quick` structural-only, `:deep` full funnel).
- **AI as primary detector**: Gemini Flash analyzes page screenshots to independently identify ALL issues, merging findings with programmatic detection results. AI-detected issues are created with `ai_confirmed: true` for immediate alerting.
- **New issue types**: `atc_not_functional` (button clicks but cart doesn't update), `checkout_broken` (checkout page fails to load), `variant_selection_broken` (cannot select product variants).
- **Immediate alerting for AI-confirmed issues**: High-confidence AI-confirmed issues skip the 2-occurrence wait and alert merchants immediately on first detection.
- **Cloudflare R2 screenshot storage**: `ScreenshotUploader` service uploads scan screenshots to R2 (S3-compatible, zero egress fees). Falls back to local `tmp/` in development.
- **ScreenshotsController**: Serves screenshots privately from R2 (production) or local storage (development) — screenshots are never publicly accessible.
- **AI analysis columns on issues**: `ai_confirmed`, `ai_confidence`, `ai_reasoning`, `ai_explanation`, `ai_suggested_fix`, `ai_verified_at` — stores Gemini analysis results per issue.
- **Scan depth column on scans**: `scan_depth` (quick/deep) and `funnel_results` (JSONB) track funnel test outcomes.
- **Smart scan depth selection**: `ScanPdpJob` automatically determines depth — deep for first scan, open critical issues, or weekly Monday scans; quick otherwise.
- **Issue severity merge logic**: `Issue#merge_new_detection!` handles escalation (override + clear AI cache), de-escalation (resolve old + create new), and same-severity context refresh.
- **BrowserService purchase funnel methods**: `select_first_variant`, `click_add_to_cart`, `read_cart_state`, `clear_cart_item`, `navigate_to_checkout` — all language-independent using Shopify platform APIs.
- **Variant selection fix**: Support for radio buttons inside `variant-selects` and `variant-radios` (Dawn theme compatibility).
- **Screenshot thumbnails in UI**: Scan screenshots displayed as clickable thumbnails with Polaris modal for full-size viewing in product page and scan detail views.
- **Funnel detection integration test**: `test/scripts/funnel_detection_test.rb` for manual end-to-end testing of the purchase flow detection.
- **Cloudflare R2 Rails skill**: `.agent/skills/cloudflare-r2-rails/SKILL.md` agent guide for R2 integration.

### Changed

- **BrowserService**: Now connects to Browserless.io via WebSocket in production (~0MB local RAM vs ~350MB for local Chrome). Refuses to launch local Chrome in production to prevent R14 memory crashes.
- **AddToCartDetector**: Rewritten with three-layer detection (structural → interaction → AI). Removed text-based button search in favor of DOM attribute selectors. Added variant pre-selection when button is initially disabled.
- **DetectionService**: Uses `Issue#merge_new_detection!` for smarter issue lifecycle instead of simple `record_occurrence!`. Added mappings for new issue types (`atc_funnel`, `checkout`, `variant_interaction`).
- **ProductPageScanner**: Passes `scan_depth` to detectors, uses `ScreenshotUploader` for R2 storage instead of local file writes, extended timeout (60s) for deep scans.
- **ScanPdpJob**: Orchestrates 5-step pipeline — programmatic detection → AI page analysis → per-issue AI explanation → alerting → conditional rescan. Only rescans for unconfirmed critical issues.
- **Issue model**: `alertable` scope updated to include AI-confirmed issues (`occurrence_count >= 2 OR ai_confirmed = true`). Added `merchant_explanation` and `merchant_suggested_fix` helper methods.
- **Alert mailer templates**: Enhanced with AI-generated explanations, suggested fixes, and inline screenshot attachments.
- **MAX_MONITORED_PAGES default**: Changed from 5 to 3 in `shop_settings`.
- **Puma configuration**: Integrated Solid Queue supervisor as Puma plugin for single-dyno deployment.

### Removed

- **Outdated documentation**: Removed `docs/` directory (app-store-listing, common-issues-and-fixes, faq, getting-started, how-detection-works, troubleshooting, understanding-results).
- **Text-based ATC button search**: Removed fallback that searched all buttons by text content — replaced with DOM selector strategies.
- **Legacy local screenshot storage**: Replaced direct `File.binwrite` to `tmp/screenshots/` with `ScreenshotUploader` service (still uses local storage in dev).

### Infrastructure

- Added `aws-sdk-s3` gem for Cloudflare R2 integration.
- Added `jemalloc` for memory optimization on Heroku.
- Integrated Solid Queue in Puma for in-process background job execution.
- Added `resend` gem and initializer for production email delivery.
- Blocked local Chrome launch in production environment (`BrowserService` raises on missing `BROWSERLESS_URL`).

### Security Fixes

- **JS injection in `BrowserService#clear_cart_item`**: Sanitized `line_item_key` input and use `to_json` for safe JS interpolation instead of raw string interpolation.
- **Path traversal in `ScreenshotUploader#download`**: Added `File.expand_path` validation to ensure resolved paths stay within `tmp/screenshots/`.
- **XSS in AI-generated mailer content**: Added `strip_tags` sanitization to `merchant_explanation` and `merchant_suggested_fix` methods on the `Issue` model.

### Bug Fixes

- **`ShopSetting#effective_alert_email`**: Fixed fallback from `shop.shopify_domain` (not an email) to `shop.email` (actual email from Shopify webhook data). Also fixed matching fallback in `AlertMailer`.
- **`alertable` scope divergence**: Added `left_joins(:alerts).where(alerts: { id: nil })` to match `should_alert?` behavior, preventing re-alerting for already-alerted issues.
- **`Issue#merge_new_detection!` de-escalation**: Changed return value from `nil` to `:de_escalated` symbol for explicit handling. Updated `DetectionService` to match.
- **Bare `rescue nil` in `BrowserService#close`**: Replaced with explicit `StandardError` rescue that logs to debug level for diagnosing resource leaks.
- **Hardcoded `sleep()` in funnel methods**: Replaced `sleep(1.5)` and `sleep(2)` with `wait_for_network_idle` polling helper that adapts to actual page responsiveness.
- **Symbol/string key inconsistency**: Normalized `Scan#parsed_dom_checks_data` to always return symbol keys via `deep_symbolize_keys`. Cleaned up defensive dual-access in `DetectionService` and `AiIssueAnalyzer`.
- **English-only sold-out detection**: Added language-independent check via Shopify product JSON (`product.available`), plus French/Spanish/German text patterns.

### Refactored

- **`ScanPipelineService`** (new): Extracted the 5-step post-scan pipeline from `ScanPdpJob` into a dedicated service. Each step is now a separate method, making the pipeline testable and the job thin.

### Database Migrations

- `20260224170652_add_ai_analysis_to_issues`: Adds AI analysis columns to issues table.
- `20260224172019_change_max_monitored_pages_default_to3`: Changes default from 5 to 3, migrates existing data.
- `20260225173147_add_funnel_testing_to_scans`: Adds `scan_depth` and `funnel_results` to scans table.
- `20260301000001_add_indexes_for_ai_and_scan_depth`: Adds partial index on `issues.ai_confirmed` and index on `scans.scan_depth`.
