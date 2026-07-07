import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_input_screen.dart';
import 'providers/plan_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/profile_provider.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'app_clock.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Set to false before deployment
const bool _DEBUG_FORCE_LOGOUT = false;

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: devDayChangerEnabled,
        builder: (context, changerOn, _) => ValueListenableBuilder<int>(
          valueListenable: debugDayOffset,
          // Rebuilds only the day pill's label; the actual screen refresh on a
          // day change is driven by _onDayChanged re-pushing a fresh HomeScreen.
          builder: (context, offset, _) => Stack(
            children: [child!, if (changerOn) _DebugDayChanger()],
          ),
        ),
      ),
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

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    AuthService().authStateChanges.listen((User? user) async {
      if (user == null) {
        // Signed out → go to Login, clear stack
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        // Signed in → check if profile exists
        final hasProfile = await FirestoreService().profileExists(user.uid);
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                hasProfile ? const HomeScreen() : const ProfileInputScreen(),
          ),
          (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFF00C97B))),
    );
  }
}
