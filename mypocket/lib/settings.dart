// settings.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'Login.dart';
import 'support_chat_screen.dart';
import 'faq_screen.dart';
import 'edit_profile.dart';
import 'theme.dart';
import 'savings.dart';
import 'recurring.dart';
import 'premium.dart';
import 'demo.dart';
import 'subscription_service.dart';
import 'widgets/glassmorphism.dart';

class SettingsScreen extends StatefulWidget {
  final Function(bool) onThemeToggle;
  final bool isDarkMode;

  const SettingsScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDarkMode,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _lightBg = Color(0xFFEAF4F0);
  final _supabase = Supabase.instance.client;

  String _userName = '';
  String _userEmail = '';
  String _studentType = '';
  String? _avatarBase64;
  double _dailyAllowanceLimit = 20.0;
  String? _nextFundingDateStr;
  double _monthlyStipendAmount = 0.0;
  bool _notifBudgetAlert = true;
  bool _notifOverLimit = true;
  bool _notifWeeklyReport = false;
  bool _darkMode = false;
  bool _loading = true;
  bool _isPremium = false;
  String _selectedCurrency = 'RM';
  bool _uniFundingEnabled = false;
  double _uniHourlyRate = 10.0;
  double _uniHoursWorked = 0.0;

  @override
  void initState() {
    super.initState();
    _darkMode = widget.isDarkMode;
    _loadData();
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDarkMode != widget.isDarkMode) {
      setState(() {
        _darkMode = widget.isDarkMode;
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        final res = await _supabase
            .from('users')
            .select('name, email, student_type, avatar_base64, daily_allowance_limit, next_funding_date, monthly_stipend_amount')
            .eq('user_id', userId)
            .maybeSingle();
        if (res != null) {
          setState(() {
            _userName = res['name'] ?? '';
            _userEmail = res['email'] ?? '';
            _studentType = res['student_type'] ?? '';
            _avatarBase64 = res['avatar_base64'];
            _dailyAllowanceLimit = double.tryParse(res['daily_allowance_limit']?.toString() ?? '') ?? 20.0;
            _nextFundingDateStr = res['next_funding_date'] != null
                ? DateTime.tryParse(res['next_funding_date'])?.toLocal().toString().split(' ').first
                : null;
            _monthlyStipendAmount = double.tryParse(res['monthly_stipend_amount']?.toString() ?? '') ?? 0.0;
          });
        }
      }
      if (_userEmail.isEmpty) {
        _userEmail = _supabase.auth.currentUser?.email ?? '';
      }
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notifBudgetAlert = prefs.getBool('notif_budget_alert') ?? true;
        _notifOverLimit = prefs.getBool('notif_over_limit') ?? true;
        _notifWeeklyReport = prefs.getBool('notif_weekly_report') ?? false;
        _selectedCurrency = prefs.getString('currency') ?? 'RM';
        _uniFundingEnabled = prefs.getBool('uni_funding_enabled') ?? false;
        _uniHourlyRate = prefs.getDouble('uni_hourly_rate') ?? 10.0;
        _uniHoursWorked = prefs.getDouble('uni_hours_worked') ?? 0.0;
      });
      // Load premium status
      final isPremium = await SubscriptionService.instance.checkPremiumStatus();
      if (mounted) setState(() => _isPremium = isPremium);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _changeJobDetails() {
    final rateCtrl = TextEditingController(text: _uniHourlyRate.toStringAsFixed(2));
    final hoursCtrl = TextEditingController(text: _uniHoursWorked.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.work_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Expanded(child: Text('Part-Time Job Settings')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hourly Wage Rate (RM)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: 'e.g. 10.00',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Hours Worked',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: hoursCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: 'e.g. 15.5',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newRate = double.tryParse(rateCtrl.text) ?? 10.0;
              final newHours = double.tryParse(hoursCtrl.text) ?? 0.0;

              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('uni_hourly_rate', newRate);
              await prefs.setDouble('uni_hours_worked', newHours);

              setState(() {
                _uniHourlyRate = newRate;
                _uniHoursWorked = newHours;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditProfile() {
    final ctrl = TextEditingController(text: _userName);
    String tempStudentType = 'School';
    if (_studentType.toLowerCase().contains('school')) {
      tempStudentType = 'School';
    } else if (_studentType.toLowerCase().contains('postgrad')) {
      tempStudentType = 'Postgrad';
    } else if (_studentType.toLowerCase().contains('university') || _studentType.toLowerCase().contains('universiti')) {
      tempStudentType = 'University';
    }

    final allowanceCtrl = TextEditingController(text: _dailyAllowanceLimit.toStringAsFixed(2));
    final stipendCtrl = TextEditingController(text: _monthlyStipendAmount.toStringAsFixed(2));
    DateTime? tempFundingDate = _nextFundingDateStr != null ? DateTime.tryParse(_nextFundingDateStr!) : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = widget.isDarkMode;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF16213E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Edit Profile',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A5C4A),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Full name',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: ctrl,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? Colors.white10 : const Color(0xFFF7FAF9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Student Level',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: tempStudentType,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    dropdownColor: isDark ? const Color(0xFF1A2238) : Colors.white,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? Colors.white10 : const Color(0xFFF7FAF9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'School', child: Text('School Student')),
                      DropdownMenuItem(value: 'University', child: Text('University Student')),
                      DropdownMenuItem(value: 'Postgrad', child: Text('Postgraduate Student')),
                    ],
                    onChanged: (val) {
                      setModalState(() {
                        tempStudentType = val ?? 'School';
                      });
                    },
                  ),

                  // Dynamic fields depending on Student Level
                  if (tempStudentType == 'School') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Daily Allowance Limit (RM)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: allowanceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? Colors.white10 : const Color(0xFFF7FAF9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                    ),
                  ],

                  if (tempStudentType == 'University' || tempStudentType == 'Postgrad') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Next Disbursement/Stipend Date',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: tempFundingDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setModalState(() {
                            tempFundingDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : const Color(0xFFF7FAF9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tempFundingDate != null
                                  ? tempFundingDate!.toString().split(' ').first
                                  : 'Select Date',
                              style: TextStyle(
                                color: tempFundingDate != null
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : Colors.grey,
                              ),
                            ),
                            const Icon(Icons.calendar_month_rounded, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (tempStudentType == 'Postgrad') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Monthly stipend Amount (RM)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: stipendCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? Colors.white10 : const Color(0xFFF7FAF9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        final newName = ctrl.text.trim();
                        if (newName.isEmpty) return;
                        try {
                          final userId = _supabase.auth.currentUser?.id;
                          final double allowanceVal = double.tryParse(allowanceCtrl.text) ?? 20.0;
                          final double stipendVal = double.tryParse(stipendCtrl.text) ?? 0.0;

                          await _supabase
                              .from('users')
                              .update({
                                'name': newName,
                                'student_type': tempStudentType,
                                'daily_allowance_limit': allowanceVal,
                                'next_funding_date': tempFundingDate?.toIso8601String(),
                                'monthly_stipend_amount': stipendVal,
                              })
                              .eq('user_id', userId!);

                          setState(() {
                            _userName = newName;
                            _studentType = tempStudentType;
                            _dailyAllowanceLimit = allowanceVal;
                            _nextFundingDateStr = tempFundingDate?.toString().split(' ').first;
                            _monthlyStipendAmount = stipendVal;
                          });

                          // Also notify Home Dashboard to reload
                          _loadData();

                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile updated!'),
                                backgroundColor: Color(0xFF1A5C4A),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                child: const Text(
                  'Save Changes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showChangePassword() {
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Change Password',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A5C4A),
                ),
              ),
              const SizedBox(height: 20),
              _pwField('New password', newCtrl),
              const SizedBox(height: 12),
              _pwField('Confirm new password', confirmCtrl),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (newCtrl.text.length < 8) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Min 8 characters'),
                                backgroundColor: Colors.orangeAccent,
                              ),
                            );
                            return;
                          }
                          if (newCtrl.text != confirmCtrl.text) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Passwords do not match'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }
                          setModal(() => saving = true);
                          try {
                            await _supabase.auth.updateUser(
                              UserAttributes(password: newCtrl.text),
                            );
                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Password changed!'),
                                  backgroundColor: Color(0xFF1A5C4A),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          } finally {
                            setModal(() => saving = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Update Password',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pwField(String label, TextEditingController ctrl) {
    bool obscure = true;
    return StatefulBuilder(
      builder: (_, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            obscureText: obscure,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF7FAF9),
              suffixIcon: GestureDetector(
                onTap: () => set(() => obscure = !obscure),
                child: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF1A5C4A),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sign out?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A5C4A),
          ),
        ),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign out',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            onThemeToggle: widget.onThemeToggle,
            isDarkMode: widget.isDarkMode,
          ),
        ),
        (_) => false,
      );
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Account?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        content: const Text(
          'This cannot be undone. All your expenses, budgets and data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Yes, delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        await _supabase.from('expenses').delete().eq('user_id', userId);
        await _supabase.from('budgets').delete().eq('user_id', userId);
        await _supabase.from('users').delete().eq('user_id', userId);
        
        // Delete the actual auth.users record via secure RPC function
        try {
          await _supabase.rpc('delete_user_account');
        } catch (rpcError) {
          debugPrint('Auth delete RPC error (Ensure delete_user_account SQL function exists): $rpcError');
        }
      }
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _lightBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.pie_chart_outline_rounded,
                color: Color(0xFF1A5C4A),
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'MyPocket',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A5C4A),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 1.0.0',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
            const SizedBox(height: 10),
            const Text(
              'A personal expense tracker and budgeting app designed for students to manage their finances effortlessly.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text(
              '© 2026 Muhammad Muinuddin',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Close',
              style: TextStyle(
                color: Color(0xFF1A5C4A),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildAvatarWidget(String initials) {
    if (_avatarBase64 != null && _avatarBase64!.isNotEmpty) {
      try {
        final base64Data = _avatarBase64!.contains(',')
            ? _avatarBase64!.split(',').last
            : _avatarBase64!;
        final bytes = base64Decode(base64Data);
        return Container(
          width: 54,
          height: 54,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(bytes, fit: BoxFit.cover),
        );
      } catch (_) {}
    }
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        color: _primaryGreen,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials.isNotEmpty ? initials : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initials = _userName
        .trim()
        .split(' ')
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0])
        .join()
        .toUpperCase();

    final isDark = widget.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : _lightBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: widget.isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primaryGreen),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        // ── Profile ───────────────────────────────────────
                        GestureDetector(
                          onTap: _showEditProfile,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                _buildAvatarWidget(initials),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _userName.isNotEmpty
                                                  ? _userName
                                                  : 'My Profile',
                                               style: TextStyle(
                                                 fontSize: 16,
                                                 fontWeight: FontWeight.bold,
                                                 color: widget.isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                                               ),
                                            ),
                                          ),
                                          if (_isPremium) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFFFFB800), Color(0xFFE09600)],
                                                ),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.star_rounded, color: Colors.white, size: 10),
                                                  SizedBox(width: 2),
                                                  Text('Premium', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _userEmail,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _lightBg,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          _studentType.isNotEmpty
                                              ? _studentType
                                              : 'Student',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: _primaryGreen,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: _primaryGreen,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    final updated = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EditProfileScreen(
                                          userData: {
                                            'name': _userName,
                                            'email': _userEmail,
                                            'student_type': _studentType,
                                          },
                                        ),
                                      ),
                                    );
                                    if (updated == true) {
                                      _loadData();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Dark Mode Toggle ─────────────────────────────
                        _label('Appearance'),
                        _card([
                          _toggle(
                            Icons.dark_mode_rounded,
                            const Color(0xFF8E44AD),
                            'Dark mode',
                            'Switch between light and dark theme',
                            _darkMode,
                            (v) {
                              setState(() {
                                _darkMode = v;
                              });
                              widget.onThemeToggle(v);
                            },
                          ),
                        ]),
                        const SizedBox(height: 20),

                        // ── Notifications ────────────────────────────────
                        _label('Notifications'),
                        _card([
                          _toggle(
                            Icons.warning_amber_rounded,
                            Colors.orangeAccent,
                            'Budget alert',
                            'Alert when nearing limit',
                            _notifBudgetAlert,
                            (v) {
                              setState(() => _notifBudgetAlert = v);
                              _savePref('notif_budget_alert', v);
                            },
                          ),
                          _div(),
                          _toggle(
                            Icons.money_off_rounded,
                            Colors.redAccent,
                            'Over limit warning',
                            'Notify when budget exceeded',
                            _notifOverLimit,
                            (v) {
                              setState(() => _notifOverLimit = v);
                              _savePref('notif_over_limit', v);
                            },
                          ),
                          _div(),
                          _toggle(
                            Icons.bar_chart_rounded,
                            _primaryGreen,
                            'Weekly report',
                            'Get weekly spending summary',
                            _notifWeeklyReport,
                            (v) {
                              setState(() => _notifWeeklyReport = v);
                              _savePref('notif_weekly_report', v);
                            },
                          ),
                        ]),
                        const SizedBox(height: 20),

                        // ── Preferences ───────────────────────────────────
                        _label('Preferences'),
                        _card([
                          if (!_isPremium)
                            _action(
                              Icons.workspace_premium_rounded,
                              const Color(0xFFFFB800),
                              'Upgrade to Premium',
                              'Unlock AI chat, full reports & more',
                              () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PremiumScreen(
                                      onPremiumActivated: () {
                                        setState(() => _isPremium = true);
                                      },
                                    ),
                                  ),
                                );
                                final updated = await SubscriptionService.instance.checkPremiumStatus();
                                if (mounted) setState(() => _isPremium = updated);
                              },
                              titleColor: const Color(0xFFE09600),
                            ),
                          if (!_isPremium) _div(),
                          _action(
                            Icons.attach_money_rounded,
                            Colors.amber.shade700,
                            'Currency',
                            'Selected currency: $_selectedCurrency',
                            _showCurrencySelector,
                          ),
                          _div(),
                          _action(
                            Icons.savings_rounded,
                            _primaryGreen,
                            'Savings Goals',
                            'Set and track target savings',
                            () {
                              if (!_isPremium) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Savings Goals is a Premium feature!'),
                                    backgroundColor: _primaryGreen,
                                  ),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const SavingsScreen()),
                              );
                            },
                          ),
                          _div(),
                          _action(
                            Icons.repeat_rounded,
                            const Color(0xFF2E9B78),
                            'Recurring Bills',
                            'Manage subscription renewals',
                            () {
                              if (!_isPremium) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Recurring Bills is a Premium feature!'),
                                    backgroundColor: _primaryGreen,
                                  ),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const RecurringScreen()),
                              );
                            },
                          ),
                          _div(),
                          _action(
                            Icons.file_download_outlined,
                            Colors.blueAccent,
                            'Export Data (CSV)',
                            'Share or save spending spreadsheet',
                            () {
                              if (!_isPremium) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('CSV Export is a Premium feature!'),
                                    backgroundColor: _primaryGreen,
                                  ),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                                );
                                return;
                              }
                              _exportToCSV();
                            },
                          ),
                        ]),
                        const SizedBox(height: 20),

                        if (_studentType.toLowerCase().contains('university')) ...[
                          _label('Part-Time Job Tracker'),
                          _card([
                            _toggle(
                              Icons.work_outline_rounded,
                              _primaryGreen,
                              'Enable Job Tracker',
                              'Show job earnings widget on home screen',
                              _uniFundingEnabled,
                              (v) async {
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setBool('uni_funding_enabled', v);
                                setState(() => _uniFundingEnabled = v);
                              },
                            ),
                            if (_uniFundingEnabled) ...[
                              _div(),
                              _action(
                                Icons.edit_note_rounded,
                                Colors.amber.shade700,
                                'Job Details',
                                'Wage: $_selectedCurrency ${_uniHourlyRate.toStringAsFixed(2)}/hr · Worked: ${_uniHoursWorked.toStringAsFixed(1)} hrs',
                                _changeJobDetails,
                              ),
                            ],
                          ]),
                          const SizedBox(height: 20),
                        ],

                        // ── Security ──────────────────────────────────────
                        if (!kDemoMode) ...[
                          _label('Security'),
                          _card([
                            _action(
                              Icons.lock_outline_rounded,
                              const Color(0xFF2980B9),
                              'Change password',
                              null,
                              _showChangePassword,
                            ),
                          ]),
                          const SizedBox(height: 20),
                        ],

                        // ── About ─────────────────────────────────────────
                        _label('About'),
                        _card([
                          _action(
                            Icons.info_outline_rounded,
                            _primaryGreen,
                            'About MyPocket',
                            'Version 1.0.0',
                            _showAbout,
                          ),
                          _div(),
                          _action(
                            Icons.privacy_tip_outlined,
                            Colors.blueGrey,
                            'Privacy policy',
                            null,
                            () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Privacy policy coming soon'),
                              ),
                            ),
                          ),
                          _action(
                            Icons.help_outline_rounded,
                            Colors.blueGrey,
                            'FAQ & Help Center',
                            'Find answers quickly',
                            () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const FaqScreen(),
                                ),
                              );
                            },
                          ),
                          if (!kDemoMode) ...[_div(),
                          _action(
                            Icons.support_agent_rounded,
                            const Color(0xFF2E9B78), // _primaryGreen
                            'Customer Support',
                            'Chat with us',
                            () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SupportChatScreen(),
                                ),
                              );
                            },
                          ),
                          ],
                        ]),
                        const SizedBox(height: 20),

                        // ── Account ───────────────────────────────────────
                        _label('Account'),
                        _card([
                          _action(
                            Icons.logout_rounded,
                            Colors.orangeAccent,
                            'Sign out',
                            null,
                            _signOut,
                          ),
                          if (!kDemoMode) ...[
                            _div(),
                            _action(
                              Icons.delete_forever_rounded,
                              Colors.redAccent,
                              'Delete account',
                              'Permanently delete all data',
                              _deleteAccount,
                              titleColor: Colors.redAccent,
                            ),
                          ],
                        ]),
                        const SizedBox(height: 32),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCurrencySelector() async {
    final currencies = ['RM', 'USD', 'EUR', 'SGD', 'IDR'];
    final isDark = _darkMode;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: GlassmorphismCard(
            borderRadius: 24,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select Currency',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : _primaryGreen,
                  ),
                ),
                const SizedBox(height: 16),
                ...currencies.map((c) => ListTile(
                      title: Text(c, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                      trailing: _selectedCurrency == c
                          ? const Icon(Icons.check_circle_rounded, color: _primaryGreen)
                          : null,
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('currency', c);
                        setState(() {
                          _selectedCurrency = c;
                        });
                        Navigator.pop(context);
                        HapticFeedback.lightImpact();
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportToCSV() async {
    HapticFeedback.lightImpact();
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final res = await _supabase
          .from('expenses')
          .select('amount, description, expense_date, categories(name)')
          .eq('user_id', userId)
          .order('expense_date', ascending: false);

      final List expenses = res as List;
      final StringBuffer csv = StringBuffer();
      csv.writeln('Date,Category,Description,Amount ($_selectedCurrency)');

      for (final e in expenses) {
        final date = e['expense_date'] ?? '';
        final cat = e['categories']?['name'] ?? 'Other';
        final desc = e['description'] ?? '';
        final amt = e['amount'] ?? 0.0;
        csv.writeln('"$date","$cat","$desc",$amt');
      }

      final String csvText = csv.toString();
      await Share.share(
        csvText,
        subject: 'MyPocket Spending Summary',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 0),
    decoration: BoxDecoration(
      color: widget.isDarkMode ? AppTheme.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(children: children),
  );

  Widget _toggle(
    IconData icon,
    Color iconColor,
    String title,
    String? sub,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: widget.isDarkMode ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeThumbColor: _primaryGreen),
      ],
    ),
  );

  Widget _action(
    IconData icon,
    Color iconColor,
    String title,
    String? sub,
    VoidCallback onTap, {
    Color? titleColor,
  }) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: titleColor ?? (widget.isDarkMode ? Colors.white : const Color(0xFF1A1A1A)),
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.grey.shade300,
            size: 20,
          ),
        ],
      ),
    ),
  );

  Widget _div() => Divider(
    height: 1,
    indent: 64,
    endIndent: 16,
    color: Colors.grey.shade100,
  );
}
