# Backend request: quantity on the auction queue

**From:** Seller app (Flutter)
**Date:** 2026-10-14
**Status:** Needed before the app can ship "sell the same product N times"

## 1. What the seller needs

1. In **Assign to live**, the seller scans the same product several times.
   The product-request row already counts this up (`quantityRequested`:
   1 → 2 → 3, `action: "incremented"` from `POST …/product-requests/scan`).
2. **Send to live** puts that product in the stream's auction queue **with its
   quantity**: 3 scanned = 3 units to auction.
3. The queue (seller room **and** buyer room) shows the product **once**, with
   a count: `Nike cap ×3`.
4. **Start auction** sells **one unit** per lot. After the lot ends:
   - **sold** (has a winner) → count goes down by 1 (`×3` → `×2`).
   - **unsold** (no winner) or **cancelled** → the unit is not lost. It goes
     back to the queue (see §4.4).
   - When the count reaches 0, the product leaves the queue.
5. Sending the same product to live again later **adds to** the count
   (`×2` + 2 more = `×4`). It never creates a second row.
6. All seller devices and all buyers see the same count, so the server has to
   be the source of truth.

## 2. What exists today (and why the app can't do this alone)

| Endpoint | Today |
|---|---|
| `POST /api/v1/seller/streams/:id/auction-room/queue` | Body `{productId, auctionType, sourceType}` or batch `{products:[…]}`. **No quantity.** |
| `DELETE …/auction-room/queue/:productId` | Keyed by product id, so it assumes one entry per product |
| `PATCH …/auction-room/queue/:productId/position` | Keyed by product id |
| `GET …/auction-room/queue/catalog` | `{productId, name, upc, type, inQueue, randomStock, …}`, with `inQueue` as a **boolean** |
| `POST …/auction-room/start` | No product id. Starts the queue head and **removes it from the queue** |
| `POST …/auction-room/end` | Ends the lot. `meta.depletedRandomProductId` exists for RANDOM products only |
| Snapshot `productQueue[]` | `{productId, title, price, image, …}`, **no quantity** |

The only multi-unit concept today is a **RANDOM** product with `randomStock`.
It's sold once per lot, its stock counts down, and it's removed when depleted.
**We need the same behaviour for USUAL (catalog) products, driven by a
quantity.**

The app can't fake this safely on the client:
- Posting the same `productId` N times: it's undefined whether the server
  accepts it, and remove/reorder by `productId` would then be ambiguous.
- Having the app re-enqueue after each lot breaks with two seller devices, an
  app restart or a dropped connection, and buyers would never see the count.

## 3. Data model

Add to the queue entry (one row per `streamId + productId`):

| Field | Type | Meaning |
|---|---|---|
| `queueEntryId` | uuid | Stable id of the entry (optional, but helps future-proof remove/reorder) |
| `quantity` | int ≥ 0 | Units **still waiting** to be auctioned. 0 means the entry is removed |
| `soldCount` | int ≥ 0 | Units sold from this entry in this stream (for display/audit) |

Invariant per stream + product:
`quantity (queued) + units in an active lot + soldCount ≤ availableQuantity` (§3.1)

### 3.1 Upper limit (`availableQuantity`)

The most units that may be queued for a product in a stream:

```
availableQuantity = SUM(product_request_items.quantityRequested
                        for this stream + productId)
                    − soldCount
                    − units in the active lot (0 or 1)
                    − quantity already queued
```

If the backend prefers to cap on warehouse stock instead (e.g.
`reservedQuantity`), please tell us which one. The app shows whatever number
you return.

## 4. API changes

### 4.1 Enqueue: accept `quantity`, merge duplicates

`POST /api/v1/seller/streams/:id/auction-room/queue`

Single:
```json
{
  "deviceId": "…", "sessionToken": "…",
  "productId": "uuid",
  "auctionType": "NORMAL",
  "sourceType": "CATALOG",
  "quantity": 3
}
```
Batch:
```json
{
  "deviceId": "…", "sessionToken": "…",
  "clientRequestId": "uuid",
  "products": [
    { "productId": "uuid-a", "auctionType": "NORMAL", "sourceType": "CATALOG", "quantity": 3 },
    { "productId": "uuid-b", "auctionType": "NORMAL", "sourceType": "CATALOG", "quantity": 1 }
  ]
}
```

