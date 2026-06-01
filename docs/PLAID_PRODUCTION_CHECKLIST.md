# Plaid Production Readiness Checklist — Budget Tracker

Last updated: 2026-05-31

This document lists what is **already implemented in this repo**, what **Plaid requires before real banks**, and **security controls beyond baseline fintech practice**.

Architecture (locked):

```
iOS (LinkKit only) → Supabase Edge Functions (JWT auth) → Plaid API → Bank
                              ↓
                    Supabase Vault (access_token)
                    Postgres + RLS (accounts, transactions)
```

---

## Current implementation status

| Capability | Status | Location |
|------------|--------|----------|
| Link token (new connections) | Done | `plaid-create-link-token` |
| Link update mode (re-auth) | Done | `plaid-create-update-link-token` |
| Public token exchange → Vault | Done | `plaid-exchange-token` |
| Transaction sync (`/transactions/sync`) | Done | `plaid-sync-transactions`, `_shared/plaid-sync.ts` |
| Account refresh | Done | `plaid-get-accounts` |
| Disconnect / token revocation | Done | `plaid-remove-item` (+ `/item/remove`) |
| Webhook receiver | Done | `plaid-webhook` (JWT + body hash verification) |
| Webhook idempotency | Done | `plaid_webhook_events.payload_hash` unique |
| Item status tracking | Done | `plaid_items.status`, error fields |
| Security audit log | Done | `security_audit_log` |
| Per-user rate limits (Edge Functions) | Done | `_shared/security.ts` |
| iOS reconnect / disconnect UI | Done | `AccountsView`, `PlaidLinkView` |
| Face ID / device passcode gate | Done | `BiometricGate.swift` |
| ATS (no arbitrary loads) | Done | `BudgetTracker/Info.plist` |

---

## Phase A — Finish Sandbox (do this now)

1. **Deploy backend** (migrations + all 7 Edge Functions):

   ```powershell
   cd C:\Users\dsmcc\Projects\Users\m1\Desktop\BudgetTracker
   .\scripts\deploy-backend.ps1
   ```

2. **Confirm webhook URL** is set automatically to:

   `https://dldbcbituquxedlkeefu.supabase.co/functions/v1/plaid-webhook`

3. **Run sandbox smoke test**:

   ```powershell
   .\scripts\test-plaid-sandbox.ps1
   ```

4. **Test webhook path** in Plaid Dashboard → Sandbox → fire `SYNC_UPDATES_AVAILABLE` for a linked item (or use `/sandbox/item/fire_webhook`).

5. **Verify iOS flows**: link bank → sync → disconnect → reconnect (update mode).

---

## Phase B — Plaid Dashboard setup (before Development / Production)

### 1. Request Production / Development access

