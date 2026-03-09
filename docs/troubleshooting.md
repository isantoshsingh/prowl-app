# Prowl Support & Troubleshooting Guide

## Table of Contents

- [How Prowl Works](#how-prowl-works)
  - [Scanning Pipeline](#scanning-pipeline)
  - [Confidence Threshold](#confidence-threshold)
  - [Alerting Rules](#alerting-rules)
- [Common Issues Detected by Prowl](#common-issues-detected-by-prowl)
  - [Missing Add to Cart Button](#missing-add-to-cart-button)
  - [Add to Cart Not Functional](#add-to-cart-not-functional)
  - [Missing Price](#missing-price)
  - [Missing or Broken Product Images](#missing-or-broken-product-images)
  - [Critical JavaScript Errors](#critical-javascript-errors)
  - [Liquid Template Errors](#liquid-template-errors)
  - [Slow Page Load](#slow-page-load)
- [Alert Troubleshooting](#alert-troubleshooting)
  - [Not Receiving Alert Emails](#not-receiving-alert-emails)
  - [Too Many Alerts](#too-many-alerts)
  - [Alert for a Non-Issue](#alert-for-a-non-issue)
- [Scan Troubleshooting](#scan-troubleshooting)
  - [Scan Shows Incorrect Results](#scan-shows-incorrect-results)
  - [Scan Takes Too Long or Times Out](#scan-takes-too-long-or-times-out)
  - [Page Status Stuck on "Pending"](#page-status-stuck-on-pending)
- [Detector-Specific Troubleshooting](#detector-specific-troubleshooting)
  - [Add to Cart Detector False Positives](#add-to-cart-detector-false-positives)
  - [Price Detector Not Finding Prices](#price-detector-not-finding-prices)
  - [Image Detector Flagging Valid Images](#image-detector-flagging-valid-images)
  - [JavaScript Errors from Third-Party Scripts](#javascript-errors-from-third-party-scripts)
- [Frequently Asked Questions](#frequently-asked-questions)

---

## How Prowl Works

### Scanning Pipeline

Each scan follows a 6-step pipeline:

1. **Browser navigation** — Prowl loads your product page in a real browser (via Browserless), capturing screenshots, HTML, JavaScript errors, and network errors.
2. **Detector execution** — Five detectors run in sequence: Add to Cart, Price Visibility, Product Image, JavaScript Error, and Liquid Error. Each returns a result with a status (pass/fail/warning/inconclusive) and a confidence score.
3. **Issue creation** — The Detection Service maps detector results to issue types. Issues are created, merged with existing ones, or resolved based on confidence and occurrence count.
4. **AI page-level analysis** — The page screenshot and all detector results are sent to AI (Gemini Flash) for independent confirmation. The AI may confirm existing issues, discover new ones, or generate plain-language explanations.
5. **AI per-issue analysis** — High-severity issues receive a follow-up AI review with the screenshot for confirmation. Lower-severity issues get text-only analysis for explanation and fix suggestions.
6. **Alert dispatch** — The Alert Service evaluates which issues qualify for alerting, batches them into a single email, and sends Shopify admin notifications.

### Confidence Threshold

Prowl uses a confidence threshold of **0.7** (on a 0.0–1.0 scale). Only detector results meeting this threshold create issues. This is the primary mechanism for reducing false positives.

Confidence is built up from individual validation checks within each detector. A detector that confirms the element exists, is visible, is interactive, and functions correctly will produce a higher confidence than one that only confirms existence.

### Alerting Rules

Alerts are sent only when all of the following are true:

- The issue severity is **HIGH**.
- The issue is either **AI-confirmed** (immediate alerting) or has been detected in **2 or more scans**.
- The issue has **not been acknowledged** by the merchant.
- An alert for this specific issue has **not already been sent** for this scan.

All alertable issues from a single scan are batched into one email. Email failures do not block scan completion.

## Common Issues Detected by Prowl

### Missing Add to Cart Button

**What Prowl found:** The Add to Cart button is missing, hidden, or disabled on your product page.

**Why this matters:** Customers cannot add the product to their cart, which directly prevents purchases.

**Common causes:**
- A theme update removed or broke the ATC button markup.
- Custom CSS is hiding the button (e.g., `display: none` or `visibility: hidden`).
- The product is sold out but the theme isn't showing the sold-out state correctly.
- A Liquid template error is preventing the button from rendering.

**How to fix:**
1. Visit your product page as a customer and verify the ATC button is visible.
2. If the product is sold out, check that your theme correctly displays "Sold Out" instead of hiding the button entirely.
3. Review recent theme customizations or app installations that may have affected the product template.
4. Check your theme's `product-form` section or snippet for Liquid errors.

### Add to Cart Not Functional

**What Prowl found:** The ATC button exists and is clickable, but clicking it does not add the product to the cart.

**Why this matters:** Customers see the button and click it, but nothing happens — leading to frustration and abandoned sessions.

**Common causes:**
- A JavaScript error is preventing the form submission handler from executing.
- The cart API endpoint is returning errors.
- A third-party app is intercepting and breaking the ATC form submission.
- The variant ID is missing or invalid in the form data.

**How to fix:**
1. Open your browser's developer tools (F12), go to the Console tab, and click the ATC button. Look for JavaScript errors.
2. Check the Network tab for failed requests to `/cart/add.js`.
3. Disable recently installed apps one at a time and test the ATC button after each.
4. Verify the product has at least one available variant.

### Missing Price

**What Prowl found:** The product price is not visible on the page.

**Why this matters:** Customers expect to see a price before adding to cart. A missing price creates distrust and prevents informed purchasing decisions.

**Common causes:**
- The price element exists in the DOM but is hidden by CSS.
- A Liquid error is preventing the price from rendering.
- The price format doesn't match expected currency patterns.
- A theme customization removed the price block from the product template.

**How to fix:**
1. Check your theme's product template for the price block — it should contain a `[data-price]`, `.price`, or `#product-price` element.
2. Inspect the price element in your browser's developer tools. Verify it's not hidden.
3. If you use a custom price display format, ensure it still contains recognizable currency characters (e.g., `$`, `€`, `£`).
4. Check the Shopify Theme Editor to confirm the price block is enabled.

### Missing or Broken Product Images

**What Prowl found:** The main product image is missing, failed to load, is too small (under 200x200px), or is a placeholder.

**Why this matters:** Product images are the primary driver of purchase decisions. Missing or broken images significantly reduce conversion rates.

**Common causes:**
- The image file was deleted from Shopify or the CDN URL changed.
- A lazy-loading implementation isn't triggering correctly.
- The image element has `complete: true` but `naturalWidth: 0`, indicating a failed load.
- A placeholder image (e.g., `blank.gif`, `no-image.png`) is being used instead of a real product photo.

**How to fix:**
1. In the Shopify admin, verify the product has images uploaded under **Products > [Product] > Media**.
2. Visit the product page and check if the image loads. Right-click and "Open image in new tab" to verify the URL works.
3. If using lazy loading, confirm your theme's lazy-load JavaScript is executing without errors.
4. If images are served from a third-party CDN, verify the URLs are still valid.

### Critical JavaScript Errors

**What Prowl found:** JavaScript errors on the page that affect purchase-related functionality (cart, checkout, variant selection, or payment flows).

**Why this matters:** These errors can silently break the buying experience. Customers may see a page that looks normal but cannot complete a purchase.

**What Prowl filters out:** Prowl automatically ignores noise from third-party scripts including Google Analytics, Facebook Pixel, Hotjar, Shopify's own analytics (monorail), chat widgets, and other non-purchase-critical sources.

**Common causes:**
- A theme update introduced a syntax error.
- Two apps are conflicting by modifying the same DOM elements.
- A required JavaScript dependency failed to load.
- Custom JavaScript in the theme has an unhandled error.

**How to fix:**
1. Open your browser's developer console (F12 > Console) on the affected product page.
2. Look for red error messages. Prowl's issue detail will show the specific errors it found.
3. If the error mentions a specific file, check if it belongs to a theme or an app.
4. For app conflicts, disable recently installed apps and test one at a time.
5. For theme errors, check recent theme updates or revert to a previous theme version.

### Liquid Template Errors

**What Prowl found:** Your page HTML contains Liquid rendering errors such as `Liquid error`, `Liquid syntax error`, `undefined method`, `missing asset`, or `translation missing`.

**Why this matters:** Liquid errors can cause page sections to render incorrectly or not at all. When visible to customers, they appear as raw error text on the page.

**Severity depends on visibility:**
- **Visible errors** (shown to customers): 0.95 confidence, high severity.
- **Hidden errors** (in HTML source only): 0.85 confidence, medium severity.

**Common causes:**
- A theme update changed variable names that custom code depends on.
- A referenced snippet or section was deleted.
- A translation key is missing for the current locale.
- An asset file (CSS, JS, image) referenced in Liquid no longer exists.

**How to fix:**
1. View the page source (Ctrl+U) and search for "Liquid error" or "translation missing".
2. The error text usually includes the file and line number where the problem occurs.
3. For `translation missing`, add the missing key in **Online Store > Themes > Edit default theme content** or your locale files.
4. For `missing asset`, re-upload the file or update the reference in your Liquid template.
5. For `undefined method`, check if a theme variable was renamed in a recent update.

### Slow Page Load

**What Prowl found:** Your product page took more than 5 seconds to load.

**Why this matters:** Slow pages increase bounce rates. Google also uses page speed as a ranking signal.

**Common causes:**
- Large, unoptimized product images.
- Too many third-party apps injecting scripts.
- Heavy custom JavaScript or CSS.
- Render-blocking resources.

**How to fix:**
1. Run your page through [Google PageSpeed Insights](https://pagespeed.web.dev/) for specific recommendations.
2. Optimize product images — Shopify automatically serves WebP format, but ensure source images aren't excessively large.
3. Audit installed apps. Each app may add its own JavaScript bundle.
4. Consider deferring or async-loading non-critical scripts.

## Alert Troubleshooting

### Not Receiving Alert Emails

**Check these in order:**

1. **Email alerts are enabled** — Go to **Settings** and confirm email alerts are toggled on.
2. **Correct email address** — If you set a custom alert email, verify it's correct. If not set, alerts go to your Shopify shop owner email.
3. **Spam/junk folder** — Check your spam folder for emails from Prowl.
4. **Issue severity** — Only HIGH severity issues trigger alerts. Medium and low severity issues do not send emails.
5. **Occurrence threshold** — Non-AI-confirmed issues require 2 or more scan occurrences before alerting. If this is the first time an issue was detected, wait for the next scan.
6. **Acknowledged issues** — If you previously acknowledged the issue, alerts are suppressed. Check the issues list with the "acknowledged" filter.

### Too Many Alerts / How to Stop Alert Emails

Prowl batches all alertable issues from a single scan into one email. However, **unacknowledged high-severity issues will re-trigger alert emails on every scan** where they are detected. This is intentional — unresolved purchase-blocking issues warrant repeated attention.

**To stop alert emails for a specific issue:**

1. **Acknowledge the issue** — This is the only way to silence alerts for an individual issue. You can acknowledge from:
   - The issue detail page in the Prowl dashboard (click **Acknowledge**).
   - The signed link in the alert email itself (no login required, valid for 30 days).
2. **Fix the issue** — Once a subsequent scan no longer detects the problem, Prowl resolves it automatically and stops alerting.

**To reduce overall alert frequency:**

3. **Switch to weekly scans** — Go to **Settings** and change scan frequency from daily to weekly. Fewer scans means fewer alert emails.
4. **Disable email alerts entirely** — Go to **Settings** and toggle email alerts off. You will still see issues in the dashboard but receive no emails.

**Common scenario:** You're receiving daily emails about the same issue. This means the issue is still being detected on every scan and hasn't been acknowledged. Either fix the root cause, or acknowledge the issue to stop the emails.

### Alert for a Non-Issue (False Positive)

If Prowl alerted you about something that isn't actually a problem:

1. **Acknowledge the issue** — Click Acknowledge on the issue detail page or use the signed link in the alert email (works without logging in, valid for 30 days). **This immediately and permanently stops alert emails for that issue.**
2. **Check the confidence score** — Issues at the 0.7 threshold are more likely to be edge cases. Prowl requires high confidence before alerting.
3. **Review the screenshot** — The scan screenshot attached to the alert email shows exactly what Prowl saw. This may reveal a transient issue (e.g., slow CDN) that has since resolved.

## Scan Troubleshooting

### Scan Shows Incorrect Results

If a scan reports problems that you can't reproduce:

1. **Check the scan screenshot** — The screenshot shows exactly what Prowl's browser rendered. The issue may be intermittent or CDN-related.
2. **Test in incognito mode** — Prowl scans as an anonymous visitor. Your logged-in view may differ.
3. **Check for geo-specific content** — Prowl's browser may see different content based on its location.
4. **Run a manual rescan** — Trigger another scan to see if the issue persists. Prowl requires 2 occurrences before alerting for non-AI-confirmed issues.

### Scan Takes Too Long or Times Out

Prowl has scan timeouts of 45 seconds (quick scan) or 60 seconds (deep scan).

1. **Check page load speed** — If your page takes more than 5 seconds to load, Prowl will have less time for its detectors.
2. **Heavy JavaScript** — Pages with heavy client-side rendering may not be fully ready within the timeout.
3. **Third-party script delays** — External scripts that take too long to load can delay page readiness.

### Page Status Stuck on "Pending"

If a product page shows "pending" status for an extended period:

1. **Trigger a manual rescan** — Click the Scan Now button on the page card.
2. **Check the scan history** — Navigate to the page detail view and review recent scans for errors.
3. **Verify the product still exists** — If the product was deleted from Shopify, the page can't be scanned.

## Detector-Specific Troubleshooting

### Add to Cart Detector False Positives

The ATC detector may report false positives in these scenarios:

- **Pre-order or back-in-stock apps** — Some apps replace the standard ATC button with a custom element that Prowl doesn't recognize. The detector tries multiple selector strategies but may miss non-standard implementations.
- **Sold-out products** — Prowl checks the Shopify product JSON endpoint (`/products/[handle].json`) to detect sold-out state. If this endpoint is blocked or returns unexpected data, the detector may misinterpret the state.
- **Custom ATC implementations** — If your theme uses a non-standard approach (e.g., a fully custom JavaScript cart), the interaction test may not work correctly.

**Resolution:** Acknowledge the issue if it's a known theme behavior. Prowl will suppress future alerts for that issue.

### Price Detector Not Finding Prices

The price detector searches 16 CSS selectors in priority order. If it can't find the price:

- **Custom price markup** — Your theme may use non-standard markup. The detector looks for elements with `data-price`, `.price`, `#product-price`, and other common selectors.
- **Prices loaded via JavaScript** — If the price is injected entirely via JavaScript after page load, it may not be present when the detector runs.
- **Non-standard currency format** — The detector validates against common currency patterns (USD, EUR, GBP, JPY, etc.). Unusual formatting may not match.

### Image Detector Flagging Valid Images

The image detector may flag images in these cases:

- **Lazy-loaded images** — Prowl scrolls to trigger lazy loading, but some implementations may require additional user interaction.
- **Images under 200x200px** — Prowl enforces a minimum size. Thumbnail-only product pages will be flagged.
- **SVG or non-standard formats** — The detector is optimized for raster images (JPEG, PNG, WebP).

### JavaScript Errors from Third-Party Scripts

Prowl filters noise from known third-party sources (Google Analytics, Facebook, Hotjar, Shopify monorail, chat widgets, etc.). However:

- **New or uncommon third-party apps** — Scripts not in Prowl's ignore list may trigger false positives if they throw errors.
- **App conflicts** — Two apps modifying the same page elements can cause errors that Prowl correctly detects as critical if they affect purchase flows.

If you believe a JavaScript error alert is from a benign third-party script, acknowledge the issue.

## Frequently Asked Questions

**How many pages can I monitor?**
Up to 3 product pages simultaneously.

**When do scheduled scans run?**
Daily at 6:00 AM UTC (if set to daily) or once per week (if set to weekly).

**Can I scan a page right now?**
Yes. Click the **Scan Now** button on any product page card or from the page detail view.

**What is a "deep scan"?**
Deep scans are more thorough checks with a 60-second timeout (vs. 45 seconds). They run automatically on the first scan of a new page, when critical issues are open, and on Mondays.

**Why didn't I get an alert for a medium-severity issue?**
Alerts are only sent for HIGH severity issues. Medium and low severity issues are visible in your dashboard and issues list but do not trigger notifications.

**Why did I get an alert on the first scan?**
If the AI independently confirmed the issue, alerting happens immediately without waiting for a second scan occurrence.

**How do I stop getting emails about the same issue?**
Acknowledge the issue. You can do this from the issue detail page in the dashboard, or by clicking the acknowledge link in the alert email (no login needed). Once acknowledged, Prowl permanently stops sending alerts for that issue. Alternatively, fix the issue — once a scan no longer detects it, Prowl resolves it automatically.

**Can I get alerts re-enabled for an acknowledged issue?**
Not directly. Acknowledged issues stay silenced. However, if the same problem re-appears after being resolved (i.e., the issue was resolved and then detected again), Prowl creates it as a new issue with fresh alerting.

**Why do I keep getting emails even though I know about the issue?**
Prowl re-alerts on every scan for unacknowledged high-severity issues. This is by design — purchase-blocking issues should not be silently ignored. Acknowledge the issue to stop the emails.

**What happens when I remove a monitored page?**
The page is soft-deleted. Scan history and issues are preserved. You can restore the page later.

**Does Prowl affect my store's performance?**
No. Prowl scans your pages using an external browser service. It does not inject any code into your storefront or affect customer-facing performance.

**How does Prowl handle password-protected stores?**
Prowl loads pages as a public visitor. If your store is password-protected (e.g., during development), scans will not be able to access the product pages.
