# Tommesalg Flutter Seller — Camera / Lens Selection Implementation Guide

**Document:** Flutter developer implementation guide  
**Feature:** Seller-side camera/lens selection for live streaming  
**Platforms:** iOS + Android  
**RTC:** Agora Flutter SDK  
**Repository reference:** Tommesalg web/staging codebase  
**Status:** Implementation specification

---

## 1. Purpose

The Tommesalg seller web application already allows the seller to select the camera used for a live stream.

On a desktop/browser this is implemented by enumerating Agora media devices and selecting a browser `deviceId`.

On a mobile application, **do not copy the browser implementation literally**.

For Flutter on iOS and Android, the correct implementation is:

1. Use Agora's mobile camera configuration APIs.
2. Query the camera's supported focal-length capabilities.
3. Build the selector from the capabilities actually returned by the device.
4. Use `CameraDirection` for front/rear selection.
5. Use `CameraFocalLengthType` for wide-angle, ultra-wide and telephoto selection.
6. Persist the seller's preferred camera mode locally.
7. When the seller changes the lens during a live stream, keep the Agora channel/session alive; only restart/reconfigure the local camera capture if required by the SDK lifecycle.

The objective is to give the seller a consistent camera selector across iOS and Android without hard-coding a particular phone's camera layout.

---

# 3. Implementation Scope

This guide defines the required implementation for the Tommesalg Flutter seller application on **iOS and Android**.

The feature must allow a seller to:

- Discover the cameras/lenses actually available on the device.
- Select the desired camera or lens before starting a live stream.
- Change the selected camera/lens during an active live stream.
- Persist the seller's preferred camera selection for the stream.
- Fall back safely when a previously selected camera/lens is unavailable.

The implementation must be based on the capabilities exposed by the installed Agora Flutter SDK and the underlying mobile device.

# 4. Important Mobile Difference

## Do NOT implement mobile as:

```text
getCameras()
    ↓
browser deviceId
    ↓
setDevice(deviceId)
```

That API model is primarily the web/desktop device-management model.

For Flutter mobile, Agora exposes camera direction and focal-length APIs.

The current Agora Flutter API provides:

```dart
CameraDirection
CameraFocalLengthType
FocalLengthInfo
```

and:

```dart
Future<List<FocalLengthInfo>> queryCameraFocalLengthCapability()
```

The supported focal-length values are:

```dart
CameraFocalLengthType.cameraFocalLengthDefault
CameraFocalLengthType.cameraFocalLengthWideAngle
CameraFocalLengthType.cameraFocalLengthUltraWide
CameraFocalLengthType.cameraFocalLengthTelephoto
```

`cameraFocalLengthTelephoto` is iOS-only.

The focal-length capability API is specifically documented for Android and iOS.

---

# 5. Required Flutter Dependency

Use the official Agora Flutter package:

```yaml
dependencies:
  agora_rtc_engine: ^6.6.3
```

**Important:** If the Flutter application already has an approved Agora SDK version, use the project's approved version rather than blindly upgrading. The APIs in this document are based on the current 6.6.x API surface verified during preparation of this guide.

Do not mix examples from old `agora_rtc_engine` 5.x documentation with the 6.x implementation.

---

# 6. Camera Capability Model

Create an application-level model rather than exposing Agora objects directly to the UI.

Recommended:

```dart
enum SellerCameraMode {
  front,
  rearStandard,
  rearWideAngle,
  rearUltraWide,
  rearTelephoto,
}

class SellerCameraOption {
  final SellerCameraMode mode;
  final String label;
  final CameraDirection direction;
  final CameraFocalLengthType focalLengthType;

  const SellerCameraOption({
    required this.mode,
    required this.label,
    required this.direction,
    required this.focalLengthType,
  });
}
```

The UI should work with `SellerCameraOption`.

It should not depend directly on `FocalLengthInfo`.

---

# 7. Camera Labels

Use friendly labels.

Recommended mapping:

| Agora capability | UI label |
|---|---|
| Front + Default | Front |
| Rear + Default | Back |
| Rear + Wide Angle | Wide |
| Rear + Ultra Wide | Ultra Wide |
| Rear + Telephoto | Telephoto |

