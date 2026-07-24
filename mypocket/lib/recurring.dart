// recurring.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import 'widgets/glassmorphism.dart';
import 'subscription_service.dart';
import 'premium.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _accentGreen = Color(0xFF2E9B78);

  final Box _recurringBox = Hive.box('recurring_expenses');
  List<Map<String, dynamic>> _subs = [];
  bool _loading = true;
  bool _isPremium = false;
  String _currency = 'RM';

  @override
  void initState() {
    super.initState();
    _checkPremiumAndLoad();
  }

  Future<void> _checkPremiumAndLoad() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _currency = prefs.getString('currency') ?? 'RM';
    final premium = await SubscriptionService.instance.checkPremiumStatus();
    if (mounted) {
      setState(() {
        _isPremium = premium;
      });
      if (premium) {
        _loadSubs();
      } else {
        setState(() => _loading = false);
      }
    }
  }

  void _loadSubs() {
    setState(() => _loading = true);
    final rawSubs = _recurringBox.values.map((v) => Map<String, dynamic>.from(v as Map)).toList();
    setState(() {
      _subs = rawSubs;
      _loading = false;
    });
  }

  void _triggerHaptic() {
    HapticFeedback.lightImpact();
  }

  Future<void> _addOrEditSub({Map<String, dynamic>? sub}) async {
    _triggerHaptic();
    final isEdit = sub != null;
    final nameController = TextEditingController(text: sub?['name'] ?? '');
    final amountController = TextEditingController(text: sub?['amount']?.toString() ?? '');
    final dateController = TextEditingController(text: sub?['due_day']?.toString() ?? '1');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
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
                  isEdit ? 'Edit Subscription' : 'New Subscription',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : _primaryGreen,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Subscription Name',
                    hintText: 'e.g. Netflix, Spotify',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Monthly Cost (RM)',
                          hintText: '14.90',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: dateController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Due Day of Month (1-31)',
                          hintText: '15',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.isEmpty || amountController.text.isEmpty) {
                        return;
                      }
                      final id = sub?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
                      final newSub = {
                        'id': id,
                        'name': nameController.text,
                        'amount': double.tryParse(amountController.text) ?? 0.0,
                        'due_day': int.tryParse(dateController.text) ?? 1,
                      };
                      await _recurringBox.put(id, newSub);
                      _loadSubs();
                      if (mounted) Navigator.pop(context);
                      _triggerHaptic();

                      // Mock scheduling reminder
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Subscription reminder scheduled for "${nameController.text}"!'),
                          backgroundColor: _primaryGreen,
                        ),
                      );
                    },
                    child: Text(isEdit ? 'Save Changes' : 'Create Subscription'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteSub(String id) async {
    _triggerHaptic();
    await _recurringBox.delete(id);
    _loadSubs();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _primaryGreen)),
      );
    }

    if (!_isPremium) {
      return Scaffold(
        backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFEAF4F0),
        appBar: AppBar(
          title: const Text('Recurring Bills', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          foregroundColor: isDark ? Colors.white : Colors.black,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _primaryGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: _primaryGreen, size: 64),
                ),
                const SizedBox(height: 24),
                Text(
                  'Recurring Bills is a Premium Feature',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'To see, edit, or manage your recurring bills, please upgrade to Premium.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PremiumScreen()),
                      ).then((_) => _checkPremiumAndLoad());
                    },
                    child: const Text(
                      'Upgrade to Premium',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final totalCost = _subs.fold<double>(0.0, (sum, item) => sum + (item['amount'] ?? 0.0));

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFEAF4F0),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark, totalCost),
            Expanded(
              child: _subs.isEmpty
                  ? _buildEmptyState()
                  : _buildSubsList(isDark),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditSub(),
        backgroundColor: _primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader(bool isDark, double totalCost) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recurring Bills',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_subs.length} bills',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _primaryGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A5C4A), Color(0xFF2E9B78)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Monthly Recurring:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  '$_currency ${totalCost.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.repeat_rounded, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No recurring expenses',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to add subscriptions.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSubsList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _subs.length,
      itemBuilder: (context, index) {
        final sub = _subs[index];
        final name = sub['name'] ?? 'Subscription';
        final double amt = (sub['amount'] as num?)?.toDouble() ?? 0.0;
        final int dueDay = sub['due_day'] ?? 1;

        return Dismissible(
          key: Key(sub['id']),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_rounded, color: Colors.white),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete Subscription?'),
                content: Text('Are you sure you want to delete "$name"?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) => _deleteSub(sub['id']),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16213E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _primaryGreen.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.repeat_one_rounded, color: _primaryGreen),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Due day: $dueDay of the month',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '$_currency ${amt.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                        fontSize: 15,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.grey, size: 20),
                      onPressed: () => _addOrEditSub(sub: sub),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
