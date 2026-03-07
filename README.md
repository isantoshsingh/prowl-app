# Prowl — Shopify PDP Monitoring & Diagnostics

Prowl is a Shopify app that helps merchants **detect, monitor, and prevent revenue loss** caused by broken product pages (PDPs), app conflicts, theme changes, and hidden frontend issues.

Instead of guessing why conversions dropped, merchants get **clear alerts, diagnostics, and guidance** when something breaks — before revenue is lost.

---

## 🚀 Phase 1 (MVP) Features

### Automated PDP Scanning
- Daily scan of up to 3 monitored product pages
- Headless browser (Puppeteer via Browserless.io in production) checks for:
  - Add-to-cart functionality (3-layer: structural DOM → funnel test → AI visual)
  - Variant selector errors
  - Missing price or images
  - JS errors (with Shopify platform noise filtering)
  - Liquid errors
  - Page load performance
- Deep scans run a full purchase funnel test (variant selection → ATC click → cart verification via `/cart.js` → cleanup)

### Issue Detection Engine
- Three-layer detection: programmatic detectors → AI page analysis (Gemini Flash) → per-issue AI confirmation
- Severity scoring (High / Medium / Low)
- AI-confirmed issues alert immediately; others require 2-scan confirmation
- Related issue deduplication prevents AI from creating escalated duplicates

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
- Solid Queue (background jobs, in-process via Puma plugin — no Redis)
- puppeteer-ruby gem (~0.45)

### Frontend
- Shopify Polaris Web Components
- Shopify App Bridge
- ERB templates + Hotwire (Turbo + Stimulus)

### Scanning & AI
- Browserless.io (cloud headless browser in production)
- Google Gemini 2.5 Flash (AI issue analysis and visual confirmation)
- Screenshot storage via Cloudflare R2
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

6. Solid Queue runs in-process via Puma plugin in production. For development, start it in another terminal:
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
| `BROWSERLESS_URL` | Browserless.io WebSocket URL (production) | Prod |
| `GEMINI_API_KEY` | Google Gemini API key for AI analysis | Prod |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | Cloudflare R2 access key | Prod |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | Cloudflare R2 secret key | Prod |
| `CLOUDFLARE_R2_BUCKET` | R2 bucket name (e.g., prowl-screenshots) | Prod |
| `CLOUDFLARE_R2_ENDPOINT` | R2 endpoint URL | Prod |
| `RESEND_API_KEY` | Resend API key for production email | Prod |

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
│   ├── product_page_scanner.rb       # Top-level scan orchestrator
│   ├── scan_pipeline_service.rb      # 5-step post-scan pipeline
│   ├── browser_service.rb            # Puppeteer lifecycle (Browserless in prod)
│   ├── detection_service.rb          # Processes detector results into Issues
│   ├── ai_issue_analyzer.rb          # Gemini Flash AI analysis
│   ├── alert_service.rb              # Email/admin notifications
│   ├── screenshot_uploader.rb        # Cloudflare R2 screenshot storage
│   └── subscription_sync_service.rb  # Billing state sync
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
- Tracks billing status via subscription fields

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
- Types: missing_add_to_cart, atc_not_functional, js_error, liquid_error, missing_price, missing_images, variant_selection_broken
- Severity: high, medium, low
- AI-confirmed issues alert immediately; others alert after 2+ occurrences
- Includes AI analysis: explanation, suggested fix, confidence score

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