Do not display internal enum names to the seller.

Do not assume that every device supports all five choices.

For example:

```text
iPhone with multiple rear lenses

Front
Back
Wide
Ultra Wide
Telephoto
```

Another device might expose:

```text
Front
Back
Ultra Wide
```

Another device may expose only:

```text
Front
Back
```

The UI must adapt to the actual capability response.

---

# 8. Query Camera Capabilities

After creating and initializing `RtcEngine`, query the device.

```dart
final List<FocalLengthInfo> infos =
    await engine.queryCameraFocalLengthCapability();
```

Example:

```dart
Future<List<SellerCameraOption>> loadCameraOptions(
  RtcEngine engine,
) async {
  final infos = await engine.queryCameraFocalLengthCapability();

  final options = <SellerCameraOption>[];

  for (final info in infos) {
    final direction = _cameraDirectionFromValue(info.cameraDirection);
    final focalLength = info.focalLengthType;

    if (direction == null || focalLength == null) {
      continue;
    }

    options.add(
      SellerCameraOption(
        mode: _modeFromCapability(direction, focalLength),
        label: _labelFromCapability(direction, focalLength),
        direction: direction,
        focalLengthType: focalLength,
      ),
    );
  }

  return _deduplicateOptions(options);
}
```

The exact nullable handling may need to match the installed Agora package version.

---

# 9. Capability Mapping

The important fields are:

```dart
FocalLengthInfo.cameraDirection
FocalLengthInfo.focalLengthType
```

The focal-length enum is:

```dart
CameraFocalLengthType.cameraFocalLengthDefault
CameraFocalLengthType.cameraFocalLengthWideAngle
CameraFocalLengthType.cameraFocalLengthUltraWide
CameraFocalLengthType.cameraFocalLengthTelephoto
```

The direction is:

```dart
CameraDirection.cameraFront
CameraDirection.cameraRear
```

Example mapping:

```dart
SellerCameraMode _modeFromCapability(
  CameraDirection direction,
  CameraFocalLengthType focalLength,
) {
  if (direction == CameraDirection.cameraFront) {
    return SellerCameraMode.front;
  }

  switch (focalLength) {
    case CameraFocalLengthType.cameraFocalLengthWideAngle:
      return SellerCameraMode.rearWideAngle;

    case CameraFocalLengthType.cameraFocalLengthUltraWide:
      return SellerCameraMode.rearUltraWide;

    case CameraFocalLengthType.cameraFocalLengthTelephoto:
      return SellerCameraMode.rearTelephoto;

    case CameraFocalLengthType.cameraFocalLengthDefault:
      return SellerCameraMode.rearStandard;
  }
}
```

Use the enum values from the installed SDK. Do not manually use integer values such as `0`, `1`, `2`, or `3` in application code.

---

# 10. Recommended Initialization Order

The seller stream camera lifecycle should be:

```text
Create RtcEngine
      ↓
Initialize
      ↓
Request camera/microphone permission
      ↓
Query focal-length capabilities
      ↓
Build camera selector
      ↓
Load saved seller preference
      ↓
Resolve preference against available capabilities
      ↓
Configure camera
      ↓
Start local preview / camera
      ↓
Join Agora channel
      ↓
Publish camera
```

The exact join/publish sequence must follow the existing Flutter Agora integration, but the camera configuration must be applied at the appropriate point before local camera capture starts.

---

# 11. Configure the Selected Camera

Agora provides:

```dart
await engine.setCameraCapturerConfiguration(
  CameraCapturerConfiguration(
    cameraDirection: CameraDirection.cameraRear,
    cameraFocalLengthType:
        CameraFocalLengthType.cameraFocalLengthUltraWide,
  ),
);
```

For front camera:

```dart
await engine.setCameraCapturerConfiguration(
  const CameraCapturerConfiguration(
    cameraDirection: CameraDirection.cameraFront,
    cameraFocalLengthType:
        CameraFocalLengthType.cameraFocalLengthDefault,
  ),
);
```

For rear standard:

```dart
await engine.setCameraCapturerConfiguration(
  const CameraCapturerConfiguration(
    cameraDirection: CameraDirection.cameraRear,
    cameraFocalLengthType:
        CameraFocalLengthType.cameraFocalLengthDefault,
  ),
);
```

