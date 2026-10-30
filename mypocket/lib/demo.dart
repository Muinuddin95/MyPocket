// lib/demo.dart
// Web demo mode. It is only on when the app is built with:
//   flutter build web --dart-define=DEMO_MODE=true
//     --dart-define=DEMO_EMAIL=... --dart-define=DEMO_PASSWORD=...
// Normal phone builds are not affected, and the demo login is not stored in this code.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';

const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');
const String _demoEmail = String.fromEnvironment('DEMO_EMAIL');
const String _demoPassword = String.fromEnvironment('DEMO_PASSWORD');

/// Shown instead of the login form in the demo: one button, no sign-up.
/// LoginScreen listens for the sign-in and opens the home screen.
class DemoWelcome extends StatefulWidget {
  const DemoWelcome({super.key});

  @override
  State<DemoWelcome> createState() => _DemoWelcomeState();
}

class _DemoWelcomeState extends State<DemoWelcome> {
  bool _isLoading = false;

  Future<void> _startDemo() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _demoEmail,
        password: _demoPassword,
      );
    } catch (e) {
      debugPrint('Demo login failed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The demo is unavailable right now. Please try again later.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 72),
                const SizedBox(height: 24),
                const Text(
                  'MyPocket',
                  style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'A student expense tracker and budgeting app.\n'
                  'Explore it with sample data, no sign-up needed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _startDemo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text(
                            'Try demo',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'This is a shared demo account. Please do not enter real personal information.\n'
                  'Receipt scanning, AI chat and payments are turned off here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
