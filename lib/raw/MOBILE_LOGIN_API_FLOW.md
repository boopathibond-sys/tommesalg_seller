# Tommesalg Mobile Login API Flow (Buyer and Seller apps)

Audience: Flutter developers on the **Buyer** and **Seller** apps.
Compiled 2026-10-10 from:
- `MOBILE_REGISTRATION_AUTH_INTEGRATION.md`
- `Tommesalg_Mobile_Google_Apple_Auth_Integration_Guide.docx`
- the buyer app's working implementation
- live probes of `https://tommesalg.no`

The backend's `MOBILE_AUTH_CONTRACT_V2.md` wins on any conflict. All sample values are fake.

Status markers used below:
- ✅ **Verified**: implemented in the buyer app and/or confirmed against the live server.
- 📄 **Documented**: stated by a backend handoff doc but not yet exercised end to end.
- ⚠️ **Open**: not settled; confirm with the backend before relying on it.

---

## 1. Architecture

```
Flutter app ──► Tommesalg API ──► Amazon Cognito   (passwords, tokens, Google/Apple federation)
                              ──► Redis            (signup OTP, OAuth state, mobile exchange codes, rate limits)
                              ──► Aurora Postgres  (users)

Identity: Cognito sub ─► users.auth_subject ─► users.id     ← use users.id everywhere
```

- The app talks **only** to the Tommesalg API. It never calls Cognito directly, holds no Cognito, Google or Apple secrets, and uses **no Supabase auth**.
- Every login method ends with the same session: a **Cognito access token plus refresh token**. Refresh, logout and API calls are identical whichever way the user signed in.
- Send `Authorization: Bearer <cognito_access_token>` on every API call. Never send an ID token (Cognito, Google or Apple); those are rejected with 401.
- The application user id is `data.id` from `/me` (or `user.id` from the social exchange). Never use the Cognito `sub`.

## 2. Base URL and response envelopes

| Env | API origin |
|---|---|
| Production | `https://tommesalg.no` ✅ |
| Staging / Local | from the backend team (`BASE_URL` in the Postman environments). Local is `http://localhost:3000` ⚠️ |

No trailing slash. Never create test accounts against production.

**Two response shapes exist. Parse them separately.**

| Routes | Success | Error |
|---|---|---|
| `/api/v1/...` (V1) | `{ "success": true, "data": { ... } }` | `{ "success": false, "error": { "code": "...", "message": "..." } }` |
| `/api/auth/cognito/*` and `/api/auth/vipps/*` (raw) | flat snake_case JSON, **no envelope** | top-level `{ "error": "invalid_code" }` |

Branch on `error.code` (or the raw `error` string), never on `message`.

## 3. Endpoint catalogue

| # | Purpose | Method + path | Auth | Status |
|---|---|---|---|---|
| 1 | Register (email) | `POST /api/v1/buyer/auth/register` | none | ✅ |
| 2 | Verify signup OTP | `POST /api/v1/buyer/auth/verify-otp` | none | ✅ |
| 3 | Resend signup OTP | `POST /api/v1/buyer/auth/resend-otp` | none | ✅ |
| 4 | Login (email + password) | `POST /api/v1/auth/login` | none | ✅ |
| 5 | Start Google / Apple | `GET /api/auth/cognito/authorize` | none (browser) | ✅ (redirect probed) |
| 6 | Browser callback | `GET /api/auth/cognito/callback` | backend only; never call it from Flutter | ✅ |
| 7 | Exchange social code | `POST /api/auth/cognito/mobile-exchange` | one-time code | ✅ (error shape probed) |
| 8 | Provision profile | `POST /api/v1/auth/ensure-profile` | Bearer | ✅ |
| 9 | Buyer profile / role | `GET /api/v1/auth/me` | Bearer | ✅ |
| 10 | Seller profile / role | `GET /api/v1/seller/auth/me` | Bearer | 📄 |
| 11 | Refresh | `POST /api/v1/auth/refresh` | refresh token in body | ✅ |
| 12 | Logout | `POST /api/v1/auth/logout` | refresh token in body | ✅ |
| 13 | Forgot password | `POST /api/v1/buyer/auth/forgot-password` | none | ✅ |
| 14 | Reset password | `POST /api/v1/auth/reset-password` | none | ✅ |
| 15 | Notification email status | `GET /api/v1/auth/notification-email` | Bearer | ✅ |
| 16 | Notification email: send OTP | `POST /api/v1/auth/notification-email/request` | Bearer | ✅ |
| 17 | Notification email: verify OTP | `POST /api/v1/auth/notification-email/verify` | Bearer | ✅ |
| 18 | Start Vipps | `GET /api/auth/vipps/authorize` | none (browser) | ⚠️ see §10 |
| 19 | Exchange Vipps code | `POST /api/auth/vipps/mobile-exchange` | one-time code | ⚠️ see §10 |

