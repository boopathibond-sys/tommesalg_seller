/// Multi-device session state from `GET /session/devices`, `GET /session/status`
/// and the `snapshot` embedded in claim / control responses. All of them return
/// the identical shape:
///
/// ```json
/// {
///   "devices": [{ "deviceId", "role", "connectedAt", "lastHeartbeatAt" }],
///   "pendingRequests": [{ "id", "fromDeviceId", "createdAt" }],
///   "auctionControllerDeviceId": "…|null",
///   "pendingAuctionControlRequests": [{ "id", "fromDeviceId", "createdAt" }]
/// }
/// ```
///
/// The two request lists back **independent** handoff systems and must never be
/// merged: `pendingRequests` ids are only valid on `/primary/{approve,reject}`,
/// and `pendingAuctionControlRequests` ids only on
/// `/auction-control/{approve,reject}`. Crossing them fails with AUTH_FORBIDDEN.
library;

class SessionDevicesSnapshot {
  const SessionDevicesSnapshot({
    this.devices = const [],
    this.pendingPrimaryRequests = const [],
    this.pendingAuctionControlRequests = const [],
    this.auctionControllerDeviceId,
  });

  final List<SessionDevice> devices;

  /// Outstanding requests for the PRIMARY role (`pendingRequests`). Answered by
  /// whichever device currently *is* PRIMARY.
  final List<ControlRequest> pendingPrimaryRequests;

  /// Outstanding requests for auction control. Answered by whichever device
  /// currently holds auction control.
  final List<ControlRequest> pendingAuctionControlRequests;

  /// Device holding auction control, or null when unset. Independent of PRIMARY
  /// — a SECONDARY device may hold auction control.
  final String? auctionControllerDeviceId;

  /// The PRIMARY device's id, derived from the device list (the server reports
  /// the role per device rather than as a top-level field).
  String? get primaryDeviceId {
    for (final d in devices) {
      if (d.isPrimary) return d.deviceId;
    }
    return null;
  }

  factory SessionDevicesSnapshot.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (json[key] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(parse)
            .toList() ??
        const [];

    return SessionDevicesSnapshot(
      devices: list('devices', SessionDevice.fromJson),
      pendingPrimaryRequests: list('pendingRequests', ControlRequest.fromJson),
      pendingAuctionControlRequests:
          list('pendingAuctionControlRequests', ControlRequest.fromJson),
      auctionControllerDeviceId: json['auctionControllerDeviceId'] as String?,
    );
  }
}

class SessionDevice {
  const SessionDevice({
    required this.deviceId,
    this.role,
    this.connectedAt,
    this.lastHeartbeatAt,
    required this.raw,
  });

  final String deviceId;
  final String? role; // PRIMARY | SECONDARY
  final String? connectedAt;
  final String? lastHeartbeatAt;
  final Map<String, dynamic> raw;

  bool get isPrimary => role == 'PRIMARY';

  factory SessionDevice.fromJson(Map<String, dynamic> json) => SessionDevice(
        deviceId: (json['deviceId'] ?? json['device_id'] ?? '') as String,
        role: (json['role'] ?? json['sessionRole']) as String?,
        connectedAt: json['connectedAt'] as String?,
        lastHeartbeatAt:
            (json['lastHeartbeatAt'] ?? json['lastSeenAt']) as String?,
        raw: json,
      );
}

class ControlRequest {
  const ControlRequest({
    required this.requestId,
    required this.deviceId,
    this.createdAt,
    required this.raw,
  });

  /// `id` — passed back as `requestId` on approve/reject.
  final String requestId;

  /// `fromDeviceId` — the device asking for control. The web client and older
  /// builds spell it `deviceId`, so both are accepted.
  final String deviceId;
  final String? createdAt;
  final Map<String, dynamic> raw;

  factory ControlRequest.fromJson(Map<String, dynamic> json) => ControlRequest(
        requestId: (json['id'] ?? json['requestId'] ?? '') as String,
        deviceId: (json['fromDeviceId'] ?? json['deviceId'] ?? '') as String,
        createdAt: (json['createdAt'] ?? json['requestedAt']) as String?,
        raw: json,
      );
}