For rear wide:

```dart
await engine.setCameraCapturerConfiguration(
  const CameraCapturerConfiguration(
    cameraDirection: CameraDirection.cameraRear,
    cameraFocalLengthType:
        CameraFocalLengthType.cameraFocalLengthWideAngle,
  ),
);
```

For rear ultra-wide:

```dart
await engine.setCameraCapturerConfiguration(
  const CameraCapturerConfiguration(
    cameraDirection: CameraDirection.cameraRear,
    cameraFocalLengthType:
        CameraFocalLengthType.cameraFocalLengthUltraWide,
  ),
);
```

For iOS telephoto:

```dart
await engine.setCameraCapturerConfiguration(
  const CameraCapturerConfiguration(
    cameraDirection: CameraDirection.cameraRear,
    cameraFocalLengthType:
        CameraFocalLengthType.cameraFocalLengthTelephoto,
  ),
);
```

---

# 12. Critical Rule: Do Not Combine cameraId and focalLengthType

For mobile lens selection, do not attempt:

```dart
CameraCapturerConfiguration(
  cameraId: '...',
  cameraFocalLengthType: CameraFocalLengthType.cameraFocalLengthUltraWide,
)
```

The Agora API documentation specifies that focal-length selection is used with `cameraDirection`, not `cameraId`.

`cameraId` is primarily the precise camera-ID mechanism for Android.

Therefore, for the Tommesalg mobile lens selector:

```text
cameraDirection + cameraFocalLengthType
```

is the preferred abstraction.

---

# 13. Android Camera IDs

Android can expose camera IDs through native Android APIs.

However, **do not make the Tommesalg UI depend on Android camera IDs for lens selection**.

Use the Agora focal-length capability API first.

Only introduce Android native `cameraId` handling if a specific Android manufacturer/device cannot be correctly addressed through the Agora focal-length API and there is a confirmed product requirement for that device.

This prevents the Flutter implementation from becoming manufacturer-specific.

---

# 14. Live Switching

This is the most important implementation distinction from the web.

## Web

The web implementation can do:

```ts
await video.setDevice(deviceId)
```

without reconnecting.

## Flutter mobile

The mobile focal-length configuration API is documented as a camera-capture configuration and must be applied before local camera capture starts.

Therefore, **do not assume that Flutter has a direct equivalent of web `video.setDevice(deviceId)` for focal-length switching**.

For a lens change while the seller is already live, use this approach:

```text
Seller is already joined to Agora
          ↓
User selects another lens
          ↓
Keep Agora channel/session alive
          ↓
Stop/reconfigure local camera capture as required
          ↓
Apply new CameraCapturerConfiguration
          ↓
Start local camera capture again
          ↓
Continue publishing
```

The Agora channel should not be unnecessarily left and rejoined.

There may be a short local-video interruption while the capture source is reconfigured. The implementation should show a small loading state during this operation.

---

# 15. Example Live Camera Switch Service

Create a dedicated service rather than putting camera logic inside the widget.

Recommended:

```text
lib/
  streaming/
    camera/
      seller_camera_service.dart
      seller_camera_models.dart
      seller_camera_storage.dart
```

Example service:

```dart
class SellerCameraService {
  final RtcEngine engine;

  SellerCameraService(this.engine);

  Future<List<SellerCameraOption>> getOptions() async {
    final infos = await engine.queryCameraFocalLengthCapability();

    return _mapCapabilities(infos);
  }

  Future<void> configureCamera(
    SellerCameraOption option,
  ) async {
    await engine.setCameraCapturerConfiguration(
      CameraCapturerConfiguration(
        cameraDirection: option.direction,
        cameraFocalLengthType: option.focalLengthType,
      ),
    );
  }
}
```

Keep this service independent from:

- auction state
- bid state
- product state
- seller control state
- chat state

Camera failure must not terminate the auction.

---

# 16. Live Switch Implementation

Use a serialized switch operation.

