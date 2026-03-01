# Implementation Plan: Screenshot Storage, AI Confirmation & Explanations, Alert Emails & Infrastructure

## Overview

This plan adds four capabilities and optimizes Prowl's infrastructure:

1. **Cloud screenshot storage** — Upload scan screenshots to Cloudflare R2, store public URL in `scans.screenshot_url`
2. **AI issue confirmation** — Use Gemini 2.0 Flash to visually verify high-severity issues
3. **AI merchant explanations** — Generate plain-language issue explanations and suggested fixes for ALL issues
4. **Screenshot in alert emails** — Include scan screenshots in critical issue alert emails via Resend
5. **Infrastructure optimization** — Switch to Browserless cloud browser, eliminate worker dyno, cut costs from ~$20/mo to ~$12/mo

---

## Infrastructure Decisions (Finalized)

| Component | Choice | Cost | Rationale |
|-----------|--------|:---:|-----------|
| Database | **Heroku Postgres Essential-0** | $5/mo | Simplest. Already on Heroku. No migration. |
| Hosting | **Heroku — single Basic dyno** | $7/mo | Web + Solid Queue in-process. Drop worker dyno. |
| Browser for scans | **Browserless.io** | $0 | 6 hrs/mo free (~400-700 scans). Fixes R14 memory error. |
| Screenshot storage | **Cloudflare R2** | $0 | Direct upload via `aws-sdk-s3`. Zero egress fees. 10GB free. |
| AI (confirmation + explanations) | **Gemini 2.0 Flash** | $0 | Free tier: 15 RPM, ~1500 req/day. |
| Email delivery | **Resend** | $0 | Free tier: 100 emails/day. SMTP integration. |
| **Total** | | **$12/mo** | Down from ~$20/mo (was ~$57/mo with AWS RDS) |

### Why these choices

**Browserless over Browserbase/Steel:**
- Best puppeteer-ruby compatibility — one-line change: `Puppeteer.connect(browser_url: ENV["BROWSERLESS_URL"])`
- Most generous free tier (6 hours/month vs 100 sessions/month)
- Self-hostable escape hatch (open-source Docker image) if costs grow later
- Mature (since 2018), battle-tested, extensive docs

**Cloudflare R2 over S3/Supabase Storage:**
- Zero egress fees forever (AI reads + email embeds = downloads = free)
- S3-compatible (uses same `aws-sdk-s3` gem)
- 10GB free storage, 1M writes/month free

**Direct R2 upload over Active Storage:**
- No extra tables (`active_storage_blobs`, `active_storage_attachments`)
- No additional migrations for storage
- Uses the existing `scans.screenshot_url` column — just stores the R2 public URL
- Simpler mental model: upload file, get URL, store URL

**Single dyno (no worker) over two dynos:**
- With Browserless, the worker no longer runs Chrome locally
- Worker jobs become lightweight HTTP/WebSocket calls (~10MB, not ~350MB)
- Solid Queue can run in-process (threaded) alongside Puma in the same dyno
- Saves $7/mo (one fewer Basic dyno)

---

## Architecture

