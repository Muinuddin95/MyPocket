import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'Login.dart';
import 'subscription_service.dart';
import 'premium_analytics.dart';
import 'admin_chat_list.dart';

String _generateUUID() {
  final random = Random();
  final hex = List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  return '${hex[0]}${hex[1]}${hex[2]}${hex[3]}-'
      '${hex[4]}${hex[5]}-'
      '4${hex[6].substring(1)}${hex[7]}-'
      '${hex[8]}${hex[9]}-'
      '${hex[10]}${hex[11]}${hex[12]}${hex[13]}${hex[14]}${hex[15]}';
}

class AdminScreen extends StatefulWidget {
  final Function(bool)? onThemeToggle;
  final bool isDarkMode;

  const AdminScreen({super.key, this.onThemeToggle, this.isDarkMode = false});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _users = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();

  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _accentGreen = Color(0xFF2E9B78);
  static const Color _lightBg = Color(0xFFEAF4F0);

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final res = await _supabase.from('users').select('*');
      setState(() {
        _users = List<Map<String, dynamic>>.from(res as List);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading users: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    return _users.where((u) {
      final name = (u['name'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || email.contains(_searchQuery);
    }).toList();
  }

  Future<void> _logout() async {
    HapticFeedback.lightImpact();
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            onThemeToggle: widget.onThemeToggle,
            isDarkMode: widget.isDarkMode,
          ),
        ),
      );
    }
  }

  void _showPayPalSettingsSheet() async {
    HapticFeedback.lightImpact();
    
    // Show a loading indicator dialog while fetching settings
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: _primaryGreen)),
    );

    Map<String, dynamic> settings;
    try {
      settings = await SubscriptionService.instance.getPayPalSettings();
    } finally {
      Navigator.pop(context); // Close the loading dialog
    }

    bool sandboxMode = settings['sandboxMode'] ?? true;
    final clientIdController = TextEditingController(text: settings['clientId'] ?? '');
    final secretKeyController = TextEditingController(text: settings['secretKey'] ?? '');
    final currencyController = TextEditingController(text: settings['currency'] ?? 'USD');
    final amountController = TextEditingController(text: (settings['amount'] ?? 2.20).toString());

    bool obscureClientId = true;
    bool obscureSecretKey = true;
    bool showSQLInstructions = false;

    const sqlScript = '''
CREATE TABLE IF NOT EXISTS paypal_settings (
  id TEXT PRIMARY KEY DEFAULT 'default',
  sandbox_mode BOOLEAN DEFAULT true,
  client_id TEXT NOT NULL,
  secret_key TEXT NOT NULL,
  currency TEXT DEFAULT 'USD',
  amount NUMERIC DEFAULT 2.20,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Enable Row Level Security (optional, or insert policy)
ALTER TABLE paypal_settings ENABLE ROW LEVEL SECURITY;
''';

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = widget.isDarkMode;
          final inputBgColor = isDark ? const Color(0xFF16213E) : Colors.grey.shade50;
          final textColor = isDark ? Colors.white : Colors.black87;

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF003087).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.paypal_rounded, color: Color(0xFF003087), size: 26),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'PayPal Configurations',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configure keys for sandbox testing or live production payments. Changes update the app dynamically.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  // Sandbox / Live Toggle Card
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: sandboxMode
                          ? Colors.amber.shade50.withValues(alpha: 0.8)
                          : Colors.green.shade50.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: sandboxMode ? Colors.amber.shade300 : Colors.green.shade300,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sandboxMode ? Icons.science_outlined : Icons.gpp_good_rounded,
                          color: sandboxMode ? Colors.amber.shade800 : Colors.green.shade800,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sandboxMode ? 'Sandbox Testing Mode' : 'Production Live Mode',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: sandboxMode ? Colors.amber.shade900 : Colors.green.shade900,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                sandboxMode
                                    ? 'Using simulated funds. Transactions won\'t cost real money.'
                                    : 'Using real money. Funds will be deposited to your PayPal account.',
                                style: TextStyle(
                                  color: sandboxMode ? Colors.amber.shade800 : Colors.green.shade800,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: !sandboxMode, // Switch is on for Live mode
                          activeColor: Colors.green.shade700,
                          activeTrackColor: Colors.green.shade100,
                          inactiveThumbColor: Colors.amber.shade700,
                          inactiveTrackColor: Colors.amber.shade100,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            setModalState(() {
                              sandboxMode = !val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Client ID Field
                  Text(
                    'PayPal Client ID',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: clientIdController,
                    obscureText: obscureClientId,
                    decoration: InputDecoration(
                      hintText: 'Enter PayPal Client ID',
                      fillColor: inputBgColor,
                      prefixIcon: const Icon(Icons.vpn_key_rounded, color: Colors.grey, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureClientId ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                          size: 20,
                        ),
                        onPressed: () {
                          setModalState(() => obscureClientId = !obscureClientId);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Secret Key Field
                  Text(
                    'PayPal Secret Key',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: secretKeyController,
                    obscureText: obscureSecretKey,
                    decoration: InputDecoration(
                      hintText: 'Enter PayPal Secret Key',
                      fillColor: inputBgColor,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: Colors.grey, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureSecretKey ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                          size: 20,
                        ),
                        onPressed: () {
                          setModalState(() => obscureSecretKey = !obscureSecretKey);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Amount and Currency in a Row
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Premium Price',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                hintText: '2.20',
                                fillColor: inputBgColor,
                                prefixIcon: const Icon(Icons.attach_money_rounded, color: Colors.grey, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Currency',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor),
                            ),
                            const SizedBox(height: 6),
                             DropdownButtonFormField<String>(
                               isExpanded: true,
                               value: currencyController.text.toUpperCase(),
                               dropdownColor: isDark ? const Color(0xFF16213E) : Colors.white,
                               decoration: InputDecoration(
                                 fillColor: inputBgColor,
                                 contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                               ),
                               items: const [
                                DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                                DropdownMenuItem(value: 'MYR', child: Text('MYR (RM)')),
                                DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                                DropdownMenuItem(value: 'GBP', child: Text('GBP (£)')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  currencyController.text = val;
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Expandable SQL settings info
                  Card(
                    elevation: 0,
                    color: isDark ? const Color(0xFF16213E) : Colors.grey.shade100,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        ListTile(
                          dense: true,
                          title: Text(
                            'Supabase Sync Guide',
                            style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                          ),
                          subtitle: const Text('Required to share configurations across all users'),
                          leading: const Icon(Icons.storage_rounded, color: _primaryGreen),
                          trailing: Icon(
                            showSQLInstructions ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            color: Colors.grey,
                          ),
                          onTap: () {
                            setModalState(() {
                              showSQLInstructions = !showSQLInstructions;
                            });
                          },
                        ),
                        if (showSQLInstructions)
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'To make credentials work for all of your users, run the following SQL script in your Supabase SQL Editor:',
                                  style: TextStyle(fontSize: 10, height: 1.4),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0F1923) : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      sqlScript,
                                      style: const TextStyle(
                                        fontFamily: 'Courier',
                                        fontSize: 9,
                                        color: _primaryGreen,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primaryGreen.withValues(alpha: 0.15),
                                    foregroundColor: _primaryGreen,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  icon: const Icon(Icons.copy_all_rounded, size: 16),
                                  label: const Text('Copy SQL Script', style: TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: sqlScript));
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text('SQL Script copied to clipboard!'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        
                        final clientId = clientIdController.text.trim();
                        final secretKey = secretKeyController.text.trim();
                        final currency = currencyController.text.trim().toUpperCase();
                        final amount = double.tryParse(amountController.text) ?? 2.20;

                        if (clientId.isEmpty || secretKey.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Client ID and Secret Key cannot be empty.'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        // Show loader
                        showDialog(
                          context: ctx,
                          barrierDismissible: false,
                          builder: (c) => const Center(child: CircularProgressIndicator(color: _primaryGreen)),
                        );

                        bool synced = false;
                        try {
                          synced = await SubscriptionService.instance.savePayPalSettings(
                            sandboxMode: sandboxMode,
                            clientId: clientId,
                            secretKey: secretKey,
                            currency: currency,
                            amount: amount,
                          );
                        } finally {
                          Navigator.pop(ctx); // Dismiss spinner loader
                        }

                        Navigator.pop(ctx); // Close configurations bottom sheet

                        if (synced) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🎉 Settings updated and synced to Supabase successfully!'),
                              backgroundColor: Color(0xFF1A5C4A),
                            ),
                          );
                        } else {
                          // Show alert that it is saved locally but not synced
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                                  SizedBox(width: 8),
                                  Text('Database Sync Failed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              content: const Text(
                                'Settings were saved locally on this device, but could not sync to your Supabase backend.\n\n'
                                'Please make sure you have created the "paypal_settings" table in Supabase. You can find the SQL setup script by clicking on the PayPal settings and opening the "Supabase Sync Guide".',
                                style: TextStyle(fontSize: 13, height: 1.5),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('Got it', style: TextStyle(color: _primaryGreen)),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      child: const Text('Save Configurations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddUserDialog() {
    HapticFeedback.lightImpact();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    String studentType = 'University';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add New User', style: TextStyle(fontWeight: FontWeight.bold, color: _primaryGreen)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: studentType,
              decoration: const InputDecoration(labelText: 'Student Type'),
              items: const [
                DropdownMenuItem(value: 'School', child: Text('School')),
                DropdownMenuItem(value: 'University', child: Text('University')),
                DropdownMenuItem(value: 'Postgrad', child: Text('Postgraduate')),
              ],
              onChanged: (val) => studentType = val ?? 'University',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
            onPressed: () async {
              if (nameController.text.isEmpty || emailController.text.isEmpty) return;
              try {
                await _supabase.from('users').insert({
                  'user_id': _generateUUID(),
                  'name': nameController.text.trim(),
                  'email': emailController.text.trim(),
                  'student_type': studentType,
                });
                Navigator.pop(ctx);
                _loadUsers();
                HapticFeedback.mediumImpact();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to add: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Add User'),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    HapticFeedback.lightImpact();
    final nameController = TextEditingController(text: user['name']);
    final emailController = TextEditingController(text: user['email']);
    String studentType = user['student_type'] ?? 'University';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit User Details', style: TextStyle(fontWeight: FontWeight.bold, color: _primaryGreen)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: studentType,
              decoration: const InputDecoration(labelText: 'Student Type'),
              items: const [
                DropdownMenuItem(value: 'School', child: Text('School')),
                DropdownMenuItem(value: 'University', child: Text('University')),
                DropdownMenuItem(value: 'Postgrad', child: Text('Postgraduate')),
              ],
              onChanged: (val) => studentType = val ?? 'University',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
            onPressed: () async {
              try {
                await _supabase.from('users').update({
                  'name': nameController.text.trim(),
                  'email': emailController.text.trim(),
                  'student_type': studentType,
                }).eq('user_id', user['user_id']);
                Navigator.pop(ctx);
                _loadUsers();
                HapticFeedback.mediumImpact();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> user) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Delete user?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryGreen),
              ),
              const SizedBox(height: 8),
              Text(
                'You are about to delete user:\n${user['name']}\n${user['email']}\n${user['student_type']}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action cannot be undone. All data will be permanently deleted.',
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        try {
                          await _supabase.from('users').delete().eq('user_id', user['user_id']);
                          Navigator.pop(ctx);
                          _loadUsers();
                          HapticFeedback.mediumImpact();
                        } catch (e) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      },
                      child: const Text('Yes, delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSendNotificationDialog(Map<String, dynamic> user) {
    HapticFeedback.lightImpact();
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    bool sending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              'Send Notification to ${user['name'] ?? 'User'}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryGreen, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Notification Title',
                    hintText: 'e.g. Budget Alert',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Message Body',
                    hintText: 'Write the notification message here...',
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _lightBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Note: This sends a real-time phone notification. If the user doesn\'t receive it, verify the Supabase custom_notifications table is configured.',
                    style: TextStyle(fontSize: 10, color: _primaryGreen),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
                onPressed: sending
                    ? null
                    : () async {
                        if (titleController.text.trim().isEmpty || bodyController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please fill all fields')),
                          );
                          return;
                        }

                        setStateDialog(() => sending = true);
                        try {
                          await _supabase.from('custom_notifications').insert({
                            'user_id': user['user_id'],
                            'title': titleController.text.trim(),
                            'body': bodyController.text.trim(),
                            'read': false,
                          });
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🎉 Notification sent successfully!'),
                              backgroundColor: _primaryGreen,
                            ),
                          );
                          HapticFeedback.mediumImpact();
                        } catch (e) {
                          setStateDialog(() => sending = false);
                          
                          // Custom error display with SQL guide if table not found
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                                  SizedBox(width: 8),
                                  Text('Table Setup Required', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'To enable admin custom notifications, run this SQL script in your Supabase SQL Editor:',
                                    style: TextStyle(fontSize: 13, height: 1.4),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SelectableText(
                                        'CREATE TABLE custom_notifications (\n'
                                        '  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),\n'
                                        '  user_id TEXT NOT NULL,\n'
                                        '  title TEXT NOT NULL,\n'
                                        '  body TEXT NOT NULL,\n'
                                        '  read BOOLEAN DEFAULT false,\n'
                                        '  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone(\'utc\'::text, now())\n'
                                        ');\n'
                                        'ALTER TABLE custom_notifications ENABLE ROW LEVEL SECURITY;\n'
                                        'CREATE POLICY "Allow read write" ON custom_notifications FOR ALL USING (true);\n'
                                        'ALTER PUBLICATION supabase_realtime ADD TABLE custom_notifications;',
                                        style: TextStyle(fontFamily: 'monospace', fontSize: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('Got it', style: TextStyle(color: _primaryGreen)),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _users.length;
    final premiumCount = _users.where((u) => u['is_premium'] == true).length;
    final isDark = widget.isDarkMode;

    return Scaffold(
      backgroundColor: _lightBg,
      appBar: AppBar(
        title: const Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminChatListScreen()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_rounded),
            tooltip: 'Premium Analytics',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PremiumAnalyticsScreen(
                    isDarkMode: widget.isDarkMode,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.paypal_rounded),
            tooltip: 'PayPal Settings',
            onPressed: _showPayPalSettingsSheet,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _primaryGreen,
        onPressed: _showAddUserDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryGreen))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatItem('Total Users', '${_users.length}'),
                          Container(width: 1, height: 30, color: Colors.grey.shade200),
                          _buildStatItem('Active', '$activeCount'),
                          Container(width: 1, height: 30, color: Colors.grey.shade200),
                          _buildStatItem('Premium', '$premiumCount'),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search users...',
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _filteredUsers.isEmpty
                      ? const Center(child: Text('No users found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, i) {
                            final user = _filteredUsers[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                              color: Colors.white,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: _primaryGreen.withValues(alpha: 0.1),
                                      backgroundImage: (user['avatar_base64'] != null && user['avatar_base64'].toString().isNotEmpty)
                                          ? MemoryImage(
                                              base64Decode(
                                                user['avatar_base64'].toString().contains(',')
                                                    ? user['avatar_base64'].toString().split(',')[1]
                                                    : user['avatar_base64'].toString(),
                                              ),
                                            )
                                          : null,
                                      child: (user['avatar_base64'] == null || user['avatar_base64'].toString().isEmpty)
                                          ? Text(
                                              (user['name'] ?? 'U')[0].toUpperCase(),
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryGreen),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user['name'] ?? 'Unnamed',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            user['email'] ?? '',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: _lightBg,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  user['student_type'] ?? 'Student',
                                                  style: const TextStyle(fontSize: 9, color: _primaryGreen, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: user['is_premium'] == true ? const Color(0xFFEAF4F0) : Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: user['is_premium'] == true ? _primaryGreen : Colors.grey.shade300,
                                                    width: 0.5,
                                                  ),
                                                ),
                                                child: Text(
                                                  user['is_premium'] == true ? 'Premium ⭐' : 'Free Basic',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: user['is_premium'] == true ? _primaryGreen : Colors.grey.shade600,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Transform.scale(
                                              scale: 0.8,
                                              child: Switch(
                                                value: user['is_premium'] == true,
                                                activeThumbColor: _accentGreen,
                                                onChanged: (val) async {
                                                  HapticFeedback.lightImpact();
                                                  try {
                                                    final expiresAt = val
                                                        ? DateTime.now().add(const Duration(days: 30)).toIso8601String()
                                                        : null;
                                                    await _supabase.from('users').update({
                                                      'is_premium': val,
                                                      'premium_expires_at': expiresAt,
                                                    }).eq('user_id', user['user_id']);
                                                    _loadUsers();
                                                  } catch (e) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Failed to update premium status: $e'),
                                                        backgroundColor: Colors.redAccent,
                                                      ),
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              constraints: const BoxConstraints(),
                                              padding: const EdgeInsets.all(4),
                                              icon: const Icon(Icons.notifications_active_outlined, color: _primaryGreen, size: 20),
                                              tooltip: 'Send Custom Notification',
                                              onPressed: () => _showSendNotificationDialog(user),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              constraints: const BoxConstraints(),
                                              padding: const EdgeInsets.all(4),
                                              icon: const Icon(Icons.edit_outlined, color: _accentGreen, size: 20),
                                              onPressed: () => _showEditUserDialog(user),
                                            ),
                                            const SizedBox(width: 16),
                                            IconButton(
                                              constraints: const BoxConstraints(),
                                              padding: const EdgeInsets.all(4),
                                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                              onPressed: () => _showDeleteConfirmation(user),
                                            ),
                                            const SizedBox(width: 4), // Align with bell icon
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem(String label, String val) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryGreen)),
      ],
    );
  }
}
