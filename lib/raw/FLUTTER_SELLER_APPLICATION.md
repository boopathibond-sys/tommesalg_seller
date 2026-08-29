# Flutter — Become a seller (managed application)

**Audience:** Flutter engineers on the Buyer app  
**Host:** `https://tommesalg.no`  
**Envelope:** Success `{ "success": true, "data": ..., "meta": {} }` · Error `{ "success": false, "error": { "code", "message" } }`  
**Product:** Managed seller programme only (web `/become-seller`). Independent seller signup is **not** in this slice.

There are two clients, matching web:

| Who | Auth | Identity fields | Status | CV + submit |
|-----|------|-----------------|--------|-------------|
| Logged-in buyer | `Authorization: Bearer <supabase_access_token>` | Taken from profile — do **not** send name / email / DOB | `GET /api/v1/buyer/seller-application` | `/api/v1/buyer/seller-application/cv` then `POST /api/v1/buyer/seller-application` |
| Guest (not logged in) | No `Authorization` header | User types full name, email, date of birth | None — show the form, then a success screen | `/api/v1/public/seller-application/cv` then `POST /api/v1/public/seller-application` |

Do **not** send a signed-in buyer through the public routes. Public submit stores `user_id = null`; the buyer routes attach the session user.

**Rate limit:** **10 requests / minute** on submit, **20 / minute** on CV → `429 RATE_LIMITED` (keyed by IP + UA + auth header).

---

## Shared form fields (both clients)

Same enums as the web form. Country is Norway only in the current product (`NO`).

| Field | Required | Values / notes |
|-------|----------|----------------|
| `phoneNumber` | yes | Non-empty string. Web uses international format (`+47…`). |
| `address.line1` | yes | Street |
| `address.line2` | no | |
| `address.postalCode` | yes | Norway: exactly **4 digits** |
| `address.city` | yes | |
| `address.country` | no | Defaults to `NO` |
| `address.state` | no | |
| `liveComfort` | yes | `very-comfortable` \| `comfortable` \| `somewhat-comfortable` \| `willing-to-learn` |
| `hoursPerWeek` | yes | `1-3` \| `3-6` \| `6-10` \| `10-plus` |
| `experience` | no | Array of `live-sales` \| `online-retail` \| `sales-certificate` \| `sale-in-store` \| `other`. Empty array is fine. |
| `experienceOther` | if `other` | Trimmed, max 150. Required when `experience` includes `other`. |
| `cvS3Key` | yes | From the CV upload response |

Minimum age is **15**. Norwegian addresses are validated with Bring on submit (same as web). There is no public address-autocomplete V1; guests type the address. Logged-in buyers may optionally call `POST /api/v1/address/validate` (Bearer) before submit.

Client-only (do not send): confirmation checkbox.

Norwegian labels (web):

- Live comfort: Veldig komfortabel / Komfortabel / Litt komfortabel / Ikke komfortabel ennå, men ønsker å lære  
- Hours: 1–3 timer / 3–6 timer / 6–10 timer / 10+ timer  
- Experience: Live Salget / Nettbutikk / Salgssertifikat / Butikksalg / Annet  

CV: **PDF, DOC, or DOCX**, max **2 MB**. Multipart field name is **`cv`**.

---

## Logged-in buyer

`requireBuyer`. Roles `buyer` and `seller_pending` are allowed. Role `seller` → `403 AUTH_FORBIDDEN` on submit. Internal rollout gate applies (same as other buyer V1 routes).

### 1. Status

`GET /api/v1/buyer/seller-application`

```
Authorization: Bearer <supabase_access_token>
Accept: application/json
```

```json
{
  "success": true,
  "data": {
    "status": "none",
    "applicationId": null,
    "applicationType": "managed",
    "canApply": true,
    "rejectionReason": null,
    "rejectedAt": null,
    "reapplyAllowedAt": null,
    "daysLeftToReapply": 0
  },
  "meta": {}
}
```

| `status` | UI |
|----------|-----|
| `none` | Show the form |
| `pending` | Disable the form. Banner: application under review. `canApply` is `false`. |
| `rejected` | If `daysLeftToReapply > 0`, disable submit and show cooldown. Else allow reapply (`canApply: true`). |
| `approved` | Hide apply. User is already a seller (or approved). |

### 2. Prefill (read-only identity)

`GET /api/v1/buyer/profile`

Use:

- **Name** — `displayName` (read-only; if empty, block submit and send them to profile)  
- **Email** — `email` (read-only)  
- **Date of birth** — `birthDate` as `YYYY-MM-DD` (read-only). If missing, block submit and send them to profile.  
- **Phone** — `phone` (editable if empty)  
- **Address** — `defaultAddress.addressLine1` / `addressLine2` / `postalCode` / `city` / `country` / `state`

If `displayName`, `email`, or `birthDate` is missing, `POST` returns `400 VALIDATION_ERROR`: complete profile name, email, and date of birth before applying.

### 3. Upload CV

`POST /api/v1/buyer/seller-application/cv`

```
Authorization: Bearer <supabase_access_token>
Content-Type: multipart/form-data
```

Field: `cv`. Success:

```json
{ "success": true, "data": { "success": true, "s3Key": "users/{userId}/cv/cv-….pdf" }, "meta": {} }
```

### 4. Submit

`POST /api/v1/buyer/seller-application`

```json
{
  "phoneNumber": "+4712345678",
  "address": {
    "line1": "Karl Johans gate 1",
    "line2": null,
    "postalCode": "0154",
    "city": "Oslo",
    "country": "NO"
  },
  "liveComfort": "comfortable",
  "hoursPerWeek": "3-6",
  "experience": ["live-sales"],
  "experienceOther": null,
  "cvS3Key": "users/…/cv/cv-….pdf"
}
```