```dart
bool _cameraSwitchInProgress = false;

Future<bool> switchCamera(
  SellerCameraOption option,
) async {
  if (_cameraSwitchInProgress) {
    return false;
  }

  _cameraSwitchInProgress = true;

  try {
    // Keep Agora channel connected.
    //
    // Stop/restart local camera capture only if required by
    // the installed Agora SDK lifecycle.

    await engine.stopCameraCapture(
      VideoSourceType.videoSourceCameraPrimary,
    );

    await engine.setCameraCapturerConfiguration(
      CameraCapturerConfiguration(
        cameraDirection: option.direction,
        cameraFocalLengthType: option.focalLengthType,
      ),
    );

    await engine.startCameraCapture(
      sourceType: VideoSourceType.videoSourceCameraPrimary,
      config: CameraCapturerConfiguration(
        cameraDirection: option.direction,
        cameraFocalLengthType: option.focalLengthType,
      ),
    );

    return true;
  } on AgoraRtcException catch (e) {
    // Log and expose a user-friendly error.
    debugPrint(
      'Camera switch failed: ${e.code} ${e.message}',
    );
    return false;
  } finally {
    _cameraSwitchInProgress = false;
  }
}
```

**Important:** Verify the exact capture restart behavior against the installed Agora Flutter SDK and the current seller publishing implementation before merging this into production.

The invariant is:

```text
DO NOT leave Agora channel just to change camera/lens.
```

---

# 17. Publishing Must Remain Enabled

When restarting camera capture during a live session, make sure the existing `ChannelMediaOptions` still has the camera publishing flag enabled.

Conceptually:

```dart
ChannelMediaOptions(
  publishCameraTrack: true,
  publishMicrophoneTrack: true,
)
```

The actual channel configuration should follow the application's existing Agora integration.

Do not create a second Agora engine.

Do not create a second channel.

Do not generate a new seller stream.

---

# 18. Local Preview

The seller should see the newly selected lens locally before or immediately when it becomes active.

Use the existing Agora local video view pattern:

```dart
AgoraVideoView(
  controller: VideoViewController(
    rtcEngine: engine,
    canvas: const VideoCanvas(
      uid: 0,
    ),
  ),
)
```

The actual UID/canvas configuration must follow the existing Flutter stream implementation.

The camera selector should be overlaid on the seller stream controls, not implemented as a separate streaming session.

---

# 19. UI Requirements

Recommended UI:

```text
┌─────────────────────────────┐
│ Camera                      │
│                             │
│  ✓ Back                     │
│    Wide                     │
│    Ultra Wide               │
│    Telephoto                │
│    Front                    │
│                             │
└─────────────────────────────┘
```

When a camera is selected:

```text
Camera switching...
```

Disable repeated taps while switching.

After success:

```text
Camera
✓ Ultra Wide
```

After failure:

```text
Unable to switch camera.
Keeping the current camera.
```

Never leave the seller without a working camera just because an optional lens failed.

---

# 20. Default Camera

Recommended default:

```text
Rear standard camera
```

for the seller live-stream experience, if available.

Fallback:

```text
Rear
↓
Front
↓
First available capability
```

Do not assume rear standard exists on every device.

The final fallback must be based on the actual capability list.

---

# 21. Persistence

The web implementation persists camera preference per stream:

```text
stream_<streamId>_camera
```

Flutter should preserve the same logical scope.

Recommended storage value:

```json
{
  "mode": "rearUltraWide"
}
```

rather than persisting only an internal device ID.

Example key:

```text
stream_<streamId>_camera
```

Example value:

```json
{
  "mode": "rearUltraWide"
}
```

Why store the logical mode?

Because mobile hardware/device identifiers can differ between platforms and devices.

The stored value is a preference:

```text
preferred lens
```

not an authoritative camera registry.

---

# 22. Preference Resolution

On stream startup:

```text
Load saved preference
       ↓
Query current capabilities
       ↓
Does saved mode exist?
   ┌───┴───┐
  YES      NO
   │        │
   ↓        ↓
Use it    Pick default
```

Example:

```dart
SellerCameraOption resolvePreferredCamera(
  String? savedMode,
  List<SellerCameraOption> available,
) {
  if (savedMode != null) {
    for (final option in available) {
      if (option.mode.name == savedMode) {
        return option;
      }
    }
  }

  return _selectDefault(available);
}
```