Rules:
- `quantity` is optional. If missing, it defaults to **1** (current clients
  keep working).
- `quantity` must be an integer ≥ 1. Otherwise return `400 VALIDATION_ERROR`.
- **The product is already queued** → **add** `quantity` to the existing
  entry. Keep its position. Don't create a second entry, and don't return
  `CONFLICT`.
- **The product is not queued** → create an entry at the **end** of the queue.
- **The same `productId` appears twice in one batch** → sum the quantities into
  one entry.
- Requested total > `availableQuantity` → return
  `409 QUANTITY_EXCEEDS_AVAILABLE`, with
  `error.details: { productId, requested, available }`. For a batch, either
  reject the whole batch (preferred, atomic) or document partial success with
  a per-item result list.
- `sourceType: "RANDOM"` → ignore `quantity` (the stock is `randomStock`), or
  reject anything other than 1. Please document which.
- **Idempotency:** with the same `clientRequestId`, return the original result
  and **don't add again**. The app retries on timeouts, and a retry must not
  double the quantity.
- Response: a snapshot whose `productQueue` includes `quantity` (as today,
  plus the new fields).

### 4.2 Set or decrease the quantity of a queued product (new)

`PATCH /api/v1/seller/streams/:id/auction-room/queue/:productId/quantity`

```json
{ "deviceId": "…", "sessionToken": "…", "quantity": 2 }
```
- `quantity` is an int ≥ 0. 0 removes the entry (same as `DELETE`).
- If it's > `availableQuantity` + the current queued quantity, return
  `409 QUANTITY_EXCEEDS_AVAILABLE`.
- If the product isn't queued, return `404 NOT_FOUND`.
- Needs auction control (same rule as the other queue mutations).
- Returns the snapshot.

### 4.3 Remove / reorder / clear (keep, define)

- `DELETE …/queue/:productId` removes the **whole entry**, all units.
- `PATCH …/queue/:productId/position` moves the entry. The quantity is
  unchanged.
- `POST …/queue/clear` removes all entries.

### 4.4 Start / end a lot

`POST …/auction-room/start` (no change to the body):
- Take **one unit** of the head entry: `quantity -= 1`.
- If `quantity` is now 0, remove the entry. Otherwise **keep it at the head**,
  so the seller can sell the next unit straight away. (If you'd rather move it
  to the end, tell us. The app only renders what you send.)
- Add to `activeAuction`: `productId` (already there) and
  `unitsRemainingAfterThis` (int, the head entry's `quantity` after the
  decrement, or 0).

`POST …/auction-room/end`, **and** the timer-driven close:
- **Sold** (has a winner): `soldCount += 1`. Nothing goes back to the queue.
- **Unsold** (no bids / no winner) or the lot was **cancelled**
  (`cancel-room`): return the unit to the queue.
  - If an entry for that product still exists: `quantity += 1` (it keeps its
    position).
  - If not: create an entry at the **end** of the queue with `quantity: 1`.
- Add to the end response `meta`: `{ returnedToQueueProductId?: uuid,
  depletedProductId?: uuid }`. The second is the USUAL-product counterpart of
  `depletedRandomProductId`, so the app can show "Nike cap: last unit sold".
- Ending must be idempotent: a double `end` (timer + button) must not
  decrement or return the unit twice.

### 4.5 Snapshot (REST + WS `SNAPSHOT`)

`productQueue[]` items:
```json
{
  "queueEntryId": "uuid",
  "productId": "uuid",
  "title": "Nike cap",
  "price": 199,
  "image": "https://…",
  "auctionType": "NORMAL",
  "quantity": 3,
  "soldCount": 1
}
```
`activeAuction` also gets `unitsRemainingAfterThis`. Buyers get the same
fields, so their queue can show `×3`.

### 4.6 Catalog

`GET …/auction-room/queue/catalog` items: keep `inQueue` (bool, for old
clients) and add:

| Field | Meaning |
|---|---|
| `queuedQuantity` | int, units currently in the queue (0 if not queued) |
| `soldCount` | int, units sold in this stream |
| `availableQuantity` | int, units that can still be added (§3.1) |

