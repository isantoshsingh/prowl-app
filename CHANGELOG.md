# Changelog

All notable changes to Prowl are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

### Database Migrations

- `20260224170652_add_ai_analysis_to_issues`: Adds AI analysis columns to issues table.
- `20260224172019_change_max_monitored_pages_default_to3`: Changes default from 5 to 3, migrates existing data.
- `20260225173147_add_funnel_testing_to_scans`: Adds `scan_depth` and `funnel_results` to scans table.
