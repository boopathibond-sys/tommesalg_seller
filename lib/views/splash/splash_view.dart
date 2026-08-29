import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/dashboard_controller.dart';
import '../../controllers/notification_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/services/auth_service.dart';
import '../../features/notifications/application/push_notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../auth/login_view.dart';
import '../home/home_view.dart';
import '../../core/localization/translation_keys.dart';
import 'package:get/get.dart';


/// First screen the app shows while we hand off to the auth stack.
///
/// Visually anchored to the rest of the app — the Seller Squad app icon and
/// wordmark, echoing the launcher icon. A staged intro animation springs the
/// logo in, then slides the wordmark and tagline up, while a soft brand glow
/// pulses behind the icon.
///
/// It is also the app's **bootstrap gate**: `AuthService.bootstrap()` runs
/// while the intro plays and the route is only chosen once it resolves, so a
/// seller with a persisted session never sees the login form on a cold start —
/// not even for a frame — and an expired access token is refreshed before we
/// decide anything. The screen stays up for whichever finishes last, the
/// animation or the auth check.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with TickerProviderStateMixin {
  // Give the staged intro room to fully play before we navigate away.
  static const _minDisplay = Duration(milliseconds: 2600);

  // Drives the one-shot staged intro (logo → wordmark → tagline → loader).
  late final AnimationController _intro;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _wordmarkFade;
  late final Animation<double> _wordmarkSlide;
  late final Animation<double> _taglineFade;
  late final Animation<double> _taglineSlide;
  late final Animation<double> _loaderFade;

  // Drives the looping ambient effects (glow pulse + bouncing dots).
  late final AnimationController _pulse;

  /// Restore-or-refresh, started at t=0 so it overlaps the intro animation.
  late final Future<AuthStatus> _bootstrap;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    _logoFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );

    _wordmarkFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.35, 0.62, curve: Curves.easeOut),
    );
    _wordmarkSlide = Tween<double>(begin: 24, end: 0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.35, 0.62, curve: Curves.easeOutCubic),
      ),
    );

    _taglineFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.55, 0.82, curve: Curves.easeOut),
    );
    _taglineSlide = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.55, 0.82, curve: Curves.easeOutCubic),
      ),
    );

    _loaderFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.72, 1.0, curve: Curves.easeOut),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _bootstrap = _runBootstrap();
    unawaited(_navigateWhenReady());
  }

  /// Resolves the session, and — when there is one — starts Home's requests
  /// straight away so the intro animation and the round-trips overlap.
  Future<AuthStatus> _runBootstrap() async {
    final status = await AuthService.instance.bootstrap();
    if (status == AuthStatus.authenticated && mounted) {
      unawaited(_primeHomeData());
    }
    return status;
  }

  /// Waits for both the intro and the auth decision before routing. Whichever
  /// is slower sets the pace: the animation is never cut short, and the route
  /// is never chosen while the session is still being restored.
  Future<void> _navigateWhenReady() async {
    final results = await Future.wait<Object?>([
      _bootstrap,
      Future<void>.delayed(_minDisplay),
    ]);
    if (!mounted) return;
    _navigate(results.first as AuthStatus);
  }

  /// Warms the controllers the Home tab reads, while the splash is on screen.
  ///
  /// Home used to mount, *then* fire these calls, so the seller watched a
  /// loading view for a full round-trip after a 2.6 s splash that had been
  /// sitting idle. [ProfileController] and [DashboardController] both fetch in
  /// `onInit`, so simply creating them here starts the work; `getOrPut` hands
  /// Home these same instances, by which point the data has usually landed.
  ///
  /// Safe to call at this point: `Supabase.initialize()` is awaited in `main()`
  /// before the app runs, so a restored session is already visible to
  /// [AuthService.isLoggedIn] — a signed-in check here can't be a false
  /// negative, and the requests carry a real token.
  ///
  /// Failures need no handling: each controller keeps its own error state and
  /// Home renders its usual error card with a retry.
  Future<void> _primeHomeData() async {
    // No `ensureFreshSession()` here any more: [_runBootstrap] only calls this
    // once the session is known-good (refreshed if the restored access token
    // had expired), so these requests can't go out carrying a stale token.
    getOrPut(() => ProfileController());
    getOrPut(() => DashboardController());
    // The bell badge. Created `permanent` to match Home — registering it any
    // other way here would leave Home's `getOrPut` finding a non-permanent
    // instance that GetX may dispose. It has no `onInit` fetch, so ask
    // explicitly.
    getOrPut(() => NotificationController(), permanent: true).fetchUnreadCount();
  }

  void _navigate(AuthStatus status) {
    if (!mounted) return;
    final signedIn = status == AuthStatus.authenticated;
    final destination = signedIn ? const HomeView() : const LoginView();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
    // Fired *after* the replacement so the OS permission sheet lands on the
    // destination screen rather than over a splash that's about to vanish.
    // Unawaited: nothing about routing may wait on a system dialog.
    unawaited(_primePushNotifications(signedIn: signedIn));
  }

  /// The "initial" notification-permission ask, plus device registration when
  /// we're entering an already-signed-in session.
  ///
  /// Both branches prompt — [PushNotificationService.onAuthenticated] asks
  /// first and only registers once granted. Asking here *and* again after a
  /// fresh sign-in is deliberate and harmless: iOS and Android only surface the
  /// system dialog the first time, and later calls just report the standing
  /// decision.
  Future<void> _primePushNotifications({required bool signedIn}) async {
    final push = PushNotificationService.instance;
    if (signedIn) {
      // Registers this handset against the restored session — the token may
      // have rotated, or the backend row been pruned, while the app was shut.
      await push.onAuthenticated();
    } else {
      // Not signed in yet: there's no account to attach a token to, so just
      // secure the permission. LoginView registers once sign-in succeeds.
      await push.requestPermission();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Decorative cloud blobs — match the login illustration's vibe.
            const Positioned(top: 60, left: 36, child: _Cloud(size: 22)),
            const Positioned(top: 110, right: 28, child: _Cloud(size: 14)),
            const Positioned(top: 38, right: 90, child: _Cloud(size: 10)),

            // Centre stack: glowing logo + animated wordmark + tagline.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo with a soft pulsing brand glow behind it.
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, _) {
                              final t = Curves.easeInOut.transform(_pulse.value);
                              return Container(
                                width: 140 + 60 * t,
                                height: 140 + 60 * t,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      AppColors.brandYellow
                                          .withOpacity(0.30 * (1 - t) + 0.12),
                                      AppColors.brandYellow.withOpacity(0.0),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: Image.asset(
                              'assets/logo/app_icon.png',
                              width: 140,
                              height: 140,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),

                  // Wordmark — slides up and fades in after the logo.
                  AnimatedBuilder(
                    animation: _intro,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _wordmarkFade.value,
                        child: Transform.translate(
                          offset: Offset(0, _wordmarkSlide.value),
                          child: child,
                        ),
                      );
                    },
                    child: const CustomText(
                      'Seller Squad',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Tagline — slides up and fades in last.
                  AnimatedBuilder(
                    animation: _intro,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _taglineFade.value,
                        child: Transform.translate(
                          offset: Offset(0, _taglineSlide.value),
                          child: child,
                        ),
                      );
                    },
                    child: CustomText(
                      TKeys.splashTagline.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom: animated dot loader, fading in at the end of the intro.
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: FadeTransition(
                opacity: _loaderFade,
                child: _DotsLoader(controller: _pulse),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated three-dot loader — each dot bounces in sequence off the shared
// [_pulse] controller, so it stays in sync with the logo glow.
// ─────────────────────────────────────────────────────────────────────────────
class _DotsLoader extends StatelessWidget {
  const _DotsLoader({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            // Stagger each dot a third of a cycle apart.
            final phase = (controller.value + i / 3) % 1.0;
            final t = Curves.easeInOut.transform(
              phase < 0.5 ? phase * 2 : (1 - phase) * 2,
            );
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  AppColors.brandYellow.withOpacity(0.4),
                  AppColors.accent,
                  t,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Decorative cloud (kept private — copied lightly from the login illustration
// to avoid leaking that file's internals).
// ─────────────────────────────────────────────────────────────────────────────
class _Cloud extends StatelessWidget {
  const _Cloud({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 2.4,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(size),
      ),
    );
  }
}