- In [Plaid Dashboard](https://dashboard.plaid.com/) → **Team Settings → Keys**, request access for your use case (personal finance / account aggregation).
- Plaid reviews your application description, data retention, and privacy posture.
- Start with **Development** environment for a small set of real institutions before **Production**.

### 2. Environment keys

| Environment | When | Secret env var |
|-------------|------|----------------|
| Sandbox | Now | `PLAID_SANDBOX_SECRET` locally → `PLAID_SECRET` in Supabase |
| Development | Real bank testing | `PLAID_DEVELOPMENT_SECRET` |
| Production | Live personal use | `PLAID_PRODUCTION_SECRET` |

Update Supabase secret when promoting:

```powershell
supabase secrets set PLAID_ENV=development PLAID_SECRET=<development_secret>
```

### 3. Allowed products

- Enable **Transactions** only (avoid billing for unused products).
- Request **730 days** of history (already set in link token `transactions.days_requested`).

### 4. OAuth + iOS Universal Links (required for most US banks in Production)

Most major US institutions use OAuth. For iOS you must:

1. Register a **redirect URI** in Plaid Dashboard (HTTPS Universal Link), e.g.  
   `https://budgettracker.app/plaid/oauth` (use your real domain).
2. Add `PLAID_REDIRECT_URI=<that URI>` to `Config/SECRETS.local.md` and redeploy secrets.
3. Configure **Apple App Site Association** file on that domain pointing to `com.budgettracker.app`.
4. Handle OAuth return in the iOS app (LinkKit `Handler` must stay alive — see [Plaid iOS OAuth guide](https://plaid.com/docs/link/ios/)).

Until OAuth is configured, Sandbox and some Development institutions work; many Production banks will fail Link without redirect URI.

### 5. Webhooks (required for ongoing sync)

Plaid **requires or strongly recommends** webhooks when:

- You call Plaid repeatedly over time (not just once after Link).
- You access transactions after the user linked.

**Already configured:** `PLAID_WEBHOOK_URL` on link token create; receiver verifies `Plaid-Verification` JWT + SHA-256 body hash.

**Operational notes:**

- Webhooks must return **HTTP 200 within 10 seconds** (receiver syncs inline today; monitor latency).
- Plaid retries up to **24 hours** with exponential backoff.
- Handle **duplicates** (idempotency table) and **out-of-order** delivery.
- Plaid webhook source IPs (subject to change): `52.21.26.131`, `52.21.47.157`, `52.41.247.19`, `52.88.82.239`.

### 6. Update mode (re-auth)

When users change bank passwords or consent expires:

- Plaid sends `ITEM` / `ERROR` with `ITEM_LOGIN_REQUIRED`.
- App shows **Reconnect** → `plaid-create-update-link-token` → Link update mode.
- Do **not** re-exchange public token in update mode (access token unchanged).

### 7. Item removal / consent revocation

When user disconnects in app:

- Call `plaid-remove-item` → Plaid `/item/remove` + Vault delete + local data purge.
- Handle `USER_PERMISSION_REVOKED` webhook → mark item `revoked`.

### 8. Compliance & policy (Plaid Launch Center)

Complete Plaid **Launch Center** checklist in Dashboard:

- Privacy policy URL describing Plaid data use.
- Accurate app name / logo in Link (`client_name: "Budget Tracker"`).
- Data retention statement (personal app: minimal retention, user can disconnect).
- Do not store credentials users enter in Link (Plaid handles this — we never see them).

### 9. Monitoring (recommended before Production)

| Signal | Action |
|--------|--------|
| Link conversion rate | Dashboard → Link analytics |
| Webhook failures | Supabase function logs + `plaid_webhook_events` |
| `ITEM_LOGIN_REQUIRED` spikes | Surface reconnect UI; check institution outages |
| Sync errors | Edge Function logs; `plaid_items.error_code` |
| Vault access failures | Supabase logs for RPC errors |

---

## Phase C — Security controls (defense in depth)

### Server-side (implemented)

| Control | Purpose |
|---------|---------|
| Plaid secrets + access tokens **never on iOS** | Stolen device ≠ stolen bank access |
| Supabase Vault for `access_token` | Encrypted at rest, service-role RPC only |
| JWT auth on all user-facing Edge Functions | Anonymous cannot invoke Plaid |
| `plaid-webhook` JWT verification disabled (Plaid has no Supabase JWT) | Uses Plaid-signed webhook JWT instead |
| Plaid webhook **ES256 JWT + body SHA-256** | Prevents forged webhook injection |
| Webhook **idempotency** (`payload_hash`) | Safe retries / duplicates |
| **Rate limits** per user per endpoint | Abuse / credential stuffing mitigation |
| **Ownership checks** (`assertPlaidItemOwnership`) | User A cannot act on User B's item |
| **Conflict check** on exchange | Same item cannot bind to two users |
| **Audit log** (link, sync, remove) | Forensics without logging secrets |
| **Generic client errors** | No internal stack traces to iOS |
| Security response headers | `nosniff`, `DENY` framing, `no-store` |
| RLS on user tables + audit log read own rows | DB layer isolation |
| `/item/remove` on disconnect | Revoke Plaid-side consent |

### iOS (implemented)

| Control | Purpose |
|---------|---------|
| Face ID / Touch ID with passcode fallback | Device-level gate before financial UI |
| Lock on background | Re-auth when app leaves foreground |
| ATS (`NSAllowsArbitraryLoads = false`) | TLS-only networking |
| API keys via `APIKeys` resolution | No hardcoded secrets in Swift |
| LinkKit only — no direct Plaid API | Attack surface minimized |
| Account numbers: **mask (last 4) only** | Reduced PCI-adjacent exposure |

### Recommended next hardening (optional)

| Item | Notes |
|------|-------|
| Supabase Auth MFA | Enable TOTP for account takeover protection |
| Auth session timebox | `[auth.sessions]` in `config.toml` — e.g. 7-day max |
| Certificate pinning | High effort; ATS usually sufficient for personal app |
| WAF / IP allowlist on webhook | Plaid IPs change; prefer JWT verification (done) |
| Async webhook queue | If sync latency exceeds 10s, enqueue and return 200 immediately |
| Credential rotation schedule | Rotate Plaid secret, Supabase service role, Gemini quarterly |
| GitHub secret scanning | Already private repo; enable secret scanning alerts |

---

## Phase D — Promote environment checklist

When moving Sandbox → Development → Production:

- [ ] Plaid Dashboard access approved for target environment
- [ ] `PLAID_ENV` and `PLAID_SECRET` updated in Supabase secrets
- [ ] `PLAID_WEBHOOK_URL` still points to deployed `plaid-webhook`
- [ ] `PLAID_REDIRECT_URI` set + Universal Link configured (Production OAuth banks)
- [ ] Link tested with at least one real institution in Development
- [ ] Webhook fires and sync completes without manual pull
- [ ] Update mode tested (Sandbox: `/sandbox/item/reset_login`)
- [ ] Disconnect removes Vault token + Plaid item
- [ ] Privacy policy / Launch Center items complete
- [ ] All secrets rotated if ever exposed in chat or logs

---

## Quick reference — Edge Functions

| Function | Auth | Purpose |
|----------|------|---------|
| `plaid-create-link-token` | User JWT | New Link session |
| `plaid-create-update-link-token` | User JWT | Re-auth (update mode) |
| `plaid-exchange-token` | User JWT | Exchange public token → Vault |
| `plaid-get-accounts` | User JWT | Refresh balances |
| `plaid-sync-transactions` | User JWT | Manual / fallback sync |
| `plaid-remove-item` | User JWT | Disconnect bank |
| `plaid-webhook` | Plaid JWT | Push sync + item status |

Deploy webhook without Supabase JWT verification:

```powershell
supabase functions deploy plaid-webhook --no-verify-jwt
```

---

## Related docs

- `docs/PROJECT_BRIEF.md` — architecture and feature scope
- `AI_PROJECT_INSTRUCTIONS.txt` — agent security rules
- [Plaid Launch Center](https://dashboard.plaid.com/overview)
- [Plaid webhook verification](https://plaid.com/docs/api/webhooks/webhook-verification/)
- [Plaid update mode](https://plaid.com/docs/link/update-mode/)
- [Plaid iOS Link](https://plaid.com/docs/link/ios/)
