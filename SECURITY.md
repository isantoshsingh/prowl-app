# Security Policy — Prowl

Prowl monitors Shopify product pages and handles sensitive store data.
Security, trust, and privacy are non-negotiable.

This document defines how security is handled in Phase 1 (MVP) and beyond.

---

## 🔒 Data We Access

Prowl only accesses what is necessary:

- Store domain
- Product page URLs
- Theme-rendered HTML
- JS console errors
- Network errors
- Screenshots of public PDPs
- Scan metadata (timestamps, results)
- Merchant email (for alerts)

We **do not** access:
- Customer PII
- Orders
- Payments
- Checkout data
- Admin credentials
- Store secrets

---

## 🔐 Data Storage

- PostgreSQL for structured data
- Encrypted credentials using Rails encrypted credentials
- Screenshots stored in private object storage (signed URLs only)
- Logs truncated to remove tokens, cookies, or headers

---

## 🔑 Authentication & Authorization

- Shopify OAuth (Online + Offline tokens)
- App Bridge session authentication
- Store-level isolation (strict scoping)
- Admin-only access

---

## 🧪 Scanning Isolation

All scanning runs:
- In isolated workers
- Without session cookies
- Without admin privileges
- As a public visitor
- With strict timeouts

No scan can:
- Modify store data
- Execute admin actions
- Access private content

---

## 🧠 AI Security (Phase 1)

- Only public page data is sent to AI models
- No merchant secrets or credentials
- AI outputs are advisory only
- No auto-fix or code writes in Phase 1

---

## 🛡 Rate Limiting & Abuse Prevention

- Scan frequency limited per store
- Manual rescans throttled
- Background workers protected
- Queue retries capped

---

## 🔍 Logging & Monitoring

- All scan jobs are logged
- Error traces stored without sensitive headers
- Alerts sent on repeated failures
- Manual review for false positives

---

## 📣 Vulnerability Disclosure

If you find a security issue:
- Email: security@prowlapp.com
- Include steps to reproduce
- No public disclosure before fix

We commit to responding within **48 hours**.

---

## 🔄 Future Enhancements (Phase 2+)

- SOC2 readiness
- Signed scan integrity hashes
- Theme diff checksum validation
- Role-based access control (RBAC)
- Audit logs for all actions

---

## ❤️ Our Promise
Prowl exists to **protect merchants**, not spy on them.

Trust is the product.
