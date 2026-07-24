// budgets.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'subscription_service.dart';
import 'premium.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _lightBg = Color(0xFFEAF4F0);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get _cardBg => _isDark ? const Color(0xFF16213E) : Colors.white;
  Color get _scaffoldBg => _isDark ? const Color(0xFF1A1A2E) : _lightBg;

  final _supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _budgets = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, double> _categorySpent = {};

  // Monthly summary
  double _totalBudget = 0;
  double _totalSpent = 0;
  String _selectedMonth = '';
  int _selectedMonthIndex = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String _currency = 'RM';

  @override
  void initState() {
    super.initState();
    _selectedMonth = _getMonthName(_selectedMonthIndex);
    _loadData();
  }

  // ————————————————————————————————————————————————————————————————
  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  void _previousMonth() {
    setState(() {
      if (_selectedMonthIndex == 1) {
        _selectedMonthIndex = 12;
        _selectedYear--;
      } else {
        _selectedMonthIndex--;
      }
      _selectedMonth = _getMonthName(_selectedMonthIndex);
      _loadData();
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedYear == now.year && _selectedMonthIndex == now.month) return;
    setState(() {
      if (_selectedMonthIndex == 12) {
        _selectedMonthIndex = 1;
        _selectedYear++;
      } else {
        _selectedMonthIndex++;
      }
      _selectedMonth = _getMonthName(_selectedMonthIndex);
      _loadData();
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedYear == now.year && _selectedMonthIndex == now.month;
  }

  // ——————————————————————————————————————————————————————————————————
  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _currency = prefs.getString('currency') ?? 'RM';
      await Future.wait([
        _loadCategories(),
        _loadBudgets(),
        _loadCategorySpent(),
      ]);
      _calculateSummary();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCategories() async {
    final res = await _supabase
        .from('categories')
        .select('category_id, name, icon, colour')
        .order('name');

    final prefs = await SharedPreferences.getInstance();
    final customCatsRaw = prefs.getString('custom_categories');
    List<Map<String, dynamic>> customCats = [];
    if (customCatsRaw != null) {
      customCats = List<Map<String, dynamic>>.from(jsonDecode(customCatsRaw));
    }

    if (mounted) {
      setState(() {
        _categories = [
          ...List<Map<String, dynamic>>.from(res as List),
          ...customCats,
        ];
      });
    }
  }

  Future<void> _loadBudgets() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final res = await _supabase
        .from('budgets')
        .select(
          'budget_id, budget_limit, category_id, month, year, categories(name, icon, colour)',
        )
        .eq('user_id', userId)
        .eq('month', _selectedMonthIndex)
        .eq('year', _selectedYear);

    final prefs = await SharedPreferences.getInstance();
    final customBudgetsRaw = prefs.getString('custom_budgets');
    List<Map<String, dynamic>> customBudgets = [];
    if (customBudgetsRaw != null) {
      final allCustomBudgets = List<Map<String, dynamic>>.from(jsonDecode(customBudgetsRaw));
      customBudgets = allCustomBudgets.where((b) => 
        b['user_id'] == userId && 
        b['month'] == _selectedMonthIndex && 
        b['year'] == _selectedYear
      ).toList();
    }

    if (mounted) {
      setState(() => _budgets = [
        ...List<Map<String, dynamic>>.from(res as List),
        ...customBudgets,
      ]);
    }
  }

  Future<void> _loadCategorySpent() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final monthStart = DateTime(
      _selectedYear,
      _selectedMonthIndex,
      1,
    ).toIso8601String();
    final monthEnd = DateTime(
      _selectedYear,
      _selectedMonthIndex + 1,
      0,
      23,
      59,
      59,
    ).toIso8601String();

    final res = await _supabase
        .from('expenses')
        .select('category_id, amount, description')
        .eq('user_id', userId)
        .gte('expense_date', monthStart)
        .lte('expense_date', monthEnd);

    final prefs = await SharedPreferences.getInstance();
    final customCatsRaw = prefs.getString('custom_categories');
    List<Map<String, dynamic>> customCats = [];
    if (customCatsRaw != null) {
      customCats = List<Map<String, dynamic>>.from(jsonDecode(customCatsRaw));
    }

    final Map<String, double> spent = {};
    for (final e in res as List) {
      String catId = e['category_id'] as String;
      final amount = (e['amount'] as num).toDouble();
      final desc = e['description'] as String? ?? '';
      
      if (desc.startsWith('[') && desc.contains(']')) {
        final closingIndex = desc.indexOf(']');
        final customCatName = desc.substring(1, closingIndex);
        final matchedCat = customCats.firstWhere(
          (c) => c['name'].toString().toLowerCase() == customCatName.toLowerCase(),
          orElse: () => {'category_id': 'custom_${customCatName.toLowerCase().replaceAll(' ', '_')}'},
        );
        catId = matchedCat['category_id'];
      }
      
      spent[catId] = (spent[catId] ?? 0) + amount;
    }

    if (mounted) {
      setState(() => _categorySpent = spent);
    }
  }

  void _calculateSummary() {
    _totalBudget = 0;
    _totalSpent = 0;
    for (final b in _budgets) {
      final limit = (b['budget_limit'] as num).toDouble();
      _totalBudget += limit;
      final catId = b['category_id'] as String;
      _totalSpent += _categorySpent[catId] ?? 0;
    }
  }

  // â”€â”€ CRUD Operations â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _addBudget() async {
    final isPremium = SubscriptionService.instance.isPremium;
    if (!isPremium && _budgets.length >= 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Free tier limited to 3 budgets. Please upgrade to Premium!'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PremiumScreen()),
        );
      }
      return;
    }

    // Get existing budget category IDs to filter them out
    final existingCategoryIds = _budgets
        .map((b) => b['category_id'] as String)
        .toSet();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetFormSheet(
        categories: _categories,
        month: _selectedMonthIndex,
        year: _selectedYear,
        existingCategoryIds: existingCategoryIds,
      ),
    );

    if (result != null && mounted) {
      try {
        final userId = _supabase.auth.currentUser?.id;
        final String categoryId = result['category_id'];
        
        if (categoryId.startsWith('custom_')) {
          final prefs = await SharedPreferences.getInstance();
          final customBudgetsRaw = prefs.getString('custom_budgets');
          List<Map<String, dynamic>> allCustomBudgets = [];
          if (customBudgetsRaw != null) {
            allCustomBudgets = List<Map<String, dynamic>>.from(jsonDecode(customBudgetsRaw));
          }
          await _loadCategories();
          final cat = _categories.firstWhere(
            (c) => c['category_id'] == categoryId,
            orElse: () => {
              'category_id': categoryId,
              'name': 'Custom',
              'icon': 'category_rounded',
              'colour': '#2E9B78',
            },
          );
          allCustomBudgets.add({
            'budget_id': 'local_budget_${DateTime.now().millisecondsSinceEpoch}',
            'user_id': userId,
            'category_id': categoryId,
            'budget_limit': result['budget_limit'],
            'month': _selectedMonthIndex,
            'year': _selectedYear,
            'categories': {
              'name': cat['name'],
              'icon': cat['icon'],
              'colour': cat['colour'],
            }
          });
          await prefs.setString('custom_budgets', jsonEncode(allCustomBudgets));
        } else {
          await _supabase.from('budgets').insert({
            'user_id': userId,
            'category_id': categoryId,
            'budget_limit': result['budget_limit'],
            'month': _selectedMonthIndex,
            'year': _selectedYear,
          });
        }
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Budget added successfully!'),
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
    }
  }

  Future<void> _editBudget(Map<String, dynamic> budget) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetFormSheet(
        categories: _categories,
        month: _selectedMonthIndex,
        year: _selectedYear,
        existing: budget,
        onDelete: () => _deleteBudgetWithConfirm(budget),
      ),
    );

    if (result != null && mounted) {
      try {
        final String budgetId = budget['budget_id'] as String;
        if (budgetId.startsWith('local_budget_')) {
          final prefs = await SharedPreferences.getInstance();
          final customBudgetsRaw = prefs.getString('custom_budgets');
          if (customBudgetsRaw != null) {
            List<Map<String, dynamic>> allCustomBudgets = List<Map<String, dynamic>>.from(jsonDecode(customBudgetsRaw));
            final index = allCustomBudgets.indexWhere((b) => b['budget_id'] == budgetId);
            if (index != -1) {
              allCustomBudgets[index]['budget_limit'] = result['budget_limit'];
              await prefs.setString('custom_budgets', jsonEncode(allCustomBudgets));
            }
          }
        } else {
          await _supabase
              .from('budgets')
              .update({
                'category_id': result['category_id'],
                'budget_limit': result['budget_limit'],
              })
              .eq('budget_id', budgetId);
        }
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Budget updated successfully!'),
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
    }
  }

  Future<void> _deleteBudgetWithConfirm(Map<String, dynamic> budget) async {
    final cat = budget['categories'];
    final name = cat?['name'] ?? 'Unknown';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Budget?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A5C4A),
          ),
        ),
        content: Text(
          'Are you sure you want to delete the budget for "$name"?',
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
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _deleteBudget(budget['budget_id'], name);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _deleteBudget(String budgetId, String categoryName) async {
    try {
      await _supabase.from('budgets').delete().eq('budget_id', budgetId);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Budget deleted'),
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
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Color _parseColour(String? hex) {
    try {
      if (hex == null || hex.isEmpty) return _primaryGreen;
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return _primaryGreen;
    }
  }

  IconData _categoryIcon(String? icon) {
    switch (icon?.toLowerCase()) {
      case 'food':
      case 'restaurant':
        return Icons.restaurant_menu_rounded;
      case 'transport':
      case 'bus':
        return Icons.directions_bus_rounded;
      case 'shopping':
      case 'shop':
        return Icons.shopping_bag_rounded;
      case 'entertainment':
        return Icons.movie_rounded;
      case 'health':
        return Icons.favorite_rounded;
      case 'education':
        return Icons.school_rounded;
      case 'bills':
      case 'utilities':
        return Icons.receipt_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildMonthSelector(),
            _buildSummaryCard(),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primaryGreen),
                    )
                  : _buildBudgetList(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBudget,
        backgroundColor: _primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // â”€â”€ HEADER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Budgets',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: _primaryGreen, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${_budgets.length} budgets',
                  style: TextStyle(
                    fontSize: 12,
                    color: _primaryGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ MONTH SELECTOR â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildMonthSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: _previousMonth,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _cardBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Icon(Icons.chevron_left_rounded, size: 24),
            ),
          ),
          Text(
            '$_selectedMonth $_selectedYear',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          GestureDetector(
            onTap: _nextMonth,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _cardBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: _isCurrentMonth ? Colors.grey.shade300 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ SUMMARY CARD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSummaryCard() {
    final remaining = _totalBudget - _totalSpent;
    final percent = _totalBudget > 0 ? (_totalSpent / _totalBudget) : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _summaryItem('Total', '$_currency ${_totalBudget.toStringAsFixed(0)}'),
                _summaryItem('Spent', '$_currency ${_totalSpent.toStringAsFixed(0)}'),
                _summaryItem(
                  'Remaining',
                  '$_currency ${remaining.toStringAsFixed(0)}',
                  color: remaining < 0 ? Colors.redAccent : _primaryGreen,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent.clamp(0.0, 1.0).toDouble(),
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  percent > 0.9 ? Colors.redAccent : _primaryGreen,
                ),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? _textColor,
          ),
        ),
      ],
    );
  }

  // â”€â”€ BUDGET LIST â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildBudgetList() {
    if (_budgets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.pie_chart_outline_rounded,
              size: 52,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'No budgets set',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to create your first budget',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _primaryGreen,
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _budgets.length,
        itemBuilder: (_, i) {
          final budget = _budgets[i];
          final cat = budget['categories'];
          final catId = budget['category_id'] as String;
          final spent = _categorySpent[catId] ?? 0;
          final limit = (budget['budget_limit'] as num).toDouble();
          final colour = _parseColour(cat?['colour']);
          final isOver = spent > limit;
          final progress = limit > 0
              ? (spent / limit).clamp(0.0, 1.0).toDouble()
              : 0.0;
          final name = cat?['name'] ?? 'Unknown';

          return _buildBudgetCard(
            id: budget['budget_id'],
            name: name,
            icon: cat?['icon'],
            colour: colour,
            spent: spent,
            limit: limit,
            progress: progress,
            isOver: isOver,
            onEdit: () => _editBudget(budget),
            onDelete: () => _deleteBudget(budget['budget_id'], name),
          );
        },
      ),
    );
  }

  Widget _buildBudgetCard({
    required String id,
    required String name,
    required String? icon,
    required Color colour,
    required double spent,
    required double limit,
    required double progress,
    required bool isOver,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Dismissible(
      key: Key(id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Delete Budget?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A5C4A),
              ),
            ),
            content: Text(
              'Are you sure you want to delete the budget for "$name"?',
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
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onEdit,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colour.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_categoryIcon(icon), color: colour, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textColor,
                          ),
                        ),
                        Text(
                          '$_currency ${limit.toStringAsFixed(0)}/month',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$_currency ${spent.toStringAsFixed(0)} spent',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isOver ? Colors.redAccent : _primaryGreen,
                        ),
                      ),
                      if (isOver)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Over budget!',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        )
                      else
                        Text(
                          '$_currency ${(limit - spent).toStringAsFixed(0)} left',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.toDouble(),
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isOver ? Colors.redAccent : colour,
                  ),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  BUDGET FORM SHEET
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _BudgetFormSheet extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final int month;
  final int year;
  final Map<String, dynamic>? existing;
  final Set<String>? existingCategoryIds;
  final VoidCallback? onDelete;

  const _BudgetFormSheet({
    required this.categories,
    required this.month,
    required this.year,
    this.existing,
    this.existingCategoryIds,
    this.onDelete,
  });

  @override
  State<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends State<_BudgetFormSheet> {
  static const Color _primaryGreen = Color(0xFF1A5C4A);
  final _supabase = Supabase.instance.client;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get _sheetBg => _isDark ? const Color(0xFF16213E) : Colors.white;
  Color get _labelColor => _isDark ? Colors.grey.shade300 : const Color(0xFF333333);
  Color get _fieldFillColor => _isDark ? Colors.white10 : const Color(0xFFF7FAF9);
  Color get _borderColor => _isDark ? Colors.white12 : Colors.grey.shade200;

  final _formKey = GlobalKey<FormState>();
  final _limitController = TextEditingController();

  String? _selectedCategoryId;
  final bool _saving = false;
  late List<Map<String, dynamic>> _sheetCategories;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _sheetCategories = List<Map<String, dynamic>>.from(widget.categories);
    if (_isEditing) {
      final e = widget.existing!;
      _selectedCategoryId = e['category_id'];
      _limitController.text = (e['budget_limit'] as num).toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a category'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'category_id': _selectedCategoryId,
      'budget_limit': double.parse(_limitController.text),
    });
  }

  Future<void> _deleteCustomCategoryPrompt(Map<String, dynamic> cat) async {
    final name = cat['name'];
    final id = cat['category_id'];
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Are you sure you want to delete the custom category "$name"? This will also clean up associated budgets.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      
      final customCatsRaw = prefs.getString('custom_categories');
      if (customCatsRaw != null) {
        List<Map<String, dynamic>> customCats = List<Map<String, dynamic>>.from(jsonDecode(customCatsRaw));
        customCats.removeWhere((c) => c['category_id'] == id);
        await prefs.setString('custom_categories', jsonEncode(customCats));
      }
      
      final customBudgetsRaw = prefs.getString('custom_budgets');
      if (customBudgetsRaw != null) {
        List<Map<String, dynamic>> customBudgets = List<Map<String, dynamic>>.from(jsonDecode(customBudgetsRaw));
        customBudgets.removeWhere((b) => b['category_id'] == id);
        await prefs.setString('custom_budgets', jsonEncode(customBudgets));
      }
      
      if (_selectedCategoryId == id) {
        setState(() {
          _selectedCategoryId = null;
        });
      }
      
      // Update local state list of categories dynamically so it is removed from this sheet immediately
      if (mounted) {
        setState(() {
          _sheetCategories.removeWhere((c) => c['category_id'] == id);
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$name" deleted!')),
      );
    }
  }

  Future<void> _addCustomCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Custom Category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Gym, Books, Gifts',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      // 1. Try to insert it into Supabase categories table
      final newCat = await _supabase.from('categories').insert({
        'name': name,
        'icon': 'category_rounded',
        'colour': '#2E9B78',
      }).select().single();
      
      // Auto reload is handled by parent, but we can set state locally so it shows selected
      setState(() {
        _selectedCategoryId = newCat['category_id'];
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Category "$name" created!'),
          backgroundColor: _primaryGreen,
        ),
      );
    } catch (e) {
      // 2. Fall back to local storage
      final prefs = await SharedPreferences.getInstance();
      final customCatsRaw = prefs.getString('custom_categories');
      List<Map<String, dynamic>> customCats = [];
      if (customCatsRaw != null) {
        customCats = List<Map<String, dynamic>>.from(jsonDecode(customCatsRaw));
      }
      
      final localCatId = 'custom_${name.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}';
      final newLocalCat = {
        'category_id': localCatId,
        'name': name,
        'icon': 'category_rounded',
        'colour': '#2E9B78',
      };
      
      customCats.add(newLocalCat);
      await prefs.setString('custom_categories', jsonEncode(customCats));
      
      // Update local state list of categories dynamically so it shows up in this sheet immediately
      if (mounted) {
        setState(() {
          _sheetCategories.add(newLocalCat);
          _selectedCategoryId = localCatId;
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Category "$name" added locally!'),
          backgroundColor: _primaryGreen,
        ),
      );
    }
  }

  void _showDeleteConfirmation() {
    final cat = widget.existing?['categories'];
    final name = cat?['name'] ?? 'Unknown';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Budget?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A5C4A),
          ),
        ),
        content: Text(
          'Are you sure you want to delete the budget for "$name"?',
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
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete?.call();
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // Filter categories for adding (exclude ones that already have budgets)
    final availableCategories = _isEditing
        ? _sheetCategories
        : _sheetCategories.where((cat) {
            final catId = cat['category_id'] as String;
            return !(widget.existingCategoryIds?.contains(catId) ?? false);
          }).toList();

    return Container(
      decoration: BoxDecoration(
        color: _sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header with Delete Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEditing ? 'Edit Budget' : 'Add Budget',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _isDark ? Colors.white : const Color(0xFF1A5C4A),
                    ),
                  ),
                  if (_isEditing && widget.onDelete != null)
                    GestureDetector(
                      onTap: _showDeleteConfirmation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_getMonthName(widget.month)} ${widget.year}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),

              // Category
              _label('Category'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...availableCategories.map((cat) {
                    final selected = _selectedCategoryId == cat['category_id'];
                    final isCustom = cat['category_id'].toString().startsWith('custom_');
                    return GestureDetector(
                      onTap: () => setState(
                        () => _selectedCategoryId = cat['category_id'],
                      ),
                      onLongPress: isCustom ? () => _deleteCustomCategoryPrompt(cat) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? _primaryGreen : (_isDark ? Colors.white10 : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? _primaryGreen
                                : (_isDark ? Colors.white24 : Colors.grey.shade300),
                          ),
                        ),
                        child: Text(
                          cat['name'],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: selected ? Colors.white : (_isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  GestureDetector(
                    onTap: _addCustomCategory,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isDark ? Colors.white24 : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add,
                            size: 16,
                            color: _isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Custom',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Budget Limit
              _label('Budget Limit (RM)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _limitController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _inputDec(
                  hint: 'e.g. 500',
                  icon: Icons.attach_money_rounded,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter budget limit';
                  if (double.tryParse(v) == null) return 'Enter a valid number';
                  if (double.parse(v) <= 0) {
                    return 'Budget must be greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isEditing ? 'Update Budget' : 'Save Budget',
                          style: const TextStyle(
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

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: _labelColor,
    ),
  );

  InputDecoration _inputDec({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 18),
      filled: true,
      fillColor: _fieldFillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1A5C4A), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}