```
Merchant's Product Page (public storefront)
         │
         ▼
┌─ Heroku Basic Dyno ($7/mo) ─────────────────────────┐
│                                                       │
│  Puma (web server)                                    │
│  Solid Queue (in-process, threaded)                   │
│     ├─ ScheduledScanJob (daily cron)                  │
│     └─ ScanPdpJob (per product page)                  │
│            │                                          │
│            ├─ Connect to Browserless ──────────────┐  │
│            │   (WebSocket, remote Chrome)           │  │
│            │                                        │  │
│            ├─ Upload screenshot to R2 ────────────┐│  │
│            │   (aws-sdk-s3, direct PUT)            ││  │
│            │                                       ││  │
│            ├─ Run detectors (existing)             ││  │
│            │                                       ││  │
│            ├─ For ALL issues:                      ││  │
│            │   └─ AiIssueAnalyzer ───────────────┐│││
│            │       High severity: screenshot+ctx  ││││
│            │       → confirmation + explanation   ││││
│            │       Med/Low: context only           ││││
│            │       → explanation + suggested fix   ││││
│            │                                     ││││
│            └─ AlertService                       ││││
│                └─ AlertMailer (Resend SMTP)       ││││
│                    └─ Screenshot + AI explanation ││││
│                                                   ││││
└───────────────────────────────────────────────────┘│││
                                                     │││
         ┌───────────────────────────────────────────┘││
         ▼                                            ││
┌─ Browserless.io (free tier) ─┐                      ││
│  Remote Chrome instance       │                      ││
│  Returns: screenshot bytes,   │                      ││
│  HTML, JS errors, network     │                      ││
│  errors, console logs         │                      ││
└───────────────────────────────┘                      ││
                                                       ││
         ┌─────────────────────────────────────────────┘│
         ▼                                              │
┌─ Cloudflare R2 (free tier) ──┐                        │
│  prowl-screenshots bucket     │                        │
│  Public URL for each image    │                        │
│  Zero egress fees             │                        │
└───────────────────────────────┘                        │
                                                         │
         ┌───────────────────────────────────────────────┘
         ▼
┌─ Google Gemini Flash (free tier) ────────────────────┐
│                                                       │
│  High-severity issues (with screenshot):              │
│  Input:  screenshot + issue type + evidence           │
│  Output: confirmation + explanation + suggested fix   │
│                                                       │
│  Medium/Low issues (text only):                       │
│  Input:  issue type + evidence                        │
│  Output: explanation + suggested fix                  │
│                                                       │
└───────────────────────────────────────────────────────┘
```

---

## Step-by-Step Implementation

### Step 1: Set Up Cloudflare R2 Screenshot Upload

**Goal:** Replace the current `tmp/screenshots/` local storage with R2 cloud storage. Store the public URL in the existing `scans.screenshot_url` column.

**Gem to add:**
```ruby
# Gemfile
gem "aws-sdk-s3", "~> 1.0"  # R2 is S3-compatible
```

**New service — `app/services/screenshot_uploader.rb`:**
- Initializes an `Aws::S3::Client` with R2 credentials
- `upload(screenshot_data, scan_id)` → PUTs the PNG to R2, returns public URL
- `download(url)` → GETs the image bytes from R2 (for email inline attachment and AI analysis)
- Falls back gracefully if R2 credentials are not configured (dev environment)

**Key design:**
```
R2 bucket structure:
  prowl-screenshots/
    scans/{scan_id}/screenshot.png

Public URL format:
  https://screenshots.getprowl.app/scans/123/screenshot.png
  (via R2 custom domain or r2.dev subdomain)
```

**Files to modify:**
- `Gemfile` — add `aws-sdk-s3`
- `app/services/screenshot_uploader.rb` — new file
- `app/services/product_page_scanner.rb` — replace `store_screenshot` method to use `ScreenshotUploader` instead of writing to `tmp/`

**No migration needed** — `scans.screenshot_url` column already exists.

**Environment variables:**
```
CLOUDFLARE_R2_ACCESS_KEY_ID=
CLOUDFLARE_R2_SECRET_ACCESS_KEY=
CLOUDFLARE_R2_BUCKET=prowl-screenshots
CLOUDFLARE_R2_ENDPOINT=https://<account_id>.r2.cloudflarestorage.com
CLOUDFLARE_R2_PUBLIC_URL=https://screenshots.getprowl.app
```

---

### Step 2: Switch BrowserService to Browserless (Cloud Browser)

**Goal:** Stop launching Chrome locally. Connect to Browserless via WebSocket instead. Fixes R14 memory error and enables single-dyno deployment.

**Core change in `app/services/browser_service.rb`:**
```ruby
# Before (local Chrome — ~350MB RAM):
@browser = Puppeteer.launch(
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage", ...]
)

# After (remote Chrome — ~0MB RAM):
@browser = Puppeteer.connect(
  browser_url: ENV["BROWSERLESS_URL"]
)
```

