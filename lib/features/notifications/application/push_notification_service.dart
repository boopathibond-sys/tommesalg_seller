import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../firebase_options.dart';
import '../data/device_identity.dart';
import '../data/models/notification_device.dart';
import '../data/notification_device_api.dart';

/// Handles a push that arrived while the app was terminated or backgrounded.
///
/// Runs in its **own isolate** with no access to the app's globals, GetX
/// bindings, or navigator — so it must re-initialise Firebase itself and can
/// only do self-contained work. We deliberately do nothing but log: Android and
/// iOS already draw the system notification from the `notification` block of
/// the payload, and the tap is handled back on the main isolate by
/// [PushNotificationService._handleTap].
///
/// `@pragma('vm:entry-point')` is mandatory — without it AOT tree-shakes this
/// function away and background pushes crash the isolate in release builds.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  PushNotificationService.logMessage(
    'RECEIVED · background/terminated',
    message,
  );
}

/// The app's single entry point for Firebase Cloud Messaging.
///
/// Lifecycle, in the order the app drives it:
///
///  1. [initialize] — from `main()`, before `runApp`. Wires the background
///     handler, the local-notification channel, and the message listeners.
///     Does **not** ask for permission and does **not** touch the network.
///  2. [requestPermission] — the "initial" ask, fired from the splash once the
///     first frame is up so the OS dialog lands on a real screen.
///  3. [onAuthenticated] — after a successful sign-in (and on cold start into
///     an already-signed-in session). Ensures permission, resolves the FCM
///     token and registers it against the seller's account.
///  4. [onSignedOut] — from the logout / session-teardown path, so a shared
///     handset stops receiving the previous seller's pushes.
///
/// Every step is best-effort. Push is an enhancement; nothing here may throw
/// into a caller or block navigation.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  /// Status-bar icon, referenced by **bare name** — see
  /// [_initLocalNotifications]. The AndroidManifest meta-data entry uses the
  /// `@drawable/…` form instead, because that one *is* a real resource
  /// reference resolved by the manifest merger rather than at runtime.
  static const String _androidIcon = 'ic_notification';

  /// Must match `default_notification_channel_id` in AndroidManifest.xml —
  /// Android 8+ silently drops a background notification whose payload names a
  /// channel that was never created. Kept identical to the buyer app's id so a
  /// backend that pins `android.notification.channel_id` hits a live channel in
  /// both apps.
  static const String _channelId = 'tommesalg_default';
  static const String _channelName = 'Streams & orders';
  static const String _channelDescription =
      'Stream approvals, bids and orders from your live auctions.';

  /// Persisted so we can `DELETE` exactly this registration on logout, and so a
  /// cold start with an unchanged token can skip a redundant POST.
  static const String _prefsRowIdKey = 'push.device_row_id';
  static const String _prefsFingerprintKey = 'push.device_fingerprint';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final NotificationDeviceApi _remote = NotificationDeviceApi();

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedSub;

  /// Invoked when the seller taps a notification (foreground, background, or
  /// the cold-start tap that launched the app).
  ///
  /// Left as an injection point rather than a hard-coded `switch` on
  /// `data['type']`, because the routing table belongs to whoever owns the
  /// backend's notification catalogue. Attach it with [attachTapHandler] — see
  /// `main.dart`.
  void Function(RemoteMessage message)? onNotificationTap;

  /// A tap that arrived before [onNotificationTap] was set — typically the
  /// cold-start tap, which is delivered during `initialize()` while the widget
  /// tree is still being built. Replayed as soon as a handler is attached.
  RemoteMessage? _pendingTap;

  // ───────────────────────────── 1. bootstrap ─────────────────────────────

  /// Wires FCM into the app. Safe to call more than once.
  ///
  /// Called from `main()` **after** `Firebase.initializeApp` and **before**
  /// `runApp`, because [FirebaseMessaging.onBackgroundMessage] must be
  /// registered before the engine can be woken by a background push.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // `main()` awaits this *before* `runApp`, so an escaping exception would
    // mean a blank app rather than an app without push. Nothing in here is
    // worth that trade: swallow, log, carry on.
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _initLocalNotifications();

      // iOS draws foreground alerts itself once these options are set. Android
      // never does, which is why [_onForegroundMessage] draws one only on
      // Android — doing both would show the same push twice on iOS.
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _onMessageSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      _onOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handleTap(message, source: 'background→foreground'),
      );

      // The tap that cold-started the app. Non-null at most once per launch.
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleTap(initial, source: 'cold start');

      // Firebase rotates tokens (app restore, ~monthly refresh, data clear). A
      // stale token on the backend is a silently undelivered notification, so
      // re-register immediately whenever it changes.
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) {
        // Also printed here: a rotation invalidates whatever token you last
        // copied, so a test push aimed at the old one silently goes nowhere.
        _printToken(token, 'rotated');
        unawaited(_registerToken(token));
      });

      log('push: initialised');
    } catch (e) {
      log('push: initialise failed — $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    // Bare resource name, NOT '@drawable/ic_notification'. The plugin resolves
    // it with `Resources.getIdentifier(name, "drawable", packageName)`, which
    // returns 0 for the '@drawable/…' form — and a 0 small-icon makes Android
    // reject the notification, so it just never appears.
    const android = AndroidInitializationSettings(_androidIcon);
    // All three `request*Permission` flags are false: permission is asked
    // explicitly via [requestPermission] at a moment we control, not as a
    // side-effect of plugin initialisation during app start.
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onLocalNotificationResponse,
    );

    // Create the channel up-front so the very first *background* push has a
    // channel to land in — Android only creates it lazily otherwise.
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
  }

  // ──────────────────────────── 2. permission ────────────────────────────

  /// Asks the OS for notification permission.
  ///
  /// Called twice by design — once on first launch ("initially") and again
  /// right after sign-in. That is safe: both platforms only ever show the
  /// system dialog once, and every later call just reports the standing
  /// decision without prompting.
  ///
  /// Returns true when notifications are allowed (including iOS's
  /// `provisional`, which delivers quietly to the notification centre).
  Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final status = settings.authorizationStatus;
      log('push: permission = $status');
      return status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
    } catch (e) {
      log('push: permission request failed — $e');
      return false;
    }
  }

  /// The current permission state without prompting.
  Future<bool> hasPermission() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      final status = settings.authorizationStatus;
      return status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────── 3. registration ───────────────────────────

  /// Ensures permission, then registers this device's FCM token against the
  /// signed-in seller. Call after every successful sign-in **and** on cold
  /// start into a restored session — the second case matters because the
  /// backend row may have been pruned, or the token rotated while the app was
  /// closed.
  ///
  /// Never throws; failures are logged and retried on the next launch.
  Future<void> onAuthenticated() async {
    try {
      final granted = await requestPermission();
      if (!granted) {
        log('push: permission denied — not registering device');
        return;
      }
      final token = await _resolveToken();
      if (token == null) return;
      await _registerToken(token);
    } catch (e) {
      log('push: onAuthenticated failed — $e');
    }
  }

  /// Resolves the FCM token, waiting for the APNs token first on iOS.
  ///
  /// On iOS `getToken()` returns null (or throws) until APNs has handed the
  /// device token to Firebase, which is racy right after launch. Poll briefly
  /// rather than failing the registration outright — `onTokenRefresh` is the
  /// backstop if this still comes up empty.
  Future<String?> _resolveToken() async {
    try {
      if (Platform.isIOS) {
        var apns = await _messaging.getAPNSToken();
        for (var i = 0; i < 5 && apns == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          apns = await _messaging.getAPNSToken();
        }
        if (apns == null) {
          log('push: no APNs token yet — deferring to onTokenRefresh');
          return null;
        }
      }
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        log('push: getToken returned empty');
        return null;
      }
      _printToken(token, 'sign-in');
      return token;
    } catch (e) {
      log('push: getToken failed — $e');
      return null;
    }
  }

  /// Dumps the FCM token to the console so it can be copied straight into the
  /// Firebase console's "Send test message" box, or a curl against the FCM v1
  /// API, without wiring up a debug screen.
  ///
  /// Debug builds only — a registration token is a send-to-this-device
  /// capability, so it must never reach a production log sink.
  void _printToken(String token, String reason) {
    if (!kDebugMode) return;
    log(
      '\n══════════ FCM TOKEN ($reason) ══════════\n'
      '$token\n'
      '════════════════════════════════════════',
    );
  }

  /// POSTs the device to the backend, skipping the call when nothing the
  /// backend stores has changed since the last successful registration.
  Future<void> _registerToken(String token) async {
    final prefs = await SharedPreferences.getInstance();

    final device = NotificationDevice(
      token: token,
      platform: NotificationDevice.currentPlatform,
      deviceId: await DeviceIdentity.id(),
      deviceName: await DeviceIdentity.name(),
      appVersion: _appVersion,
      locale: Get.locale?.languageCode,
    );

    // The fingerprint is only ever written after a *successful* POST, so its
    // presence means "the backend already has exactly this payload" and the
    // call can be skipped. A failed attempt leaves it untouched, which is what
    // makes the next launch retry instead of silently giving up.
    if (prefs.getString(_prefsFingerprintKey) == device.fingerprint) {
      log('push: device already registered — skipping');
      return;
    }

    final result = await _remote.register(device);
    if (!result.ok) return;

    // Not every backend echoes a row id; when it doesn't we simply can't issue
    // a targeted DELETE later. See [onSignedOut] for how that degrades.
    final rowId = result.id;
    if (rowId != null && rowId.isNotEmpty) {
      await prefs.setString(_prefsRowIdKey, rowId);
    }
    await prefs.setString(_prefsFingerprintKey, device.fingerprint);
  }

  // ──────────────────────────── 4. teardown ─────────────────────────────

  /// Detaches this device from the account being signed out.
  ///
  /// Deletes the backend row, clears the cached fingerprint, and drops the FCM
  /// token so the next seller gets a fresh one rather than inheriting delivery
  /// aimed at the previous account.
  ///
  /// **Call this before `signOut()`** — the DELETE needs the bearer token that
  /// signing out throws away. When it runs after (a forced sign-out on an
  /// expired session), the network call is skipped and only the local state is
  /// cleared; the backend then reaps the row itself, or the next
  /// registration overwrites it via the `deviceId` upsert key.
  ///
  /// Best-effort and non-blocking by contract — the logout path must complete
  /// even with no network.
  Future<void> onSignedOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rowId = prefs.getString(_prefsRowIdKey);

      // Hard ceiling on the network portion. This runs *inside* the logout /
      // session-teardown path, which the seller is watching, so it must not be
      // able to stall it — on timeout we abandon the DELETE and still clear the
      // local state below.
      await _remote
          .unregister(rowId)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);

      await prefs.remove(_prefsRowIdKey);
      await prefs.remove(_prefsFingerprintKey);

      // Invalidate the token itself so pushes already queued for the old
      // account can't land on the next seller's session.
      try {
        await _messaging.deleteToken();
      } catch (_) {}

      log('push: device detached on sign-out');
    } catch (e) {
      log('push: onSignedOut failed — $e');
    }
  }

  // ───────────────────────────── logging ─────────────────────────────────

  /// Renders one push into a single multi-line console entry.
  ///
  /// Every arrival and every tap funnels through here, so the console shows the
  /// same fields in the same order no matter which of the five paths delivered
  /// the message (foreground, background isolate, background tap, cold-start
  /// tap, tap on a locally-drawn notification). That uniformity is the point:
  /// "did this push actually arrive, and did the tap carry its payload?" is
  /// answerable from the log alone, without instrumenting a screen.
  ///
  /// Public and static because the background handler runs in its own isolate
  /// as a top-level function and has no instance to reach for.
  static void logMessage(String event, RemoteMessage message) {
    final notification = message.notification;
    final data = message.data;

    // FCM data values are strings, but a tap replayed from a locally-drawn
    // notification round-trips through JSON and can carry anything. Never let a
    // log line be the thing that throws.
    String encodedData;
    try {
      encodedData = data.isEmpty ? '{}' : jsonEncode(data);
    } catch (_) {
      encodedData = data.toString();
    }

    log(
      '\n╔═══════ PUSH $event\n'
      '║ messageId : ${message.messageId ?? '—'}\n'
      '║ sentTime  : ${message.sentTime?.toIso8601String() ?? '—'}\n'
      '║ from      : ${message.from ?? '—'}\n'
      '║ title     : ${notification?.title ?? '—'}\n'
      '║ body      : ${notification?.body ?? '—'}\n'
      '║ type      : ${data['type'] ?? '—'}\n'
      '║ data      : $encodedData\n'
      '╚════════════════════════════════════════',
    );
  }

  // ───────────────────────────── message flow ────────────────────────────

  /// A push that arrived while the app is in the foreground.
  ///
  /// Android suppresses system notifications in this state, so we draw one
  /// ourselves. iOS already showed it via
  /// [FirebaseMessaging.setForegroundNotificationPresentationOptions].
  void _onForegroundMessage(RemoteMessage message) {
    logMessage('RECEIVED · foreground', message);
    if (!Platform.isAndroid) return;

    final notification = message.notification;
    if (notification == null) {
      // Worth its own line: a data-only push arrives but draws nothing, which
      // otherwise looks identical to "the push never came".
      log('push: data-only payload — no notification drawn');
      return;
    }

    _local.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: _androidIcon,
        ),
      ),
      // Carry the data payload through so a tap on *this* locally-drawn
      // notification routes the same way a system one would.
      payload: jsonEncode(message.data),
    );
  }

  /// Tap on a notification we drew ourselves via flutter_local_notifications.
  /// Rebuilt into a [RemoteMessage] so both tap paths converge on [_handleTap].
  void _onLocalNotificationResponse(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) {
      log('push: local notification tapped with an empty payload — not routed');
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        log('push: local notification payload was not a map — not routed');
        return;
      }
      _handleTap(
        RemoteMessage(data: decoded.map((k, v) => MapEntry(k.toString(), v))),
        source: 'foreground/local',
      );
    } catch (e) {
      log('push: bad local notification payload — $e');
    }
  }

  void _handleTap(RemoteMessage message, {required String source}) {
    logMessage('TAPPED · $source', message);
    final handler = onNotificationTap;
    if (handler == null) {
      // Handler not attached yet (cold-start tap). Hold it for replay.
      log('push: tap queued — no handler attached yet, will replay');
      _pendingTap = message;
      return;
    }
    handler(message);
  }

  /// Attaches the tap handler and immediately replays a tap that arrived before
  /// it existed. Prefer this over assigning [onNotificationTap] directly —
  /// otherwise the cold-start tap is silently dropped.
  void attachTapHandler(void Function(RemoteMessage message) handler) {
    onNotificationTap = handler;
    final pending = _pendingTap;
    if (pending != null) {
      _pendingTap = null;
      log('push: replaying queued tap ${pending.messageId ?? '—'}');
      handler(pending);
    }
  }

  /// Version string sent with the registration. Read from a const rather than
  /// package_info_plus to avoid pulling in another plugin for one field — keep
  /// in step with `version:` in pubspec.yaml.
  static const String _appVersion = '1.0.1+13';

  /// Only meaningful in tests / hot-restart scenarios; the service is a
  /// process-lifetime singleton in normal use.
  @visibleForTesting
  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _onMessageSub?.cancel();
    await _onOpenedSub?.cancel();
    _initialized = false;
  }
}