Never fail stream startup merely because the previously selected lens is unavailable.

---

# 23. iOS Multi-Lens Behavior

Agora's current Flutter API explicitly supports focal-length types on iOS:

```text
Default
Wide Angle
Ultra Wide
Telephoto
```

Telephoto is iOS-only.

For multi-lens rear cameras, Agora documents support for selecting ultra-wide through the focal-length configuration.

There is also a zoom-based alternative:

```dart
await engine.setCameraZoomFactor(0.5);
```

when supported.

Do not use the zoom workaround as the primary Tommesalg implementation.

Use:

```dart
cameraFocalLengthType:
    CameraFocalLengthType.cameraFocalLengthUltraWide
```

when the capability is returned.

Use zoom only if there is a product requirement for continuous zoom rather than discrete lens selection.

---

# 24. Android Multi-Camera Behavior

Android device camera layouts vary considerably by manufacturer.

Therefore:

**Do not hard-code:**

```text
Samsung = Wide + Ultra Wide + Telephoto
Pixel = ...
```

Instead:

```dart
final capabilities =
    await engine.queryCameraFocalLengthCapability();
```

and construct the selector dynamically.

Important: Agora documentation notes that on some Android devices a requested focal-length setting may still not take effect even when the capability query reports support.

Therefore the implementation must verify the actual result and handle failure gracefully.

---

# 25. Permission Handling

The app must have camera and microphone permissions before starting the seller stream.

Android requires camera/microphone permissions in the application configuration.

iOS requires:

```text
NSCameraUsageDescription
NSMicrophoneUsageDescription
```

Use seller-facing descriptions appropriate for the Tommesalg app.

Example:

```xml
<key>NSCameraUsageDescription</key>
<string>Tommesalg needs camera access to broadcast your live auction.</string>

<key>NSMicrophoneUsageDescription</key>
<string>Tommesalg needs microphone access to broadcast audio during your live auction.</string>
```

The exact project wording can be adjusted to the application's existing privacy/permission copy.

---

# 26. Error Handling

Handle these cases explicitly:

### Permission denied

Show:

```text
Camera permission is required to start the live stream.
```

### No camera capability

Show:

```text
No compatible camera was found.
```

### Requested lens unavailable

Fallback to current camera.

### Camera switch fails

Do not terminate Agora.

Show:

```text
Unable to switch camera. The current camera is still active.
```

### Camera disconnected / native failure

Attempt the existing camera recovery flow.

Do not end the auction.

---

# 27. Camera and Auction Separation

This is a mandatory architectural rule.

Camera code must not control:

```text
auction start
auction end
bid acceptance
product queue
auction timer
seller control ownership
```

The relationship must be:

```text
Auction
   │
   └── Stream
          │
          └── Agora
                 │
                 └── Camera
```

A camera error is a media error.

It is not an auction error.

This matches the existing web architecture where Agora/video is intentionally isolated from auction state.

---

# 28. Seller PRIMARY / SECONDARY Consideration

The Tommesalg web application has a seller stream-session control model:

```text
PRIMARY
SECONDARY
```

and separate auction-controller ownership.

Flutter must respect the same server-side authority model.

Camera selection itself is a local media operation, but:

- only the appropriate publishing device should publish
- SECONDARY devices must not accidentally become publishers
- UI state must follow the seller session role
- server/API authority remains the source of truth for auction actions

Do not implement PRIMARY/SECONDARY security only in Flutter UI.

---

# 29. Agora Token Flow

The Tommesalg backend already contains Agora token endpoints.

Relevant routes include:

```text
POST /api/v1/agora/token
POST /api/agora/token
```

The Flutter application should use the API contract already established for the mobile integration rather than generating Agora certificates/tokens inside the app.

Never put:

```text
AGORA_APP_CERTIFICATE
```

inside the Flutter application.

The certificate remains server-side.

---

# 30. Suggested Flutter Project Structure

Recommended:

