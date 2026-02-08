# CLAUDE.md — Silent Profit (PDP-Diagnostics)

This file provides context for AI assistants working on this codebase.

## Project Overview

**Silent Profit** is a Shopify app that detects, monitors, and alerts merchants about broken product detail pages (PDPs) causing silent revenue loss. It scans pages with a headless browser, detects issues (missing add-to-cart, JS errors, broken images, etc.), and sends alerts.

**Current phase: Phase 1 (MVP)** — scanning, detection, alerts, dashboard only. No auto-fix, SEO tooling, or optimization features.

## Tech Stack

- **Framework:** Ruby on Rails 8.1.2
- **Ruby:** 3.4.7
- **Database:** PostgreSQL
- **Job Queue:** Solid Queue (database-backed)
- **Cache:** Solid Cache (database-backed)
- **Frontend:** ERB templates + Shopify Polaris Web Components + Turbo/Stimulus
- **Asset Pipeline:** Propshaft + importmap-rails (no webpack/esbuild)
- **PDP Scanning:** puppeteer-ruby (~0.45) with headless Chromium
- **HTTP Client:** HTTParty (~0.22)
- **Web Server:** Puma (>= 7.0)
- **Deployment:** Docker + Kamal

## Quick Reference Commands

```bash
# Setup
bin/setup                          # Full development setup

# Run the app
bin/dev                            # Start development server (port 3000)

# Tests
bin/rails test                     # Run all tests
bin/rails test test/models/        # Run model tests only
bin/rails test test/services/      # Run service tests only

# Linting & Security
bin/rubocop                        # Ruby style checks (Omakase style)
bin/brakeman --quiet --no-pager    # Security analysis
bin/bundler-audit                  # Gem vulnerability audit
bin/importmap audit                # JS dependency audit

# Full CI pipeline
bin/ci                             # Runs setup, rubocop, bundler-audit, importmap audit, brakeman

# Database
bin/rails db:create db:migrate     # Create and migrate database
bin/rails db:prepare               # Prepare database (create + migrate + seed)
```

## Project Structure

```
app/
  controllers/          # Request handlers (inherit AuthenticatedController)
    webhooks/           # Shopify webhook handlers
  models/               # ActiveRecord models
  services/             # Business logic (scanner, detection, alerts, subscriptions)
  jobs/                 # Solid Queue background jobs
  mailers/              # Email notifications (AlertMailer)
  views/                # ERB templates with Polaris web components
  helpers/              # View helpers
config/
  routes.rb             # Route definitions
  database.yml          # PostgreSQL config (dev/test/production)
  recurring.yml         # Scheduled jobs (daily scan at 6am UTC)
  solid_queue.yml       # Queue configuration (default, scans, mailers)
  initializers/
    shopify_app.rb      # Shopify OAuth, scopes, billing config
  ci.rb                 # CI pipeline definition
db/
  migrate/              # 14 database migrations
test/
  models/               # Model tests (shop, product_page, issue)
  services/             # Service tests (detection_service)
  fixtures/             # YAML test fixtures
```

## Architecture & Key Patterns

### Data Model

```
Shop → ProductPage → Scan → Issue → Alert
Shop → ShopSetting (1:1)
Shop → Subscription
```

### Service Objects

All business logic lives in `app/services/`:

- `PdpScannerService` — Puppeteer-based headless browser scanning
- `DetectionService` — Analyzes scan results, creates/updates issues
- `AlertService` — Sends notifications when issues meet alert criteria
- `SubscriptionSyncService` — Syncs billing status with Shopify

### Background Jobs

Jobs use Solid Queue with three queues: `default`, `scans`, `mailers`.

- `ScheduledScanJob` — Daily scheduler (6am UTC), queues scans for all monitored PDPs
- `ScanPdpJob` — Scans a single product page (runs on `scans` queue)
- Retry: polynomial backoff, 3 attempts max

### Issue Detection

7 issue types in priority order:
1. `missing_add_to_cart` (high)
2. `variant_selector_error` (high)
3. `js_error` (high)
4. `liquid_error` (medium)
5. `missing_images` (medium)
6. `missing_price` (high)
7. `slow_page_load` (low)

Alerts only fire when: severity=high, status=open, occurrence_count >= 2 (reduces false positives).

### Controllers

All authenticated controllers inherit from `AuthenticatedController`, which includes `ShopifyApp::EnsureHasSession` and `ShopifyApp::EnsureBilling`. Key controllers:

- `HomeController` — Dashboard
- `ProductPagesController` — CRUD for monitored PDPs + rescan action
- `IssuesController` — View/acknowledge issues
- `ScansController` — Scan history
- `SettingsController` — Shop configuration
- `BillingController` — Pricing page

### Webhooks

Handled at `/webhooks/*`:
- `app_uninstalled` — Cleanup on app removal
- `app_subscription_update` — Track billing changes
- `shop_update` — Update shop metadata

## Conventions

### Code Style

- **Rubocop** with `rubocop-rails-omakase` (Rails Omakase style)
- `frozen_string_literal: true` at the top of every Ruby file
- snake_case for methods and variables
- Boolean methods end with `?` (e.g., `should_alert?`, `open?`, `high_severity?`)

### Naming

- `*Service` — Business logic classes
- `*Job` — Background job classes
- `*Controller` — Request handlers
- `*Mailer` — Email notification classes
- `Detect*` — Detection logic
- `Alert*` — Notification logic

### Testing

- Rails Test Unit (not RSpec)
- Fixtures in `test/fixtures/*.yml` (auto-loaded)
- Parallel test execution enabled
- Test database: `pdp_diagnostics_test`

### Database

- PostgreSQL everywhere (dev, test, production)
- Production uses separate databases for cache and queue
- JSON columns for arrays: `js_errors`, `network_errors`, `console_logs`
- String-based statuses: `pending`/`running`/`completed`/`failed` (scans), `open`/`acknowledged`/`resolved` (issues)

### Frontend

- Shopify Polaris Web Components (not React Polaris)
- ERB templates in `app/views/`
- Turbo for SPA-like navigation
- Stimulus for JavaScript behavior
- Importmap for JS module loading (no bundler)

## Important Constraints

- **Phase 1 only**: Do not build auto-fix, SEO tools, optimization features, or marketing features
- **Shopify scopes**: `read_products, read_themes` (read-only)
- **Scan limits**: 3-5 PDPs max per shop (MVP)
- **Scan timeout**: 30 seconds per page
- **Alert threshold**: 2 occurrences before alerting (avoid false positives)
- **Billing**: $10/month with 14-day free trial

## Environment Variables

Key variables (see `.env` or credentials):
- `SHOPIFY_API_KEY` / `SHOPIFY_API_SECRET` — Shopify app credentials
- `DATABASE_URL` — PostgreSQL connection (production)
- `RAILS_MASTER_KEY` — Credentials decryption key
- `HOST` — Application host URL

## Related Documentation

- `README.md` — Project overview and setup guide
- `PRD.md` — Product requirements document
- `ROADMAP.md` — Phased product roadmap
- `SECURITY.md` — Security policy and practices
- `agent.md` — AI agent behavioral instructions and product identity
