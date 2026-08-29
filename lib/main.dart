import 'dart:async';
import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tommesalg_seller_app/core/config/env_config.dart';
import 'package:tommesalg_seller_app/core/localization/app_translations.dart';
import 'package:tommesalg_seller_app/core/localization/localization_service.dart';
import 'package:tommesalg_seller_app/core/localization/translation_keys.dart';
import 'package:tommesalg_seller_app/core/services/api_client.dart';
import 'package:tommesalg_seller_app/core/services/auth_service.dart';
import 'package:tommesalg_seller_app/core/services/deep_link_service.dart';
import 'package:tommesalg_seller_app/controllers/notification_controller.dart';
import 'package:tommesalg_seller_app/features/notifications/application/notification_router.dart';
import 'package:tommesalg_seller_app/features/notifications/application/push_destination.dart';
import 'package:tommesalg_seller_app/features/notifications/application/push_notification_service.dart';
import 'package:tommesalg_seller_app/views/auth/login_view.dart';
import 'package:tommesalg_seller_app/views/splash/splash_view.dart';

import 'firebase_options.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await EnvConfig.init();
  // Loads nb/en catalogues and resolves the start locale, so the very first
  // frame already paints in the right language.
  await LocalizationService.init();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // FCM wiring. Must run before `runApp` because `onBackgroundMessage` has to
  // be registered before the engine can be woken by a push. Asks for no
  // permission and makes no network call here: the initial permission prompt
  // happens on the splash, and device registration after sign-in.
  await PushNotificationService.instance.initialize();
  // Restores any persisted session and turns on automatic token refresh.
  // Both are SDK defaults — no manual refresh logic required.
  await Supabase.initialize(
    url: EnvConfig.supabaseProdUrl,
    anonKey: EnvConfig.supabaseProdAnonKey,
  );
  await AuthService.instance.init();

  // Our backend reported the JWT is dead (401 AUTH_EXPIRED). That is not proof
  // the seller has to sign in again — the access token may just have aged out
  // while the refresh token is still good — so try one refresh first and only
  // sign out when that fails. Signing out on every 401 would drop sellers out
  // of a live auction over a token that was simply due for rotation.
  ApiClient.instance.onSessionExpired =
      () => unawaited(AuthService.instance.recoverOrLogout());

  // The signed-in account isn't a seller (any API → AUTH_ROLE_REQUIRED). Sign
  // out and bounce to login; `onSignedOut` handles the actual routing.
  ApiClient.instance.onRoleRequired = () {
    Get.snackbar(TKeys.accessDeniedTitle.tr, TKeys.accessDeniedBody.tr);
    AuthService.instance.logout();
  };

  // The only paths that send the user back to login: a manual logout, or a
  // refresh-token failure the SDK couldn't recover from.
  //
  // The push teardown here is the *backstop* for forced sign-outs (expired
  // session, wrong role) — by this point the bearer token is gone, so the
  // backend DELETE is skipped and only local state is cleared. A deliberate
  // logout detaches the device properly in `AuthController.logout`, which runs
  // before the token is thrown away.
  AuthService.instance.onSignedOut = () {
    unawaited(PushNotificationService.instance.onSignedOut());
    _routeToLogin();
  };

  // Listens for the password-recovery deep link, installs the recovery
  // session, and routes to ResetPasswordView. Idempotent across hot restarts.
  await DeepLinkService.instance.start();

  // Attached (rather than assigned) so the tap that cold-started the app —
  // delivered during `initialize()` above, before this line ran — is replayed
  // instead of dropped.
  PushNotificationService.instance.attachTapHandler(_onNotificationTap);

  runApp(const MyApp());
}
//
/// Routes a tapped notification.
///
/// The payload is read by [PushDestination] — which digs the same ids out of
/// the several shapes the backend spreads them across — and the navigation
/// itself is [NotificationRouter]'s, shared with the taps that come from rows
/// in the notification inbox. A payload that points at nothing the seller app
/// can open leaves the app on whatever screen it was on, which is the safe
/// default: routing to the wrong screen is worse than not routing at all.
void _onNotificationTap(RemoteMessage message) {
  // The service already logged the full payload; this line is about the routing
  // decision, so the console shows the tap *and* what the app did with it.
  log('push: tap routed to handler — messageId=${message.messageId ?? '—'} '
      'type=${message.data['type'] ?? '—'}');

  // A push that arrived is a push the badge doesn't know about yet.
  if (Get.isRegistered<NotificationController>()) {
    unawaited(Get.find<NotificationController>().fetchUnreadCount());
  }

  final destination = PushDestination.parse(message.data);
  if (destination == null) {
    log('push: payload carries no destination — staying on the current screen');
    return;
  }
  unawaited(
    NotificationRouter.openWith(appNavigatorKey.currentState, destination),
  );
}

void _routeToLogin() {
  appNavigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginView()),
    (route) => false,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Seller Squad',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      // Norwegian is the primary language; English is the per-key fallback so
      // a gap in nb.json renders English rather than the raw key.
      translations: AppTranslations(LocalizationService.translations),
      locale: LocalizationService.startLocale,
      fallbackLocale: LocalizationService.fallbackLocale,
      supportedLocales: LocalizationService.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SplashView(),
    );
  }
}