**Retired. Do not call:** `POST /api/auth/signup` (410), the cookie web routes `/api/auth/ensure-profile` and `/api/auth/notification-email/*`, and `/api/auth/google/authorize`. That last one is the web cookie flow.

> **Seller app note.** Registration (#1–3) and forgot-password (#13) live under `/buyer/`. There is no separate seller registration. A seller is a buyer account that has passed seller onboarding and approval. See §11.

---

## 4. Flow A: Email registration → login

```
Register ──► email OTP ──► Verify OTP (no tokens) ──► Login ──► [ensure-profile] ──► /me
```

### 4.1 Register: `POST /api/v1/buyer/auth/register`

```json
{ "email": "buyer@example.com", "password": "SecurePass1!", "firstName": "John", "lastName": "Doe",
  "phone": "+4712345678", "dateOfBirth": "2000-01-15", "gender": "male" }
```

- Required fields: `email`, `password`, `firstName`, `lastName`.
- Optional fields:
  - `phone`: E.164, 5–30 chars.
  - `dateOfBirth`: `YYYY-MM-DD`; a minimum age is enforced.
  - `gender`: `male|female|other|prefer_not_to_say`.
- Empty strings count as omitted.
- **Password policy:** 6–128 chars, with at least one lowercase letter, one uppercase letter, one digit and one symbol. Validate on the client with the same rule.

```json
200 { "success": true, "data": { "email": "buyer@example.com", "otpSent": true, "message": "..." } }
```

No tokens are returned. Errors: `400 VALIDATION_ERROR` (blocked domain, under age, bad field) and `409 CONFLICT` (account exists → offer sign-in).

### 4.2 Verify: `POST /api/v1/buyer/auth/verify-otp`

```json
{ "email": "buyer@example.com", "otp": "123456" }
```
```json
200 { "success": true, "data": { "verified": true,
      "user": { "id": "<uuid>", "email": "...", "displayName": "John Doe", "role": "buyer", "verified": true } } }
```

- **No tokens are returned.**
- The code is 6 digits, valid for 15 minutes, and locks after 5 wrong attempts.
- Every failure (wrong, expired, used, locked, unknown email) returns `401 UNAUTHORIZED`. Show "Invalid or expired code" and offer resend.

### 4.3 Resend: `POST /api/v1/buyer/auth/resend-otp`

- Body: `{ "email": "..." }`. It always returns `200 { email, otpSent: true, message }`.
- Resending invalidates the previous code.
- Limits: a 30 s cooldown and at most 5 per 15 minutes. Disable the button for 30 s and honour `Retry-After` on `429`.

### 4.4 Then log in

Call §5 immediately with the email and password the user just typed. Keep the password in memory only for this hand-off, then discard it.

---

## 5. Flow B: Email + password login

### `POST /api/v1/auth/login`

```json
{ "email": "buyer@example.com", "password": "SecurePass1!", "client": "mobile" }
```

**`"client": "mobile"` is mandatory.** Without it the server treats the call as web: it sets a cookie and returns no tokens.

```json
200 { "success": true, "data": { "authenticated": true, "accessToken": "<access>", "refreshToken": "<refresh>",
      "expiresIn": 3600, "tokenType": "Bearer", "appIdentity": "mapped" } }
```

| Status | Meaning | App behaviour |
|---|---|---|
| `401 UNAUTHORIZED` | wrong password, unknown, unverified or reset-required account (all generic) | "Invalid email or password" |
| `403 FORBIDDEN` | suspended | restricted-account message |
| `429` | 20 per 15 min per IP, 10 per 15 min per email | wait for `Retry-After` |
| `503` | Cognito or session store unavailable | "temporarily unavailable" |

After a successful login:
1. Store both tokens (§8).
2. If `appIdentity == "unmapped"`, call `POST /api/v1/auth/ensure-profile` (§7.1).
3. Call `/me` (§7.2).

On any failed login, clear stored tokens.

---

## 6. Flow C: Continue with Google / Continue with Apple

Both providers use the **same server-managed Cognito Hosted-UI flow**. No native Google/Apple SDK is involved, and there is **no endpoint that accepts a provider ID token**. Both buttons handle sign-up and returning sign-in alike: the backend decides whether a profile must be created.

```
App ──open OS auth browser──► GET /api/auth/cognito/authorize ──307──► Cognito Hosted UI ──► Google / Apple
                                                                                          │
App ◄── deep link ?code=… ◄── 307 ◄── GET /api/auth/cognito/callback ◄────────────────────┘
 │        (backend provisions the app profile and stores tokens behind a one-time code in Redis)
 └──► POST /api/auth/cognito/mobile-exchange {code} ──► tokens ──► ensure-profile ──► /me
```

### 6.1 Start: `GET /api/auth/cognito/authorize` (open in a browser, not via Dio)

| Param | Value |
|---|---|
| `identity_provider` | `Google` or `SignInWithApple`. **Case-sensitive**: `Apple` → `400 unsupported_identity_provider` ✅ |
| `mobile` | `1` (required for a deep-link return) |
| `redirect` | the app's **allowlisted** custom-scheme deep link, URL-encoded |
| `mode` | `login` (or `signup` on a signup screen; same backend path) |
| `next` | optional safe internal web path such as `/auctions`. The app chooses its own screen after `/me`. |

```
GET https://tommesalg.no/api/auth/cognito/authorize?identity_provider=Google&mobile=1
    &redirect=no.tommesalg.buyer%3A%2F%2Fauth%2Fvipps%2Fgoogle&mode=login
```

**Deep-link allowlist (⚠️ open).** The backend accepts only redirects matching `MOBILE_AUTH_DEEP_LINK_PREFIXES` (or the legacy `VIPPS_MOBILE_DEEP_LINK_PREFIXES`).
- As probed on production on 2026-10-10, only `no.tommesalg.buyer://auth/vipps…` passes.
- `…://auth/google` and `…://auth` return `400 invalid_redirect` (`redirect_not_allowed`).
- HTTP(S) redirects are rejected (`http_redirect_not_allowed`).
- The Buyer app therefore uses `no.tommesalg.buyer://auth/vipps/google` and `…/vipps/apple`.
- **The Seller app needs its own scheme added to the allowlist by the backend.** Do not reuse the buyer scheme, or the buyer app may catch the callback.

Authorize errors (JSON, shown in the browser unless you pre-check):

| Status | `error` | Action |
|---|---|---|
| 400 | `unsupported_identity_provider` | wrong provider value; no retry |
| 400 | `invalid_redirect` | deep link not allowlisted; fix config |
| 503 | `mobile_auth_unavailable` | OAuth state store down; show a temporary error |

> Buyer-app technique: first send a background `GET` to the same URL with redirects disabled. `3xx` means OK, so open the browser. `4xx/5xx` means show a localized error. The extra state it creates expires unused after 5 minutes.

**Browser surface:**
- **iOS:** `ASWebAuthenticationSession`. It catches the custom-scheme return by itself and reports Cancel distinctly.
- **Android:** Chrome Custom Tabs, with the return delivered through a manifest intent-filter.
- **Never** use an embedded WebView; Google blocks sign-in inside one.

### 6.2 Callback deep link

- Success: `<redirect>?code=<opaque_exchange_code>`. No tokens ever appear in the URL.
- Failure: `<redirect>?error=...&error_description=...`.
  - If `error` contains `cancel` or `access_denied`, treat it as a quiet cancel.
  - Otherwise show a generic localized error. Never show the raw text.
- Only handle a callback while a matching sign-in is pending. Ignore unsolicited links.

### 6.3 Exchange: `POST /api/auth/cognito/mobile-exchange`

```json
{ "code": "<EXCHANGE_CODE_FROM_DEEP_LINK>" }
```

The code is **single-use and valid for 60 seconds.**
- Call the endpoint immediately and exactly once.
- Never retry the same code, persist it, or log it.

```json
200 {
  "access_token": "<COGNITO_ACCESS_TOKEN>",
  "refresh_token": "<COGNITO_REFRESH_TOKEN>",
  "expires_in": 3600,
  "user": { "id": "<APP_USER_UUID>", "name": "Alex", "email": "alex@example.com", "phone": null, "verified": true },
  "needs_profile_completion": false
}
```

- **Raw snake_case, no V1 envelope, and no `appIdentity`.** Use a dedicated parser.
- `profile_prefill` may appear. It is for Vipps; don't depend on it.

| Status | `error` | Action |
|---|---|---|
| 400 | `missing_code` / `invalid_code` | missing or expired: start a new browser sign-in |
| 410 | `invalid_code` | already used: never retry this code |
| 429 | `rate_limited` | back off by `Retry-After` |
| 5xx / network | – | temporary error. The code may be consumed, so start a new sign-in. |

### 6.4 After the exchange

1. Store the tokens (§8). Take the app user id from `user.id`.
2. `POST /api/v1/auth/ensure-profile` (Bearer, no body). The callback normally provisions already, so expect `{created:false}`. Call it once anyway, defensively.
3. Call `GET /api/v1/auth/me` in the Buyer app or `GET /api/v1/seller/auth/me` in the Seller app, then route.

New federated identities are provisioned **as buyers**. Signing in through the Seller app **does not** create a seller role.

### 6.5 Platform setup

| | iOS | Android |
|---|---|---|
| Callback registration | URL type with the approved scheme. `ASWebAuthenticationSession` needs only the scheme string. | `<intent-filter>` with the approved scheme and host on the main activity, kept as narrow as possible |
| Cancel detection | `ASWebAuthenticationSessionError.canceledLogin` | activity resumes with no callback. The buyer app treats 3 s without a callback as a cancel. |
| Cold start | rare: the sheet is in-process | **Required.** The process can die while the Custom Tab is up, and the callback then arrives as the launch intent. Persist a "pending provider plus start time" marker (never the code) before launching. At startup, if the launch link is a callback and the marker is under 5 minutes old, run the exchange. |
| Not needed | `GIDClientID`, `sign_in_with_apple` ID-token flow | `serverClientId`, SHA-1 for Google ID tokens |

The Google and Apple consoles and the Cognito IdP setup are **owned by the backend operators**. Their redirect is Cognito `/oauth2/idpresponse`. Flutter developers need no secrets.

Three different URLs are involved, and they must not be confused:
1. Provider → Cognito `/oauth2/idpresponse`
2. Cognito → Tommesalg `/api/auth/cognito/callback`
3. Tommesalg → app deep link

---

## 7. Profile bootstrap (all login methods)

### 7.1 `POST /api/v1/auth/ensure-profile`

- Auth: Bearer access token, empty body.
- Response: `200 { success: true, data: { created: true|false } }`.
- It is idempotent and never creates duplicates. Rate limit: 30 per minute.

When to call it:
- after a password login with `appIdentity: "unmapped"`;
- once after every Google/Apple exchange;
- once when any `/api/v1` call returns `401 AUTH_USER_NOT_FOUND`. Then retry that call **once**. Do not loop.

On `503`, the mapping is unavailable. Retry later; never invent an id.

### 7.2 `GET /api/v1/auth/me` (Buyer)

```json
{ "success": true, "data": {
  "id": "<APP_USER_UUID>", "role": "buyer", "email": "...", "displayName": "...", "avatarUrl": null,
  "buyerTier": "...", "verified": true,
  "identityEmailIsPrivateRelay": false, "notificationEmail": null,
  "hasVerifiedPrimaryEmail": true, "needsNotificationEmailCollection": false } }
```

- `data.id` is the app user id. Persist it, and use it for winner and chat comparisons.
- **Role gate (buyer app):** `success:true` with `role == "buyer"` lets the user in.
- Treat these as "not a buyer": any other role, HTTP `403`, or `error.code == "AUTH_ROLE_REQUIRED"`. Log out and show "this app is for buyers".
- Any other non-2xx or network failure is an error. Retry; don't log the user out.

### 7.3 `GET /api/v1/seller/auth/me` (Seller) 📄

Same Bearer token. It returns the seller profile and confirms seller authorization. ⚠️ The exact response fields are not in the reviewed docs; take them from the backend schema (`lib/contracts/auth/me.ts`, seller variant).

Expected handling:
- **Approved seller:** enter the seller app.
- **`403` or `AUTH_ROLE_REQUIRED`** (an account without seller access): keep the session, but route to the seller onboarding / application-status screen, or explain that seller approval is required. Never escalate a role on the client.

---

## 8. Tokens, refresh and logout

### 8.1 Storage

- Keep `accessToken`, `refreshToken`, the expiry time and the app user id in **`flutter_secure_storage`**: iOS Keychain (`first_unlock`, so background refresh works) and Android Keystore. **Never** use SharedPreferences.
- Never log tokens, passwords, OTPs or exchange codes.

### 8.2 Refresh: `POST /api/v1/auth/refresh`

```json
{ "refreshToken": "<refresh>" }
→ 200 { "success": true, "data": { "accessToken": "...", "refreshToken": "...?", "expiresIn": 3600, "tokenType": "Bearer" } }
```

When a call returns `401` with `error.code == "AUTH_EXPIRED"`, or before a call if the token expires within about 60 s:
1. Share **one in-flight refresh** across concurrent requests.
2. Save the new access token. Replace the refresh token **only if one was returned**.
3. Retry the original request **once**.

| Refresh result | Action |
|---|---|
| `200` | save, then continue |
| `400` / `401 AUTH_EXPIRED` / `403` | refresh token is dead: clear storage, go to login |
| `429`, `5xx`, network | **keep the tokens** and retry later. Never log the user out over connectivity. |

The same rules apply to WebSocket and Agora/RTM token requests: they all use the Cognito access token.

### 8.3 Logout: `POST /api/v1/auth/logout`

- Body: `{ "refreshToken": "<refresh>" }`. Response: `200 { loggedOut: true }`.
- **Clear local storage whatever the result.**
- Also unregister the push token, clear account-scoped caches, and reset any social-auth UI state.

---

## 9. Forgot and reset password

1. `POST /api/v1/buyer/auth/forgot-password` with `{ "email": "..." }`.
   - It always returns the same generic 200. Limit: 5 per 15 min per IP.
   - The server message says "link", but **a numeric code is emailed**. Show your own copy ("If an account exists, we emailed a code") and don't wait for a deep link.
2. `POST /api/v1/auth/reset-password` with `{ "email": "...", "code": "123456", "newPassword": "..." }`.
   - The code is 4–10 digits. The password policy from §4.1 applies.
   - A wrong or expired code returns `400 VALIDATION_ERROR`. `429` means wait.
   - On success, send the user to login. Treat older sessions as invalid.

Seller app: use the same routes. The `/buyer/` path is shared ⚠️ (confirm there is no seller-specific variant).

---

## 10. Vipps ⚠️

The buyer app's current Vipps flow:
1. Open `GET /api/auth/vipps/authorize?mobile=1&redirect=no.tommesalg.buyer://auth/vipps&mode=login|signup[&next=…]` in a Custom Tab or SFSafariViewController.
2. The deep link returns `?code=`.
3. Call `POST /api/auth/vipps/mobile-exchange {code}` once.
   - The response is raw snake_case: `access_token, refresh_token, expires_in, user, needs_profile_completion, profile_prefill`.
   - Errors: `400 invalid_json|missing_code|invalid_code`, `410` replay, `429 rate_limited` with `retry_after_seconds`.

**Open issue:** the buyer app still installs this result as a **Supabase** session, and the Supabase project is gone. `MOBILE_REGISTRATION_AUTH_INTEGRATION.md` §11 says Vipps is "unchanged" and points to `MOBILE_VIPPS_AUTH_FLOW.md`, which is not in this repo. Confirm with the backend whether the Vipps exchange now returns **Cognito** tokens. If it does, treat it exactly like §6.3–6.4 (store in secure storage, ensure-profile, `/me`). If `needs_profile_completion` is true, show the signup form prefilled from `profile_prefill`.

---

## 11. Seller app specifics

| Topic | Seller app rule |
|---|---|
| Accounts | Same Cognito pool and the same `users` table. A seller is an approved account, not a separate login. |
| Email signup | Uses the buyer register / verify / resend routes. Seller access then comes from the seller application and approval process. |
| Login, refresh, logout, reset | Identical endpoints to the buyer app (§5, §8, §9) |
| Google / Apple / Vipps | Identical authorize and exchange endpoints. The **Seller app needs its own deep-link scheme**, allowlisted on the server ⚠️ |
| Profile endpoint | `GET /api/v1/seller/auth/me` instead of `/api/v1/auth/me` |
| Role | Federated sign-ups are created as **buyers**. Never assume seller access; gate on the seller `/me` result. |
| Notification email | A verified primary email is required before a seller application (§12) |
| Session isolation | Use separate secure-storage keys per app; don't share the Keychain group with the buyer app unless that is intended |

---

## 12. Apple Hide My Email and notification email

Apple can return an `@privaterelay.appleid.com` identity. In that case `/me.email` may be null, and `identityEmailIsPrivateRelay` is true.

- **Don't block the home screen** on it. `needsNotificationEmailCollection` is currently always `false`.
- Collect a real address from Account or before an action that needs one. Delivery-address creation and the seller application require a verified primary email (`hasVerifiedPrimaryEmail`).

| Step | Call |
|---|---|
| Status | `GET /api/v1/auth/notification-email` (Bearer) |
| Send code | `POST /api/v1/auth/notification-email/request` with `{ "email": "user@example.com" }` |
| Verify | `POST /api/v1/auth/notification-email/verify` with `{ "email": "user@example.com", "code": "123456" }` |

- The OTP is 6 digits and lasts 10 minutes, with a 60 s resend cooldown. After verifying, re-read `/me`.
- `409 CONFLICT` means the address is verified on another account. **No auto-merge**: tell the user to sign in with that account.
- Never store the relay as the user's personal email.

---

## 13. Error matrix (V1 routes)

| HTTP | `error.code` | App behaviour |
|---|---|---|
| 400 | `VALIDATION_ERROR` | field or password feedback (a bad reset code also lands here) |
| 401 | `UNAUTHORIZED` | generic "invalid credentials" / "invalid or expired code" |
| 401 | `AUTH_EXPIRED` | refresh once and retry. From `/auth/refresh` itself, go to login. |
| 401 | `AUTH_USER_NOT_FOUND` | ensure-profile once, then retry once. It's not a token problem, so don't refresh or log out. |
| 403 | `FORBIDDEN` / `AUTH_ROLE_REQUIRED` | suspended account, or wrong role for this app |
| 409 | `CONFLICT` | account exists (offer sign-in) or the identity belongs to another account (no merge) |
| 429 | `RATE_LIMITED` | disable the action until `Retry-After` |
| 500 / 503 | `INTERNAL_ERROR` | "temporarily unavailable", back off; nothing was created |

Never show Dio or exception text on screen. Map every failure to localized copy.

## 14. Implementation checklist

- [ ] One secure token store with synchronous reads after startup; it emits a sign-in/sign-out event.
- [ ] Every Dio client and the WebSocket/RTM token requests take the bearer from that store.
- [ ] One refresh funnel: a shared Future, rotation only when a refresh token is returned, a single retry, and logout only on 400/401/403.
- [ ] Password login sends `client: "mobile"`, then the unmapped check runs ensure-profile, then `/me`.
- [ ] Register → verify (no tokens) → login with the in-memory password.
- [ ] Google and Apple: preflight, OS auth browser, a callback accepted only while pending, one raw exchange, ensure-profile, `/me`.
- [ ] Android cold-start callback recovery; iOS `ASWebAuthenticationSession` cancel handling.
- [ ] A role gate on the app-specific `/me`.
- [ ] Logout clears storage even when the API call fails.
- [ ] No tokens, codes, OTPs or passwords in logs, analytics or crash reports.

## 15. QA (both apps, real iOS and Android builds on staging)

| Test | Expected |
|---|---|
| Register → verify → auto-login | OTP email arrives; verify returns no tokens; login succeeds |
| Wrong or expired OTP, resend | generic error; resend cooldown enforced; old code invalidated |
| Password login, wrong / suspended | generic 401; restricted message on 403 |
| Google first-time and returning | same `user.id` on both; no duplicate profile |
| Apple, Share My Email and Hide My Email | sign-in works; relay never shown; optional email OTP works |
| Cancel the Google/Apple sheet | quiet return to login, buttons re-enabled |
| Android process killed mid-sign-in | the callback relaunches the app and the user lands signed in |
| Exchange replay or >60 s | 410 / 400; the user must sign in again |
| Expired access token | exactly one refresh, one retry |
| Expired refresh token / logout | storage cleared, login shown |
| Offline / 5xx during refresh | **no** logout |
| Seller app with a buyer-only account | seller `/me` denies access and onboarding is shown; no role escalation |

## 16. Open items to confirm with the backend

1. The approved callback deep links for **Buyer** and **Seller** (and their addition to `MOBILE_AUTH_DEEP_LINK_PREFIXES`).
2. The response schema of `GET /api/v1/seller/auth/me` and its error codes for non-sellers.
3. Whether the Vipps mobile exchange now returns Cognito tokens (§10).
4. Staging API origin; whether the Google and `SignInWithApple` IdPs are enabled on the staging Cognito app client; Apple `email_verified` provisioning.
5. Whether forgot-password and register have seller-specific variants or are shared (assumed shared).
6. How existing Supabase-era users migrate (forgot-password, or a migration).
