# Product Requirements Document (PRD)
## Prowl — Phase 1 (MVP)

---

## 1. Objective
Detect and alert merchants when their Shopify product pages (PDPs) break due to app conflicts, theme changes, or frontend errors.

---

## 2. User Personas

### Merchant
- Non-technical
- Revenue-focused
- Wants early warning
- Hates debugging

### Developer / Agency
- Wants reliable detection
- Needs evidence (logs + screenshots)
- Wants clarity, not noise

---

## 3. Problems to Solve
- PDP breaks silently
- Merchants notice after revenue drop
- No monitoring exists
- Debugging is time-consuming

---

## 4. Non-goals
- Auto-fix
- Optimization
- Theme editing
- CRO tools
- SEO tools
- Marketing features

---

## 5. Core User Flows

### 5.1 Install Flow
1. Install app
2. OAuth approval
3. Select 3–5 product pages
4. Enable daily scan
5. Done

---

### 5.2 Scan Flow
1. Solid Queue triggers scan
2. Puppeteer loads PDP
3. Capture errors, HTML, screenshot
4. Detection engine runs
5. Issues created
6. Alert if severity = high

---

### 5.3 Alert Flow
1. Issue detected twice
2. Alert sent (email / admin)
3. Merchant clicks link
4. Sees issue detail
5. Rescan or acknowledge

---

## 6. Functional Requirements

### 6.1 Scanning
- Must detect missing ATC
- Must detect JS errors
- Must detect Liquid errors
- Must detect missing images
- Must detect variant failure

---

### 6.2 Dashboard
- Health summary
- Issues table
- Trend graph
- Manual rescan

---

### 6.3 Alerts
- Email + Admin
- No alert spam
- Clear language
- Link to detail page

---

### 6.4 Settings
- Page selection
- Alert preferences
- Scan frequency
- Save confirmation

---

## 7. Technical Constraints

- Must use Puppeteer Ruby gem
- Must use Solid Queue
- Must use Shopify Polaris Web Components
- Must follow Shopify App Home UX guidelines
- Must support 100 stores in MVP
- Must scan under 30s per page

---

## 8. UX Principles
- Calm
- Minimal
- Non-alarming
- Clear language
- Shopify-native feel

---

## 9. Success Metrics
- Installs → paid conversion
- Alert trust rate
- False positive rate
- Weekly active stores
- Support tickets

---

## 10. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| False positives | 2-scan confirmation |
| Scan flakiness | Retry with backoff |
| Merchant panic | Calm language |
| Theme diversity | Rule-based + logs |
| App conflicts | Explain, don’t auto-fix |

---

## 11. Open Questions (To Validate)
- Which alerts feel most valuable?
- What is acceptable scan frequency?
- Do merchants want AI explanations?
- What pricing triggers upgrade?

---

## 12. Acceptance Criteria
MVP is complete when:
- Merchants trust alerts
- Issues are actionable
- App feels calm
- System is stable for 30 days

---

## 13. Pricing & Trial Requirements
- App must require payment approval during install
- 14-day free trial
- Billing handled via Shopify Billing API
- No functionality lock during trial
- Alerts + scans fully enabled during trial

