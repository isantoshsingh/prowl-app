# How Detection Works

Prowl runs five main checks on every product page it scans. Here's what each one looks for and why it matters.

## How Scanning Works

When Prowl scans a product page, it opens the page in a real browser — just like a customer visiting your store. It loads the page, waits for everything to appear, and then runs a series of checks. This means it catches problems that only show up when someone actually visits the page, not just problems in your code.

Each scan takes up to 30 seconds per page.

---

## The 5 Detection Checks

### 1. Add-to-Cart Button

**What it checks:** Is there a working "Add to Cart" button on the page?

**Why it matters:** If the Add to Cart button is missing, broken, or hidden, customers literally cannot buy your product. This is the most critical issue Prowl looks for.

**What can go wrong:** A theme update, app conflict, or custom code change might accidentally hide or break the button. Sometimes it works on desktop but not on mobile, or it breaks only for certain product variants.

---

### 2. JavaScript Errors

**What it checks:** Are there JavaScript errors happening when the page loads?

**Why it matters:** JavaScript powers most of the interactive features on your product page — variant selectors, image galleries, quantity pickers, and more. When JavaScript breaks, these features stop working, and customers may not be able to complete a purchase.

**What gets flagged:** Prowl focuses on errors that could affect the shopping experience. It ignores common noise from analytics tools and third-party trackers so you only see what matters.

---

### 3. Liquid Template Errors

**What it checks:** Are there Liquid rendering errors visible on the page?

**Why it matters:** Liquid is the template language Shopify uses to build your pages. When a Liquid error occurs, part of your page content may not display correctly. You might see error messages on the page, missing sections, or broken layouts.

**What gets flagged:** The scan looks for error messages like "Liquid error" or "Translation missing" in your page content — signs that something in your theme templates isn't rendering properly.

---

### 4. Price Display

**What it checks:** Is the product price visible on the page?

**Why it matters:** If customers can't see how much a product costs, they're far less likely to buy it. A missing price can be caused by theme issues, Liquid errors, or problems with how your product data is set up.

**What gets flagged:** Prowl looks for price-related elements and currency formatting on the page. If it can't find any indication of a price, it flags the issue.

---

### 5. Image Loading

**What it checks:** Are the product images loading correctly?

**Why it matters:** Product images are one of the biggest factors in a customer's decision to buy. If images fail to load, customers see broken placeholders or empty spaces, which hurts trust and reduces conversions.

**What gets flagged:** The scan monitors all image requests while the page loads and flags any that fail. This catches broken image links, deleted files, or server issues that prevent images from displaying.

---

## Bonus Check: Page Speed

In addition to the five main checks, Prowl also measures how long your page takes to load. If a page takes more than **5 seconds**, it gets flagged as slow. Slow pages frustrate customers and can lead to them leaving before they even see your product.

---

## What Happens After Detection

After each scan, Prowl:

1. **Updates your dashboard** with the latest results for each page
2. **Creates or updates issues** for any problems it finds
3. **Automatically resolves issues** that are no longer detected (the problem went away)
4. **Sends an alert** if a high-priority issue is confirmed across two consecutive scans

This two-scan confirmation helps make sure you're only notified about real, persistent problems — not one-time glitches.

## Learn More

- [Understanding Your Results](understanding-results.md) — What the status indicators and severity levels mean
- [Common Issues and Fixes](common-issues-and-fixes.md) — Step-by-step guidance for each issue type
