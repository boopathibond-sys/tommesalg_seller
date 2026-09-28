# Warehouse / Stock module — standalone app build spec

Everything below the line is the brief for a **new, separate Flutter app** that contains
only the Warehouse (Stock) module lifted out of `tommesalg_seller_app`: SKU management,
Assign to SKU (scan + manual UPC), warehouse search, SKU detail, assigned / pending
products, product quick views with discrepancy reporting, and measurements.

Sign-in stays exactly as it is today (Supabase + the seller backend), so the auth layer is
**ported verbatim, not redesigned**.

Paste the whole thing into a Claude Code session opened on the new app's repo.

Source of truth for every behaviour described here is the seller app at
`tommesalg_seller_app` — `lib/views/stock/**`, `lib/controllers/inventory_controller.dart`,
`lib/controllers/sku_detail_controller.dart`. Where this doc and that code disagree, the
code wins; copy the file rather than re-writing it from the prose.

---

## PROMPT

Build a standalone Flutter app — working name **Tommesalg Warehouse** — that is the seller
app's Warehouse tab as a whole product. It talks to the same backend, authenticates the
same way, and looks identical. No feature may regress: a seller must be able to do
everything in this app that they can do today inside the seller app's Stock tab.

---

## 1. Scope

### In scope (port all of it)

| Area | What it is |
| --- | --- |
| Auth | Supabase email+password / email OTP login, session persistence, silent refresh, forgot + reset password, logout. Copied verbatim. |
| Shell | Warehouse header + horizontally scrollable segment bar: **Overview · SKUs · Assign to SKU · Search**. Pull-to-refresh per segment. |
| Overview | Two stat cards (Total, Assigned) + four quick-action cards. |
| SKUs | Debounced live SKU suggest, tap a hit → SKU detail. "New SKU" button. |
| Assign to SKU | Pick a SKU → scan barcode / type a UPC → known product is placed, unknown UPC opens the manual add sheet. Assigned + pending lists underneath. |
| Search | Three modes — UPC (with scanner), Tag (suggest → search), SKU (suggest → detail). Grouped results: SKUs section, Products section. |
| SKU detail | Full page: code, name, status badges, tags, location path, edit dialog, assign panel, assigned + pending lists. |
| Assigned products | Edit (increment quantity + primary flag), Move to another SKU, Delete, Quick view. |
| Pending products | Edit (name, UPC, quantity, images), Delete. |
| Product quick views | Product info from `/products/{id}/preview` + report-a-discrepancy (message, preset chips, up to 10 images) + the Measurements block. |
| New SKU dialog | Create + Edit modes, auto-composed SKU code, tag search / tag create inline. |
| Barcode scanner | Full-screen `mobile_scanner` page; Code128 strips the first 3 chars; the assign flow strips leading zeros. |
| Measurements | `MeasurementGoalsSection` — measurement bundle, per-type numeric rows, size-spec photos. |
| Localization | Norwegian (`nb`, primary) + English (`en`) through GetX. 215 keys, extracted in §11. |
| Push (optional) | Only if you want SKU deep links — `destinationType == 'SKU'` / `locationId` opens `SkuDetailView`. Drop it for v1 if push isn't being set up. |

### Out of scope (do not port)

Streams / live auction, Manage Products, orders, profile & become-a-seller, dashboard,
notifications inbox, Agora, web sockets. The `Activity` segment exists in the source but is
commented out and shows static placeholder rows — **leave it out**.

---

## 2. Stack

Flutter, GetX for state + routing + i18n, `http`/`dart:io` for networking (no Dio).

```yaml
dependencies:
  flutter: {sdk: flutter}
  flutter_localizations: {sdk: flutter}   # Material/Cupertino nb strings
  get: ^4.6.6
  supabase_flutter: ^2.8.0                # auth + session persistence
  http: ^1.2.0
  http_parser: ^4.0.2                     # multipart Content-Type for uploads
  shared_preferences: ^2.2.0              # persisted locale
  mobile_scanner: ^7.2.0                  # barcode scanning
  image_picker: ^1.0.7                    # report + pending-product photos
  google_fonts: ^6.2.1
  app_links: ^7.0.0                       # password-reset deep link
  url_launcher: ^6.3.2                    # optional
```

Not needed: agora_rtc_engine, agora_rtm, web_socket_channel, hive, file_picker,
image_cropper, firebase_* (unless you keep push), device_info_plus, permission_handler
(image_picker and mobile_scanner ask for their own grants).

---

## 3. File tree to create

```
lib/
  main.dart
  core/
    config/env_config.dart            # copy verbatim
    config/get_or_put.dart            # copy verbatim
    config/session_scope.dart         # trim to the controllers this app owns
    services/api_client.dart          # copy verbatim
    services/auth_service.dart        # copy verbatim
    services/measurement_service.dart # copy verbatim
    services/deep_link_service.dart   # copy verbatim (password reset)
    theme/app_colors.dart             # copy verbatim
    theme/app_text_styles.dart
    localization/app_translations.dart
    localization/localization_service.dart
    localization/translation_keys.dart  # keep only the keys in §11
    widgets/custom_text.dart
    widgets/branded_refresh_indicator.dart
    widgets/branded_loading_view.dart
    widgets/branded_error_view.dart
    widgets/confirm_dialog.dart
    widgets/auto_quick_view_toggle.dart
  controllers/
    auth_controller.dart
    inventory_controller.dart         # ~1035 lines, copy whole
    sku_detail_controller.dart        # ~829 lines, copy whole
    stock_nav_controller.dart         # optional once Stock is the whole app
  models/
    inventory_stats.dart
    inventory_location.dart
    inventory_location_detail.dart
    inventory_placement.dart
    inventory_search.dart
    inventory_tag.dart
    location_suggestion.dart
    pending_product.dart
    product_request_model.dart        # ProductRequestProduct + ProductRequestIssue only
    measurement.dart
  views/
    auth/login_view.dart
    auth/forgot_password_view.dart
    auth/reset_password_view.dart
    auth/verify_code_view.dart
    auth/widgets/…
    splash/splash_view.dart
    scanner/barcode_scanner_view.dart
    measurements/measurement_goals_section.dart
    stock/
      stock_view.dart                 # becomes the app home
      sku_detail_view.dart
      shared/stock_segment.dart
      shared/stock_widgets.dart
      shared/sku_products_section.dart
      shared/product_quick_view.dart
      shared/assigned_product_quick_view.dart
      overview/overview_section.dart
      skus/skus_section.dart
      assign/assign_section.dart
      assign/assign_products_panel.dart
      search/search_section.dart
      widgets/new_sku_dialog.dart
assets/
  translations/nb.json
  translations/en.json
.env                                   # bundled asset, see §4.1
```

