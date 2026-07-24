// expenses.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'widgets/glassmorphism.dart';
import 'dart:convert';

import 'subscription_service.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _lightBg = Color(0xFFEAF4F0);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get _cardBg => _isDark ? const Color(0xFF16213E) : Colors.white;
  Color get _scaffoldBg => _isDark ? const Color(0xFF1A1A2E) : _lightBg;

  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _loading = true;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  List<Map<String, dynamic>> _allExpenses = [];
  List<Map<String, dynamic>> _categories = [];
  String _currency = 'RM';

  double? _minAmount;
  double? _maxAmount;
  DateTimeRange? _selectedDateRange;
  String _sortBy = 'date_desc';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Load data ─────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _currency = prefs.getString('currency') ?? 'RM';
      await Future.wait([_loadExpenses(), _loadCategories()]);
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadExpenses() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    var query = _supabase
        .from('expenses')
        .select(
          'expense_id, amount, description, expense_date, category_id, categories(name, icon, colour)',
        )
        .eq('user_id', userId);

    final isPremium = SubscriptionService.instance.isPremium;
    if (!isPremium) {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      query = query.gte('expense_date', thirtyDaysAgo);
    }

    final res = await query.order('expense_date', ascending: false);

    final List<Map<String, dynamic>> processed = [];
    for (var e in res as List) {
      var item = Map<String, dynamic>.from(e);
      final desc = item['description'] as String? ?? '';
      if (desc.startsWith('[') && desc.contains(']')) {
        final closingIndex = desc.indexOf(']');
        final customCatName = desc.substring(1, closingIndex);
        final realDesc = desc.substring(closingIndex + 1).trim();
        item['description'] = realDesc;
        item['categories'] = {
          'name': customCatName,
          'icon': 'category_rounded',
          'colour': '#2E9B78',
        };
        item['category_id'] = 'custom_${customCatName.toLowerCase().replaceAll(' ', '_')}';
      }
      processed.add(item);
    }

    if (mounted) {
      setState(
        () => _allExpenses = processed,
      );
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

  // ── Filtered + grouped expenses ───────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    List<Map<String, dynamic>> list = _allExpenses.where((e) {
      final cat = e['categories'];
      final catName = (cat?['name'] ?? '').toString();
      final desc = (e['description'] ?? '').toString().toLowerCase();
      final double amt = (e['amount'] as num).toDouble();
      final DateTime? date = e['expense_date'] != null ? DateTime.tryParse(e['expense_date'])?.toLocal() : null;

      final matchCat =
          _selectedCategory == 'All' ||
          catName.toLowerCase() == _selectedCategory.toLowerCase();
      final matchSearch =
          _searchQuery.isEmpty ||
          desc.contains(_searchQuery) ||
          catName.toLowerCase().contains(_searchQuery);
      final matchMin = _minAmount == null || amt >= _minAmount!;
      final matchMax = _maxAmount == null || amt <= _maxAmount!;
      final matchDate = _selectedDateRange == null ||
          (date != null &&
              date.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
              date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1))));

      return matchCat && matchSearch && matchMin && matchMax && matchDate;
    }).toList();

    // Apply sorting
    if (_sortBy == 'date_desc') {
      list.sort((a, b) => (b['expense_date'] ?? '').compareTo(a['expense_date'] ?? ''));
    } else if (_sortBy == 'date_asc') {
      list.sort((a, b) => (a['expense_date'] ?? '').compareTo(b['expense_date'] ?? ''));
    } else if (_sortBy == 'amount_desc') {
      list.sort((a, b) => (b['amount'] as num).compareTo(a['amount'] as num));
    } else if (_sortBy == 'amount_asc') {
      list.sort((a, b) => (a['amount'] as num).compareTo(b['amount'] as num));
    }

    return list;
  }

  // Group by date label
  Map<String, List<Map<String, dynamic>>> get _grouped {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final e in _filtered) {
      final label = _dateGroupLabel(e['expense_date']);
      groups.putIfAbsent(label, () => []).add(e);
    }
    return groups;
  }

  String _dateGroupLabel(String? raw) {
    if (raw == null) return 'Unknown';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return 'Unknown';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    if (diff == 0) return 'Today — ${_fullDate(dt)}';
    if (diff == 1) return 'Yesterday — ${_fullDate(dt)}';
    return _fullDate(dt);
  }

  String _fullDate(DateTime dt) {
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _timeAndCat(Map<String, dynamic> e) {
    final raw = e['expense_date'];
    final dt = raw != null ? DateTime.tryParse(raw)?.toLocal() : null;
    final cat = e['categories'];
    final catName = cat?['name'] ?? '';
    if (dt == null) return catName;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm · $catName';
  }

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

  // ── Add Expense ───────────────────────────────────────────────────────
  void _showAddExpense() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AddExpenseSheet(categories: _categories, onSaved: _loadData),
    );
  }

  // ── Delete expense ────────────────────────────────────────────────────
  Future<void> _deleteExpense(String expenseId) async {
    try {
      await _supabase.from('expenses').delete().eq('expense_id', expenseId);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expense deleted'),
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

  Future<void> _deleteExpenseWithConfirm(Map<String, dynamic> expense) async {
    final name =
        (expense['description'] != null &&
            expense['description'].toString().isNotEmpty)
        ? expense['description']
        : (expense['categories']?['name'] ?? 'Expense');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete expense?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A5C4A),
          ),
        ),
        content: Text('Are you sure you want to delete "$name"?'),
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
      await _deleteExpense(expense['expense_id']);
      if (mounted) Navigator.pop(context);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildCategoryFilter(),
            const SizedBox(height: 8),
            Expanded(child: _loading ? _buildLoading() : _buildList()),
          ],
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Expenses',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          GestureDetector(
            onTap: _showAddExpense,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: _primaryGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // ── SEARCH BAR ────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
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
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search expenses...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.grey.shade400,
                      size: 18,
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.filter_list_rounded,
                    color: (_minAmount != null || _maxAmount != null || _selectedDateRange != null)
                        ? _primaryGreen
                        : Colors.grey.shade400,
                    size: 20,
                  ),
                  onPressed: _showFilterSheet,
                ),
              ],
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  void _showFilterSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Filter & Sort', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              _minAmount = null;
                              _maxAmount = null;
                              _selectedDateRange = null;
                              _sortBy = 'date_desc';
                            });
                            setState(() {});
                            HapticFeedback.lightImpact();
                          },
                          child: const Text('Reset', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Sort by', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _sortBy,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      items: const [
                        DropdownMenuItem(value: 'date_desc', child: Text('Date (Newest first)')),
                        DropdownMenuItem(value: 'date_asc', child: Text('Date (Oldest first)')),
                        DropdownMenuItem(value: 'amount_desc', child: Text('Amount (Highest first)')),
                        DropdownMenuItem(value: 'amount_asc', child: Text('Amount (Lowest first)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => _sortBy = val);
                          setState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Amount Range (RM)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: 'Min', prefixText: '$_currency '),
                            onChanged: (val) {
                              _minAmount = double.tryParse(val);
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(hintText: 'Max', prefixText: '$_currency '),
                            onChanged: (val) {
                              _maxAmount = double.tryParse(val);
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: _selectedDateRange,
                          builder: (ctx, child) => Theme(
                            data: Theme.of(ctx).copyWith(
                              colorScheme: const ColorScheme.light(primary: _primaryGreen),
                            ),
                            child: child!,
                          ),
                        );
                        if (range != null) {
                          setSheetState(() => _selectedDateRange = range);
                          setState(() {});
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : const Color(0xFFF7FAF9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedDateRange == null
                                  ? 'All time'
                                  : '${_selectedDateRange!.start.day}/${_selectedDateRange!.start.month} - ${_selectedDateRange!.end.day}/${_selectedDateRange!.end.month}',
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            ),
                            const Icon(Icons.calendar_month_rounded, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          HapticFeedback.lightImpact();
                        },
                        child: const Text('Apply Filters'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── CATEGORY FILTER ───────────────────────────────────────────────────
  Widget _buildCategoryFilter() {
    final chips = ['All', ..._categories.map((c) => c['name'] as String)];

    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        itemCount: chips.length,
        itemBuilder: (_, i) {
          final label = chips[i];
          final selected = _selectedCategory == label;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _primaryGreen : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? _primaryGreen : Colors.grey.shade300,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── LIST ──────────────────────────────────────────────────────────────
  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator(color: _primaryGreen));
  }

  Widget _buildList() {
    final grouped = _grouped;

    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 52,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'No expenses found',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
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
        itemCount: grouped.length,
        itemBuilder: (_, i) {
          final groupLabel = grouped.keys.elementAt(i);
          final items = grouped[groupLabel]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 10),
                child: Text(
                  groupLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              ...items.map((e) => _buildExpenseRow(e)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExpenseRow(Map<String, dynamic> e) {
    final cat = e['categories'];
    final colour = _parseColour(cat?['colour']);
    final String name =
        (e['description'] != null && e['description'].toString().isNotEmpty)
        ? e['description']
        : (cat?['name'] ?? 'Expense');
    final double amount = (e['amount'] as num).toDouble();

    return GestureDetector(
      onTap: () => _showEditExpense(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
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
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colour.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_categoryIcon(cat?['icon']), color: colour, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _timeAndCat(e),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            Text(
              '-$_currency ${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit expense ──────────────────────────────────────────────────────
  void _showEditExpense(Map<String, dynamic> expense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(
        categories: _categories,
        onSaved: _loadData,
        existing: expense,
        onDelete: () => _deleteExpenseWithConfirm(expense),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ADD / EDIT EXPENSE BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _AddExpenseSheet extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final VoidCallback onSaved;
  final Map<String, dynamic>? existing;
  final VoidCallback? onDelete;

  const _AddExpenseSheet({
    required this.categories,
    required this.onSaved,
    this.existing,
    this.onDelete,
  });

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  static const Color _primaryGreen = Color(0xFF1A5C4A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get _sheetBg => _isDark ? const Color(0xFF16213E) : Colors.white;
  Color get _labelColor => _isDark ? Colors.grey.shade300 : const Color(0xFF333333);
  Color get _fieldFillColor => _isDark ? Colors.white10 : const Color(0xFFF7FAF9);
  Color get _borderColor => _isDark ? Colors.white12 : Colors.grey.shade200;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _supabase = Supabase.instance.client;

  String? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  bool _saving = false;
  String _currency = 'RM';

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final e = widget.existing!;
      _amountController.text = (e['amount'] as num).toStringAsFixed(2);
      _descController.text = e['description'] ?? '';
      _selectedCategoryId = e['category_id'];
      if (e['expense_date'] != null) {
        _selectedDate =
            DateTime.tryParse(e['expense_date'])?.toLocal() ?? DateTime.now();
      }
    }

    

    _descController.addListener(_onDescChanged);
    _loadCurrency();
  }

  Future<void> _loadCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currency = prefs.getString('currency') ?? 'RM';
      });
    }
  }

  void _onDescChanged() {
    final text = _descController.text.toLowerCase();
    String? matchedCatId;

    if (text.contains('kfc') ||
        text.contains('mcd') ||
        text.contains('starbucks') ||
        text.contains('food') ||
        text.contains('coffee') ||
        text.contains('lunch') ||
        text.contains('dinner')) {
      matchedCatId = _findCategoryByName('food');
    } else if (text.contains('grab') ||
        text.contains('taxi') ||
        text.contains('bus') ||
        text.contains('train') ||
        text.contains('ride')) {
      matchedCatId = _findCategoryByName('transport');
    } else if (text.contains('movie') ||
        text.contains('cinema') ||
        text.contains('netflix')) {
      matchedCatId = _findCategoryByName('entertainment');
    } else if (text.contains('bill') ||
        text.contains('electric') ||
        text.contains('water') ||
        text.contains('wifi')) {
      matchedCatId = _findCategoryByName('bills');
    }

    if (matchedCatId != null && _selectedCategoryId != matchedCatId) {
      setState(() {
        _selectedCategoryId = matchedCatId;
      });
    }
  }

  String? _findCategoryByName(String name) {
    try {
      return widget.categories.firstWhere(
        (c) => c['name'].toString().toLowerCase().contains(name),
      )['category_id'];
    } catch (_) {
      return null;
    }
  }

  /// Real receipt scanner using Google ML Kit on-device OCR
  Future<void> _scanReceipt() async {
    HapticFeedback.lightImpact();

    // 1. Pick image from camera
    final picker = ImagePicker();
    XFile? photo;
    try {
      photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    if (photo == null) return; // user cancelled

    // 2. Show scanning progress
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 12),
              CircularProgressIndicator(color: _primaryGreen),
              SizedBox(height: 20),
              Text('Scanning receipt...', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('Reading text from image...', style: TextStyle(fontSize: 12, color: Colors.grey)),
              SizedBox(height: 12),
            ],
          ),
        ),
      );
    }

    try {
      // 3. Run ML Kit OCR
      final inputImage = InputImage.fromFilePath(photo.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognized = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      if (!mounted) return;
      Navigator.pop(context); // close progress dialog

      final fullText = recognized.text;

      if (fullText.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No text found on receipt. Try a clearer photo.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // 4. Parse total amount from receipt text
      double? amount = _parseReceiptTotal(fullText);
      String? storeName = _parseStoreName(fullText);

      if (amount == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find total amount. Please enter manually.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // 5. Auto-fill the form
      setState(() {
        _amountController.text = amount.toStringAsFixed(2);
        if (storeName != null && storeName.isNotEmpty) {
          _descController.text = storeName;
        }
      });

      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Receipt scanned! Total $_currency ${amount.toStringAsFixed(2)} auto-filled.'),
          backgroundColor: _primaryGreen,
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close progress dialog if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Parse the total/grand total amount from receipt OCR text.
  /// Looks for keywords like TOTAL, GRAND TOTAL, JUMLAH, AMOUNT DUE
  double? _parseReceiptTotal(String text) {
    final lines = text.split('\n');

    // Priority keywords to look for (highest to lowest priority)
    final priorityPatterns = [
      RegExp(r'grand\s*total', caseSensitive: false),
      RegExp(r'total\s*amount', caseSensitive: false),
      RegExp(r'amount\s*due', caseSensitive: false),
      RegExp(r'jumlah\s*besar', caseSensitive: false),  // Malay: grand total
      RegExp(r'jumlah\s*keseluruhan', caseSensitive: false),
      RegExp(r'\btotal\b', caseSensitive: false),
      RegExp(r'\bjumlah\b', caseSensitive: false),       // Malay: total
      RegExp(r'amount\s*payable', caseSensitive: false),
      RegExp(r'\bpayable\b', caseSensitive: false),
      RegExp(r'\bsubtotal\b', caseSensitive: false),
    ];

    // Number pattern: optional RM/MYR prefix, digits, decimal
    final numPattern = RegExp(r'(?:rm|myr)?\s*(\d+\.\d{2})', caseSensitive: false);

    for (final pattern in priorityPatterns) {
      for (final line in lines) {
        if (pattern.hasMatch(line)) {
          final numMatch = numPattern.firstMatch(line);
          if (numMatch != null) {
            return double.tryParse(numMatch.group(1)!);
          }
          // Number might be on the next line
          final idx = lines.indexOf(line);
          if (idx + 1 < lines.length) {
            final nextMatch = numPattern.firstMatch(lines[idx + 1]);
            if (nextMatch != null) {
              return double.tryParse(nextMatch.group(1)!);
            }
          }
        }
      }
    }

    // Fallback: find the largest number on any line (likely the total)
    double? largest;
    for (final line in lines) {
      for (final m in numPattern.allMatches(line)) {
        final val = double.tryParse(m.group(1)!);
        if (val != null && (largest == null || val > largest)) {
          largest = val;
        }
      }
    }
    return largest;
  }

  /// Try to extract a store/merchant name from the top lines of the receipt
  String? _parseStoreName(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Skip very short lines and lines that are numbers/dates at the top
    for (final line in lines.take(5)) {
      if (line.length > 3 &&
          !RegExp(r'^[\d\s\-\/:.]+$').hasMatch(line) &&
          !RegExp(r'^(no|ref|inv|receipt|tel|fax|gst|sst)', caseSensitive: false).hasMatch(line)) {
        return _toTitleCase(line);
      }
    }
    return null;
  }

  String _toTitleCase(String s) {
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  @override
  void dispose() {
    _descController.removeListener(_onDescChanged);
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _primaryGreen),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
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
      
      widget.onSaved();
      
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

    setState(() => _saving = true);
    try {
      // 1. Try to insert it into Supabase categories table
      final newCat = await _supabase.from('categories').insert({
        'name': name,
        'icon': 'category_rounded',
        'colour': '#2E9B78',
      }).select().single();
      
      widget.onSaved(); // trigger parent update
      
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
      
      widget.onSaved();
      
      setState(() {
        _selectedCategoryId = localCatId;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Category "$name" added locally!'),
          backgroundColor: _primaryGreen,
        ),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
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

    setState(() => _saving = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      
      String categoryIdToSave = _selectedCategoryId!;
      String descriptionToSave = _descController.text.trim();

      if (categoryIdToSave.startsWith('custom_')) {
        final cat = widget.categories.firstWhere((c) => c['category_id'] == categoryIdToSave);
        final customCatName = cat['name'];
        descriptionToSave = '[$customCatName] $descriptionToSave';
        
        final defaultDbCat = widget.categories.firstWhere((c) => !c['category_id'].toString().startsWith('custom_'));
        categoryIdToSave = defaultDbCat['category_id'];
      }

      final data = {
        'user_id': userId,
        'category_id': categoryIdToSave,
        'amount': double.parse(_amountController.text),
        'description': descriptionToSave,
        'expense_date': _selectedDate.toIso8601String(),
      };

      if (_isEditing) {
        await _supabase
            .from('expenses')
            .update(data)
            .eq('expense_id', widget.existing!['expense_id']);
      } else {
        await _supabase.from('expenses').insert(data);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Expense updated!' : 'Expense added!'),
            backgroundColor: _primaryGreen,
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
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showDeleteConfirmation() {
    final name =
        (widget.existing?['description'] != null &&
            widget.existing!['description'].toString().isNotEmpty)
        ? widget.existing!['description']
        : (widget.existing?['categories']?['name'] ?? 'Expense');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete expense?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A5C4A),
          ),
        ),
        content: Text('Are you sure you want to delete "$name"?'),
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

  String _formatDate(DateTime dt) {
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
                    _isEditing ? 'Edit Expense' : 'Add Expense',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _isDark ? Colors.white : const Color(0xFF1A5C4A),
                    ),
                  ),
                  if (!_isEditing)
                    TextButton.icon(
                      onPressed: _scanReceipt,
                      icon: Icon(Icons.qr_code_scanner_rounded, color: _isDark ? Colors.tealAccent.shade400 : _primaryGreen, size: 18),
                      label: Text(
                        'Scan Receipt',
                        style: TextStyle(
                          color: _isDark ? Colors.tealAccent.shade400 : _primaryGreen,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
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
              const SizedBox(height: 24),

              // Amount
              _label('Amount (RM)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _inputDec(
                  hint: '0.00',
                  icon: Icons.attach_money_rounded,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter amount';
                  if (double.tryParse(v) == null) return 'Enter a valid number';
                  if (double.parse(v) <= 0) {
                    return 'Amount must be greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description
              _label('Description (optional)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descController,
                decoration: _inputDec(
                  hint: 'e.g. KFC Jurong East',
                  icon: Icons.notes_rounded,
                ),
              ),
              const SizedBox(height: 16),

              // Category
              _label('Category'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...widget.categories.map((cat) {
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

              // Date
              _label('Date'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _fieldFillColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        color: Colors.grey.shade400,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatDate(_selectedDate),
                        style: TextStyle(
                          fontSize: 14,
                          color: _textColor,
                        ),
                      ),
                    ],
                  ),
                ),
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
                          _isEditing ? 'Update Expense' : 'Save Expense',
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
