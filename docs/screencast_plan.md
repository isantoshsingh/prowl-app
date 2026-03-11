# Prowl — Screencast Plan (YouTube / App Store Submission)

**Target length**: 4–5 minutes
**Format**: Screen recording of the Shopify admin with Prowl installed
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
> "Your product pages can break without anyone noticing — a missing Add to Cart button, a broken variant selector, images that won't load. Your site looks fine from the outside, but customers can't buy. Prowl catches these problems before your customers leave."

**Visual**: Brief text overlay: *"Silent breaks cost you sales every day."*

---

### Scene 2 — Installation & Onboarding (0:20–1:00)

**Screen**: Shopify App Store → Prowl listing → "Add app" → Approve permissions

> **Voiceover**:
> "Installing Prowl takes about 30 seconds. It only requests read-only access to your product catalog — it never modifies your store."

**Screen**: Prowl opens → Billing approval screen ($10/month, 14-day free trial) → Approve

> "You get a full 14-day free trial with no limitations. Every feature is available from day one."

**Screen**: Onboarding setup guide appears (3-step checklist)

> "Once installed, the setup guide walks you through three steps: add your products, run your first scan, and configure your alerts."

**Action**: Click to expand Step 1 ("Add products"), then click the "Add products" button.

---

### Scene 3 — Adding Product Pages (1:00–1:40)

**Screen**: Shopify resource picker opens → browse/search products

> **Voiceover**:
> "The product picker lets you choose which pages to monitor. We recommend your highest-traffic or highest-revenue products — the ones where a broken page costs you the most."

**Action**: Select 2–3 products → click "Add"

**Screen**: Product Pages list appears with products showing "Pending" status

> "Your pages are now being tracked. You can monitor up to 3 products."

---

### Scene 4 — Running a Scan (1:40–2:20)

**Screen**: Click "Scan now" on a product page

> **Voiceover**:
> "You can trigger a scan at any time. Prowl loads your product page in a real browser — just like a customer would — and checks every critical element."

**Screen**: Scan progress banner appears ("Scan in progress" with spinner)

> "It checks for the Add to Cart button, variant selectors, product images, pricing, JavaScript errors, and page load speed."

**Screen**: Scan completes → page refreshes → status updates to "Healthy" or "Critical"

> "Scans take about 45 to 60 seconds. When it's done, you'll see the result immediately."

**Screen**: Show the latest screenshot thumbnail → click to open full-size modal

> "Every scan captures a screenshot of your page, so you can see exactly what Prowl saw."

---

### Scene 5 — Reviewing an Issue (2:20–3:20)

**Screen**: Navigate to Dashboard → show critical alert banner → click through to Issues list

> **Voiceover**:
> "When Prowl finds a problem, it shows up right on your dashboard. Let's look at a critical issue."

**Action**: Click on an issue (e.g., "Missing Add to Cart button")

**Screen**: Issue detail page — title, severity badge, description

> "Each issue includes a plain-language explanation of what went wrong..."

**Screen**: Scroll to screenshot section → click thumbnail to open modal

> "...a screenshot showing exactly what the page looked like..."

**Screen**: Scroll to "What you can do" section

> "...and step-by-step troubleshooting advice tailored to the specific issue type."

**Screen**: Scroll to technical details (JSON evidence)

> "For developers, there's a technical details section with the raw diagnostic data."

**Action**: Click "Acknowledge" button → toast confirmation

> "If you're already aware of the issue and working on a fix, click Acknowledge to stop repeat alerts."

---

### Scene 6 — Email Alerts (3:20–3:50)

**Screen**: Switch to email client (or show a screenshot of the alert email)

> **Voiceover**:
> "When a critical issue is detected, you get an email alert with the screenshot, the explanation, and a suggested fix — all inline, no login required."

**Screen**: Highlight the inline screenshot, the explanation text, and the suggested fix box

> "There's also an acknowledge link right in the email, so you can stop alerts without opening the app."

**Screen**: Show the "issues resolved" email

> "And when the issue is fixed, you get a confirmation email so you know your page is healthy again."

---

### Scene 7 — Settings (3:50–4:15)

**Screen**: Navigate to Settings

> **Voiceover**:
> "In Settings, you can set a custom email for alerts, choose between daily or weekly scans, and toggle notifications on or off."

**Action**: Change alert email → change scan frequency → save (show toast: "Settings saved")

**Screen**: Scroll to "Help and support" section

> "There's also a direct link to our support center if you ever need help."

---

### Scene 8 — Closing (4:15–4:40)

**Screen**: Navigate back to Dashboard showing healthy status ("All systems operational")

> **Voiceover**:
> "Prowl runs every day at 6 AM UTC, so you don't have to think about it. If something breaks, you'll know within hours — not days."

> "Start your free 14-day trial today. No limitations, no credit card surprises. Just peace of mind that your product pages are working."

**Screen**: Fade to card with:
- Prowl logo
- "14-day free trial · $10/month"
- "Install from the Shopify App Store"

---

## Recording Tips

1. **Pace**: Don't rush. Pause briefly after each action so viewers can follow.
2. **Cursor**: Use a visible cursor highlight (yellow circle) so viewers can track clicks.
3. **Zoom**: Use post-production zoom-ins for important UI elements (issue detail, screenshot modal, email content).
4. **Transitions**: Simple crossfade between scenes. No flashy transitions.
5. **Captions**: Add English subtitles (required by Shopify if no audio, recommended regardless for accessibility).
6. **Thumbnail**: Use a frame from Scene 5 (issue detail with screenshot) — it's the most visually compelling.

## YouTube Upload Settings

- **Title**: Prowl — Product Page Monitoring for Shopify | App Demo
- **Description**: See how Prowl monitors your Shopify product pages for broken Add to Cart buttons, missing images, JavaScript errors, and more. Get alerted with screenshots and suggested fixes before customers notice. 14-day free trial, $10/month.
- **Tags**: Shopify app, product page monitoring, Shopify QA, ecommerce monitoring, broken Add to Cart, Shopify store monitoring
- **Visibility**: Public (or Unlisted if only for Shopify review)