---

## 4. Foundations — copy these before writing any screen

### 4.1 `.env` (Flutter asset, loaded by `EnvConfig.init()`)

```
BASE_URL=<seller backend host>
BUYER_BASE_URL=<buyer backend host — only for forgot-password>
SUPABASE_PROD_URL=<supabase project url>
SUPABASE_PROD_ANON_KEY=<supabase anon key>
```

Assets ship unencrypted, so only hostnames and the Supabase **anon** key belong here.
Nothing else, ever.

### 4.2 `ApiClient`

Singleton (`ApiClient.instance`) over `dart:io` `HttpClient` with `get/post/put/patch/delete`
plus `uploadFile` (multipart, field name `file`, explicit `MediaType` per extension because
`octet-stream` is rejected server-side). It pretty-prints every request/response in debug.

Two global hooks wired once in `main()`:

- `onSessionExpired` — fires on `401` + `error.code == "AUTH_EXPIRED"`. Do **not** log the
  user out here: call `AuthService.recoverOrLogout()`, which tries one refresh first.
- `onRoleRequired` — fires on `error.code == "AUTH_ROLE_REQUIRED"` (the account isn't a
  seller). Snackbar + `logout()`.

`ApiResponse` exposes `statusCode`, `body`, `isSuccess` (2xx), `json`.

### 4.3 Auth — keep it, don't redesign it

`AuthService` is a façade over `supabase_flutter`'s `GoTrueClient`:

- `Supabase.initialize()` persists and silently refreshes the session. **Add no manual
  refresh logic.**
- `status` is a `ValueNotifier<AuthStatus>` with `bootstrapping / authenticated /
  unauthenticated`. Never route to Login while `bootstrapping` — that's what makes a
  signed-in user see the login form on a cold start.
- `authHeaders` → `{Authorization: Bearer <jwt>, Content-Type: application/json}`.
  **Every** warehouse call passes this.
- `ensuredAuthHeaders()` / `ensureAccessToken()` wait out a token rotation before forcing a
  refresh. Not needed for warehouse calls (no WS layer here) but harmless to keep.
- `onSignedOut` is the only path back to Login: manual logout, or an unrecoverable refresh
  failure.

Ported screens: splash → login (password **and** email OTP) → forgot password → reset
password (via `app_links` deep link). `AuthController` adds `GET /api/v1/auth/me`.

### 4.4 Theme

Copy `AppColors` verbatim. The values the warehouse UI leans on:

| Token | Value | Used for |
| --- | --- | --- |
| `brandNavy` | `#0A1420` | primary text, active pills, tag chips, primary buttons |
| `brandYellow` | `#FFD84D` | SKU code badges at 30 % opacity, primary badge |
| `background` / `white` | `#FFFFFF` | page + card surfaces |
| `inputFill` | `#F2F3F5` | every field fill |
| `inputBorder` | `#E6CC85` | field + card borders, dividers |
| `textPrimary` / `textSecondary` / `textMuted` | `#0A1420` / `#4F5C70` / `#8A93A4` | text ramp |
| `primaryYellow` → `primaryOrange` | `#FFD84D` → `#FFD84D` | scan-card gradient |
| `buttonShadow` | `#330A1420` | scan card shadow |
| `vipps` | `#FF5B24` | destructive / error icons |
| `mascotShadow` | `#C9A53A` | ACTIVE badge |

All copy renders through `CustomText(title, {fontSize, fontWeight, color, letterSpacing,
height, maxLines, overflow, textAlign})` — a flat-parameter `Text` wrapper. Use it
everywhere; do not call `Text()` directly.

### 4.5 Localization

`LocalizationService.init()` runs **before** `runApp` so the first frame is already in the
right language.

- `defaultLocale = Locale('nb','NO')` (primary), fallback `en`.
- Catalogues are `assets/translations/<code>.json`, flat `{key: value}`.
- `GetMaterialApp(translations: AppTranslations(...), locale:, fallbackLocale:,
  supportedLocales:, localizationsDelegates: [GlobalMaterial/Widgets/Cupertino])`.
- Strings are referenced as `TKeys.someKey.tr`, and with placeholders as
  `TKeys.k.trParams({'count': '3'})`.
- Persisted in SharedPreferences, so the choice survives a cold start.

**Rule for this port: every new string lands in both `nb.json` and `en.json`.** A key in one
file only renders the other language, which is the bug class this app has to avoid.

### 4.6 GetX registration

`getOrPut<T>(builder, {tag, permanent})` — find-or-put helper used everywhere instead of
bare `Get.put`.

