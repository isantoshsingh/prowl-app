# Silent Profit — Shopify PDP Monitoring & Diagnostics

Silent Profit is a Shopify app that helps merchants **detect, monitor, and prevent revenue loss** caused by broken product pages (PDPs), app conflicts, theme changes, and hidden frontend issues.

Instead of guessing why conversions dropped, merchants get **clear alerts, diagnostics, and guidance** when something breaks — before revenue is lost.

---

## 🚀 Problem

Shopify stores break silently all the time due to:
- App conflicts
- Theme updates
- Script injections
- Liquid errors
- JavaScript overrides
- CSS layout shifts

Merchants usually notice **after revenue drops**.

There is no reliable tool that:
- Monitors PDP health
- Detects breakage automatically
- Explains the root cause
- Alerts immediately

Silent Profit fixes that.

---

## 💡 Solution

Silent Profit acts like **monitoring + diagnostics + alerting** for Shopify stores.

Think:
> Datadog + Snyk + PagerDuty for Shopify product pages

---

## ✨ Core Features (Phase 1 - MVP)

### 🔍 Automated PDP Scanning
- Daily scan of 3–5 product pages
- Headless browser checks for:
  - Add-to-cart functionality
  - Variant selector errors
  - Missing price or images
  - JS errors
  - Liquid errors
  - Performance red flags

---

## 💰 Pricing (Phase 1)

Silent Profit is a paid app to ensure we serve serious merchants and maintain reliability.

- $10/month
- 14-day free trial
- No free plan
- Cancel anytime

Why paid from day one?
- Reduces noise
- Improves alert quality
- Ensures sustainability
- Aligns with merchant ROI

If Silent Profit saves even one sale, it pays for itself.

---

### 🧠 Issue Detection Engine
- Rule-based detection for common breakages
- Severity scoring (High / Medium / Low)
- Change detection (today vs yesterday)

---

### 📸 Visual Snapshot
- Screenshot captured for each scan
- (Optional) AI visual inspection for UI breakage

---

### 🚨 Alerts
- Email alerts for critical issues
- Shopify admin notifications
- Clear, human-readable explanations

---

### 📊 Simple Dashboard
- PDP health overview
- Issue list & detail view
- 7-day trend
- Manual rescan button

---

## 🏗 Tech Stack

### Backend
- Ruby on Rails 8.1
- Shopify_app gem
- PostgreSQL
- Solid Queue (background jobs)
- Puppeteer Ruby gem

### Scanning
- Headless Chromium
- Screenshot capture
- JS / network error logging

### Frontend
- Shopify Polaris
- App Bridge (https://shopify.dev/docs/api/app-bridge)
- ERB (Polaris web components)

### AI (Optional in MVP)
- Vision model for UI detection
- Text model for explanation & guidance

---

## 📦 Project Structure (Suggested)

```

/app
/models
/controllers
/views
/services
/jobs
/policies
/lib
/scanners
/detectors
/alerts
/ai
/docs
README.md
agent.md

```

---

## 📈 Roadmap

### Phase 1 (MVP)
- PDP scanning
- Alerts
- Dashboard
- Manual rescan
- 3–5 monitored pages

### Phase 2 (Scale)
- Real-time monitoring
- AI auto-fix suggestions
- Theme integrity monitoring
- Agency dashboard
- Revenue impact estimation
- Uptime monitoring

### Phase 3 (Dominance)
- Auto-fix engine
- Multi-platform (Woo, BigCommerce)
- Shopify Plus deep integrations
- Enterprise reliability platform

---

## 🎯 Success Metrics (MVP)
- 100 installs
- 20 paid merchants
- <5% false positives
- Merchants report saved revenue

---

## 🧭 Philosophy

Silent Profit is built with one principle:
> **Calm growth beats chaotic growth**

We value:
- Clarity over features
- Trust over hype
- Guidance over automation
- Long-term reliability over shortcuts

---

## 🤝 Contributing
This project is currently in private build mode.
Architecture, scope, and principles are intentionally strict to avoid bloat.

---

## 📄 License
Private / Proprietary