```text
lib/
├── streaming/
│   ├── agora/
│   │   ├── agora_service.dart
│   │   ├── agora_token_service.dart
│   │   └── agora_stream_controller.dart
│   │
│   └── camera/
│       ├── seller_camera_models.dart
│       ├── seller_camera_service.dart
│       ├── seller_camera_storage.dart
│       └── seller_camera_controller.dart
│
└── features/
    └── seller_stream/
        ├── seller_stream_screen.dart
        ├── widgets/
        │   ├── seller_camera_selector.dart
        │   └── seller_camera_preview.dart
        └── state/
            └── seller_stream_state.dart
```

The camera service should be reusable independently of the UI.

---

# 31. Controller Example

Recommended state:

```dart
class SellerCameraState {
  final List<SellerCameraOption> options;
  final SellerCameraOption? selected;
  final bool loading;
  final bool switching;
  final String? error;

  const SellerCameraState({
    this.options = const [],
    this.selected,
    this.loading = false,
    this.switching = false,
    this.error,
  });
}
```

Controller operations:

```dart
Future<void> loadCameras();

Future<void> selectCamera(
  SellerCameraOption option,
);

Future<void> refreshCapabilities();
```

UI:

```dart
ListView.builder(
  itemCount: state.options.length,
  itemBuilder: (_, index) {
    final option = state.options[index];

    return ListTile(
      title: Text(option.label),
      trailing: state.selected?.mode == option.mode
          ? const Icon(Icons.check)
          : null,
      onTap: state.switching
          ? null
          : () => controller.selectCamera(option),
    );
  },
)
```

---

# 32. Testing Matrix

The developer must test on real devices.

## iOS

At minimum:

```text
iPhone with single rear camera
iPhone with wide + ultra-wide
iPhone with wide + ultra-wide + telephoto
iPhone front camera
```

Verify:

```text
Front
Back
Wide
Ultra Wide
Telephoto
```

only appear when actually supported.

## Android

At minimum:

```text
one Android device with rear + front
one Android device with ultra-wide
one Android device with telephoto, if available
```

Verify manufacturer differences.

---

# 33. Live-Switch Test

This is mandatory.

Test:

```text
Start seller preview
↓
Start publishing
↓
Open camera selector
↓
Switch Back → Ultra Wide
↓
Switch Ultra Wide → Wide
↓
Switch Wide → Front
↓
Switch Front → Back
```

Verify:

1. Seller remains in the same stream room.
2. Agora channel is not unnecessarily left/rejoined.
3. Buyers continue receiving the seller stream.
4. The selected camera appears locally.
5. No auction state changes.
6. Auction timer continues.
7. Bids continue.
8. Camera switch failure does not end the auction.

---

# 34. Persistence Test

Test:

```text
Select Ultra Wide
↓
Stop stream
↓
Open the same stream again
```

Expected:

```text
Ultra Wide
```

if the device still supports it.

Then test:

```text
Saved = Telephoto
Device = no Telephoto
```

Expected:

```text
Fallback to available default camera
```

The stream must still start.

---

# 35. Permission Test

Test:

```text
Camera permission allowed
Microphone permission allowed
```

and:

```text
Camera permission denied
```

and:

```text
Microphone permission denied
```

The UI must provide a clear recovery path.

---

# 36. Do Not Implement These Shortcuts

Do not:

```text
Hard-code iPhone lens list
```

Do not:

```text
Assume every Android phone has the same cameras
```

Do not:

```text
Use browser getUserMedia/deviceId logic in Flutter
```

Do not:

```text
Store only a platform-specific camera ID as the business preference
```

Do not:

```text
Leave/rejoin Agora for every lens selection
```

Do not:

```text
Create another RtcEngine during a camera switch
```

Do not:

```text
Tie camera errors to auction termination
```

Do not:

```text
Put Agora App Certificate in Flutter
```

---

# 37. Acceptance Criteria

The implementation is complete only when all of the following are true.

### Capability discovery

- [ ] Flutter queries actual camera focal-length capabilities.
- [ ] Front/rear is supported.
- [ ] Wide-angle is shown only when supported.
- [ ] Ultra-wide is shown only when supported.
- [ ] Telephoto is shown only when supported.
- [ ] Telephoto is treated as iOS-only.

### Seller UI

