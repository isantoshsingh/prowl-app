# Prowl — Screencast Plan (Shopify App Review Submission)

**Target length**: 4–5 minutes
**Format**: Screen recording of the Shopify admin with Prowl installed
**Audience**: Shopify App Review Team
**Audio**: Voiceover narration (calm, clear, conversational tone)
**Resolution**: 1920×1080 (16:9), 60fps
**Background music**: Light, unobtrusive ambient track (low volume under voiceover)

---

## Pre-Recording Setup

Before recording, make sure your demo store has:

- [ ] Prowl installed with an active subscription (or trial)
- [ ] 2–3 monitored product pages with scan data
- [ ] At least one **critical** issue detected (e.g., missing ATC or JS error)
- [ ] At least one **healthy** page (green status)
- [ ] A completed scan with a screenshot captured
- [ ] An alert email ready to show (screenshot or real email in a mail client)
- [ ] Onboarding state reset (`shop.update(show_onboarding: true)`) for the opening scene
- [ ] Browser at 100% zoom, no bookmarks bar, minimal distractions
- [ ] Shopify admin in light mode

---

## Scene-by-Scene Script

### Scene 1 — Hook (0:00–0:20)

**Screen**: Static split-screen or text card before the app

> **Voiceover**:
> "Hi, thanks for reviewing Prowl. Prowl is a product page monitoring app that detects silent failures on Shopify storefronts — things like a missing Add to Cart button, broken variant selectors, or images that won't load. In this video, we'll walk you through every feature of the app."

**Visual**: Brief text overlay: *"Product Page Monitoring for Shopify"*

---

### Scene 2 — Installation & Onboarding (0:20–1:00)

**Screen**: Shopify App Store → Prowl listing → "Add app" → Approve permissions

> **Voiceover**:
> "Installation takes about 30 seconds. The app only requests read-only access to the product catalog — it never modifies the store."

**Screen**: Prowl opens → Billing approval screen ($10/month, 14-day free trial) → Approve

> "Merchants get a full 14-day free trial with no limitations. Every feature is available from day one."

**Screen**: Onboarding setup guide appears (3-step checklist)

> "After installation, a setup guide walks the merchant through three steps: add products, run the first scan, and configure alerts."

**Action**: Click to expand Step 1 ("Add products"), then click the "Add products" button.

---

### Scene 3 — Adding Product Pages (1:00–1:40)

**Screen**: Shopify resource picker opens → browse/search products

> **Voiceover**:
> "The product picker uses the standard Shopify resource picker to select which pages to monitor. Merchants would typically choose their highest-traffic products."

**Action**: Select 2–3 products → click "Add"

**Screen**: Product Pages list appears with scanning indicators — spinner + "Scanning…" badge on each row, global "Scans in progress" banner at top

> "As you can see, the selected pages are now being scanned. The UI shows a live scanning indicator while Prowl checks each page. The plan allows monitoring up to 3 products."

**Screen**: After ~30–60 seconds, page auto-refreshes → status updates to "Healthy" or shows detected issues

> "Once the scan completes, the page refreshes automatically and displays the results."

---

### Scene 4 — Running a Scan (1:40–2:20)

**Screen**: Click "Scan now" on a product page

> **Voiceover**:
> "Merchants can trigger a scan at any time. Prowl loads the product page in a real headless browser — just like a customer would — and checks every critical element."

**Screen**: Scan progress banner appears ("Scan in progress" with spinner)

> "It checks for the Add to Cart button, variant selectors, product images, pricing, JavaScript errors, and page load speed."

**Screen**: Scan completes → page refreshes → status updates to "Healthy" or "Critical"

> "Scans take about 45 to 60 seconds. When complete, the result is displayed immediately."

**Screen**: Show the latest screenshot thumbnail → click to open full-size modal

> "Every scan captures a screenshot of the page, so the merchant can see exactly what Prowl saw."

---

### Scene 5 — Reviewing an Issue (2:20–3:20)

**Screen**: Navigate to Dashboard → show critical alert banner → click through to Issues list

> **Voiceover**:
> "When Prowl detects a problem, it surfaces on the dashboard. Let's walk through a critical issue."

**Action**: Click on an issue (e.g., "Missing Add to Cart button")

**Screen**: Issue detail page — title, severity badge, description

> "Each issue includes a plain-language explanation of what went wrong..."

**Screen**: Scroll to screenshot section → click thumbnail to open modal

> "...a screenshot showing exactly what the page looked like at the time of the scan..."

**Screen**: Scroll to "What you can do" section

> "...and step-by-step troubleshooting advice tailored to the specific issue type."

**Screen**: Scroll to technical details (JSON evidence)

> "For merchants with developers on their team, there's a technical details section with the raw diagnostic data."

**Action**: Click "Acknowledge" button → toast confirmation

> "The merchant can acknowledge an issue to stop repeat alerts while they work on a fix."

---

### Scene 6 — Email Alerts (3:20–3:50)

**Screen**: Switch to email client (or show a screenshot of the alert email)

> **Voiceover**:
> "When a critical issue is detected, the merchant receives an email alert with the screenshot, the explanation, and a suggested fix — all inline, no login required."

**Screen**: Highlight the inline screenshot, the explanation text, and the suggested fix box

> "There's also an acknowledge link right in the email, so the merchant can stop alerts without opening the app."

**Screen**: Show the "issues resolved" email

> "When the issue is resolved, a confirmation email is sent so the merchant knows the page is healthy again."

---

### Scene 7 — Settings (3:50–4:15)

**Screen**: Navigate to Settings

> **Voiceover**:
> "In Settings, merchants can set a custom email for alerts, choose between daily or weekly scans, and toggle notifications on or off."

**Action**: Change alert email → change scan frequency → save (show toast: "Settings saved")

**Screen**: Scroll to "Help and support" section

> "There's also a direct link to our support center for merchant assistance."

---

### Scene 8 — Closing (4:15–4:40)

**Screen**: Navigate back to Dashboard showing healthy status ("All systems operational")

> **Voiceover**:
> "Prowl runs automatically every day at 6 AM UTC, so merchants don't need to think about it. If something breaks, they'll know within hours — not days."

> "That covers the full functionality of Prowl. The app offers a 14-day free trial with no limitations, followed by a $10/month subscription. Thank you for reviewing Prowl — we're happy to answer any questions."

**Screen**: Fade to card with:
- Prowl logo
- "14-day free trial · $10/month"
- "Thank you for reviewing Prowl"

---

## Recording Tips

1. **Pace**: Don't rush. Pause briefly after each action so viewers can follow.
2. **Cursor**: Use a visible cursor highlight (yellow circle) so viewers can track clicks.
3. **Zoom**: Use post-production zoom-ins for important UI elements (issue detail, screenshot modal, email content).
4. **Transitions**: Simple crossfade between scenes. No flashy transitions.
5. **Captions**: Add English subtitles (required by Shopify if no audio, recommended regardless for accessibility).
6. **Thumbnail**: Use a frame from Scene 5 (issue detail with screenshot) — it's the most visually compelling.

## YouTube Upload Settings

- **Title**: Prowl — Product Page Monitoring for Shopify | App Review Demo
- **Description**: Screencast for the Shopify App Review team. Demonstrates how Prowl monitors Shopify product pages for broken Add to Cart buttons, missing images, JavaScript errors, and more. Shows the full merchant experience: installation, scanning, issue detection, email alerts, and settings.
- **Tags**: Shopify app, product page monitoring, Shopify QA, ecommerce monitoring, broken Add to Cart, Shopify store monitoring
- **Visibility**: Unlisted (for Shopify review only)