- `InventoryController` — one app-wide instance via `getOrPut`.
- `SkuDetailController` — **one per SKU, tagged with the location id**, created by the view
  that opens the SKU and `Get.delete`d in that view's `dispose`.
- `session_scope.dart` → `resetSessionControllers()` must drop `InventoryController` (and
  any nav controller) on sign-out, or a second account signing in on the same handset sees
  the first account's stock.

---

## 5. App shell — what changes now that Stock is the whole app

In the seller app `StockView` is tab index 3 of a 5-tab bottom bar and renders as a bare
`Column` inside the home `Scaffold`. In the new app:

1. `StockView` becomes the post-login home. Wrap it in its own `Scaffold` with
   `backgroundColor: AppColors.background` and keep the existing 28 px w800 "Warehouse"
   title + 13 px subtitle as an in-body header (not an `AppBar`) so the layout is unchanged.
2. Put **logout + language picker** in an overflow menu or a small profile row in that
   header — the seller app carries those on its Profile tab, which isn't coming across.
3. `StockNavController` exists only to let *other tabs* (the Home quick actions) jump into a
   segment. With no other tabs it can go; keep it only if you want deep links. If you drop
   it, delete the `ever`/`consume` wiring in `_StockViewState.initState`.
4. Keep the 5-way bottom bar out. If you want bottom navigation at all, the segment bar is
   already the navigation.

Everything below §6 is unchanged from the seller app.

---

## 6. Backend contract

Base: `{BASE_URL}/api/v1/seller`. Every request carries `AuthService.instance.authHeaders`.

Envelope, for all of them:

```jsonc
{ "success": true,  "data": { … }, "meta": {} }
{ "success": false, "error": { "code": "…", "message": "…" } }
```

List endpoints put their rows in `data.items[]`.

### 6.1 Stats & SKUs (locations)

| # | Call | Notes |
| --- | --- | --- |
| 1 | `GET /inventory/stats` | → `{ totalSkus, activeSkus, assignedProducts }`. Parser also accepts snake_case and string numbers. |
| 2 | `GET /inventory/locations?limit=25[&isActive=true]` | SKU list. `isActive` only sent when the "active only" filter is on. |
| 3 | `GET /inventory/locations/suggest?q=…` | → `items[{id, code, name}]`. Backs **every** SKU search box (SKUs segment, Assign picker, Search→SKU mode, Move-placement dialog). |
| 4 | `GET /inventory/locations/by-code/{code}` | Exact-match resolve → full detail. `404` → "No SKU found for …". |
| 5 | `GET /inventory/locations/{id}` | → `{ location: {...}, tags: [...], placementCount }`. |
| 6 | `POST /inventory/locations` | Body `{code, name, zone, aisle, shelf, sortOrder, notes, tagIds[]}`; blank strings sent as `null`. `409` → code already exists. On success re-fetch list + stats. |
| 7 | `PATCH /inventory/locations/{id}` | Only non-null fields sent: `{name, zone, aisle, shelf, isActive, notes, tagIds[]}`. Used by Edit **and** Deactivate. |

### 6.2 Tags

| # | Call | Notes |
| --- | --- | --- |
| 8 | `GET /inventory/location-tags` | Whole dictionary → `items[{id, slug, label}]`. |
| 9 | `GET /inventory/location-tags/suggest?q=…` | Live tag search. |
| 10 | `POST /inventory/location-tags` | Body `{slug, label}`. `409` → slug taken. **After a successful create, re-fetch the list and select the tag by slug** — the create response wraps the tag differently from `items[]` and rendering it directly produced a blank chip. |

### 6.3 Placements (products in a SKU)

| # | Call | Notes |
| --- | --- | --- |
| 11 | `GET /inventory/locations/{id}/placements` | → `items[{type:'product', product:{id,name,upc,image}, placements:[…], primaryPlacement:{…}}]`. Quantity is the **sum** of the placement rows. |
| 12 | `POST /inventory/locations/{id}/placements/batch` | `{idempotencyKey, items:[{productId, quantity, quantityMode, isPrimary, clientItemKey}]}`. `quantityMode: "increment"` for the assign flow (quantity 1, isPrimary true); `"set"` for edits and the Save-all action. |
| 13 | `POST /inventory/products/{productId}/placements` | `{locationId, quantity, quantityMode:"increment", isPrimary}`. **The API has no decrement** — the edit sheet therefore asks "how many to add", never "new total". |
| 14 | `DELETE /inventory/placements/{placementId}` | Unlink one product from one bin. |
| 15 | `POST /inventory/placements/{placementId}/move` | `{targetLocationId}`. After success, optimistically drop the row, re-fetch, then drop it again — a read-after-write can still return the moved row. |

### 6.4 Pending / unknown products

| # | Call | Notes |
| --- | --- | --- |
| 16 | `GET /inventory/locations/{id}/pending-unknown` | → `items[{itemId, upc, name, quantity, imageUrls[], submittedAt, updatedAt}]`. |
| 17 | `POST /inventory/locations/{id}/unknown-product` | `{upc, requestedName, quantityRequested, requestedImageUrls:[s3Key…]}`. This is where an unrecognised UPC lands. |
| 18 | `PATCH /inventory/locations/{id}/pending-unknown/{itemId}` | `{name, upc?, quantity, imageUrls[]}` — `imageUrls` is the **final set** (kept existing + newly uploaded keys), sent verbatim. |
| 19 | `DELETE /inventory/locations/{id}/pending-unknown/{itemId}` | |

### 6.5 Search

