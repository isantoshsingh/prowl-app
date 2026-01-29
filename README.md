Here is a clean **MVP Specification (Markdown format)** for your new Shopify App idea — ready to paste directly into a ChatGPT Project.

---

# 🧩 **Shopify PDP Diagnostics & Monitoring App — MVP Specification**

## **1. App Summary**

A Shopify app that **scans product pages**, detects common issues (broken add-to-cart, variant selector conflicts, hidden UI, Liquid errors, JS errors), and alerts merchants automatically.

The MVP focuses on:

* Automated scanning
* Detection of high-impact PDP issues
* Alerts to merchants
* Simple dashboard showing issues

---

## **2. Core MVP Features**

### **2.1 Daily PDP Scan (Automated)**

* Crawl **3–5 most-visited product pages** (Shopify Analytics API, fallback: last created products).
* Visit each PDP using a headless browser (Playwright/Puppeteer).
* Check critical functions:

  * Add to Cart button present?
  * Button clickable?
  * Variant selector working?
  * Price visible?
  * Product media visible?
  * JS errors on load?
  * Liquid errors?
  * Page load time > 4 sec?

---

### **2.2 AI Visual Check (Optional in MVP)**

* Take screenshot of the PDP.
* Send to Vision Model (e.g., GPT-4o or o4-mini for cost).
* Ask:

  > “Identify if any elements are broken, overlapping, missing, hidden, or not visible to a typical shopper.”

Return:

* Summary of issues
* Screenshot with bounding boxes (if possible later)

---

### **2.3 Issue Detection (Rules Engine)**

A first-version static rules engine:

#### **Check 1 — Add-to-Cart**

* Button missing
* Button disabled
* JS click intercepted
* Wrong selector

#### **Check 2 — Variants**

* Variant dropdown or swatches not visible
* Changing variant throws JS error
* Add-to-cart fails for variant

#### **Check 3 — Liquid/Theme Issues**

* “Liquid error: …” on page
* Missing snippet
* Section fails to render

#### **Check 4 — UI Breakage**

* Image not loading
* Main image width < 200px
* Elements overlapping (vision AI later)

#### **Check 5 — Performance Warning**

* Page load > 4s
* Script load failures
* App script errors

---

## **3. Dashboard (Merchant UI)**

### **3.1 Home Page**

**Section: “Today’s PDP Health”**

* Green = No issues
* Yellow = 1–2 warnings
* Red = Issues detected

**Section: Last 7 days trend**

* Simple line graph showing number of issues per day.

---

### **3.2 Issues Page**

Table with:

* Page URL
* Issue type
* Severity: High / Medium / Low
* First detected date
* Latest scan date
* “View Details” → shows screenshot, logs, suggestions

---

### **3.3 Settings**

* Enable/disable daily scan
* Select product pages to monitor
* Alert preferences:

  * Email
  * Shopify notification
  * Slack (Phase 2)

---

## **4. Alerts (Critical MVP Feature)**

### When issues are detected:

Send an alert with:

* Product page URL
* Issue name
* Short explanation
* Suggestion

**Example:**

> **⚠ Add-to-Cart Not Working**
> Detected on: /products/blue-tshirt
> The Add-to-Cart button is present but unclickable due to a JavaScript error from “VITALS App”.
> Recommend: disable “Sticky Modal” feature or remove conflicting script.

---

## **5. MVP Tech Stack**

### Backend

* Ruby on Rails 8.1
* Shopify_app gem
* PostgreSQL
* solid_jobs for scheduled scans
* Puppeteer Ruby gem

### Frontend

* Shopify Polaris web components
* App Bridge Auth

### AI (optional for MVP)

* Vision: GPT-4o-mini or o4-mini
* Text: GPT-4o or GPT-5 mini

---

## **6. Data to Store (Minimal)**

### Tables:

#### **1) shops**

* shop_id
* domain
* plan
* settings (jsonb)

#### **2) product_pages**

* shop_id
* product_id
* url
* last_status (green/yellow/red)
* last_scanned_at

#### **3) issues**

* product_page_id
* issue_type
* description
* severity
* detected_at
* resolved_at (nullable)

#### **4) scans**

* shop_id
* product_page_id
* raw_logs (jsonb)
* screenshot_url
* ai_analysis (jsonb)

---

## **7. Scanning Logic**

### **Step-by-step**

1. Select target PDPs (top 3–5 by traffic).
2. Launch headless browser.
3. Load PDP.
4. Capture network errors.
5. Capture JS errors.
6. Check HTML elements (button, variant selector, price, images).
7. Screenshot page.
8. (Optional) Send screenshot to Vision AI.
9. Create issue objects.
10. Save results.
11. Trigger alerts if severity = HIGH.

---

## **8. MVP Scope Cut (Very Important)**

### ❌ Out of MVP

* Auto-fix issues
* In-depth SEO audits
* Theme code scanning
* 100+ product scans
* A/B testing
* Performance optimization

### ✔ Included

* **Basic scanning**
* **Basic AI detection**
* **Simple Polaris UI**
* **Alerts**
* **5 product pages max**

