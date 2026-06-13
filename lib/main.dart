import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tommesalg_seller_app/core/config/env_config.dart';
import 'package:tommesalg_seller_app/core/services/api_client.dart';
import 'package:tommesalg_seller_app/core/services/auth_service.dart';
import 'package:tommesalg_seller_app/core/services/deep_link_service.dart';
import 'package:tommesalg_seller_app/views/auth/login_view.dart';
import 'package:tommesalg_seller_app/views/splash/splash_view.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await EnvConfig.init();

  // Restores any persisted session and turns on automatic token refresh.
  // Both are SDK defaults — no manual refresh logic required.
  await Supabase.initialize(
    url: EnvConfig.supabaseProdUrl,
    anonKey: EnvConfig.supabaseProdAnonKey,
  );
  await AuthService.instance.init();

  // Our backend reported the JWT is dead (401 AUTH_EXPIRED) → sign out of
  // Supabase. With auto-refresh this should be rare (a genuinely revoked
  // session). The resulting `signedOut` event routes us to login below.
  ApiClient.instance.onSessionExpired = () => AuthService.instance.logout();

  // The signed-in account isn't a seller (any API → AUTH_ROLE_REQUIRED). Sign
  // out and bounce to login; `onSignedOut` handles the actual routing.
  ApiClient.instance.onRoleRequired = () {
    Get.snackbar('Access denied', 'Seller role required. Please sign in with a seller account.');
    AuthService.instance.logout();
  };

  // The only paths that send the user back to login: a manual logout, or a
  // refresh-token failure the SDK couldn't recover from.
  AuthService.instance.onSignedOut = _routeToLogin;

  // Listens for the password-recovery deep link, installs the recovery
  // session, and routes to ResetPasswordView. Idempotent across hot restarts.
  await DeepLinkService.instance.start();

  runApp(const MyApp());
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
      title: 'Tommesalg Seller',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SplashView(),
    );
  }
}