| # | Call | Notes |
| --- | --- | --- |
| 20 | `GET /inventory/search/by-upc?upc=…` | → `{kind:"upc", query, items[]}`. Item `type` is `product` / `placement` / `location`. `404` is **an empty result, not an error**. |
| 21 | `GET /inventory/search/by-tag?tagSlug=…&includeProducts=true` | Same shape, `kind:"tag"`. |

Endpoint 20 is also the assign-flow catalog lookup: first item carrying a non-empty
`product.id` → *found*; no items, `404`, or `error.code == "NOT_FOUND"` → *not found* (open
the manual sheet); anything else → *error*.

### 6.6 Product detail & discrepancy reports

| # | Call | Notes |
| --- | --- | --- |
| 22 | `GET /products/{productId}/preview` | Rich product for the quick views. Payload may carry the product at the root **or** nested under `product` — handle both. |
| 23 | `GET /inventory/products/{productId}/issue[?locationId=…]` | → `data.issue {description|message, imageUrls[]}`, or nothing when there's no report. Prefills the report form. |
| 24 | `PATCH /inventory/products/{productId}/issue` | `{message, imageKeys[], locationId?}`. Product-level from Search; bin-scoped (with `locationId`) from a SKU. |
| 25 | `POST /product-request-issue-images` | multipart, field `file`, JPEG/PNG/WebP ≤ 5 MB → `{s3Key}`. Shared by report photos, pending-product photos and the manual-add sheet. |

### 6.7 Measurements (inside both quick views)

| # | Call | Notes |
| --- | --- | --- |
| 26 | `GET /products/{id}/measurement-bundle` | Recorded values + the measurement-type catalog in one read. |
| 27 | `POST /measurements/{id}` | Bare array body `[{fieldKey, valueCm}]`. Render the response's own `measurements` — re-reading the bundle can serve pre-write data. |
| 28 | `DELETE /measurements/by-id/{id}` | `404` counts as success. |
| 29 | `POST /products/{id}/size-spec-images` | multipart `file`, ≤ 5 MB → `{s3Key}`. Nothing is attached until #30 runs. |
| 30 | `PUT /products/{id}/size-spec-images` | `{imageUrls: [key…]}` — **replaces** the whole set; an empty list clears it. There is no delete endpoint by design. |

### 6.8 Error handling — apply uniformly

| Status / code | Meaning | UI |
| --- | --- | --- |
| `403` | Not a managed seller | "Warehouse is only available for managed sellers." — the whole module is gated on this. |
| `404` | Missing SKU / placement / product | Friendly per-call message; on **search** it means "no results". |
| `409` | Duplicate SKU code or tag slug | "A SKU/tag with that code already exists." |
| `422` | Validation | "Please check the details and try again." |
| `401` + `AUTH_EXPIRED` | Token aged out | `recoverOrLogout()` — refresh first, sign out only if that fails. |
| `AUTH_ROLE_REQUIRED` | Not a seller account | Snackbar + logout. |
| exception | Network | "Network error. Please try again." |

Reads set an `*Error` observable that the section renders in a `StockStatsError` card with a
retry. Writes **return** a nullable error string (`null` == success) and the caller shows a
`Get.snackbar`.

---

## 7. Models

Copy these eight files unchanged; they're deliberately tolerant of server shape drift.

- **`InventoryStats`** — `totalSkus`, `activeSkus`, `productsAssigned`. Reads any of
  `assignedProducts / productsAssigned / placements / totalPlacements`, camel or snake, num
  or string.
- **`InventoryLocation`** — `id, code, name, zone?, aisle?, shelf?, isActive, sortOrder,
  tagSlugs[]` + `locationPath` = non-blank parts joined with `" · "`.
- **`InventoryLocationDetail`** — same fields plus `notes?`, `tags[InventoryTag]`,
  `placementCount`; reads `json['location']` or falls back to the root.
  `locationPath` here is labelled: `"Zone 01 · Aisle A · Shelf B3"`.
- **`InventoryPlacement`** — `productId, productName, upc?, image?, quantity, isPrimary,
  placementId?`. `quantity` sums `placements[]`; `placementId` is the primary's id, else the
  first row's; `isPrimary` true when `primaryPlacement` exists or any row flags it.
- **`InventoryTag`** — `id, slug, label` (label falls back to slug).
- **`LocationSuggestion`** — `id, code, name`.
- **`PendingProduct`** — `itemId, name, upc?, quantity, imageUrls[], submittedAt?,
  updatedAt?` + `displayImage` = first `http…` entry (the list mixes URLs and storage keys).
- **`InventorySearchResult` / `InventorySearchItem` / `SearchProduct` / `SearchPlacement`** —
  normalizes the three item shapes; `isProduct / isPlacement / isLocation` helpers.
  `SearchPlacement` carries `id, productId, locationId, locationCode, locationName,
  quantity, isPrimary, locationIsActive`.

Plus `ProductRequestProduct` (id, name, brand?, shortDescription?, image?, thumbnailUrl?,
images[], colour?, sizesAvailable[], colorsAvailable[], originalPrice?, regularPrice?),
`ProductRequestIssue` (message, imageUrls[], reportedAt?) and the measurement models.

---

## 8. Controllers

### `InventoryController` (app-wide, `getOrPut`)

One controller, several independent state groups — each has its own loading flag, error
string and data field, so one failing section never blanks another.

