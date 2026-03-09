# Prowl — Progress

Current status of Prowl against the Phase 1 MVP roadmap.

---

## Table of Contents

- [Phase 1 — MVP Status](#phase-1--mvp-status)
  - [Product Features](#product-features)
  - [Engineering](#engineering)
  - [Monetization](#monetization)
- [Detection Engine](#detection-engine)
  - [Programmatic Detectors](#programmatic-detectors)
  - [AI Layer](#ai-layer)
  - [Alerting](#alerting)
- [Documentation](#documentation)
- [Known Limitations](#known-limitations)
- [What's Next (Phase 2)](#whats-next-phase-2)

---

## Phase 1 — MVP Status

### Product Features

| Feature | Status | Notes |
|---------|--------|-------|
| Dashboard (PDP health overview) | Done | Health summary, open issues, scan history, 7-day trend chart |
| Issues list & detail view | Done | Filter by status/severity, AI-generated explanations, suggested fixes |
| Manual scan | Done | Per-page rescan from page card or detail view |
| Daily automatic scan | Done | Scheduled via Solid Queue, runs at 6:00 AM UTC |
| 3 monitored product pages | Done | Configurable limit (default 3), soft-delete with restore |
| Severity scoring | Done | HIGH / MEDIUM / LOW with confidence thresholds |
| Screenshot capture | Done | Stored on Cloudflare R2, served via private controller |
| Email + Shopify admin alerts | Done | Batched emails via Resend, signed email action links |
| Settings screen | Done | Alert preferences, scan frequency, custom alert email |
| Polaris web components UI | Done | Shopify App Bridge + Polaris, ERB with Hotwire (Turbo + Stimulus) |
| Onboarding guide | Done | 3-step dismissible guide on dashboard |

### Engineering

| Component | Status | Notes |
|-----------|--------|-------|
| Rails Shopify app (single Heroku dyno) | Done | Rails 8.1 + PostgreSQL |
| Solid Queue background jobs | Done | In-process via Puma plugin, no Redis required |
| puppeteer-ruby + Browserless.io | Done | WebSocket connection in production, local Chrome in dev |
| Three-layer detection engine | Done | Programmatic → AI page analysis → per-issue AI confirmation |
| Google Gemini 2.5 Flash integration | Done | Visual confirmation and plain-language merchant explanations |
| Purchase funnel testing (deep scans) | Done | Variant → ATC → cart verify → cleanup |
| Cloudflare R2 screenshot storage | Done | S3-compatible, zero egress fees, local fallback in dev |
| Scan logs & audit trail | Done | Scan records with detector results, HTML, errors, screenshots |

### Monetization

| Item | Status | Notes |
|------|--------|-------|
| Paid-only from launch | Done | Shopify Billing API integration |
| $10/month with 14-day trial | Done | Trial tracking via Subscription model |
| Billing redirect fix | Done | Charge callback sync, reinstall status reset |

---

## Detection Engine

### Programmatic Detectors

| Detector | Checks | Confidence Range |
|----------|--------|-----------------|
| **AddToCartDetector** | Button existence, visibility, enabled state, funnel test (variant → ATC → cart verify) | 0.0–1.0, 3-layer validation |
| **PriceVisibilityDetector** | Price element existence, visibility, currency format, non-placeholder | 16 selector strategies |
| **ProductImageDetector** | Image existence, loaded state, visibility, minimum 200x200px, not placeholder | 14 selector strategies with lazy-load handling |
| **JavascriptErrorDetector** | Critical JS errors (cart/checkout/variant/payment), filters third-party noise | 0.85 critical, 0.95 critical+syntax |
| **LiquidErrorDetector** | Liquid error patterns in HTML, visible vs. hidden errors | 0.85 hidden high-severity, 0.95 visible |

Global confidence threshold: **0.7** — detections below this are discarded.

### AI Layer

- **Page-level analysis**: Screenshot + all detector results sent to Gemini Flash for independent issue discovery and confirmation.
- **Per-issue analysis**: High-severity issues get screenshot-based confirmation; lower-severity get text-only analysis.
- **AI-confirmed issues**: Skip the 2-occurrence wait and alert immediately.
- **`checkout_broken` disabled**: Removed from AI prompt in Phase 1 due to false positives. Scheduled for Phase 2 with a proper programmatic detector.

### Alerting

- Only HIGH severity issues trigger alerts.
- Non-AI-confirmed issues require 2+ scan occurrences.
- AI-confirmed issues alert immediately.
- Acknowledged issues are suppressed.
- All issues from a scan are batched into one email.
- Signed email links allow acknowledge without login (30-day expiry).
- Failed email delivery does not block scan completion.

---

## Documentation

| Document | Path | Description |
|----------|------|-------------|
| README | `README.md` | Setup, features, tech stack |
| PRD | `PRD.md` | Product requirements, user flows, success metrics |
| Security | `SECURITY.md` | Security policy, minimal scopes, PII handling |
| Roadmap | `ROADMAP.md` | Phase 1–3 feature plan |
| Changelog | `CHANGELOG.md` | All notable changes |
| Merchant Guide | `docs/merchant-guide.md` | Onboarding, detectors, issues, settings |
| Troubleshooting | `docs/troubleshooting.md` | Support reference, fixes, FAQ |

---

## Known Limitations

- **3-page monitoring limit** — MVP constraint; will increase in Phase 2.
- **No checkout flow detector** — `checkout_broken` issue type is disabled; AI was over-escalating without a programmatic detector to back it up.
- **No real-time monitoring** — Scans run daily or weekly on a schedule. Near-real-time (10–30 min) is planned for Phase 2.
- **No Slack/WhatsApp alerts** — Email and Shopify admin only in Phase 1.
- **No multi-store or agency support** — Single-store monitoring only.
- **Password-protected stores** — Prowl scans as a public visitor; password-protected stores cannot be scanned.

---

## What's Next (Phase 2)

Priority items from the roadmap:

1. **Checkout flow detector** — Programmatic detector to re-enable `checkout_broken` with confidence scoring.
2. **Real-time monitoring** — Reduce scan intervals to 10–30 minutes.
3. **Slack & WhatsApp alerts** — Additional notification channels.
4. **Theme integrity monitoring** — Detect theme changes that break pages.
5. **App conflict intelligence** — Identify which installed apps cause issues.
6. **Revenue loss estimator** — Quantify the business impact of detected issues.
7. **Agency dashboard & multi-store** — Support agencies managing multiple stores.

See `ROADMAP.md` for the full Phase 2 and Phase 3 plans.
