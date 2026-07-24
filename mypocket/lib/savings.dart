// savings.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';
import 'widgets/glassmorphism.dart';
import 'subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'premium.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _accentGreen = Color(0xFF2E9B78);
  
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _goals = [];
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
        await _loadGoals();
      } else {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadGoals() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await _supabase
          .from('savings_goals')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _goals = List<Map<String, dynamic>>.from(res);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading goals: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _triggerHaptic() {
    HapticFeedback.lightImpact();
  }

  Future<void> _addOrEditGoal({Map<String, dynamic>? goal}) async {
    _triggerHaptic();
    final isEdit = goal != null;
    final titleController = TextEditingController(text: goal?['title'] ?? '');
    final targetController = TextEditingController(text: goal?['target']?.toString() ?? '');
    final currentController = TextEditingController(text: goal?['current']?.toString() ?? '0');
    final autoAllocController = TextEditingController(text: goal?['auto_allocate']?.toString() ?? '0');

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
                  isEdit ? 'Edit Savings Goal' : 'New Savings Goal',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : _primaryGreen,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Goal Title',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Emergency Fund',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Target (RM)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: targetController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              hintText: '1000',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Saved (RM)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: currentController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              hintText: '0',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Auto-allocate from Income (%)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: autoAllocController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '5',
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (titleController.text.isEmpty || targetController.text.isEmpty) {
                        return;
                      }
                      final dbId = goal?['goal_id'] ?? goal?['id'];
                      final double targetVal = double.tryParse(targetController.text) ?? 0.0;
                      final double currentVal = double.tryParse(currentController.text) ?? 0.0;
                      final double autoVal = double.tryParse(autoAllocController.text) ?? 0.0;

                      final newGoal = {
                        'title': titleController.text,
                        'target': targetVal,
                        'current': currentVal,
                        'auto_allocate': autoVal,
                      };

                      final userId = _supabase.auth.currentUser?.id;
                      if (userId != null) {
                        try {
                          if (dbId != null) {
                            await _supabase
                                .from('savings_goals')
                                .update(newGoal)
                                .eq('goal_id', dbId);
                          } else {
                            newGoal['user_id'] = userId;
                            final inserted = await _supabase
                                .from('savings_goals')
                                .insert(newGoal)
                                .select()
                                .single();
                            // Use Supabase-generated goal_id for local cache
                            newGoal['goal_id'] = inserted['goal_id'];
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error saving goal: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                          return;
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('You must be logged in to save goals.'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                        return;
                      }

                      _loadGoals();
                      if (mounted) Navigator.pop(context);
                      _triggerHaptic();
                    },
                    child: Text(isEdit ? 'Save Changes' : 'Create Goal'),
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

  Future<void> _deleteGoal(dynamic goalId) async {
    _triggerHaptic();
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      try {
        await _supabase
            .from('savings_goals')
            .delete()
            .eq('goal_id', goalId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting goal: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
    _loadGoals();
  }

  Future<void> _quickAddFunds(Map<String, dynamic> goal) async {
    _triggerHaptic();
    final amountController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Add Funds to ${goal['title']}'),
          content: TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Amount (RM)',
              hintText: '50.00',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final val = double.tryParse(amountController.text) ?? 0.0;
                if (val > 0) {
                  final double cur = double.tryParse(goal['current']?.toString() ?? '0') ?? 0.0;
                  final double newCurrent = cur + val;

                  final dbId = goal['goal_id'] ?? goal['id'];
                  final userId = _supabase.auth.currentUser?.id;
                  if (userId != null && dbId != null) {
                    try {
                      await _supabase
                          .from('savings_goals')
                          .update({'current': newCurrent})
                          .eq('goal_id', dbId);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error adding funds: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  }

                  _loadGoals();
                }
                if (mounted) Navigator.pop(ctx);
                _triggerHaptic();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
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
          title: const Text('Savings Goals', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  'Savings Goals is a Premium Feature',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'To see, edit, or manage your savings goals, please upgrade to Premium.',
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

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFEAF4F0),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            Expanded(
              child: _goals.isEmpty
                  ? _buildEmptyState()
                  : _buildGoalsList(isDark),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditGoal(),
        backgroundColor: _primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Savings Goals',
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
              '${_goals.length} goals',
              style: const TextStyle(
                fontSize: 12,
                color: _primaryGreen,
                fontWeight: FontWeight.w500,
              ),
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
          Icon(Icons.savings_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No savings goals set',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to create a savings goal.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalsList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _goals.length,
      itemBuilder: (context, index) {
        final goal = _goals[index];
        final double target = (goal['target'] as num?)?.toDouble() ?? 1.0;
        final double current = (goal['current'] as num?)?.toDouble() ?? 0.0;
        final double progress = (current / target).clamp(0.0, 1.0);
        final double autoAlloc = (goal['auto_allocate'] as num?)?.toDouble() ?? 0.0;

        final goalId = goal['goal_id'] ?? goal['id'];
        return Dismissible(
          key: Key(goalId.toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 16),
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
                title: const Text('Delete Goal?'),
                content: Text('Are you sure you want to delete "${goal['title']}"?'),
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
          onDismissed: (_) => _deleteGoal(goalId),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        goal['title'] ?? 'Savings Goal',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded, color: _accentGreen),
                          onPressed: () => _quickAddFunds(goal),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.grey),
                          onPressed: () => _addOrEditGoal(goal: goal),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_currency ${current.toStringAsFixed(2)} saved',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _primaryGreen,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Target: $_currency ${target.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Stack(
                  children: [
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          height: 12,
                          width: constraints.maxWidth * progress,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_accentGreen, _primaryGreen],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        );
                      }
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress: ${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    if (autoAlloc > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primaryGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Auto-allocating: ${autoAlloc.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _primaryGreen,
                          ),
                        ),
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