| Group | State | Methods |
| --- | --- | --- |
| Stats | `isLoadingStats`, `statsError`, `stats` | `fetchStats()` — called in `onInit` |
| SKU list | `isLoadingLocations`, `locationsError`, `locations`, `activeOnly` | `fetchLocations({activeOnly})` |
| Resolve by code | `isResolvingCode`, `byCodeError`, `byCode` | `fetchLocationByCode(code)`, `clearByCode()` |
| SKU suggest | `isSuggesting`, `suggestError`, `suggestions`, `hasSuggested` | `suggestLocations(q)`, `clearSuggestions()` |
| Tag suggest | `isSuggestingTags`, `tagSuggestions`, `hasSuggestedTags` | `suggestTags(q)`, `clearTagSuggestions()` |
| Tags | `isLoadingTags`, `tagsError`, `tags`, `isCreatingTag` | `fetchTags()`, `createTag(slug, label)` |
| Search | `isSearching`, `searchError`, `searchResult`, `hasSearched` | `searchByUpc(upc)`, `searchByTag(slug)`, `clearSearch()` |
| Writes | `isCreatingLocation` | `createLocation(...)`, `addProductPlacement(...)`, `addUnknownProductToLocation(...)` |
| Quick view | — | `fetchQuickViewProduct(id)`, `fetchProductIssue(...)`, `submitProductIssue(...)`, `uploadProductRequestImage(path)` |
| Assign lookup | — | `lookupUpcForAssign(upc) → UpcLookupResult{status: found/notFound/error, productId, productName, message}` |

`hasSuggested` / `hasSearched` matter: they separate "nothing typed yet" (show the hint)
from "searched and got nothing" (show the empty state).

### `SkuDetailController(locationId)` (one per SKU, tagged)

`_base = {BASE_URL}/api/v1/seller/inventory/locations/{locationId}`.

State: `isLoadingDetail/detailError/detail`, `isLoadingPlacements/placementsError/
placements`, `isLoadingPending/pendingError/pending`, `isSaving`, `primaryCount`.
`onInit` loads detail + placements.

Methods: `fetchDetail`, `fetchPlacements`, `fetchPendingUnknown`, `updateLocation(...)`,
`saveAllPlacements()`, `savePlacement(productId, quantity, isPrimary)`,
`incrementPlacement(productId, addQuantity, isPrimary)`, `deletePlacement(placementId)`,
`movePlacement(placementId, targetLocationId)`, `searchLocations(q)` (its own, so the move
dialog never touches shared suggest state), `updatePendingUnknown(...)`,
`deletePendingUnknown(itemId)`, `uploadIssueImage(path)`, `fetchQuickViewProduct(id)`,
`fetchProductIssue(...)`, `submitProductIssue(...)`.

Every write re-fetches the list it touched before returning.

---

## 9. Screens

### 9.1 Shell + segment bar — `stock_view.dart`

- `BrandedRefreshIndicator` → `SingleChildScrollView(AlwaysScrollableScrollPhysics(parent:
  BouncingScrollPhysics()))`.
- Header padding `(18,14,18,0)`: title 28 px w800 `letterSpacing -0.6`; 6 px gap; subtitle
  13 px w500 `height 1.45` muted.
- 12 px gap → segment bar → 16 px gap → body in `EdgeInsets.symmetric(horizontal: 18)` →
  32 px tail.
- **Segment pill**: `AnimatedContainer` 180 ms, padding `(16, 9)`, radius 22, 8 px gap,
  active = navy fill + navy border + white label, inactive = white fill + `inputBorder` +
  `textSecondary`. Label is `UPPERCASE`, 11.5 px w800, `letterSpacing 0.5`. The row scrolls
  horizontally with `BouncingScrollPhysics` and 20 px side padding.
- Pull-to-refresh is per segment: Overview/SKUs → `fetchStats()`; Assign → the section's
  `refresh()` (detail + placements + pending, or re-run the SKU query); Search → the
  section's `refresh()` (re-run the current mode's query). Assign and Search are reached
  through `GlobalKey<…SectionState>`.

### 9.2 Overview

`StockStatsCards(compact: true)` — two cards, TOTAL and ASSIGNED, in one row (the ACTIVE
card is intentionally commented out). Then "Quick actions" (14 px w800) and 2×2 cards with
12 px gutters:

| Card | Icon | Action |
| --- | --- | --- |
| Manage SKUs | `inventory_2_rounded` | → SKUs segment |
| Assign to SKU | `add_box_rounded` | → Assign segment |
| Search | `search_rounded` | → Search segment |
| New SKU | `add_rounded` | opens `NewSkuDialog` — **highlighted** (navy fill, white text) |

Card: radius 16, 1.2 px border (`#BFC7D2` normal / navy when highlighted), 40×40 icon tile
radius 12 (`brandYellow @ 30 %`, or `white @ 14 %` when highlighted), title 14.5 px w800,
subtitle 11.5 px w500.

### 9.3 SKUs

Subtitle row + dense "New SKU" pill → `StockSearchField` → results.
Typing debounces **350 ms** into `suggestLocations`; submit runs it immediately and unfocuses.
States: 3 skeleton boxes while loading · `StockStatsError` with retry · idle hint
("Start typing…", `inventory_2_outlined`) · empty hint ("No SKUs match", `search_off_rounded`)
· the list. List is one white container, radius 14, `inputBorder`, rows split by 1 px
dividers. Row = yellow-tinted code badge (radius 8, 12 px w800 navy), name 14 px w700,
chevron. Tap → `SkuDetailView(locationId, initialCode)`; on return, `fetchStats()`.

### 9.4 Assign to SKU

Hint line, then one white card (radius 16, `inputBorder`, padding 16) that is either the
**picker** or the **selected SKU**.

*Picker*: "Select SKU" 16 px w600 → same debounced suggest search and the same five states
as §9.3.

*Selected*: code badge + name + a "Change" chip (resets everything and tears the tagged
`SkuDetailController` down). Then:

1. **`AssignProductsPanel`** (`key: ValueKey(sku.id)`)
   - Right-aligned `AutoQuickViewToggle` (static `AutoQuickViewPref.enabled`, defaults **on**
     each launch, not persisted).
   - **Scan card** — yellow→amber gradient, radius 20, `buttonShadow` blur 22 offset (0,12),
     padding 20, 46×46 navy icon tile with `qr_code_scanner_rounded`, title 17 px w800,
     subtitle 12.5 px, trailing arrow.
   - **UPC row** — `Expanded` numeric `TextField` (hint "Enter UPC", `qr_code_2_rounded`
     prefix, `inputFill`, radius 12, no border) + a 52 px navy button, radius 12,
     padding-h 20, label 14 px w700. **The button is labelled "Add" / "Legg til"**
     (`TKeys.addAction`) — it read "Thrown"/"Kastet" in an earlier build; don't reintroduce
     that. `onSubmitted` runs the same handler, and the button shows a 20 px spinner while
     busy.
2. **`SkuProductsSection`** — the assigned + pending lists (§9.7).

**Scan / type → add flow** (identical for both entry points):

```
raw barcode ──► strip leading zeros (fall back to raw if all zeros)
            ──► lookupUpcForAssign(upc)              [GET /inventory/search/by-upc]
    found    ──► addProductPlacement(locationId, productId, qty 1, isPrimary true)
                 └─ ok → append to the session list, clear the field, onAdded(),
                         if AutoQuickViewPref.enabled → refetch placements, find the row,
                         open AssignedProductQuickView, snackbar "Product added to SKU"
                 └─ err → error snackbar
    notFound ──► open the manual add sheet with the UPC pre-filled
    error    ──► error snackbar
```

**Manual add sheet** (bottom sheet, `isScrollControlled`, padded by `viewInsets.bottom`,
radius 20 top): title "Add UPC manually" 18 px w800 + body 13 px, close button; fields UPC
(numeric) / Product name / Quantity (digits only), each `inputFill` + radius 12 + no border
+ content padding `(16,14)`; a 110 px horizontal image strip (thumbnails with a remove
badge, in-flight spinners, then an "Add Image" tile); full-width 50 px navy submit, radius
12, label "Add Product" (switches to "Uploading images…" while uploads run). Images upload
one at a time to **#25** for their `s3Key`, then the sheet POSTs **#17**.

Code128 barcodes drop their first three characters inside the scanner view itself.

### 9.5 Search

Mode selector (segmented: **UPC · Tag · SKU**) over one adaptive search card.

- **UPC** — numeric field, an outlined "Scan" button, and a Search button. No live search:
  it runs on submit or on Scan (the scanned code is dropped into the field and searched
  immediately).
- **Tag** — 350 ms debounced `suggestTags`; suggestions render *inside* the search card
  under a divider; picking one sets the field to the tag label and runs `searchByTag(slug)`.
- **SKU** — 350 ms debounced `suggestLocations`, results are tappable rows → SKU detail.

Switching modes clears the field, the selected tag and all three result states.

**Results** (UPC / Tag) are grouped: a **SKUs** section first, then **Products**. Each group
is a header with a count plus one soft container with hairline dividers — no per-row cards.
`placement` items whose product already appears as a `product` item are dropped so nothing
shows twice. A SKU row shows code badge, name, an active/inactive status dot and tag slugs,
and opens the detail page. A product row shows name + UPC, small bin chips (`code ×qty`) for
each placement, and a navy "Quick view" text button that opens `ProductQuickView`.

Empty / not-yet-searched states use one centred placeholder.

### 9.6 SKU detail — `sku_detail_view.dart`

`Scaffold`, white `AppBar`, title = `detail.code` (falls back to `initialCode`, then `"SKU"`),
action = **Edit** `TextButton.icon` opening `NewSkuDialog` in edit mode. Body is a
`BrandedRefreshIndicator` over a `ListView` padded `(20,16,20,32)`:

1. **Header** — "SKU CODE" caption 11 px w700 `letterSpacing 0.6`, code 30 px w800
   `letterSpacing -0.6`, name 16 px w700 secondary, then badges: `ACTIVE`/`INACTIVE`
   (filled, `mascotShadow` / muted), "N products assigned", "N PRIMARY" (yellow). Badge =
   radius 8, padding `(10,5)`, 11 px w800, colour at 14 % (filled) or 8 % opacity.
2. **Tags card** — white, radius 16, `inputBorder`, padding 18. "SKU TAGS" caption, then
   navy pill chips (radius 22, padding `(14,9)`, uppercase 11.5 px w800 white) built from
   `tags[].label`, falling back to `tagSlugs`. "No tags" when empty. Location path 13.5 px
   w600 underneath when present.
3. **Assign product** — caption + body, then the same `AssignProductsPanel`; `onAdded`
   refreshes detail + placements + pending.
4. **Products in SKU** — `SkuProductsSection`.

Loading = centred navy spinner; error = card with message + "Try again".

### 9.7 `SkuProductsSection` — assigned + pending

Shared verbatim by Assign and SKU detail so both have identical powers. A two-tab switcher
("Assigned" / "Pending"), then:

**Assigned rows** — image (falls back to an icon), name, UPC, quantity, a red delete
affordance, an **Edit** button, and **Move**. Deleting confirms first, then calls #14.

**`EditPlacementDialog`** — because the API can't decrement, the sheet asks **how many units
to add** on top of the current quantity, plus the primary flag, and calls #13. (`savePlacement`
with `quantityMode:"set"` exists for the Save-all path.)

**`MovePlacementDialog`** — searches SKUs with the controller's own `searchLocations(q)`,
shows the hits, and on confirm calls #15.