- [ ] Camera selector exists in seller live-stream controls.
- [ ] Selected camera is clearly indicated.
- [ ] Switching shows a loading state.
- [ ] Repeated selection taps are serialized/blocked.
- [ ] Failure displays a friendly message.

### Agora

- [ ] Existing Agora engine is reused.
- [ ] Existing Agora channel is reused.
- [ ] Camera configuration uses `CameraDirection` + `CameraFocalLengthType`.
- [ ] No browser `deviceId` dependency exists in mobile camera selection.
- [ ] No unnecessary channel leave/rejoin occurs.

### Persistence

- [ ] Preferred camera mode is persisted per stream.
- [ ] Saved preference is validated against current capabilities.
- [ ] Missing cameras fall back safely.

### Auction isolation

- [ ] Camera failure cannot terminate an auction.
- [ ] Camera failure cannot modify bids.
- [ ] Camera failure cannot modify auction timers.
- [ ] Camera selection does not bypass PRIMARY/auction-controller authorization.

### Real-device validation

- [ ] Tested on iOS multi-lens device.
- [ ] Tested on Android device.
- [ ] Tested while actively publishing.
- [ ] Tested with camera permission denied.
- [ ] Tested with previously saved unavailable lens.

---

# 38. Implementation Order

Implement in this order:

```text
STEP 1
Add/verify Agora Flutter dependency
        ↓
STEP 2
Create SellerCameraOption model
        ↓
STEP 3
Create SellerCameraService
        ↓
STEP 4
Query queryCameraFocalLengthCapability()
        ↓
STEP 5
Map FocalLengthInfo → SellerCameraOption
        ↓
STEP 6
Build camera selector UI
        ↓
STEP 7
Add local persistence
        ↓
STEP 8
Configure initial camera before capture
        ↓
STEP 9
Implement live camera/lens switch without leaving Agora
        ↓
STEP 10
Integrate into seller stream screen
        ↓
STEP 11
Run iOS/Android real-device tests
        ↓
STEP 12
Run live buyer-side verification
```

---

# 39. Final Architecture

The finished architecture should look like:

```text
                    TOMMESALG SELLER APP
                            │
                    Seller Stream Screen
                            │
             ┌──────────────┴──────────────┐
             │                             │
        Auction State                Camera State
             │                             │
       Server authority              Camera Service
                                           │
                              queryCameraFocalLengthCapability()
                                           │
                                  Available capabilities
                                           │
                                  SellerCameraOption[]
                                           │
                                  Camera Selector UI
                                           │
                              CameraCapturerConfiguration
                                           │
                                  Agora RtcEngine
                                           │
                                     Live Stream
                                           │
                              ┌────────────┴────────────┐
                              │                         │
                           Buyers                   Seller Preview
```

The key principle is:

> **The UI selects a logical camera/lens capability; the camera service translates that selection into the Agora mobile camera configuration.**

This keeps the Flutter implementation portable across iOS and Android and avoids coupling the product UI to platform-specific camera IDs.

---

## 39. Reference Implementation Summary

The minimum important APIs are:

```dart
// Discover mobile lens capabilities.
final capabilities =
    await engine.queryCameraFocalLengthCapability();

// Configure selected camera/lens.
await engine.setCameraCapturerConfiguration(
  CameraCapturerConfiguration(
    cameraDirection: CameraDirection.cameraRear,
    cameraFocalLengthType:
        CameraFocalLengthType.cameraFocalLengthUltraWide,
  ),
);

// Simple front/rear switch.
await engine.switchCamera();

// Optional zoom control.
await engine.setCameraZoomFactor(1.0);
```

Use `queryCameraFocalLengthCapability()` for the Tommesalg lens selector rather than trying to enumerate browser-style camera IDs.

---

## 40. Developer Note

Before production merge, verify the exact behavior of `setCameraCapturerConfiguration()` and camera capture restart with the Agora Flutter SDK version pinned by the Flutter application.

The API contract is clear about camera focal-length selection, but the **live capture restart sequence is the platform-sensitive part**. It must be validated on real iOS and Android hardware before considering live lens switching production-ready.

The required product behavior remains:

```text
Same seller
Same stream
Same Agora channel
Same auction
Different local camera/lens
```

No camera selection operation should create a new Tommesalg stream or affect auction state.
