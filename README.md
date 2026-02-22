# Prowl — Shopify PDP Monitoring & Diagnostics

Prowl is a Shopify app that helps merchants **detect, monitor, and prevent revenue loss** caused by broken product pages (PDPs), app conflicts, theme changes, and hidden frontend issues.

Instead of guessing why conversions dropped, merchants get **clear alerts, diagnostics, and guidance** when something breaks — before revenue is lost.

---

## 🚀 Phase 1 (MVP) Features

### Automated PDP Scanning
- Daily scan of 3–5 product pages
- Headless browser (Puppeteer) checks for:
  - Add-to-cart functionality
  - Variant selector errors
  - Missing price or images
  - JS errors
  - Liquid errors
  - Page load performance

### Issue Detection Engine
- Rule-based detection for common breakages
- Severity scoring (High / Medium / Low)
- 2-scan confirmation to avoid false positives

### Alerts
- Email alerts for critical issues
- Shopify admin notifications
- Clear, human-readable explanations
- No spam: only alerts after issue persists across 2 scans

### Dashboard
- PDP health overview
- Issue list & detail view
- Scan history
- Manual rescan button
- Settings management

### Billing
- $10/month subscription
- 14-day free trial
- Shopify Billing API integration

---

## 🏗 Tech Stack

### Backend
- Ruby on Rails 8.1
- shopify_app gem 23.0+
- PostgreSQL
- Solid Queue (background jobs)
- Puppeteer Ruby gem

### Frontend
- Shopify Polaris Web Components
- App Bridge
- ERB templates

### Scanning
- Headless Chromium
- Screenshot capture
- JS / network error logging

---

## 📦 Getting Started

### Prerequisites
- Ruby 3.3+
- PostgreSQL
- Node.js (for Puppeteer/Chrome)
- Shopify Partner account

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd PDP-Diagnostics
```

2. Install dependencies:
```bash
bundle install
```

3. Setup environment:
```bash
cp .env.sample .env
# Edit .env with your Shopify credentials
```

4. Create database:
```bash
bin/rails db:create db:migrate
```

5. Start the server:
```bash
bin/rails server
```

6. Start Solid Queue worker (in another terminal):
```bash
bin/rails solid_queue:start
```

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `SHOPIFY_API_KEY` | Your Shopify app API key | Yes |
| `SHOPIFY_API_SECRET` | Your Shopify app API secret | Yes |
| `HOST` | Your app's public URL (e.g., ngrok) | Yes |
| `SHOPIFY_TEST_CHARGES` | Set to "true" for test billing | No |

---

## 📁 Project Structure

```
app/
├── controllers/     # Request handling
│   ├── home_controller.rb          # Dashboard
│   ├── product_pages_controller.rb # Monitored pages
│   ├── issues_controller.rb        # Issue management
│   ├── settings_controller.rb      # Configuration
│   ├── billing_controller.rb       # Subscription flow
│   └── scans_controller.rb         # Scan history
├── models/          # Data models
│   ├── shop.rb           # Merchant store
│   ├── product_page.rb   # Monitored PDP
│   ├── scan.rb           # Scan record
│   ├── issue.rb          # Detected problem
│   ├── alert.rb          # Notification record
│   └── shop_setting.rb   # Configuration
├── services/        # Business logic
│   ├── pdp_scanner_service.rb  # Puppeteer scanning
│   ├── detection_service.rb    # Issue detection
│   ├── alert_service.rb        # Notifications
│   └── billing_service.rb      # Subscription management
├── jobs/            # Background jobs
│   ├── scan_pdp_job.rb       # Single page scan
│   └── scheduled_scan_job.rb # Daily scheduler
├── mailers/         # Email notifications
│   └── alert_mailer.rb
└── views/           # UI templates (Polaris)
```

---

## 🧪 Running Tests

```bash
bin/rails test
```

---

## 🔧 Configuration

### Solid Queue

Background jobs are processed by Solid Queue. Configuration is in `config/solid_queue.yml`.

Queues:
- `default` - Standard priority
- `scans` - PDP scanning (resource-intensive)
- `mailers` - Email delivery

### Recurring Jobs

Daily scans are scheduled via `config/recurring.yml`:
- `scheduled_scan` runs at 6am UTC

---

## 📊 Models

### Shop
The merchant store. Created during OAuth install.
- Has many product_pages
- Has one shop_setting
- Tracks billing status via shop_setting

### ProductPage
A product page being monitored.
- Belongs to shop
- Has many scans and issues
- Status: pending, healthy, warning, critical, error

### Scan
A single PDP scan run.
- Captures screenshot, HTML, JS errors, network errors
- Status: pending, running, completed, failed

### Issue
A detected problem.
- Linked to product_page and scan
- Types: missing_add_to_cart, js_error, liquid_error, etc.
- Severity: high, medium, low
- Only alerts after 2+ occurrences

### Alert
A notification sent to the merchant.
- Types: email, admin
- Tracks delivery status

### ShopSetting
Configuration for each shop.
- Alert preferences
- Scan frequency
- Billing status

---

## 🧭 Philosophy

Prowl is built with one principle:
> **Calm growth beats chaotic growth**

We value:
- Clarity over features
- Trust over hype
- Guidance over automation
- Long-term reliability over shortcuts

---

## 🔒 Security

See [SECURITY.md](SECURITY.md) for security policy.

Key points:
- Minimal scopes (read_products only)
- No customer PII access
- Scans run as public visitor
- Screenshots stored with signed URLs
- All data encrypted at rest

---

## 📄 License

Private / Proprietary
