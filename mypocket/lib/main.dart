// main.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'Login.dart';
import 'demo.dart';
import 'home.dart';
import 'onboarding.dart';
import 'theme.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter();
    await Hive.openBox('savings_goals');
    await Hive.openBox('recurring_expenses');

    await Supabase.initialize(
      url: 'https://pxawnnywajzyibppamwb.supabase.co',
      anonKey: 'sb_publishable_fMd8Y9CeO7nEAADmVIVxsg_52YyTs0L',
    );
    
    // Initialize notification service
    await NotificationService.instance.initialize();
  } catch (e, stacktrace) {
    debugPrint("Initialization Error: $e");
    debugPrint("Stacktrace: $stacktrace");
  }

  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  final isDarkMode = prefs.getBool('dark_mode') ?? false;

  runApp(MyApp(seenOnboarding: seenOnboarding, isDarkMode: isDarkMode));
}

class MyApp extends StatefulWidget {
  final bool seenOnboarding;
  final bool isDarkMode;

  const MyApp({
    super.key,
    required this.seenOnboarding,
    required this.isDarkMode,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late bool _isDarkMode;
  bool _showSplash = true;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.isDarkMode;

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {});
      }
    });

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void toggleTheme(bool isDark) {
    setState(() {
      _isDarkMode = isDark;
    });
    _saveThemePreference(isDark);
  }

  Future<void> _saveThemePreference(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', isDark);
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    Widget home;
    if (session != null) {
      home = HomeScreen(
        onThemeToggle: toggleTheme, // ← FIXED: was togglTheme
        isDarkMode: _isDarkMode,
      );
    } else if (widget.seenOnboarding || kDemoMode) {
      home = LoginScreen(
        onThemeToggle: toggleTheme,
        isDarkMode: _isDarkMode,
      );
    } else {
      home = OnboardingScreen(
        onThemeToggle: toggleTheme,
        isDarkMode: _isDarkMode,
      );
    }

    return MaterialApp(
      title: 'MyPocket',
      debugShowCheckedModeBanner: false,
      theme: _isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: _showSplash ? _buildSplashScreen() : home,
      builder: (context, child) {
        if (!kIsWeb) return child!;
        // Phone-shaped frame on large screens, full screen on phones.
        // It shrinks to fit shorter screens so nothing is cut off.
        final screen = MediaQuery.sizeOf(context);
        final isPhone = screen.width < 500;
        final frame = Size(
          isPhone ? screen.width : 390,
          isPhone || screen.height < 844 ? screen.height : 844,
        );
        return Container(
          color: const Color(0xFF1E222B),
          child: Center(
            child: Container(
              width: frame.width,
              height: frame.height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isPhone ? 0 : 36),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: frame),
                child: child!,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSplashScreen() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
            child: Center(
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.8 + 0.2 * value,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: ClipRect(
                            child: Align(
                              alignment: Alignment.center,
                              heightFactor: 0.55,
                              widthFactor: 0.55,
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 130,
                                height: 130,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.pie_chart_outline_rounded,
                                  color: Colors.white,
                                  size: 60,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'MyPocket',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your personal finance companion',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          color: Colors.white.withValues(alpha: 0.8),
                          strokeWidth: 2.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
