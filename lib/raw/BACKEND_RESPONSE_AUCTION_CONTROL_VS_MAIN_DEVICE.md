# Backend response: auction control vs main device

**To:** Seller mobile app (Flutter) · **Re:** `BACKEND_AUCTION_CONTROL_VS_MAIN_DEVICE.md` (2026-10-23)
**Branch:** `TW-102`

Status of every item in your request. Section numbers match your document.

## Summary

| # | Request | Status |
|---|---------|--------|
| 2.1 | `/auction-control/approve` never changes `sessionRole` | Already correct, no change |
| 2.2 | Agora publisher token only for main device | Done (send `deviceId` + `sessionToken`) |
| 2.3 | Controller leaves, control returns to main device | Already in place |
| 2.4 | Promote a new main device when PRIMARY leaves | Already in place |
| 2.5 | Main device takes auction control back | Done (`/auction-control/release`) |
| 2.6 | Define what `/primary/approve` does to auction control | Documented below |
| 2.7 | Request hygiene | Done |
| 2.8 | Enforce main device on `/go-live` and `/end` | Done (send `deviceId` + `sessionToken`) |
| 2.9 | Realtime on every change | Done |

## What you need to change in the app

Send `{deviceId, sessionToken}` on these calls. They are optional on the server for backward compatibility, so **until you send them the new protection does not apply**:

- `POST /api/v1/seller/streams/:streamId/go-live`
- `POST /api/v1/seller/streams/:streamId/end`
- `POST /api/v1/agora/token`

Then optionally: add a "Give control back" button (2.5), read the new realtime fields (2.9), and handle 409 (2.7).

## Item by item

### 2.1 Approve never changes `sessionRole` (no change needed)
`/auction-control/approve` only sets `auctionControllerDeviceId` to the requester and marks the request `APPROVED`. It does not touch `sessionRole`. It is a different database function from the primary handoff (`/primary/approve`), and they share no helper. If you still see PRIMARY swap after an auction-control approval, send us the request/response pair. The server cannot cause it from this endpoint.

### 2.2 Agora publisher token (done)
`POST /api/v1/agora/token` accepts optional `deviceId` and `sessionToken`. When both are sent and the session is **not** the PRIMARY of that stream, the server returns a **subscriber** token instead of a publisher token (it does not return an error). Without them, behaviour is unchanged.

### 2.3 Controller leaves (already in place)
When the controller disconnects, a database trigger clears `auctionControllerDeviceId` to `null`, which means "PRIMARY holds it". If the controller's lease expires without a disconnect, auction-control checks fall back to PRIMARY immediately. The stored value may still point at the dead device until it is next changed, so treat a controller with no live session in `devices[]` as `null`.

### 2.4 PRIMARY leaves (already in place)
On explicit disconnect and on heartbeat timeout, the server promotes the next SECONDARY to PRIMARY. The disconnect response contains `wasPrimary` and `promotedSession`.

### 2.5 Release auction control (done)
`POST /session/auction-control/release` with `{deviceId, sessionToken}`.
- Caller must be the current auction controller, otherwise 403.
- Sets `auctionControllerDeviceId` to `null` (PRIMARY holds it).
- Idempotent: calling it when you are not the explicit controller changes nothing.
- Returns `{success: true, snapshot}`, the same shape as approve.
- No auto-approve was added for PRIMARY's `/auction-control/request`. Use release instead.

### 2.6 What `/primary/approve` does to auction control (documented)
It **leaves `auctionControllerDeviceId` unchanged**. The two roles stay independent, as you recommended. A device that becomes the main device and also wants the auction must ask for both. The response returns the `snapshot` with the final `auctionControllerDeviceId` and per-device `role`.

### 2.7 Request hygiene (done)
- **Stale requests:** pending requests (both kinds) from a device with no live session are left out of `pendingRequests` and `pendingAuctionControlRequests`. They reappear if the same device reconnects.
- **Duplicate requests:** a second request from the same device now returns the **existing pending `requestId`** with the "already pending" message (200). Before, `requestId` was `null`.
- **Not pending any more:** approve/reject on a request that is already resolved, whose requester is gone, or who was already promoted returns **409 `CONFLICT`**, never 500.
- **Wrong list:** a `requestId` from the other list (primary vs auction control), and any authorization failure, stays **403**.

### 2.8 `/go-live` and `/end` require the main device (done)
With `{deviceId, sessionToken}` in the body, a session that is not the live PRIMARY gets **403**.
Exception for `/end`: if there is no live PRIMARY, any valid seller session on that stream may end it.

### 2.9 Realtime (done)
`CONTROL_REQUESTS_UPDATED` now includes:
- `auctionControllerDeviceId` (string or `null`)
- `devices`: `[{deviceId, role}]`

New `action` values: `DISCONNECTED`, `EXPIRED` (lease expiry), `PROMOTED` (a new main device was promoted on disconnect), in addition to `REQUESTED`, `APPROVED`, `REJECTED`, `CONNECTED`. Release is sent as `controlType: AUCTION`, `action: APPROVED`. The fields are omitted if the server could not load them, so keep the poll as a fallback.

## Test cases from your document

Cases 1, 2, 3, 5, 7, 12, 13 and 14 depend on the app and the unchanged server behaviour. The cases below are the ones these changes affect.

| # | Expected from the server |
|---|--------------------------|
| 4 | A releases or requests back. With release: B calls `/auction-control/release`, control returns to A, no camera change. |
| 8 | B leaves: control returns to A and `DISCONNECTED` is broadcast. B killed: `EXPIRED` after the lease times out. |
| 9 | A killed: B is promoted to PRIMARY (`PROMOTED` / `EXPIRED`). If no PRIMARY is listed, B can call `/end`. |
| 10 | Second request returns the same `requestId` (200). |
| 11 | B leaves before A answers: B's request drops out of A's `pendingAuctionControlRequests`. |
| 17 | Non-PRIMARY `/go-live` returns 403 and `/agora/token` returns a subscriber token (when credentials are sent). |

## Not covered

- Not tested end to end against a live environment (two real devices). Verified by typecheck and the existing test suite, plus new tests for the Agora token change.
- The web client throttles control events to one per 3 seconds. In the Flutter app, apply the payload fields directly so that quick sequences are not missed.
- The primary/auction request routes still return a 5xx if the database fails.