**Pending rows** — image, name, UPC, quantity, Edit + red Delete.
**`_EditPendingDialog`** — name, UPC (display-only), quantity, and images: existing images
are removable, newly picked ones upload immediately for their `s3Key`s (72×72 thumbs, spinner
placeholders while uploading), and save PATCHes #18 with `imageUrls` = kept + new.

### 9.8 `NewSkuDialog` — create **and** edit

Full-height scroll-controlled bottom sheet. `show(context, inventoryCtrl, {initial,
detailCtrl})` — passing `initial` + `detailCtrl` switches it to edit mode (prefilled, current
tags selected, saves with `PATCH` #7 including `tagIds` so tag changes stick). Create posts #6.

- Opens by loading the tag dictionary (#8).
- **Auto-composed SKU code**: zone + rack + shelf + sort order concatenate into one uppercase
  code (`PL · L8 · 06 · 10 → "PLL80610"`). It keeps recomposing as those fields change —
  until the user types in the code field themselves, after which their value is kept. Only in
  create mode. Setting `.text` programmatically must not trip the "user edited" flag.
- **Tags**: debounced search over #9, tap a suggestion to select it, selected tags render as
  removable chips, and a "New tag" button slugifies the current query
  ("Cold Storage" → `cold-storage`) and creates it via #10, then selects it.
- There's also a framed "NEW SKU TAG" sub-form (label + slug + add).
- Primary button is full-width with an inline spinner while saving.

### 9.9 Quick views

Two near-identical bottom sheets — keep them both, they differ in where the report is filed:

| | `ProductQuickView` (from Search) | `AssignedProductQuickView` (from a SKU) |
| --- | --- | --- |
| Input | `SearchProduct` + its placements | `InventoryPlacement` + `SkuDetailController` |
| Product data | #22 via `InventoryController` | #22 via `SkuDetailController` |
| Report scope | product-level (**no** `locationId`) | bin-scoped (`locationId` sent) |

Both: load the product on open and fall back to the caller's own fields, showing unavailable
specs as `-`; render hero image, brand, title, suggested / MRP price, colour, sizes,
description; then **Report a discrepancy** — a message field, preset chips (Size / Color /
Picture / Other) that append a word to the field and keep the caret at the end, and up to
**10** images (camera or gallery via a source sheet; only JPEG/PNG/WebP — anything else
raises an "unsupported file" snackbar). On open, #23 prefills the message and previously
uploaded images. Submitting uploads each new image via #25 and then PATCHes #24; a failed
upload aborts with a per-file message. Both embed `MeasurementGoalsSection`
(`AssignedProductQuickView` passes `placementId` + `skuCode`; `ProductQuickView` doesn't).

### 9.10 `MeasurementGoalsSection`

`{productId, placementId?, skuCode?}`. Loads #26 + the product's size-spec images, lets the
seller add one numeric row per measurement type and attach photos, saves with #27 and #30,
removes server-side rows via #28. Copy the file whole — the shape-tolerant parsing in
`measurement.dart` (`valueCm`/`value`/`valueInCm`, `key`/`fieldKey`, `s3Key`/`key`/`url`)
exists because the endpoint's payload varies.

### 9.11 `BarcodeScannerView`

Full-screen `mobile_scanner`, `DetectionSpeed.normal`, back camera, stops on the first valid
detection and slides a result card up with rescan / accept. Pops the `Barcode`. **Code128
codes have their first three characters removed** inside `_onDetect`. Leading-zero stripping
is the *caller's* job (assign flow only).

### 9.12 Shared chrome — `stock_widgets.dart`

- **`StockSearchField`** — container `inputFill`, radius 14, `inputBorder`, padding `(14,6)`,
  19 px leading icon, 10 px gap, borderless dense `TextField` 13.5 px w600.
- **`StockPillButton`** — navy, radius 12 (10 dense), padding `(16,11)` / `(11,7)` dense,
  icon 17/14, label 13/11.5 w700; `expanded` makes it full-width.
- **`StockStatsCards`** / **`StockStatCard`** — compact: padding `(10,12)`, radius 12, label
  9.5 px, value 20 px; full: padding 18, radius 16, label 11 px, value 30 px w800
  `letterSpacing -0.5`, optional note, navy 4 % shadow.
- **`StockStatsLoading`** — same boxes with a 22 px spinner.
- **`StockStatsError`** — white card, radius 16, error icon in `vipps`, "Something went
  wrong" 14 px w700, the message 12.5 px, and a `StockPillButton` "Try again". Used for
  every read failure in the module, not just stats.

---

## 10. Cross-cutting rules

1. **Debounce is 350 ms** for every live suggest (SKU, tag). UPC search never live-searches.
2. **Clear on entry.** Each section clears its search / suggestion state in `initState` so
   reopening a segment never shows the previous query's results.
3. **Unfocus** before running a search, picking a suggestion or opening a scanner.
4. **Reads set error observables, writes return error strings.** Keep that split — the UI
   depends on it (inline error card vs. snackbar).
5. **Refetch after every write**, inside the controller method, before it returns.
6. **`Get.snackbar(TKeys.successTitle.tr | TKeys.errorTitle.tr, …)`** for all write feedback.
7. **One `SkuDetailController` per SKU, tagged by location id**, deleted by whoever created
   it. Assign creates one when a SKU is picked and disposes it on "Change".
8. **Auto quick view** is a static, non-persisted, default-on preference shared by every
   scanning screen.
9. **Currency is NOK** — prices render as `kr 1234`, never with `$`.
10. **Empty vs. idle** are different states everywhere (`hasSearched` / `hasSuggested`).

---

## 11. Localization

The module uses **215 keys** (including the scanner and measurements screens), all present in
both `nb.json` and `en.json` today — 129 of them are the `st_*` warehouse namespace. Extract
exactly those into the new app:

```bash
# from the seller app repo
grep -rhoE "TKeys\.[a-zA-Z0-9_]+" lib/views/stock lib/views/scanner lib/views/measurements \
  lib/controllers/inventory_controller.dart lib/controllers/sku_detail_controller.dart \
  lib/core/widgets | sed 's/TKeys\.//' | sort -u > /tmp/used.txt
python3 - <<'PY'
import json, re
src = open('lib/core/localization/translation_keys.dart').read()
const = dict(re.findall(r"static const (\w+)\s*=\s*'([^']+)'", src))
used  = [l.strip() for l in open('/tmp/used.txt') if l.strip()]
keys  = sorted({const[u] for u in used if u in const})
for cat in ('en', 'nb'):
    full = json.load(open(f'assets/translations/{cat}.json'))
    out  = {k: full[k] for k in keys if k in full}
    json.dump(out, open(f'/tmp/{cat}.stock.json', 'w'), ensure_ascii=False, indent=2)
    print(cat, len(out), 'of', len(keys))
PY
```

Namespaces in play: `st_*` (warehouse), plus shared keys — `error_title`, `success_title`,
`try_again`, `retry`, `loading`, `edit`, `delete`, `save`, `cancel`, `add_action`,
`quick_actions`, `enter_upc`, `enter_upc_label`, `enter_upc_number`, `add_upc_manually`,
`add_upc_manually_body`, `scan_and_add_product`, `use_camera_to_scan`, `add_image`,
`product_name_label`, `enter_name_hint`, `size_label`, `color_label`, `picture_label`,
`other_label`, `unsupported_file`, `only_image_types`, `report_updated`,
`describe_discrepancy_error`, `cs_change`, `svc_*` (service-layer messages) and the
measurement keys.

**Two gaps to close while porting** (both are bugs in the source, don't copy them across):

- `AutoQuickViewToggle` hardcodes the English `'Auto quick view'`. Give it a key in both
  catalogues.
- Most `InventoryController` / `SkuDetailController` error strings are hardcoded English
  ("Warehouse is only available for managed sellers.", "Network error. Please try again.",
  "A SKU with that code already exists.", …) while a handful already use `TKeys.svc*`.
  Move **all** of them onto keys, in both languages.

---

## 12. Things to fix on the way over

1. The two localization gaps above.
2. `lib/views/stock/overview/overview_section.dart` carries a large commented-out SKU search
   block, and `stock_widgets.dart` a commented-out ACTIVE stat card. Delete the dead code
   rather than porting it.
3. `StockSegment.activity` and `activity_section.dart` are commented out / placeholder.
   Leave them behind.
4. `assign_products_panel.dart`'s class doc still says the UPC field has a "Thrown button" —
   the button is now **Add**. Fix the comment when you copy it.
5. `InventoryController`'s class doc claims it "only wraps `/inventory/stats`" — badly stale;
   rewrite it.
6. The models reference `lib/raw/MOBILE_SELLER_INVENTORY_API_GUIDE.md`, which is **not in the
   repo**. Either get that guide from the backend team and ship it alongside this file, or
   strip the "(guide §5.x)" references so nobody chases a missing doc.
7. `withOpacity` is deprecated across all of these files. Since it's a fresh repo, convert to
   `withValues(alpha:)` as you paste — it's mechanical and it'll silence ~40 analyzer infos.
8. Several commented-out blocks in `assign_products_panel.dart` (the "added this session"
   list and `_AssignItemCard`) are dead. Decide: ship the feature or delete it.

---

## 13. Acceptance checklist

A build is done when a seller can, signed in on a fresh install:

- [ ] Cold-start straight into the Warehouse without seeing a login flash, and stay signed in
      across restarts.
- [ ] See live Total / Assigned counts, and a clear "managed sellers only" message on a 403.
- [ ] Create a SKU — code auto-composes from zone/rack/shelf/sort, and stops auto-composing
      the moment the code is typed by hand.
- [ ] Attach an existing tag **and** create a brand-new tag inline, with the new chip
      rendering its label (not blank).
- [ ] Find a SKU by typing three characters, open it, edit it, and deactivate it.
- [ ] Assign to a SKU by **scanning** a known barcode — the product lands and its quick view
      opens automatically (and doesn't, when the toggle is off).
- [ ] Assign by typing a UPC and pressing **Add** / **Legg til**.
- [ ] Scan an unknown UPC → the manual sheet opens UPC-prefilled, accept photos, and the row
      appears under **Pending**.
- [ ] Edit an assigned product's quantity (adding units, not setting a total), flip the
      primary flag, move it to another SKU, and delete it.
- [ ] Edit a pending product's name / quantity / images, and delete it.
- [ ] Search by UPC, by tag, and by SKU, with results grouped SKUs-then-Products and no
      duplicate product rows.
- [ ] Open a product quick view, see its specs, file a discrepancy with 3 photos, reopen it
      and find the message and photos prefilled.
- [ ] Record measurements and a size-spec photo, reopen, and see them.
- [ ] Pull to refresh on every segment and re-fetch the right thing.
- [ ] Switch the language to English and back to Norwegian with **no raw keys and no
      untranslated English** anywhere in the module.
- [ ] Sign out and sign in as a second seller — no trace of the first account's stock.

---

*Generated from `tommesalg_seller_app` @ branch `boopathi`. Companion docs in `lib/raw/`:
`FLUTTER_SELLER_APPLICATION.md`, `SELLER_CHAT_UI_PROMPT.md`,
`FLUTTER_SELLER_CAMERA_LENS_SELECTION_GUIDE.md`.*