**What stays the same:** Everything else in BrowserService — `navigate_to`, `take_screenshot`, `page_content`, `js_errors`, `network_errors`, `console_logs`, `page_load_time_ms`, and all detectors. The Puppeteer API is identical whether local or remote.

**Fallback for development:** If `BROWSERLESS_URL` is not set, fall back to local Chrome launch (for `shopify app dev` workflow where Browserless isn't needed and local Chrome is fine).

```ruby
def start
  if ENV["BROWSERLESS_URL"].present?
    @browser = Puppeteer.connect(browser_url: ENV["BROWSERLESS_URL"])
  else
    @browser = Puppeteer.launch(headless: true, args: chrome_args)
  end
end
```

**Files to modify:**
- `app/services/browser_service.rb` — add Browserless connection mode

**Environment variables:**
```
BROWSERLESS_URL=wss://chrome.browserless.io?token=YOUR_TOKEN
```

---

### Step 3: Eliminate Worker Dyno (Solid Queue In-Process)

**Goal:** Run Solid Queue inside the Puma web process instead of a separate worker dyno. The worker is now lightweight (no local Chrome) so this is safe.

**How Solid Queue in-process works:**
- Solid Queue ships with a Puma plugin (`solid_queue/puma/plugin`)
- Add one line to `config/puma.rb`: `plugin :solid_queue`
- Puma spawns the Solid Queue supervisor as a background thread
- Jobs run in the same process, sharing the dyno's memory

**Files to modify:**
- `config/puma.rb` — add `plugin :solid_queue`
- `Procfile` — remove the `worker:` line (keep only `web:`)

**Current Procfile (expected):**
```
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake solid_queue:start
```

**New Procfile:**
```
web: bundle exec puma -C config/puma.rb
```

**Memory budget with in-process Solid Queue:**
```
Puma (4 threads)          ~150MB
Solid Queue supervisor     ~30MB
Job execution (HTTP calls) ~20MB
─────────────────────────────────
Total:                    ~200MB of 512MB ✅
```

**Risk mitigation:** If a single scan job takes too long or too much memory, it could affect web requests. Mitigations:
- Browserless handles the heavy lifting (Chrome runs remotely)
- Scan jobs are now just HTTP calls + DB writes — lightweight
- Solid Queue respects concurrency limits (`limits_concurrency to: 1`)
- Jobs already have a 45-second timeout

---

### Step 4: AI Issue Analyzer Service (Gemini Flash)

**Goal:** Analyze detected issues with AI. For high-severity issues: confirm the issue visually using the screenshot AND generate a merchant-friendly explanation. For medium/low issues: generate an explanation and suggested fix using issue context only.

**New service — `app/services/ai_issue_analyzer.rb`:**

This replaces the previously planned `ai_issue_confirmer.rb` with a broader service that handles both confirmation and explanation.

**Input:**
- `scan` — the completed Scan record (has `screenshot_url` pointing to R2)
- `issue` — the Issue record with type, severity, description, evidence
- `product_page` — the ProductPage record (for product title and context)

**Two modes of operation:**

#### Mode 1: High-severity issues (with screenshot)

**Input to Gemini:** Screenshot image (base64) + issue context text
**Output from Gemini:**
```json
{
  "confirmed": true,
  "confidence": 0.92,
  "reasoning": "The Add to Cart button is not visible in the main product area",
  "merchant_explanation": "Your product page for 'Blue Denim Jacket' appears to have a problem with the Add to Cart button — it's either missing or hidden from view. This means customers visiting this page cannot add the product to their cart, which is likely causing lost sales.",
  "suggested_fix": "This is often caused by a recent theme update or a conflict with an installed app. Try these steps:\n1. Preview your theme and check if the button appears\n2. If you recently updated your theme, try reverting to the previous version\n3. Temporarily disable recently installed apps to check for conflicts\n4. Contact your theme developer if the issue persists"
}
```

**Prompt for high-severity:**
```
You are a Shopify store advisor who helps non-technical merchants understand issues with their product pages. Analyze this screenshot of a product page.

Product: {product_title}
Store: {shop_domain}

A scan detected the following issue:
- Issue type: {issue_type}
- Title: {title}
- Evidence: {evidence_json}

Please provide:

1. CONFIRMATION: Is this issue visible in the screenshot? (true/false)
2. CONFIDENCE: How confident are you? (0.0 to 1.0)
3. REASONING: Brief technical reasoning (1-2 sentences)
4. MERCHANT EXPLANATION: Explain this issue in simple, non-technical language that a store owner would understand. Be specific about what this means for their customers and sales. 2-3 sentences max.
5. SUGGESTED FIX: Provide actionable steps the merchant can take to fix this. Use numbered steps. Keep it simple — assume the merchant is not a developer.

Respond in JSON format only:
{
  "confirmed": true/false,
  "confidence": 0.0-1.0,
  "reasoning": "...",
  "merchant_explanation": "...",
  "suggested_fix": "..."
}
```

#### Mode 2: Medium/Low-severity issues (text only, no screenshot)

**Input to Gemini:** Issue context text only (no image = cheaper, faster)
**Output from Gemini:**
```json
{
  "merchant_explanation": "Some images on your 'Blue Denim Jacket' product page are taking longer than usual to load. While the page still works, slow-loading images can frustrate customers and may cause some to leave before seeing your product.",
  "suggested_fix": "1. Check that your product images are optimized (under 500KB each)\n2. Use Shopify's built-in image editor to compress large images\n3. Remove any unused images from the product listing"
}
```

**Prompt for medium/low:**
```
You are a Shopify store advisor who helps non-technical merchants understand issues with their product pages.

Product: {product_title}
Store: {shop_domain}

A scan detected the following issue:
- Issue type: {issue_type}
- Severity: {severity}
- Title: {title}
- Evidence: {evidence_json}

Please provide:

1. MERCHANT EXPLANATION: Explain this issue in simple, non-technical language that a store owner would understand. Be specific about what this means for their customers and sales. 2-3 sentences max.
2. SUGGESTED FIX: Provide actionable steps the merchant can take to fix this. Use numbered steps. Keep it simple — assume the merchant is not a developer.

Respond in JSON format only:
{
  "merchant_explanation": "...",
  "suggested_fix": "..."
}
```

**Key design decisions:**

- **Fail-open:** If Gemini API fails, is not configured, or returns an error → fall back to existing hardcoded descriptions. Never block the scan flow.
- **Runs for ALL issues:** Both modes are cheap. High-severity gets screenshot analysis + explanation. Medium/low gets text-only explanation.
- **Phase 1 (confirmation is informational):** AI confirmation is stored but does NOT gate alerting. This lets us observe accuracy before relying on it.
- **Phase 2 (future):** Once AI accuracy is validated, add `ai_confirmed != false` to `Issue#should_alert?` to reduce false positive alerts.
- **No gem dependency:** Uses `httparty` (already in Gemfile) to call Gemini REST API directly.
- **Tone:** Prompts instruct AI to be calm, specific, and actionable — matching Prowl's existing UX principle of being non-alarming.

**API call format:**
```
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=API_KEY

# High-severity (with image):
Body: { contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: "image/png", data: base64 } }] }] }

# Medium/Low (text only):
Body: { contents: [{ parts: [{ text: prompt }] }] }
```

**Environment variables:**
```
GEMINI_API_KEY=
```

---

### Step 5: Add AI Columns to Issues Table

**Goal:** Store AI analysis results on the Issue record.

**Migration:**
```ruby
class AddAiAnalysisToIssues < ActiveRecord::Migration[8.1]
  def change
    # AI confirmation (high-severity only)
    add_column :issues, :ai_confirmed, :boolean
    add_column :issues, :ai_confidence, :float
    add_column :issues, :ai_reasoning, :text

    # AI merchant-facing content (all severities)
    add_column :issues, :ai_explanation, :text
    add_column :issues, :ai_suggested_fix, :text

    # Metadata
    add_column :issues, :ai_verified_at, :datetime
  end
end
```

**Column usage:**

| Column | High-severity | Medium/Low | Purpose |
|--------|:---:|:---:|---------|
| `ai_confirmed` | ✅ | — | Did AI visually confirm the issue in the screenshot? |
| `ai_confidence` | ✅ | — | AI's confidence in the confirmation (0.0-1.0) |
| `ai_reasoning` | ✅ | — | Brief technical reasoning (internal, for debugging) |
| `ai_explanation` | ✅ | ✅ | Plain-language explanation shown to merchant |
| `ai_suggested_fix` | ✅ | ✅ | Actionable fix steps shown to merchant |
| `ai_verified_at` | ✅ | ✅ | When the AI analysis was performed |

**Files to modify:**
- New migration file
- `app/models/issue.rb` — no code changes needed (columns are accessed via standard ActiveRecord)

---

### Step 6: Integrate AI Analysis into Scan Flow

**Goal:** After detection creates/updates issues, run AI analysis for all issues.

**File to modify:** `app/jobs/scan_pdp_job.rb`

**Current flow (lines 59-67):**
```ruby
issues.each do |issue|
  if issue.should_alert?
    AlertService.new(issue).perform
  end
end
```

**New flow:**
```ruby
issues.each do |issue|
  # AI analysis for all issues
  begin
    ai_result = AiIssueAnalyzer.new(
      scan: result[:scan],
      issue: issue,
      product_page: product_page
    ).perform

    update_attrs = {
      ai_explanation: ai_result[:merchant_explanation],
      ai_suggested_fix: ai_result[:suggested_fix],
      ai_verified_at: Time.current
    }

    # High-severity issues also get confirmation data
    if issue.high_severity? && ai_result.key?(:confirmed)
      update_attrs.merge!(
        ai_confirmed: ai_result[:confirmed],
        ai_confidence: ai_result[:confidence],
        ai_reasoning: ai_result[:reasoning]
      )
    end

    issue.update!(update_attrs)
  rescue StandardError => e
    Rails.logger.error("[ScanPdpJob] AI analysis failed for issue #{issue.id}: #{e.message}")
    # Fail-open: continue with hardcoded descriptions
  end

  # Alert logic unchanged — AI does NOT gate alerts in Phase 1
  if issue.should_alert?
    AlertService.new(issue).perform
  end
end
```

**Display logic for issue descriptions (used in views and emails):**

Add a helper method to `Issue` model:
```ruby
# app/models/issue.rb

# Returns the best available explanation for the merchant
def merchant_explanation
  ai_explanation.presence || Issue::ISSUE_TYPES.dig(issue_type, :description) || description
end

# Returns the suggested fix if available
def merchant_suggested_fix
  ai_suggested_fix
end
```

Views and email templates should use `issue.merchant_explanation` instead of `issue.description`. If AI analysis hasn't run or failed, it falls back to the existing hardcoded description seamlessly.

---

### Step 7: Add Screenshot and AI Explanation to Alert Emails

**Goal:** When a critical issue email is sent, include: (1) the scan screenshot, (2) the AI-generated explanation, and (3) the AI-suggested fix.

**Approach:** Download screenshot from R2 (zero egress cost) and attach inline. Use AI explanation in the email body. Fall back to hardcoded text if AI hasn't run.

**Files to modify:**

**`app/mailers/alert_mailer.rb` — attach screenshot inline:**
```ruby
def issue_detected(shop, issue)
  @shop = shop
  @issue = issue
  @product_page = issue.product_page
  @scan = issue.scan
  @app_url = "#{ENV.fetch('HOST', 'https://localhost:3000')}/issues/#{issue.id}"

  # Attach screenshot inline if available
  @has_screenshot = false
  if @scan&.screenshot_url.present?
    begin
      screenshot_data = ScreenshotUploader.new.download(@scan.screenshot_url)
      attachments.inline["screenshot.png"] = screenshot_data
      @has_screenshot = true
    rescue StandardError => e
      Rails.logger.warn("[AlertMailer] Failed to attach screenshot: #{e.message}")
    end
  end

  mail(
    to: shop.shop_setting&.effective_alert_email || shop.shopify_domain,
    subject: "Prowl: Issue detected on #{@product_page.title}"
  )
end
```

**`app/views/alert_mailer/issue_detected.html.erb` — updated template:**

```erb
<h1 style="font-size: 24px; color: #202223; margin-bottom: 16px;">
  We noticed something on your product page
</h1>

<p style="margin-bottom: 16px;">
  Hi there,
</p>

<p style="margin-bottom: 16px;">
  Prowl detected a potential issue on <strong><%= @product_page.title %></strong> that may affect your customers' ability to purchase.
</p>

<%# Issue description — AI-generated or fallback to hardcoded %>
<div style="background-color: #fef3cd; border-left: 4px solid #f0b429; padding: 16px; margin-bottom: 24px; border-radius: 4px;">
  <strong style="color: #856404;"><%= @issue.title %></strong>
  <p style="margin: 8px 0 0 0; color: #856404;"><%= @issue.merchant_explanation %></p>
</div>

<%# Screenshot from scan %>
<% if @has_screenshot %>
<div style="margin-bottom: 24px;">
  <p style="font-weight: 600; margin-bottom: 8px; color: #202223;">Here's what we saw:</p>
  <img src="<%= attachments['screenshot.png'].url %>"
       alt="Screenshot of <%= @product_page.title %>"
       style="max-width: 100%; border: 1px solid #e1e3e5; border-radius: 8px;" />
</div>
<% end %>

<%# AI suggested fix %>
<% if @issue.merchant_suggested_fix.present? %>
<div style="background-color: #f0faf5; border-left: 4px solid #008060; padding: 16px; margin-bottom: 24px; border-radius: 4px;">
  <strong style="color: #004c3f;">💡 Suggested fix:</strong>
  <p style="margin: 8px 0 0 0; color: #004c3f; white-space: pre-line;"><%= @issue.merchant_suggested_fix %></p>
</div>
<% end %>

<%# AI confidence badge %>
<% if @issue.ai_confirmed == true %>
<p style="margin-bottom: 16px; color: #2c6ecb; font-size: 14px;">
  🤖 Our AI also confirmed this issue with <%= (@issue.ai_confidence * 100).round %>% confidence.
</p>
<% end %>

<p style="margin-bottom: 24px;">
  <a href="<%= @app_url %>" class="button" style="display: inline-block; background-color: #008060; color: #ffffff !important; text-decoration: none; padding: 12px 24px; border-radius: 4px; font-weight: 500;">
    View Issue Details
  </a>
</p>

<p style="margin-bottom: 16px; color: #6d7175; font-size: 14px;">
  <em>We only alert you when we're confident there's a real issue. This helps us avoid false alarms.</em>
</p>
```

**Key changes from current template:**
- Replaced `@issue.description` with `@issue.merchant_explanation` (AI-generated, falls back to hardcoded)
- Added screenshot image block
- Added suggested fix block (green box)
- Added AI confidence badge for confirmed issues

---

### Step 8: Configure Resend for Production Email Delivery

**Goal:** Configure Action Mailer to use Resend's SMTP for production email delivery.

**Files to modify:**

**`config/environments/production.rb`:**
```ruby
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: "smtp.resend.com",
  port: 465,
  user_name: "resend",
  password: ENV["RESEND_API_KEY"],
  authentication: :plain,
  enable_starttls_auto: true,
  tls: true
}
config.action_mailer.default_url_options = {
  host: ENV.fetch("HOST", "localhost:3000").then { |h| h.include?("://") ? URI.parse(h).host : h }
}
```

**`app/mailers/application_mailer.rb`:**
```ruby
default from: "Prowl <alerts@getprowl.app>"  # Must match verified Resend domain
```

**Environment variables:**
```
RESEND_API_KEY=re_xxxxx
```

**Note:** You'll need to verify your domain (`getprowl.app` or similar) in Resend's dashboard and add DNS records (SPF, DKIM, DMARC) for email deliverability.

---

## Implementation Order

| Step | What | Dependencies | Effort |
|:---:|------|:---:|:---:|
| **1** | Screenshot upload to R2 | None (R2 account needed) | Small |
| **2** | BrowserService → Browserless | None (Browserless account needed) | Small |
| **3** | Eliminate worker dyno (Solid Queue in-process) | Step 2 (worker must be lightweight first) | Small |
| **4** | AI issue analyzer service | Step 1 (needs screenshot URL for high-severity) | Medium |
| **5** | AI columns migration | None | Trivial |
| **6** | AI integration in scan flow | Steps 4 + 5 | Small |
| **7** | Screenshot + AI explanation in alert emails | Steps 1 + 6 | Small |
| **8** | Resend email config | None (Resend account needed) | Small |

**Recommended execution:** Steps 1-3 first (infrastructure), then 4-6 (AI), then 7-8 (email). Steps 5 and 8 can be done in parallel with earlier steps.

---

## Files Changed Summary

| File | Change Type | Step |
|------|:-----------:|:---:|
| `Gemfile` | Modify (add `aws-sdk-s3`) | 1 |
| `app/services/screenshot_uploader.rb` | **New** | 1 |
| `app/services/product_page_scanner.rb` | Modify (`store_screenshot`) | 1 |
| `app/services/browser_service.rb` | Modify (Browserless connect) | 2 |
| `config/puma.rb` | Modify (add Solid Queue plugin) | 3 |
| `Procfile` | Modify (remove worker line) | 3 |
| `app/services/ai_issue_analyzer.rb` | **New** | 4 |
| `db/migrate/xxx_add_ai_analysis_to_issues.rb` | **New** | 5 |
| `app/models/issue.rb` | Modify (add `merchant_explanation` and `merchant_suggested_fix` methods) | 6 |
| `app/jobs/scan_pdp_job.rb` | Modify (add AI analysis step for all issues) | 6 |
| `app/mailers/alert_mailer.rb` | Modify (inline screenshot) | 7 |
| `app/views/alert_mailer/issue_detected.html.erb` | Modify (screenshot + AI explanation + suggested fix) | 7 |
| `config/environments/production.rb` | Modify (Resend SMTP + mailer URL) | 8 |
| `app/mailers/application_mailer.rb` | Modify (from address) | 8 |

---

## Environment Variables Required

```bash
# Cloudflare R2 (Step 1)
CLOUDFLARE_R2_ACCESS_KEY_ID=
CLOUDFLARE_R2_SECRET_ACCESS_KEY=
CLOUDFLARE_R2_BUCKET=prowl-screenshots
CLOUDFLARE_R2_ENDPOINT=https://<account_id>.r2.cloudflarestorage.com
CLOUDFLARE_R2_PUBLIC_URL=https://screenshots.getprowl.app

# Browserless (Step 2)
BROWSERLESS_URL=wss://chrome.browserless.io?token=YOUR_TOKEN

# Google Gemini (Step 4)
GEMINI_API_KEY=

# Resend (Step 8)
RESEND_API_KEY=re_xxxxx
```

---

## Accounts to Create Before Implementation

1. **Cloudflare** → Create R2 bucket, enable public access, get API keys
2. **Browserless.io** → Sign up for free tier, get API token
3. **Google AI Studio** → Get Gemini API key (free)
4. **Resend** → Sign up, verify domain, get API key
5. **Heroku Postgres** → `heroku addons:create heroku-postgresql:essential-0`

---

## AI Explanation: Before & After

### What merchants see today (hardcoded):

| Issue Type | Current Description |
|------------|-------------------|
| `missing_add_to_cart` | "We couldn't find a working Add to Cart button on this page. Customers may not be able to purchase this product." |
| `js_error` | "We detected JavaScript errors on this page. This may affect functionality and customer experience." |
| `liquid_error` | "There may be template errors on this page. Some content might not display correctly." |
| `slow_page_load` | "This page took longer than expected to load. This may affect customer experience." |

### What merchants will see with AI (personalized):

| Issue Type | AI-Generated Explanation | AI-Suggested Fix |
|------------|------------------------|------------------|
| `missing_add_to_cart` | "Your product page for **Blue Denim Jacket** appears to have a problem with the Add to Cart button — it's either missing or hidden from view. Customers visiting this page cannot add the product to their cart, which is likely causing lost sales." | "1. Preview your theme and check if the button appears\n2. If you recently updated your theme, try reverting\n3. Temporarily disable recently installed apps to check for conflicts" |
| `js_error` | "There's a script error on your **Blue Denim Jacket** page that's preventing the size selector from working. When customers try to pick a size, nothing happens — they won't be able to complete their purchase." | "1. Check if you recently added any new apps or custom code\n2. Try switching to a different theme temporarily to test\n3. Contact your theme developer about the error" |
| `liquid_error` | "Some product details on your **Blue Denim Jacket** page aren't displaying correctly due to a template issue. Customers might see blank spaces or missing information where the product description should be." | "1. Check your theme's product template in the theme editor\n2. Look for any recent customizations that may have introduced an error\n3. If you're using a third-party theme, check for available updates" |
| `slow_page_load` | "Your **Blue Denim Jacket** page is taking about 8 seconds to load, which is quite slow. Research shows that 53% of mobile visitors leave a page that takes over 3 seconds to load, so this may be causing some customers to leave before they even see your product." | "1. Optimize your product images — keep them under 500KB each\n2. Remove any unused apps that might be adding scripts to your page\n3. Consider using fewer product images or compressing them" |

---

## Cost Summary

| Component | Zero customers | 100 stores × 5 pages × daily |
|-----------|:-:|:-:|
| Heroku (1 Basic dyno) | $7 | $7 |
| Heroku Postgres Essential-0 | $5 | $5 |
| Cloudflare R2 storage | $0 | ~$0.08 |
| Cloudflare R2 egress | $0 | **$0** (always free) |
| Browserless.io | $0 (6 hrs free) | ~$0 (self-host fallback) |
| Gemini Flash (confirmation) | $0 (free tier) | $0 (free tier) |
| Gemini Flash (explanations) | $0 (free tier) | $0 (free tier) |
| Resend | $0 (100/day free) | $0 |
| **Total** | **$12/mo** | **~$12.08/mo** |

**Gemini free tier usage at scale:**
- 100 stores × 5 pages × daily = 500 scans/day
- Assume ~2 issues per scan = ~1,000 AI calls/day
- Gemini free tier: ~1,500 requests/day → fits, but getting close
- If exceeded: Gemini Flash is $0.10/1M input tokens, practically free at this volume

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Browserless free tier exhausted | Falls back to local Chrome in dev. At scale: self-host Docker image on $5 VPS (unlimited). |
| R2 upload fails | `ScreenshotUploader` catches errors. Scan still completes, just no screenshot. `screenshot_url` stays nil. |
| AI gives wrong confirmation | Phase 1: AI is informational only, does NOT gate alerts. Observe accuracy first. |
| AI generates misleading explanation | Fallback to hardcoded description if AI output is empty/invalid. Prompt instructs "calm, non-alarming" tone. |
| AI suggests a bad fix | Prompt instructs safe, reversible steps only (no "delete files", no "edit code"). Suggested fix is prefaced with "💡 Suggested fix" to frame it as advisory. |
| Gemini API key missing | Fail-open: issues keep hardcoded descriptions and alerts send normally. |
| In-process Solid Queue affects web requests | Jobs are lightweight (HTTP calls + DB writes). 45s timeout. Concurrency limited to 1 scan at a time. |
| Resend domain not verified | Emails will fail silently. Must verify domain + add DNS records before go-live. |
| Screenshot increases email size | Screenshots are ~150-300KB PNG. Well within Resend's 40MB email limit. |
