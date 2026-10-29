# Google sign-in fails for emails that already have a password account

**From:** Seller mobile app (Flutter) · **Date:** 2026-10-23
**Area:** `GET /api/auth/cognito/callback` (Cognito Hosted UI → Google), account linking

## What happens

1. Seller app opens `GET /api/auth/cognito/authorize?identity_provider=Google&mobile=1&redirect=no.tommesalg.buyer://auth/vipps/google&mode=login`, which returns 307.
2. The user picks a Google account whose email **already has a Tømmesalg account created with email + password** (a native Cognito user).
3. The backend deep-links back with:

```
no.tommesalg.buyer://auth/vipps/google
  ?error=auth_failed
  &error_description=An account with this email already exists. Sign in instead.
```

No `code` comes back, so the app cannot sign in. Sellers almost always have a password account already, because seller accounts are created through the application flow. So for sellers, Google sign-in effectively never works today.

## What we need

When the Google identity's **verified** email matches an existing user, sign that user in. Do not refuse.

The usual Cognito way:
- In the **Pre sign-up** Lambda trigger, for `triggerSource = PreSignUp_ExternalProvider`, look up the native user by email (`ListUsers` with `email = "<email>"`).
- If one exists, call `AdminLinkProviderForUser` (`DestinationUser` = the native user, `SourceUser` = `Google_<sub>`).
- Then let the flow continue. Cognito then issues tokens for the **existing** user (same `sub`, so the same app `users.id`).

Conditions:
- Link only when Google reports `email_verified = true`.
- Never auto-merge two existing app users (409 stays a hard stop, as for the notification-email flow).
- Apple: the same rule applies once the Apple callback fix lands. Relay emails (`@privaterelay.appleid.com`) won't match and will simply create a new user.

## Also helpful

- Send a stable machine-readable code for this case, e.g. `error=account_exists`, so apps don't have to match the English `error_description`. The Seller app currently matches `"already exists"` in the description to show *"This email already has a Tømmesalg account. Sign in with your email and password instead."*

## Test

| Case | Expected after the fix |
|---|---|
| Google email = existing password account | Code returned → exchange OK → `/api/v1/seller/auth/me` returns that same seller |
| Google email with no account | New buyer-role user (as today). The seller app shows "no seller access". |
| Same user signs in with password afterwards | Still works, same `users.id` |
