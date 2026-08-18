import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_input_screen.dart';
import 'screens/splash_screen.dart';
import 'providers/plan_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/connectivity_provider.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'theme/app_text_scale.dart';
import 'app_clock.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Set to false before deployment
const bool _DEBUG_FORCE_LOGOUT = false;

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A missing/unreadable .env must not block cold launch (e.g. offline first
  // run) — the network services that read it fail gracefully on their own.
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('dotenv load failed (continuing without it): $e');
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Make Firestore's on-device offline persistence explicit. It is on by
  // default on Android, but configuring it here documents the intent and lets
  // every cached read/queued write drive the offline experience deliberately.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  if (_DEBUG_FORCE_LOGOUT) {
    await FirebaseAuth.instance.signOut();
    debugPrint('User signed out');
  }

  final themeProvider = await ThemeProvider.create();

  // Restore the Developer Mode toggle (day-changer stays off until re-enabled
  // so a real user is never left on a shifted day after a restart).
  final prefs = await SharedPreferences.getInstance();
  developerModeEnabled.value = prefs.getBool('developerMode') ?? false;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => PlanProvider()),
        ChangeNotifierProvider(create: (_) => ProgressProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
      ],
      child: const OneFitApp(),
    ),
  );
}

class OneFitApp extends StatefulWidget {
  const OneFitApp({super.key});

  @override
  State<OneFitApp> createState() => _OneFitAppState();
}

class _OneFitAppState extends State<OneFitApp> {
  @override
  void initState() {
    super.initState();
    // Both the offset and the on/off toggle change what appNow() returns, so
    // either one requires rebuilding the stack against the new simulated day.
    debugDayOffset.addListener(_onDayChanged);
    devDayChangerEnabled.addListener(_onDayChanged);
  }

  @override
  void dispose() {
    debugDayOffset.removeListener(_onDayChanged);
    devDayChangerEnabled.removeListener(_onDayChanged);
    super.dispose();
  }

  /// When the simulated day changes, rebuild the navigation stack from a fresh
  /// HomeScreen so every screen re-runs its initState/build against the new
  /// appNow(). Re-keying the navigator subtree alone doesn't work because the
  /// Navigator is held by a GlobalKey, which preserves its state across rekeys.
  void _onDayChanged() {
    if (FirebaseAuth.instance.currentUser == null) return;
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'OneFit',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      themeMode: themeProvider.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: (context, child) {
        // Lift the app's authored font sizes (they run 1–2pt under the platform
        // norm) and cap the total so large text can't overflow the app's many
        // fixed-height rows/cards. See AppTextScale — one constant tunes it.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: AppTextScale.resolve(mq.textScaler)),
          child: ValueListenableBuilder<bool>(
            valueListenable: devDayChangerEnabled,
            builder: (context, changerOn, _) => ValueListenableBuilder<int>(
              valueListenable: debugDayOffset,
              // Rebuilds only the day pill's label; the actual screen refresh on
              // a day change is driven by _onDayChanged re-pushing a fresh
              // HomeScreen.
              builder: (context, offset, _) => Stack(
                children: [
                  child!,
                  // Slim "you're offline" banner — auto on connection loss and
                  // on the dev Force-Offline toggle. Below the day pill so both
                  // can coexist while testing.
                  if (context.watch<ConnectivityProvider>().isOffline)
                    const _OfflineBanner(),
                  if (changerOn) _DebugDayChanger(),
                ],
              ),
            ),
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}

/// Debug-only floating control to shift the app's notion of "today".
/// Visible only while [devDayChangerEnabled] is true (the "Change Day" toggle
/// inside Developer Mode).
class _DebugDayChanger extends StatelessWidget {
  const _DebugDayChanger();

  String _label(int offset) {
    final d = appToday();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final sign = offset > 0 ? '+$offset' : '$offset';
    final tag = offset == 0 ? 'today' : sign;
    return '${days[d.weekday - 1]} ${months[d.month - 1]} ${d.day}  ($tag)';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.primary),
                boxShadow: [BoxShadow(color: c.shadow, blurRadius: 8)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _iconBtn(Icons.chevron_left, () => debugDayOffset.value -= 1),
                  GestureDetector(
                    onTap: () => debugDayOffset.value = 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        _label(debugDayOffset.value),
                        style: TextStyle(
                          color: c.onBackground,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  _iconBtn(
                    Icons.chevron_right,
                    () => debugDayOffset.value += 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => InkResponse(
    onTap: onTap,
    radius: 20,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Icon(icon, color: AppColors.primary, size: 22),
    ),
  );
}

/// Slim top banner shown while [ConnectivityProvider.isOffline]. Reassures the
/// user that logging still works and will sync — the offline promise is
/// "nothing you type is lost". Visibility is decided by the caller in the
/// `MaterialApp.builder` Stack; this widget only paints.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Material(
        color: Colors.transparent,
        child: Container(
          color: AppColors.amber.withValues(alpha: 0.16),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      color: AppColors.amber, size: 15),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "You're offline — changes will sync when you reconnect.",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: c.onBackground,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Keep the launch splash on screen at least this long on cold boot so the
  // logo doesn't just flash by when auth state resolves instantly.
  static const _minSplash = Duration(milliseconds: 2200);
  final DateTime _bootedAt = DateTime.now();
  bool _handledFirstEvent = false;

  @override
  void initState() {
    super.initState();
    AuthService().authStateChanges.listen(_routeForAuthState);
  }

  Future<void> _routeForAuthState(User? user) async {
    // Reset app-scoped in-memory state whenever the signed-in identity changes
    // (sign-out OR a different uid) so one account never inherits another's
    // cached profile/plan. Read via navigatorKey.currentContext (a descendant
    // of the providers, valid for the app's lifetime) rather than this State's
    // `context`: AuthGate's own route is removed by the first pushAndRemoveUntil,
    // so `mounted` is false on every later auth event. clear() is in-memory only
    // — the signed-out account's persisted data is untouched. Same-user re-fires
    // (token refresh, cold boot) match the cached uid and skip the reset.
    final navCtx = navigatorKey.currentContext;
    if (navCtx != null) {
      final pp = navCtx.read<ProfileProvider>();
      if (user == null || pp.uid != user.uid) {
        navCtx.read<PlanProvider>().clear();
        pp.clear();
      }
    }

    // Resolve where this auth state should land.
    Widget destination;
    if (user == null) {
      destination = const LoginScreen();
    } else {
      // Signed in → Home if a profile exists, else onboarding.
      final hasProfile = await FirestoreService().profileExists(user.uid);
      destination = hasProfile
          ? const HomeScreen()
          : const ProfileInputScreen();
    }

    // Only the first (cold-boot) event honours the minimum splash time; later
    // sign-in / sign-out transitions route immediately.
    if (!_handledFirstEvent) {
      _handledFirstEvent = true;
      final remaining = _minSplash - DateTime.now().difference(_bootedAt);
      if (remaining > Duration.zero) await Future.delayed(remaining);
    }

    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