**201:**

```json
{
  "success": true,
  "data": {
    "applicationId": "8f3c1a2e-…",
    "status": "pending",
    "message": "Application submitted"
  },
  "meta": {}
}
```

`seller_pending` already, or a pending row → **409 CONFLICT**. Rejection still in the 30-day window → **409 CONFLICT** with `daysLeftToReapply` / `reapplyAllowedAt` / `rejectionReason` in `error.details` when debug details are on; always show `error.message`.

---

## Guest (not logged in)

No Bearer token. No status endpoint. After success, show the same thank-you screen as web and stop.

### 1. Upload CV

`POST /api/v1/public/seller-application/cv`

```
Accept: application/json
Content-Type: multipart/form-data
```

Field: `cv`. Key is under `public-applications/cv/…`.

```json
{ "success": true, "data": { "success": true, "s3Key": "public-applications/cv/cv-….pdf" }, "meta": {} }
```

### 2. Submit

`POST /api/v1/public/seller-application`

Same shared fields **plus** identity:

```json
{
  "fullName": "Ada Lovelace",
  "email": "ada@example.com",
  "dateOfBirth": "2000-01-15",
  "phoneNumber": "+4712345678",
  "address": {
    "line1": "Karl Johans gate 1",
    "postalCode": "0154",
    "city": "Oslo",
    "country": "NO"
  },
  "liveComfort": "comfortable",
  "hoursPerWeek": "3-6",
  "experience": ["live-sales"],
  "cvS3Key": "public-applications/cv/cv-….pdf"
}
```

`dateOfBirth` must be `YYYY-MM-DD`. Under 15 → `400 VALIDATION_ERROR`. Duplicate pending application for that **email** → `409 CONFLICT`. Same 30-day reapply cooldown as logged-in (matched by email).

**201** body is the same shape as the buyer submit.

---

## Status codes

| HTTP | `error.code` | When |
|------|----------------|------|
| 201 | — | Application created |
| 200 | — | CV uploaded |
| 400 | `VALIDATION_ERROR` | Bad enum, missing identity, invalid DOB, postal code, Bring address, CV type/size, `experienceOther` |
| 401 | `AUTH_MISSING_TOKEN` / `AUTH_EXPIRED` / `AUTH_INVALID_TOKEN` | Buyer routes only |
| 403 | `AUTH_FORBIDDEN` | Not a buyer, or already a seller (submit) |
| 409 | `CONFLICT` | Pending application, or reapply cooldown |
| 429 | `RATE_LIMITED` | Over the per-route limit |

---

## Dart notes

```dart
// Logged-in: status first
final status = await api.get<Map<String, dynamic>>(
  '/api/v1/buyer/seller-application',
);
if (status['canApply'] != true) {
  // pending / cooldown / already seller
}

final profile = await api.get<Map<String, dynamic>>('/api/v1/buyer/profile');
final defaultAddress =
    profile['defaultAddress'] as Map<String, dynamic>?;

final cv = await api.postMultipart<Map<String, dynamic>>(
  '/api/v1/buyer/seller-application/cv',
  fileField: 'cv',
  file: cvFile,
);
final s3Key = cv['s3Key'] as String;

await api.post('/api/v1/buyer/seller-application', body: {
  'phoneNumber': phone,
  'address': {
    'line1': defaultAddress?['addressLine1'] ?? street,
    'line2': defaultAddress?['addressLine2'],
    'postalCode': defaultAddress?['postalCode'] ?? postal,
    'city': defaultAddress?['city'] ?? city,
    'country': defaultAddress?['country'] ?? 'NO',
  },
  'liveComfort': liveComfort,
  'hoursPerWeek': hoursPerWeek,
  'experience': experience,
  'experienceOther': experienceOther,
  'cvS3Key': s3Key,
});

// Guest: no status, no profile. Upload then submit identity + form.
final guestCv = await api.postMultipart<Map<String, dynamic>>(
  '/api/v1/public/seller-application/cv',
  fileField: 'cv',
  file: cvFile,
  authenticated: false,
);
await api.post(
  '/api/v1/public/seller-application',
  authenticated: false,
  body: {
    'fullName': fullName,
    'email': email,
    'dateOfBirth': dateOfBirth, // YYYY-MM-DD
    'phoneNumber': phone,
    'address': {
      'line1': street,
      'postalCode': postal,
      'city': city,
      'country': 'NO',
    },
    'liveComfort': liveComfort,
    'hoursPerWeek': hoursPerWeek,
    'experience': experience,
    'cvS3Key': guestCv['s3Key'],
  },
);
```

After deploy, guest path (no token):

```bash
# 1) Upload CV
CV_KEY=$(curl -sS -X POST https://tommesalg.no/api/v1/public/seller-application/cv \
  -F "cv=@./cv.pdf;type=application/pdf" | jq -r '.data.s3Key')

# 2) Submit
curl -sS -X POST https://tommesalg.no/api/v1/public/seller-application \
  -H "Content-Type: application/json" \
  -d "{\"fullName\":\"Ada Lovelace\",\"email\":\"ada@example.com\",\"dateOfBirth\":\"2000-01-15\",\"phoneNumber\":\"+4712345678\",\"address\":{\"line1\":\"Karl Johans gate 1\",\"postalCode\":\"0154\",\"city\":\"Oslo\",\"country\":\"NO\"},\"liveComfort\":\"comfortable\",\"hoursPerWeek\":\"3-6\",\"experience\":[\"live-sales\"],\"cvS3Key\":\"$CV_KEY\"}"
```
