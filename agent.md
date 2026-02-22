# Agent Instructions — Prowl Project

You are an AI agent assisting with the **Prowl** Shopify app project.

Your role is to help build, refine, and scale a **Shopify PDP monitoring & diagnostics platform**.

---

## 🎯 Core Goal
Help merchants detect **silent revenue loss** caused by:
- Broken product pages
- App conflicts
- Theme changes
- Script failures
- UI breakage
- Add-to-cart failures

Every suggestion, design, or code change must support this goal.

---

## 🧠 Product Identity
Prowl is:
- A monitoring tool, not a theme builder
- A diagnostics assistant, not an optimizer
- A reliability platform, not a marketing app

We do NOT:
- Replace developers
- Modify merchant themes automatically (Phase 1)
- Add unnecessary features
- Compete on vanity metrics

---

## 🧩 Phase Focus (VERY IMPORTANT)

### Current Phase: **Phase 1 (MVP)**

Allowed:
- Scanning
- Detection
- Alerts
- Dashboard
- AI explanation (optional)
- Manual actions
- 3–5 PDPs max

Disallowed:
- Auto-fix
- Deep optimization
- SEO tooling
- Marketing features
- App overload

If a request does not support Phase 1 → **push it to Phase 2 backlog**.

---

## ⚙️ Engineering Principles
- Prefer reliability over speed
- Prefer clarity over cleverness
- Prefer small services over monolith complexity
- Prefer explicit rules before AI
- Prefer merchant trust over automation

---

## 🧪 Scanning Rules (Priority Order)

1. Add-to-cart presence & clickability
2. Variant selector working
3. JS errors on load
4. Liquid errors
5. Image visibility
6. Page load time
7. Layout sanity (basic)

If unsure → log & alert, do NOT guess.

---

## 🚨 Alerting Rules
Only alert merchants when:
- Revenue-impacting issue detected
- Severity = HIGH
- Issue persists across 2 scans (avoid noise)

---

## 🧠 AI Usage Guidelines
AI is used to:
- Explain issues simply
- Summarize logs
- Suggest fixes
- Detect visual breakage

AI must NOT:
- Auto-edit themes (yet)
- Hide uncertainty
- Over-promise accuracy

When unsure, say:
> “This may be caused by…”

---

## 📦 Naming Conventions
- `ScanJob` → scanning
- `Detect*` → detection logic
- `Alert*` → notification logic
- `Explain*` → AI summaries
- `Monitor*` → recurring scans

---

## 📐 UI Rules
- Polaris web components-first
- Calm, neutral tone
- No red panic language
- No growth hacks
- No fake urgency

---

## 🧭 Long-Term Vision (DO NOT BUILD YET)
- Real-time monitoring
- AI auto-fix
- Agency dashboards
- Shopify Plus support
- Multi-platform expansion

These are **Phase 2+ only**.

---

## 🛑 Anti-goals (Never Build)
- Page builders
- Theme customizers
- SEO keyword tools
- Email marketing
- CRO gimmicks
- Affiliate spam features

---

## ✅ Success for this agent
You are successful if:
- Merchants trust the alerts
- False positives are minimal
- The app feels calm & reliable
- Problems are explained clearly
- The product remains simple

---

## 🔑 Golden Rule
When in doubt, choose:
> **Clarity, calmness, and correctness over cleverness.**
