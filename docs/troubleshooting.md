# Troubleshooting

Having trouble with Silent Profit? This guide covers the most common problems and how to resolve them.

---

## Scan Not Running

### The scan seems stuck on "Pending"

Scans are processed in a queue, so there may be a short delay before yours starts. If a scan has been in "Pending" status for more than a few minutes:

- **Wait a moment and refresh** — The dashboard doesn't auto-refresh. Reload the page to see the latest status.
- **Try a manual rescan** — Click the "Rescan" button on the product page to queue a new scan.
- **Check your subscription status** — Scans only run for stores with an active subscription or active free trial. Go to **Settings** or **Billing** in the Silent Profit dashboard to verify your billing status.

### The scan completed but shows "Failed"

A failed scan means Silent Profit's browser couldn't fully load your product page. Common causes:

- **The page URL is incorrect** — Double-check that the product page URL is valid and the product is published (not in draft status).
- **The page requires a password** — If your store is password-protected (common during setup), Silent Profit can't access it. Remove the password from **Online Store > Preferences** to enable scanning.
- **The page took too long to load** — Each scan has a 30-second timeout. If your page is extremely slow or has resources that hang, the scan may fail. See [Slow Page Load fixes](common-issues-and-fixes.md#slow-page-load) for tips.
- **Temporary network issue** — Occasionally, a scan can fail due to a brief network hiccup. Try running another scan — if it succeeds, the failure was temporary.

---

## No Results Showing

### I added pages but don't see any results

- **Check if the first scan has completed** — After adding a page, the first scan needs to finish before results appear. Look for the scan status next to the page (Pending, Running, Completed, or Failed).
- **Refresh your dashboard** — Results appear after the scan completes, but you may need to reload the page to see them.
- **Verify the page was added successfully** — Go to the product pages section and confirm your page is listed there with "Monitored" status.

### I don't see any issues listed, but I know my page has problems

- **Silent Profit checks for specific issue types** — It looks for the problems described in [How Detection Works](how-detection-works.md). If the issue you're seeing isn't one of those types, it won't be flagged.
- **The issue may be below the confidence threshold** — If the detection confidence is too low, the issue won't be shown to avoid false positives.
- **Try a manual rescan** — Issues can sometimes be intermittent. Running another scan may catch it.

---

## Not Receiving Email Alerts

### I have issues on my dashboard but no email alerts

This is usually expected behavior. Email alerts are only sent when **all** of the following are true:

1. The issue is **high priority** (high severity)
2. The issue has been detected on **at least two separate scans**
3. The issue status is **open** (not acknowledged)
4. An alert hasn't already been sent for that specific issue

If your issue is medium or low priority, it won't trigger an email — it only appears on your dashboard.

### I'm not getting any emails at all

- **Check your alert settings** — Go to **Settings** in the Silent Profit dashboard and make sure email alerts are turned on.
- **Check your alert email address** — Verify the email address in your settings is correct. If no custom email is set, alerts go to the email associated with your Shopify store.
- **Check your spam/junk folder** — Alert emails may have been filtered by your email provider.
- **Verify your subscription is active** — Alerts are only sent to stores with active billing. Check your billing status in **Settings** or **Billing**.

---

## Permissions Issues

### I'm seeing a permissions or access error

- **Re-authenticate the app** — Sometimes Shopify sessions expire. Try navigating to the app from your Shopify admin panel. If prompted, approve the permissions again.
- **Check that the app is still installed** — Go to **Settings > Apps and sales channels** in your Shopify admin to confirm Silent Profit is listed.
- **Verify required permissions** — Silent Profit needs permission to read your products and themes. If these permissions were revoked, you may need to reinstall the app.

### The app is asking me to approve billing again

This can happen if:
- Your free trial has ended and you need to approve the paid subscription
- Your previous billing approval expired or was declined
- The app was reinstalled

Follow the prompts in Shopify to approve billing. The app will resume normal operation after approval.

---

## Pages Not Loading in Scans

### A specific page always fails to scan

- **Check if the page is publicly accessible** — Open the product page URL in an incognito/private browser window. If you can't access it, Silent Profit can't either.
- **Make sure the product is published** — Draft or archived products may not have publicly accessible pages.
- **Remove store password protection** — If your store has a password page enabled, Silent Profit cannot access any pages. Disable it in **Online Store > Preferences**.
- **Check the URL** — Make sure the URL hasn't changed. If you've edited the product's URL handle in Shopify, the old URL won't work.

### All my pages are failing to scan

If every page is failing:
- **Check your store's password protection** — This is the most common cause of all-page failures.
- **Verify your store is online** — Make sure your store hasn't been paused or deactivated in Shopify.
- **Wait and try again** — If there's a temporary issue with your store's hosting, scans may fail across the board. Try again in an hour.

---

## Dashboard Issues

### The dashboard looks outdated or isn't showing recent data

- **Hard refresh the page** — Press `Ctrl+Shift+R` (Windows) or `Cmd+Shift+R` (Mac) to bypass your browser cache.
- **Check when the last scan ran** — Look at the scan timestamps on your dashboard. If the last scan was more than 24 hours ago, there may be a billing or scheduling issue.

### I can't add more pages to monitor

- **Check your page limit** — You can monitor up to 5 pages at a time. If you're at the limit, remove a page before adding a new one.
- **Check your subscription** — Page monitoring requires an active subscription or free trial.

---

## Still Need Help?

If none of the above resolved your issue:

1. **Check our other guides:**
   - [Getting Started](getting-started.md)
   - [FAQ](faq.md)
   - [Common Issues and Fixes](common-issues-and-fixes.md)

2. **Contact support** — Reach out to us through the Shopify App Store listing with a description of your problem and any error messages you're seeing.
