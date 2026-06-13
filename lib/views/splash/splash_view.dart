import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../auth/login_view.dart';
import '../home/home_view.dart';


/// First screen the app shows while we hand off to the auth stack.
///
/// Visually anchored to the rest of the app — same warm cream gradient as
/// [LoginView], a yellow squircle mascot mark echoing the login illustration,
/// and the Tommesalg wordmark underneath. The screen also opportunistically
/// checks for a restored Supabase session, so already-signed-in users skip
/// the login form on cold start (forward-compatible: when a real home view
/// exists, swap the TODO target below).
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  static const _minDisplay = Duration(milliseconds: 1600);

  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
  Future.delayed(_minDisplay, _navigate);
  }

  void _navigate() {
    if (!mounted) return;
    final destination = AuthService.instance.isLoggedIn
        ? const HomeView()
        : const LoginView();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Container(
        color: AppColors.white,
        child: SafeArea(
          child: Stack(
            children: [
              // Decorative cloud blobs — match the login illustration's vibe.
              const Positioned(top: 60,  left: 36,  child: _Cloud(size: 22)),
              const Positioned(top: 110, right: 28, child: _Cloud(size: 14)),
              const Positioned(top: 38,  right: 90, child: _Cloud(size: 10)),

              // Centre stack: brand logo.
              Center(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _fade.value,
                      child: Transform.scale(
                        scale: _scale.value,
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Image.asset(
                      'assets/logo/splash_icon.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              // Bottom progress affordance + tagline.
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.accent.withOpacity(0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const CustomText(
                      'Loading…',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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

