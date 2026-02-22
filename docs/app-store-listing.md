# Shopify App Store Listing — Prowl

Use this document as the source of truth when filling out the Shopify App Store listing form.
Follows the [Shopify App Store best practices](https://shopify.dev/docs/apps/launch/shopify-app-store/best-practices).

---

## App Name

**Prowl**

_(30 characters max — "Prowl" = 5 characters. Starts with brand name per requirement 5.A.)_

---

## App Icon

- Format: JPEG or PNG
- Size: 1200px x 1200px
- Keep corners square (automatically rounded by Shopify)
- Include padding so the logo doesn't touch the edges
- Use bold colors and a simple, recognizable pattern
- Do NOT include text, screenshots, or Shopify trademarks
- Do NOT include pricing information in the icon

**TODO:** Create icon asset and upload to Partner Dashboard.

---

## App Card Subtitle

```
Know when product pages break — before they cost you sales
```

_(Highlights merchant benefit, not just the function. Avoids jargon like "PDP". Per section 5.E.)_

---

## App Introduction (100 characters max)

```
Detect broken product pages before they cost you sales. Protect revenue with daily automated scans.
```

_(98 characters. First sentence states what the app does. Second ties it to a measurable business outcome — revenue protection. Per section 5.B.4.)_

---

## App Details (500 characters max)

```
Prowl monitors your product pages daily, the same way your customers experience them. It detects missing add-to-cart buttons, JavaScript errors, broken images, invisible prices, and more.

When a real issue is confirmed across two consecutive scans, you get a clear alert with guidance on what went wrong and how to fix it. No false alarms, no noise.

Setup takes under a minute: pick up to 5 product pages, and Prowl handles the rest. Works with every Shopify theme.
```

_(470 characters. Describes functional elements and what makes the app unique. No support info, links, URLs, testimonials, keyword stuffing, or outcome guarantees. Per section 5.B.5.)_

---

## Feature List (up to 80 characters each)

1. `Daily automated scans that check your product pages for problems`
2. `Detects missing add-to-cart buttons, JS errors, broken images, and more`
3. `Alerts only fire after an issue is confirmed across two consecutive scans`
4. `Clear fix guidance with every alert — know what's wrong and how to fix it`
5. `Works with every Shopify theme, free or third-party`
6. `Zero impact on your storefront speed or customer experience`
7. `Dashboard with color-coded health status for every monitored page`
8. `Read-only access — Prowl never modifies your store data`

_(Each under 80 characters. Describes functionality, not technical mechanics. No "real browser", "headless", or implementation details. Per section 5.B.6.)_

---

## Feature Media (video or image)

- Preferred: Short promotional video (2-3 minutes)
  - Keep it promotional, not instructional
  - Limit screencasts to 25% of the video
- Fallback: Static feature image
  - Size: 1600px x 900px (16:9 ratio)
  - One focal point, solid background, good contrast (4.5:1 ratio recommended)
  - Include alt text
  - Do NOT use Shopify logos or repeat the app card subtitle

**TODO:** Create feature video or image asset.

---

## Screenshots

- Size: 1600px x 900px (16:9 ratio)
- Include 3-6 desktop screenshots
- At least one must show the app's UI
- Crop out browser chrome and sensitive information
- Provide alt text for every screenshot
- Do NOT include pricing, reviews, outcome guarantees, or PII

**Recommended screenshots:**
1. Dashboard showing color-coded product page health overview
2. Product page detail with scan results and detected issues
3. Issues list with severity levels and status indicators
4. Scan history showing completed scans and results
5. Settings page with alert preferences and email configuration
6. Manual scan in progress or scan completed state

**TODO:** Capture and upload screenshot assets.

---

## Demo Store URL

Provide a link to a development store with Prowl installed. Link directly to the dashboard page that best demonstrates the app's functionality.

**TODO:** Set up a demo development store with sample product pages and pre-run scans.

---

## Pricing

**Billing method:** Recurring charge (via Shopify Billing API)

**Plan:**
- Plan name: Prowl
- Price: $10/month
- Free trial: 14 days (full access, no limitations)

_(Per section 5.C: pricing information only in designated pricing section. 14-day trial recommended by Shopify.)_

---

## Integrations

_(Up to 6 integrations. Do NOT include Shopify itself, other shopping carts, or other Shopify apps unless directly integrated. Per section 5.B.7.)_

No third-party integrations in Phase 1. Leave blank or omit.

---

## Search Terms (up to 5)

1. broken product page
2. product page monitoring
3. add to cart missing
4. product page errors
5. revenue loss prevention

_(Max 5 terms. Complete words only, one idea per term. No jargon like "PDP". Per section 5.E.)_

---

## Categories and Tags

Select categories and tags that reflect the app's core functionality. Up to 25 structured features per category can be selected to help merchants compare apps.

**Suggested primary category:** Store management / Monitoring
**Suggested tags:** product pages, monitoring, alerts, diagnostics, page health

**TODO:** Select exact categories and structured features in the Partner Dashboard.

---

## Privacy Policy

A privacy policy link is required. Include it in the listing.

**Key points the privacy policy should cover:**
- Prowl accesses: store domain, product page URLs, theme-rendered HTML, JS console errors, network errors, scan screenshots, merchant email for alerts
- Prowl does NOT access: customer PII, orders, payments, checkout data, admin credentials
- Read-only permissions (`read_products`, `read_themes`)
- Scans run as a public visitor (no admin privileges)
- Data isolation per store
- Screenshots stored in private object storage with signed URLs

**TODO:** Create privacy policy page and add URL to the listing.

---

## Additional Links (recommended)

- FAQ page
- Changelog
- Support portal or help documentation
- Tutorial or getting started guide

_(Link to dedicated pages, not promotional landing pages or cloud documents. Per section 5.E.)_

---

## SEO: Title Tag and Meta Description

**Title tag:** `Prowl — Product Page Monitoring for Shopify | Detect Broken Pages`

**Meta description:** `Prowl scans your Shopify product pages daily and alerts you when something breaks — missing add-to-cart buttons, JS errors, broken images. Protect your revenue with smart monitoring.`

_(Follow Google's title tag best practices and write effective meta descriptions for click-through rates. Per section 5.E.)_

---

## Merchant Install Eligibility

- **Required sales channel:** Online Store
- **Geography:** No restrictions (works globally)
- **Currency:** No restrictions

_(Set eligibility criteria to reduce uninstalls from ineligible merchants. Per section 5.F.)_

---

## Translations

English listing set as primary is automatically translated by Shopify to: Brazilian Portuguese, Danish, Dutch, French, German, Simplified Chinese, Spanish, Swedish.

No custom translations needed for Phase 1. Automated translations cover: subtitle, introduction, details, features, pricing details, search terms, and image alt text.

_(Per section 5.D.)_

---

## App Review Preparation

### Step-by-step review instructions

1. Install the app on a development store.
2. On first launch, the app redirects to the billing approval screen ($10/month, 14-day free trial).
3. After approving billing, you land on the dashboard.
4. Navigate to **Product Pages** and click **Add Product Page**.
5. Use the Shopify resource picker to select 1-3 products.
6. Click **Scan Now** on any product page to trigger a manual scan.
7. After the scan completes (up to 30 seconds), view the results on the product page detail screen.
8. Navigate to **Issues** to see any detected problems with severity levels.
9. Navigate to **Scans** to view scan history.
10. Navigate to **Settings** to configure alert email and preferences.

### Expected behavior

- Scans run without affecting the storefront.
- Issues are created only when problems are detected.
- Alerts are sent only for high-severity issues confirmed across 2 scans.
- The dashboard shows color-coded status: green (healthy), yellow (warnings), red (critical issues).

### Screencast requirement

A complete screencast is required showing:
- The full setup process (install, billing approval, first page added)
- All features as described in the listing
- Expected outcome for each test case
- Must be in English or include English subtitles

**TODO:** Record and upload screencast.

_(Per section 5.G.)_

---

## Submission Checklist

- [ ] App icon uploaded (1200x1200, JPEG/PNG)
- [ ] Feature media uploaded (video or 1600x900 image)
- [ ] 3-6 screenshots uploaded (1600x900 each, with alt text)
- [ ] Demo store URL provided
- [ ] Privacy policy URL provided
- [ ] Screencast recorded and uploaded
- [ ] Categories and tags selected
- [ ] Billing uses Shopify Billing API
- [ ] OAuth authentication works correctly
- [ ] App scopes are minimal: `read_products`, `read_themes`
- [ ] App functions in Chrome incognito mode
- [ ] App name in TOML matches listing name
- [ ] No unsubstantiated claims, stats, or guarantees in listing copy
- [ ] No pricing info outside designated pricing section
- [ ] No Shopify trademarks in icon or feature images

---

## Notes for Submission

- **Billing:** All charges go through the Shopify Billing API.
- **Scopes:** `read_products`, `read_themes` (read-only).
- **No customer data:** The app does not access orders, customers, or checkout data.
- **Webhooks:** Handles `app_uninstalled`, `app_subscription_update`, and `shop_update`.
- **Embedded app:** Uses Shopify App Bridge, session tokens, Polaris Web Components.
- **Phase 1 only:** The listing must not reference auto-fix, SEO, or optimization features — those are planned for future phases.

---

## Key Benefits (internal reference / marketing)

| Benefit | Description |
|---|---|
| **Early warning system** | Catch broken pages before your revenue drops |
| **Minimal false positives** | Two-scan confirmation means alerts you can trust |
| **No technical skills needed** | Plain-language diagnostics and guided fixes |
| **All themes supported** | Works with any Shopify theme out of the box |
| **No store slowdown** | Scans run externally — your storefront stays fast |
| **Privacy-first** | Read-only access, no customer data collected |