The room's "Add products" dialog will then allow a product that's already
queued while `availableQuantity > 0`, with a quantity stepper capped at
`availableQuantity`.

### 4.7 Product-request items (Assign to live)

`GET …/streams/:id/product-requests/:requestId` items: add

| Field | Meaning |
|---|---|
| `queuedQuantity` | units of this row currently in the auction queue |
| `soldQuantity` | units of this row sold in this stream |

With this, the Assign-to-live list can show "not yet sent =
`quantityRequested − queuedQuantity − soldQuantity`" from the server. Today
the app hides already-sent rows with a device-local list, which other devices
can't see.

## 5. Edge cases the backend must handle

| # | Case | Expected |
|---|---|---|
| 1 | Enqueue a product already in the queue | Quantity added, same position, no `CONFLICT` |
| 2 | Same productId twice in one batch | One entry, quantities summed |
| 3 | `quantity` 0, negative, decimal, string | `400 VALIDATION_ERROR` |
| 4 | `quantity` missing | Treated as 1 |
| 5 | Requested > available | `409 QUANTITY_EXCEEDS_AVAILABLE` with `available` in details |
| 6 | Network retry of the same batch (`clientRequestId`) | No double add |
| 7 | Two seller devices enqueue the same product at the same time | Both increments applied atomically (row lock / `UPDATE … SET quantity = quantity + n`) |
| 8 | Start with head `quantity` 1 | Entry removed, lot runs |
| 9 | Start with head `quantity` 3 | Entry stays at head with `quantity` 2 |
| 10 | Lot sold | `soldCount + 1`, nothing returned |
| 11 | Lot unsold / no bids | Unit returned (entry `+1`, or new entry at the end) |
| 12 | Room cancelled while a lot is active | Unit returned |
| 13 | Timer close and manual end race | Exactly one outcome applied |
| 14 | `DELETE` an entry with `quantity` 3 | Whole entry removed |
| 15 | `PATCH quantity` to 0 | Entry removed |
| 16 | Product-request row deleted while its units are queued | Either block the delete (`409`) or shrink/remove the queue entry. Please document which |
| 17 | Product-request quantity lowered below what's queued | Same as #16 |
| 18 | RANDOM product | Unchanged; `randomStock` keeps driving it |
| 19 | Stream ends with units still queued | Entries discarded; nothing is sold |
| 20 | Old app versions (no `quantity` sent) | Behaves as today with quantity 1 |

## 6. Acceptance tests (please run them against staging)

1. Enqueue A ×3 → snapshot `productQueue` = `[A quantity 3]`.
2. Enqueue A ×2 again → `[A quantity 5]`, same position.
3. Batch `[A×1, A×1, B×2]` on an empty queue → `[A 2, B 2]`.
4. Start → active lot A, queue `[A 1, B 2]`, `unitsRemainingAfterThis` 1.
5. End with a winner → queue `[A 1, B 2]`, A `soldCount` 1.
6. Start → active A, queue `[B 2]`. End **with no bids** → queue `[B 2, A 1]`.
7. Enqueue A with `quantity` > available → `409 QUANTITY_EXCEEDS_AVAILABLE`,
   queue unchanged.
8. Retry step 1's request with the same `clientRequestId` → quantity unchanged.
9. `PATCH` B quantity 0 → B removed.
10. Catalog after each step: `queuedQuantity` / `availableQuantity` match.
11. The buyer room WS `SNAPSHOT` after each step carries the same `quantity`.

## 7. What the app will do once this is live

- **Send to live** sends `quantity` = the unsent units of each row, with a
  `clientRequestId`, and stops excluding products that are already in the
  queue.
- **Queue tab (seller and buyer):** one row per product with an `×N` badge.
  The seller can tap it to change N (via `PATCH …/quantity`).
- **Add products dialog:** a quantity stepper capped at `availableQuantity`,
  and queued products stay selectable while units remain.
- **Start / end:** show "N left" on the active lot and "last unit sold" from
  `meta.depletedProductId`.
- **Assign to live:** read `queuedQuantity` / `soldQuantity` from the server
  and drop the device-local "already sent" list.

Please reply with: the cap source (§3.1), RANDOM + quantity (§4.1), whether
the head stays or moves after start (§4.4), and edge case #16.
