# Understanding Your Results

After Prowl scans your product pages, you'll see results on your dashboard. This guide explains what the different statuses, severity levels, and confidence scores mean.

## Page Status Colors

Each monitored product page has a status indicator on your dashboard:

### Green — Healthy

Everything looks good. No issues were detected on the most recent scan. Your product page is working as expected.

### Yellow — Minor Issues

One or more medium- or low-priority issues were found. These won't prevent customers from buying, but they could affect the shopping experience. Examples include slow page loading or Liquid template warnings.

### Red — Critical Issues

One or more high-priority issues were found. These could directly prevent customers from purchasing. You should investigate and address these as soon as possible.

---

## Issue Severity Levels

Every issue Prowl detects is assigned a severity level based on how much it could affect your sales.

### High Priority

These issues can directly block purchases or seriously hurt the customer experience:

- **Add to Cart button not working** — Customers can't buy the product
- **Variant selector errors** — Customers can't choose sizes, colors, or other options
- **JavaScript errors** — Interactive features on the page may be broken
- **Price not visible** — Customers can't see how much the product costs

**High-priority issues trigger email alerts** if they persist across two consecutive scans.

### Medium Priority

These issues affect the shopping experience but don't completely block purchases:

- **Liquid template errors** — Some page content may not display correctly
- **Images not loading** — Product photos may be missing or broken

Medium-priority issues appear on your dashboard but do not trigger email alerts.

### Low Priority

These issues are worth knowing about but have a smaller impact:

- **Slow page load** — The page takes more than 5 seconds to load

Low-priority issues appear on your dashboard but do not trigger email alerts.

---

## Confidence Scores

For each detected issue, Prowl assigns a confidence score. This reflects how certain the detection is.

- **High confidence** — The issue was clearly identified. For example, the Add to Cart button is definitely missing from the page.
- **Moderate confidence** — There are strong signs of the issue, but it may need a closer look. For example, an image request failed, but it might be a non-essential image.

Prowl only reports issues when the confidence score is above a minimum threshold. Detections that fall below this threshold are not shown, which helps reduce noise and keep your dashboard focused on real problems.

---

## Issue Statuses

Each issue on your dashboard has one of three statuses:

### Open

The issue was detected on the most recent scan and has not been addressed yet. Open issues remain visible on your dashboard and can trigger alerts (if high severity).

### Acknowledged

You've reviewed the issue and marked it as acknowledged. This is useful when you're aware of the problem and are working on a fix, or when you've decided it's not something you need to address right now. Acknowledged issues stay on your dashboard but won't trigger further alerts.

### Resolved

The issue was not detected on the most recent scan — it's gone. Prowl automatically resolves issues when a scan shows the problem has been fixed. You'll also get a notification when all issues on a page are resolved, confirming that the page is healthy again.

---

## How Alerts Work

Prowl sends email alerts only for **high-priority issues** that are **confirmed across two consecutive scans**. This two-scan requirement exists to avoid false alarms — a one-time glitch won't trigger a notification.

When all issues on a page are resolved, you'll receive a follow-up email letting you know the page is healthy.

You can manage your alert preferences in **Settings**, including:

- Turning email alerts on or off
- Setting a custom email address for alerts

---

## Tips for Using Your Dashboard

- **Check your dashboard regularly** — Even medium- and low-priority issues are worth reviewing periodically.
- **Use the Rescan button** — After making a fix, trigger a manual rescan to confirm the issue is resolved.
- **Acknowledge issues you're aware of** — This keeps your dashboard focused on new problems.
- **Start with red items** — Always address high-priority issues first, as they have the biggest impact on sales.

## Learn More

- [Common Issues and Fixes](common-issues-and-fixes.md) — Detailed guidance for resolving each issue type
- [FAQ](faq.md) — Answers to common questions
