# Auction control vs main device — backend changes needed

**From:** Seller mobile app (Flutter) · **Date:** 2026-10-23
**Area:** `/api/v1/seller/streams/:streamId/session/*`, `/api/v1/agora/token`, `/go-live`, `/end`

---

## 1. The model the app now implements

A live stream can have several seller devices in the room. They hold **two independent roles**:

| Role | Who | What it allows | How it moves |
|---|---|---|---|
| **Main device** (`sessionRole: PRIMARY`) | exactly one device | The **camera**: publishing to Agora, Go Live, Stop/Resume feed, mic/camera/lens, End stream, Media Push | Only via `POST /session/primary/request` → `/primary/approve` |
| **Auction control** (`auctionControllerDeviceId`) | exactly one device (PRIMARY by default) | The **auction**: queue add/remove/reorder/clear, start lot, end lot, cancel, Dutch price drops, answering auction-control requests | Only via `POST /session/auction-control/request` → `/auction-control/approve` |

A secondary device that asks for **auction control** and gets it can run the queue and the lots. It keeps **watching** the main device's camera; it never becomes a broadcaster. The camera moves only when a device asks for, and is granted, **main device**.

**Reported bug:** a secondary device requested auction control only. When the main device accepted, the requester became the broadcaster and the main device became a watcher, so the roles looked fully swapped.

**Fixed in the app:** the app tied its camera role to auction control. It now ties the camera to `PRIMARY` only.

**Needs the backend:** the items below. Item 2.1 is the one that matters most: if the server swaps `PRIMARY` on an auction-control approval, the app will still move the camera, because it trusts the server's `devices[].role`.

---

## 2. Backend changes (priority order)

### 2.1 🔴 `/auction-control/approve` must never change `sessionRole`

**Expected:** approving an auction-control request only sets `auctionControllerDeviceId` to the requester. Both devices keep their `sessionRole` (PRIMARY stays PRIMARY, SECONDARY stays SECONDARY).

**Please verify:**
1. Device A claims, so A is PRIMARY and holds auction control.
2. Device B claims, so B is SECONDARY.
3. B: `POST /session/auction-control/request`.
4. A: `POST /session/auction-control/approve {requestId}`.
5. Inspect the response snapshot, then `GET /session/devices`.

| Field | Must be |
|---|---|
| `auctionControllerDeviceId` | B |
| `devices[A].role` | `PRIMARY` |
| `devices[B].role` | `SECONDARY` |
| `pendingAuctionControlRequests` | without B's request |
| `pendingRequests` (primary) | unchanged |

If A comes back `SECONDARY` (or B `PRIMARY`), that is the bug: the approve handler is also running the primary-handoff logic, or sharing a "transfer" helper with it. The app logs `[session] BACKEND BUG: auction-control approve demoted PRIMARY` when it sees this.

### 2.2 🔴 Agora RTC publisher tokens only for the main device

`POST /api/v1/agora/token` takes only `{channelName, uid}` and returns a token any seller device can **publish** with. Today only the app stops a secondary device from broadcasting.

**Ask:** accept `{deviceId, sessionToken}` (optional, for backward compatibility) and mint:
- **publisher** role only when that session is `PRIMARY` for the stream's channel;
- **subscriber** role for any other seller session.

Without this, a modified or older client on a second phone can publish into the stream at the same time as the main device.

### 2.3 🟠 Return auction control to the main device when the controller leaves

If the device holding auction control disconnects (`/session/disconnect`), loses its lease (no heartbeat), or the app is killed, `auctionControllerDeviceId` still points at a dead device. Nobody can then start or end lots, and nobody can approve a new auction-control request, because only the controller may approve.

**Ask:** on controller disconnect or lease expiry, set `auctionControllerDeviceId` to the current PRIMARY (or `null`, which the app already treats as "PRIMARY holds it"), and broadcast `CONTROL_REQUESTS_UPDATED`.

### 2.4 🟠 Promote a new main device when PRIMARY leaves

If the PRIMARY device disconnects or its lease expires, no device has the camera, and `/primary/request` can never be approved.

**Ask:** either
- (a) on PRIMARY lease expiry or disconnect, promote the longest-connected live SECONDARY to `PRIMARY`; or
- (b) let `/primary/request` succeed immediately (auto-approve) when there is no live PRIMARY.

Either way, broadcast `CONTROL_REQUESTS_UPDATED`.

Until this is done, the app lets any device **End stream** when the device list contains no PRIMARY (`/end` is seller-level), so a stream whose camera phone died can at least be closed.

### 2.5 🟡 Let the main device take auction control back

