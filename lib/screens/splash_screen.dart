import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Branded launch screen: the OneFit logo fades/scales in over a fixed dark
/// background while [AuthGate] resolves the signed-in state, then AuthGate
/// routes on to Login or Home. Presentational only — no navigation lives here.
///
/// The background is pinned to the brand dark (not the theme background) so the
/// white-text logo stays legible even for users on the light theme.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.85,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Image.asset('assets/images/logo2.png', width: 200),
              ),
            ),
            const SizedBox(height: 48),
            FadeTransition(
              opacity: _fade,
              child: const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
