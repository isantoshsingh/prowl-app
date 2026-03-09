# Prowl Merchant Guide

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
  - [Adding Product Pages to Monitor](#adding-product-pages-to-monitor)
  - [Running Your First Scan](#running-your-first-scan)
  - [Configuring Alerts](#configuring-alerts)
- [Dashboard](#dashboard)
  - [Health Summary](#health-summary)
  - [Open Issues](#open-issues)
  - [Scan History](#scan-history)
- [What Prowl Checks](#what-prowl-checks)
  - [Add to Cart Button](#add-to-cart-button)
  - [Price Visibility](#price-visibility)
  - [Product Images](#product-images)
  - [JavaScript Errors](#javascript-errors)
  - [Liquid Template Errors](#liquid-template-errors)
- [Understanding Issues](#understanding-issues)
  - [Severity Levels](#severity-levels)
  - [Issue Types](#issue-types)
  - [Confidence Scoring](#confidence-scoring)
  - [AI Confirmation](#ai-confirmation)
- [Managing Issues](#managing-issues)
  - [Viewing Issue Details](#viewing-issue-details)
  - [Acknowledging Issues](#acknowledging-issues)
  - [Resolved Issues](#resolved-issues)
- [Settings](#settings)
  - [Alert Preferences](#alert-preferences)
  - [Scan Frequency](#scan-frequency)
  - [Monitored Page Limits](#monitored-page-limits)
- [Scanning Behavior](#scanning-behavior)
  - [Scheduled Scans](#scheduled-scans)
  - [Manual Rescans](#manual-rescans)
  - [Deep Scans](#deep-scans)

---

## Overview

Prowl monitors your Shopify product detail pages (PDPs) for issues that could prevent customers from completing a purchase. It runs automated checks against your live storefront, uses confidence scoring to reduce false positives, and sends you alerts only when real problems are detected.

## Getting Started

### Adding Product Pages to Monitor

1. Navigate to the **Product Pages** section from the sidebar.
2. Click **Add Products** to open the Shopify Resource Picker.
3. Select up to 3 product pages to monitor.
4. Each added page appears as a card showing the product image, title, URL, and current status.

To remove a page, click the remove button on its card. Removed pages are soft-deleted, preserving scan history, and can be restored later.

### Running Your First Scan

After adding a product page, click the **Scan Now** button on the page card. Prowl will:

1. Load your product page in a real browser.
2. Run all detectors (Add to Cart, Price, Images, JavaScript, Liquid).
3. Capture a screenshot of the page.
4. Analyze results with AI for confirmation.
5. Create issues for any problems found.

A progress indicator polls every 2 seconds while the scan is running.

### Configuring Alerts

Go to **Settings** to configure how you receive notifications:

- **Email alerts**: Toggle on/off. Set a custom alert email or use your shop owner email.
- **Admin alerts**: Toggle Shopify admin notifications on/off.
- **Scan frequency**: Choose daily or weekly automatic scans.

## Dashboard

### Health Summary

The dashboard shows your PDP health at a glance with counts for:

- **Healthy** pages — no open issues detected.
- **Warning** pages — medium or low severity issues found.
- **Critical** pages — high severity issues that may block purchases.

### Open Issues

The top 10 open issues are listed, ordered by severity. Each entry links to the full issue detail view.

### Scan History

The last 5 scans are shown with a 7-day trend chart so you can track how your pages' health changes over time.

## What Prowl Checks

### Add to Cart Button

Prowl's Add to Cart detector runs a 3-layer check:

1. **Structural check** — Verifies the ATC button/form exists in the DOM, is visible, and is enabled.
2. **Interaction check** — Performs a deep funnel test: selects a variant, clicks ATC, polls the cart API, verifies the item was added, then cleans up.
3. **AI confirmation** — Sends the page screenshot to AI for independent verification.

The detector handles multiple theme layouts and detects sold-out states using the Shopify product JSON endpoint, independent of language or theme text.

### Price Visibility

The Price Visibility detector checks that product pricing is displayed correctly:

- Searches across 16 CSS/data selectors in priority order for price elements.
- Validates that the price text is visible, at least 2 characters long, and not a placeholder.
- Matches currency formats (USD, EUR, GBP, JPY, and others).
- Detects compare-at and sale pricing.

### Product Images

The Product Image detector validates your main product image:

- Confirms the image element exists, has loaded, and is visible.
- Enforces a minimum size of 200x200 pixels.
- Handles lazy-loaded images by scrolling to trigger loading.
- Tries 14 image selectors with a fallback to the largest image in the product area.
- Filters out broken images and detects placeholder patterns (e.g., `no-image`, `placeholder`, `blank.gif`).

### JavaScript Errors

The JavaScript Error detector monitors for client-side errors that affect purchasing:

- Filters out third-party noise from analytics, pixels, chat widgets, and Shopify internals (Google Analytics, Facebook, Hotjar, Shopify monorail, etc.).
- Categorizes errors as **critical** (related to cart, checkout, variant, payment, or purchase flows) or non-critical.
- Returns high confidence (0.95) when both syntax and critical errors are found, 0.85 for critical errors alone.

### Liquid Template Errors

The Liquid Error detector scans your page HTML for template rendering problems:

- Detects patterns: `Liquid error`, `Liquid syntax error`, `undefined method`, `missing asset`, `translation missing`, `no template found`.
- Uses a JavaScript DOM walker to determine if errors are visible to customers.
- Assigns severity: high for rendering errors, medium for missing assets, low for warnings.
- Visible errors receive 0.95 confidence; hidden high-severity errors receive 0.85.

## Understanding Issues

### Severity Levels

| Severity | Meaning | Alert Behavior |
|----------|---------|----------------|
| **HIGH** | Likely blocks purchases (broken ATC, missing price, critical JS errors) | Triggers email and admin alerts |
| **MEDIUM** | Degrades experience but doesn't block checkout (Liquid errors, missing images) | No automatic alerts |
| **LOW** | Minor issues (slow page load) | No automatic alerts |

### Issue Types

| Issue Type | Severity | What It Means |
|------------|----------|---------------|
| Missing Add to Cart | HIGH | The ATC button is missing, hidden, or disabled |
| ATC Not Functional | HIGH | The ATC button clicks but the cart doesn't update |
| Checkout Broken | HIGH | The checkout page fails after adding to cart |
| Variant Selection Broken | HIGH | Customers cannot select product options |
| Variant Selector Error | HIGH | The variant picker has JavaScript errors |
| JavaScript Error | HIGH | Critical JavaScript errors on the page |
| Liquid Error | MEDIUM | Liquid template rendering errors |
| Missing Images | MEDIUM | Product images are not loading |
| Missing Price | HIGH | The product price is not visible |
| Slow Page Load | LOW | Page takes more than 5 seconds to load |

### Confidence Scoring

Every detection result includes a confidence score from 0.0 to 1.0. Prowl only creates issues for detections with confidence at or above **0.7**. This threshold reduces false positives — a low-confidence detection is discarded rather than turned into a noisy alert.

Confidence is calculated based on how many validation checks pass within each detector. For example, the Price Visibility detector gains confidence from finding a price element, verifying its visibility, confirming it matches a currency format, and checking it's not a placeholder.

### AI Confirmation

After programmatic detectors run, Prowl sends the page screenshot and detector results to an AI model for independent analysis. The AI can:

- **Confirm** an issue — marking it as `ai_confirmed`, which enables immediate alerting (no need to wait for a second scan).
- **Discover new issues** that programmatic detectors missed.
- **Generate plain-language explanations** so you understand what went wrong without needing technical knowledge.

## Managing Issues

### Viewing Issue Details

Click any issue to see its detail page, which includes:

- A **plain-language explanation** generated by AI describing the problem.
- **Technical details** and evidence from the detector.
- **Suggested fix steps** tailored to the specific issue.
- A link to the related scan and its screenshot.

### Acknowledging Issues

**Acknowledging an issue is the only way to stop receiving alert emails for it.** As long as a high-severity issue remains open and unacknowledged, Prowl will continue to send alert emails on every scan where the issue is detected.

If you've reviewed an issue and determined it doesn't need action (e.g., intentionally sold-out products, a known theme behavior, or an issue you're already working on), click the **Acknowledge** button. Acknowledged issues:

- **Stop triggering alert emails and admin notifications** — this is immediate and permanent for that issue.
- Still appear in your issues list under the "acknowledged" filter so you don't lose track of them.
- Can be acknowledged directly from alert emails without logging in, via a signed link (valid for 30 days).

If you do not acknowledge an issue, Prowl will re-alert you on each subsequent scan where the issue persists. This is by design — unacknowledged high-severity issues represent potential lost revenue and warrant repeated attention until addressed or explicitly dismissed.

### Resolved Issues

When a subsequent scan no longer detects the problem, Prowl automatically marks the issue as resolved and sends an "all clear" email notification. Resolved issues remain in your history for reference. If the same problem re-appears later, it is created as a new issue with fresh alerting — previous acknowledgements do not carry over.

## Settings

### Alert Preferences

- **Email alerts** (default: on) — Receive batched email notifications for high-severity issues. All alertable issues from a scan are grouped into a single email with screenshots attached inline. Turning this off disables all Prowl alert emails.
- **Admin alerts** (default: on) — Receive notifications in your Shopify admin panel.
- **Alert email** (optional) — Specify a custom email address for alerts (e.g., a shared team inbox). If not set, alerts go to the shop owner email registered with Shopify.

**How alert emails work:**

- Each scan produces **one batched email** containing all high-severity issues found, not one email per issue.
- Emails include the scan **screenshot** as an inline attachment so you can see exactly what Prowl saw.
- Each email contains a **signed acknowledge link** per issue — click it to silence future alerts for that issue without logging in (link expires after 30 days).
- **Prowl will keep sending alert emails** for any unacknowledged high-severity issue on every scan where it is detected. To stop emails for a specific issue, you must [acknowledge it](#acknowledging-issues).
- When all issues on a product page are resolved, Prowl sends an **"all clear" email** confirming the page is healthy again.

### Scan Frequency

Choose between:

- **Daily** (default) — Scans run every day at 6:00 AM UTC.
- **Weekly** — Scans run once per week.

### Monitored Page Limits

You can monitor up to **3 product pages** simultaneously.

## Scanning Behavior

### Scheduled Scans

Prowl automatically scans your monitored pages based on your configured frequency. The scheduled job runs at 6:00 AM UTC and queues scans for all pages that are due.

### Manual Rescans

You can trigger a manual rescan at any time from the product page card or the page detail view. Use this after making theme changes or fixing an issue to verify the fix.

### Deep Scans

Prowl performs more thorough "deep scans" in certain situations:

- The **first scan** of a newly added page.
- When there are **open critical issues** on the page.
- On **Mondays** as a weekly deep check.

Deep scans have a longer timeout (60 seconds vs. 45 seconds for quick scans) and perform more extensive interaction testing.