Today, if the main device handed auction control to a secondary device, it must *request* it back, and the secondary device has to approve. `/auction-control/release` returns **501**.

**Ask (either one):**
- Implement `POST /session/auction-control/release {deviceId, sessionToken}`: the current controller hands control back to PRIMARY. The app will add a "Give control back" button.
- Or let PRIMARY's `/auction-control/request` succeed immediately (auto-approve) when the requester is PRIMARY.

### 2.6 🟡 Define what `/primary/approve` does to auction control

The app copes with both behaviours, but the docs should say which one applies. **Recommended:** leave `auctionControllerDeviceId` unchanged, so the two roles stay independent. A device that becomes main and also wants the auction asks for both.

If instead you move auction control together with PRIMARY when the old PRIMARY held it, say so in the integration guide. Either way, return the final `auctionControllerDeviceId` and per-device `role` in the approve response.

### 2.7 🟡 Request hygiene

- Drop a pending request (either kind) when its requester disconnects or loses its lease. Otherwise the approver gets prompted about a device that is gone.
- Make a duplicate request idempotent: return the existing pending request instead of creating a second one or answering 409.
- Approving or rejecting a request that is no longer pending should return **409 `CONFLICT`** with a clear message, never 500.
- Approving with a `requestId` from the *other* list (primary vs auction control) must stay **403**. The app never mixes them, but keep the guard.

### 2.8 🟡 Enforce main device on `/go-live` and `/end`

Both are seller-level: any device of the seller can call them. The app now restricts them to the main device. Please accept `{deviceId, sessionToken}` and reject non-PRIMARY sessions with 403. Exception: allow `/end` when there is no live PRIMARY (see 2.4).

### 2.9 🟢 Realtime

Fire `CONTROL_REQUESTS_UPDATED` on **every** change: request, approve, reject, disconnect, lease expiry, and promotion. Include `auctionControllerDeviceId` and per-device `role` in the payload, so devices update without waiting for the 5–12 s poll.

---

## 3. Test cases (app + backend)

`A` = phone that claimed first (main device). `B` = second phone.

| # | Scenario | Expected |
|---|---|---|
| 1 | B requests **auction control**; A accepts | A keeps camera, stays PRIMARY, keeps publishing with no interruption. B can edit the queue and start/end lots, and still watches A's camera. B has no Go Live, mic or camera controls. |
| 2 | Same as 1, then B starts a lot | Server accepts B's lot mutation. A sees the lot card read-only, and its Start/End buttons are gated. |
| 3 | Same as 1, then A tries to start a lot | App shows "Auction control needed". Server also returns 403. |
| 4 | Same as 1, then A requests auction control back | B gets the prompt. On accept, control returns to A and the camera does not move. |
| 5 | B requests **main device**; A accepts | B becomes PRIMARY and its camera preview comes up ("Tap Go Live"). A drops to watching B. Auction control follows rule 2.6. |
| 6 | B requests main device while A is live | Buyers see A until B taps Go Live. A stops publishing the moment it is demoted. |
| 7 | A declines B's request (either kind) | Nothing moves. B's pill or button resets to "Request …". |
| 8 | B holds auction control, then B leaves the room or is killed | (backend 2.3) Control returns to A within one lease, and A can run lots again. |
| 9 | A (main) is killed while B holds auction control | B's stage shows "waiting for main device". B can still run lots if the stream is live. (backend 2.4) B is promoted or can become main. B can End stream when no PRIMARY is listed. |
| 10 | B requests auction control twice quickly | One pending request (2.7). The app shows "still waiting". |
| 11 | B requests auction control, then leaves before A answers | A's prompt disappears on the next poll (2.7). |
| 12 | A has the accept dialog open when B's request is answered on the web console | The dialog closes itself on the next poll. |
| 13 | B holds auction control and asks for main device too | After approval, B is PRIMARY and controller. A is a watcher with no control. |
| 14 | Re-enter the room (app restart) on B while it holds auction control | B rejoins as a watcher with control (the camera stays on A). No "control moved" toast on entry. |
| 15 | B denies camera/mic permission after becoming main device | Permission screen. The session is not left holding PRIMARY with no camera (the app re-bootstraps). |
| 16 | B with auction control opens ⋮ | No camera-source tile. End stream only shows if B is main or no main device exists. |
| 17 | B (no main) taps Go Live through any path | Blocked by the app ("Main device needed"). (backend 2.2/2.8) Also refused by the server. |
| 18 | Three devices: C holds auction control, B requests it | Only C gets the prompt. A (main) only sees it in the Devices sheet. |
