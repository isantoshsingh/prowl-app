# Prowl Roadmap

This roadmap prioritizes **reliability, trust, and calm execution** over speed or hype.

We ship in phases. We do not rush phases.

---

# Phase 1 — MVP (0–3 Months)

Goal: Detect broken PDPs & alert merchants reliably.

### Product
- Dashboard (PDP health overview)
- Issues list & detail view
- Manual scan
- Daily automatic scan
- 3–5 monitored product pages
- Severity scoring
- Screenshot capture
- Email + Shopify admin alerts
- Settings screen
- Polaris web components UI
- App Home Page per Shopify UX guidelines

### Engineering
- Rails Shopify app (single Heroku dyno)
- Solid Queue background jobs (in-process via Puma plugin, no Redis)
- puppeteer-ruby + Browserless.io cloud browser scanning
- Three-layer detection engine (programmatic → AI page analysis → per-issue AI)
- Google Gemini 2.5 Flash for visual confirmation and merchant explanations
- Purchase funnel testing (deep scans: variant → ATC → cart verify → cleanup)
- Cloudflare R2 screenshot storage
- Scan logs & audit trail

### Success Criteria
- 100 installs
- 20 paying stores
- <5% false positives
- Merchants trust alerts

### Monetization
- Paid-only app from launch
- $10/month with 14-day free trial
- No free plan in Phase 1
- Pricing increases in Phase 2 based on value tiers

---

# Phase 2 — Scale (3–12 Months)

Goal: Become the default store monitoring app.

### Product
- Real-time monitoring (10–30 min)
- Theme integrity monitoring
- ~~AI visual breakage detection~~ *(shipped in Phase 1)*
- ~~AI explanation engine~~ *(shipped in Phase 1)*
- Checkout flow detection (re-enable `checkout_broken` with proper detector)
- App conflict intelligence
- Revenue loss estimator
- Slack & WhatsApp alerts
- Agency dashboard
- Multi-store monitoring
- API & webhooks

### Engineering
- Scan worker sharding
- Queue prioritization
- ~~Vision AI pipeline~~ *(shipped in Phase 1 via Gemini Flash)*
- Diff engine for theme changes
- AI fix suggestions
- Screenshot comparison engine
- Checkout flow detector (programmatic)
- Performance optimizations

### Success Criteria
- 1,500+ installs
- 200+ paying stores
- 50+ agencies
- <8% churn

---

# Phase 3 — Category Leadership (12–24 Months)

Goal: Own the “Store Reliability” category.

### Product
- Auto-fix engine (opt-in)
- Full store monitoring
- Shopify Plus deep integrations
- White-labeled agency reports
- Multi-platform support
- Compliance & uptime monitoring
- Custom alerts & SLAs

### Business
- Enterprise pricing
- Agency partnerships
- Platform expansion

---

# Philosophy
We only scale what merchants trust.
