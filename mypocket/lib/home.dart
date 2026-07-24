// home.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'Login.dart';
import 'expenses.dart';
import 'budgets.dart';
import 'reports.dart';
import 'settings.dart';
import 'savings.dart';
import 'recurring.dart';
import 'ai_chat.dart';
import 'premium.dart';
import 'subscription_service.dart';
import 'notification_service.dart';
import 'widgets/glassmorphism.dart';
import 'widgets/animated_button.dart';
import 'theme.dart';
import 'tour_service.dart';
import 'tour_overlay.dart';

class HomeScreen extends StatefulWidget {
  final Function(bool) onThemeToggle;
  final bool isDarkMode;

  const HomeScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDarkMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  late PageController _pageController;
  StreamSubscription? _notificationSubscription;

  // Global keys for the guided tour
  final GlobalKey _totalSpentCardKey = GlobalKey();
  final GlobalKey _budgetOverviewKey = GlobalKey();
  final GlobalKey _notificationBellKey = GlobalKey();
  final GlobalKey _expensesTabKey = GlobalKey();
  final GlobalKey _budgetsTabKey = GlobalKey();
  final GlobalKey _reportsTabKey = GlobalKey();
  final GlobalKey _settingsTabKey = GlobalKey();

  OverlayEntry? _tourOverlayEntry;

  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _accentGreen = Color(0xFF2E9B78);
  static const Color _lightBg = Color(0xFFEAF4F0);

  final _supabase = Supabase.instance.client;

  // ── State ────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _isPremium = false;
  String _userName = '';
  double _totalSpent = 0;
  double _totalBudget = 0;
  double _todaySpent = 0;
  double _weekSpent = 0;
  int _transactionCount = 0;
  String _currency = 'RM';
  String? _avatarPath;
  String _studentType = 'School';
  double _dailyAllowanceLimit = 20.0;
  DateTime? _nextFundingDate;
  double _monthlyStipendAmount = 0.0;
  List<Map<String, dynamic>> _budgets = [];
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _savingsGoals = [];
  bool _uniFundingEnabled = false;
  
  // Custom Uni/Postgrad trackers
  String _uniSavingsGoalName = 'Laptop Fund';
  double _uniSavingsTarget = 3000.0;
  double _uniSavingsSaved = 1200.0;
  double _uniHourlyRate = 10.0;
  double _uniHoursWorked = 0.0;
  
  String _postgradThesisProject = 'Thesis & Lab Research';
  double _postgradThesisBudget = 1500.0;
  double _postgradThesisSpent = 450.0;

  // Over-budget categories for notification bell
  List<String> get _overBudgetCategories => _budgets
      .where((b) => (b['spent'] as double) > (b['limit'] as double))
      .map((b) => b['label'] as String)
      .toList();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedTab);
    _loadAll();
    _setupNotificationListener();
  }

  @override
  void dispose() {
    _removeTourOverlay();
    _pageController.dispose();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _setupNotificationListener() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Listen to real-time custom notifications for the current user
    _notificationSubscription = _supabase
        .from('custom_notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((List<Map<String, dynamic>> data) async {
          if (data.isNotEmpty) {
            for (final notif in data) {
              final isRead = notif['read'] == true;
              if (isRead) continue;

              final notifId = notif['id'].toString();
              final title = notif['title'] ?? 'MyPocket Notification';
              final body = notif['body'] ?? '';

              // Trigger actual system notification on the device
              await NotificationService.instance.showNotification(
                id: notifId.hashCode,
                title: title,
                body: body,
              );

              // Mark as read in Supabase so it won't display again
              try {
                await _supabase
                    .from('custom_notifications')
                    .update({'read': true})
                    .eq('id', notif['id']);
              } catch (e) {
                debugPrint('Error marking notification as read: $e');
              }
            }
          }
        });

    // Listen to real-time support chat replies
    _supabase.channel('public:support_messages').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'support_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord['is_from_admin'] == true) {
          NotificationService.instance.showNotification(
            id: newRecord['id'].hashCode,
            title: 'Support Reply',
            body: newRecord['content'] ?? 'You have a new message from Support.',
          );
        }
      },
    ).subscribe();
  }

  // ── Data loading ─────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final isPremium = await SubscriptionService.instance.checkPremiumStatus();
      if (mounted) {
        setState(() {
          _isPremium = isPremium;
        });
      }
      await Future.wait([
        _loadUser(),
        _loadSummary(),
        _loadBudgets(),
        _loadTransactions(),
        _loadCurrency(),
        _loadAvatar(),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await _checkAndShowWeeklyReport(prefs);
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
      if (mounted) {
        setState(() => _loading = false);
        // Wait for the home screen to fully paint itself before showing the tour.
        // Without this delay, the tour overlay appears on top of the loading/shimmer screen
        // causing the "white screen" bug. 1.5 seconds gives enough time for the full
        // home screen layout to render and all widget keys to be attached.
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _checkAndShowTour();
          }
        });
      }
    }
  }

  Future<void> _refreshData() async {
    try {
      final isPremium = await SubscriptionService.instance.checkPremiumStatus();
      if (mounted) {
        setState(() {
          _isPremium = isPremium;
        });
      }
      await Future.wait([
        _loadUser(),
        _loadSummary(),
        _loadBudgets(),
        _loadTransactions(),
        _loadCurrency(),
        _loadAvatar(),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await _checkAndShowWeeklyReport(prefs);
    } catch (_) {}
  }

  Future<void> _loadCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currency = prefs.getString('currency') ?? 'RM';
      });
    }
  }

  Future<void> _loadAvatar() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      try {
        final res = await _supabase
            .from('users')
            .select('avatar_base64')
            .eq('user_id', userId)
            .maybeSingle();
        if (res != null && res['avatar_base64'] != null) {
          if (mounted) {
            setState(() {
              _avatarPath = res['avatar_base64'];
            });
          }
          return;
        }
      } catch (e) {
        // Fallback
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _avatarPath = prefs.getString('profile_image_path');
      });
    }
  }

  Future<void> _changeProfilePicture() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = widget.isDarkMode;
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
                  'Profile Photo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : _primaryGreen,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_rounded,
                    color: _primaryGreen,
                  ),
                  title: Text(
                    'Choose from Gallery',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (image != null) {
                      final bytes = await image.readAsBytes();
                      final base64String = base64Encode(bytes);
                      final dataUrl = 'data:image/png;base64,$base64String';

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('profile_image_path', dataUrl);

                      final userId = _supabase.auth.currentUser?.id;
                      if (userId != null) {
                        try {
                          await _supabase
                              .from('users')
                              .update({'avatar_base64': dataUrl})
                              .eq('user_id', userId);
                        } catch (e) {
                          // ignore
                        }
                      }

                      setState(() {
                        _avatarPath = dataUrl;
                      });
                      HapticFeedback.mediumImpact();
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt_rounded,
                    color: _primaryGreen,
                  ),
                  title: Text(
                    'Take Photo',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.camera,
                    );
                    if (image != null) {
                      final bytes = await image.readAsBytes();
                      final base64String = base64Encode(bytes);
                      final dataUrl = 'data:image/png;base64,$base64String';

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('profile_image_path', dataUrl);

                      final userId = _supabase.auth.currentUser?.id;
                      if (userId != null) {
                        try {
                          await _supabase
                              .from('users')
                              .update({'avatar_base64': dataUrl})
                              .eq('user_id', userId);
                        } catch (e) {
                          // ignore
                        }
                      }

                      setState(() {
                        _avatarPath = dataUrl;
                      });
                      HapticFeedback.mediumImpact();
                    }
                  },
                ),
                if (_avatarPath != null)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_rounded,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      'Remove Photo',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('profile_image_path');

                      final userId = _supabase.auth.currentUser?.id;
                      if (userId != null) {
                        try {
                          await _supabase
                              .from('users')
                              .update({'avatar_base64': null})
                              .eq('user_id', userId);
                        } catch (e) {
                          // ignore
                        }
                      }

                      setState(() {
                        _avatarPath = null;
                      });
                      HapticFeedback.mediumImpact();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadUser() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    var res = await _supabase
        .from('users')
        .select(
          'name, student_type, daily_allowance_limit, next_funding_date, monthly_stipend_amount',
        )
        .eq('user_id', userId)
        .maybeSingle();

    // If no profile was found by user_id, check if it was created manually by an admin via email
    if (res == null) {
      final email = _supabase.auth.currentUser?.email;
      if (email != null) {
        final emailRes = await _supabase
            .from('users')
            .select(
              'name, student_type, daily_allowance_limit, next_funding_date, monthly_stipend_amount',
            )
            .eq('email', email)
            .maybeSingle();
            
        if (emailRes != null) {
          res = emailRes;
          // Silently fix the database linkage for future queries
          try {
            await _supabase.from('users').update({'user_id': userId}).eq('email', email);
          } catch (_) {}
        }
      }
    }

    // Google/OAuth fallback creation: if still null, build their profile row now
    if (res == null) {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        try {
          final String fullName = user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? 'Google User';
          final newProfile = {
            'user_id': user.id,
            'name': fullName,
            'email': user.email,
            'student_type': 'School',
            'daily_allowance_limit': 20.0,
            'monthly_stipend_amount': 0.0,
          };
          await _supabase.from('users').insert(newProfile);
          res = newProfile;
        } catch (_) {}
      }
    }

    if (res != null && mounted) {
      final safeRes = res;
      setState(() {
        _userName = safeRes['name'] ?? '';
        _studentType = safeRes['student_type'] ?? 'School';
        _dailyAllowanceLimit =
            double.tryParse(safeRes['daily_allowance_limit']?.toString() ?? '') ??
            20.0;
        if (safeRes['next_funding_date'] != null) {
          _nextFundingDate = DateTime.tryParse(safeRes['next_funding_date']);
        }
 else {
          _nextFundingDate = null;
        }
        _monthlyStipendAmount =
            double.tryParse(safeRes['monthly_stipend_amount']?.toString() ?? '') ??
            0.0;
      });
      
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _uniFundingEnabled = prefs.getBool('uni_funding_enabled') ?? false;
          _uniHourlyRate = prefs.getDouble('uni_hourly_rate') ?? 10.0;
          _uniHoursWorked = prefs.getDouble('uni_hours_worked') ?? 0.0;
          
          _uniSavingsGoalName = prefs.getString('uni_savings_name') ?? 'Laptop Fund';
          _uniSavingsTarget = prefs.getDouble('uni_savings_target') ?? 3000.0;
          _uniSavingsSaved = prefs.getDouble('uni_savings_saved') ?? 1200.0;
          
          _postgradThesisProject = prefs.getString('postgrad_thesis_project') ?? 'Thesis & Lab Research';
          _postgradThesisBudget = prefs.getDouble('postgrad_thesis_budget') ?? 1500.0;
          _postgradThesisSpent = prefs.getDouble('postgrad_thesis_spent') ?? 450.0;
        });
      }
    }
    if (_userName.isEmpty) {
      final meta = _supabase.auth.currentUser?.userMetadata;
      _userName =
          meta?['name'] ??
          _supabase.auth.currentUser?.email?.split('@').first ??
          'User';
    }
  }

  Future<void> _loadSummary() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final monthEnd = DateTime(
      now.year,
      now.month + 1,
      0,
      23,
      59,
      59,
    ).toIso8601String();

    final expensesRes = await _supabase
        .from('expenses')
        .select('amount, expense_date')
        .eq('user_id', userId)
        .gte('expense_date', monthStart)
        .lte('expense_date', monthEnd);

    double spent = 0;
    double todaySpentVal = 0;
    double weekSpentVal = 0;

    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 7));

    for (final e in expensesRes as List) {
      final amt = (e['amount'] as num).toDouble();
      spent += amt;

      final dateStr = e['expense_date'] as String?;
      if (dateStr != null) {
        final expDate = DateTime.tryParse(dateStr)?.toLocal();
        if (expDate != null) {
          if (expDate.isAfter(todayStart)) {
            todaySpentVal += amt;
          }
          if (expDate.isAfter(weekStart)) {
            weekSpentVal += amt;
          }
        }
      }
    }

    final budgetsRes = await _supabase
        .from('budgets')
        .select('budget_limit')
        .eq('user_id', userId)
        .eq('month', now.month)
        .eq('year', now.year);

    double budget = 0;
    for (final b in budgetsRes as List) {
      budget += (b['budget_limit'] as num).toDouble();
    }

    List<Map<String, dynamic>> goalsList = [];
    try {
      final goalsRes = await _supabase
          .from('savings_goals')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);
      goalsList = List<Map<String, dynamic>>.from(goalsRes);
    } catch (e) {
      // ignore
    }

    if (mounted) {
      setState(() {
        _totalSpent = spent;
        _totalBudget = budget;
        _todaySpent = todaySpentVal;
        _weekSpent = weekSpentVal;
        _transactionCount = (expensesRes as List).length;
        _savingsGoals = goalsList;
      });
    }
  }

  Future<void> _loadBudgets() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final monthEnd = DateTime(
      now.year,
      now.month + 1,
      0,
      23,
      59,
      59,
    ).toIso8601String();

    final budgetsRes = await _supabase
        .from('budgets')
        .select(
          'budget_id, budget_limit, category_id, categories(name, icon, colour)',
        )
        .eq('user_id', userId)
        .eq('month', now.month)
        .eq('year', now.year);

    final prefs = await SharedPreferences.getInstance();
    
    // Load custom categories
    final customCatsRaw = prefs.getString('custom_categories');
    List<Map<String, dynamic>> customCats = [];
    if (customCatsRaw != null) {
      customCats = List<Map<String, dynamic>>.from(jsonDecode(customCatsRaw));
    }
    
    // Load local custom budgets
    final customBudgetsRaw = prefs.getString('custom_budgets');
    List<Map<String, dynamic>> customBudgets = [];
    if (customBudgetsRaw != null) {
      final allCustomBudgets = List<Map<String, dynamic>>.from(jsonDecode(customBudgetsRaw));
      customBudgets = allCustomBudgets.where((b) => 
        b['user_id'] == userId && 
        b['month'] == now.month && 
        b['year'] == now.year
      ).toList();
    }

    // Load all expenses for current month
    final expensesRes = await _supabase
        .from('expenses')
        .select('amount, description, category_id')
        .eq('user_id', userId)
        .gte('expense_date', monthStart)
        .lte('expense_date', monthEnd);

    // Group expenses by category_id (handling custom categories embedded in description)
    final Map<String, double> categorySpent = {};
    for (final e in expensesRes as List) {
      final double amt = (e['amount'] as num).toDouble();
      String catId = e['category_id'];
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
      
      categorySpent[catId] = (categorySpent[catId] ?? 0.0) + amt;
    }

    List<Map<String, dynamic>> result = [];
    
    // 1. Process database budgets
    for (final b in budgetsRes as List) {
      final catId = b['category_id'];
      final double spent = categorySpent[catId] ?? 0.0;
      final cat = b['categories'];
      final catName = cat?['name'] ?? 'Category';
      final limit = (b['budget_limit'] as num).toDouble();

      final bool notifBudgetAlert = prefs.getBool('notif_budget_alert') ?? true;
      final bool notifOverLimit = prefs.getBool('notif_over_limit') ?? true;

      if (notifOverLimit && spent > limit) {
        final lastNotifiedStr = prefs.getString('last_notified_$catName');
        bool shouldNotify = false;
        if (lastNotifiedStr == null) {
          shouldNotify = true;
        } else {
          final lastNotified = DateTime.tryParse(lastNotifiedStr);
          if (lastNotified == null || DateTime.now().difference(lastNotified).inHours >= 4) {
            shouldNotify = true;
          }
        }

        if (shouldNotify) {
          await prefs.setString('last_notified_$catName', DateTime.now().toIso8601String());
          NotificationService.instance.showNotification(
            id: catName.hashCode,
            title: 'Budget Exceeded! ⚠️',
            body: 'You have gone over your $catName budget limit of $_currency ${limit.toStringAsFixed(0)}.',
          );
        }
      } else {
        await prefs.remove('last_notified_$catName');
      }

      if (notifBudgetAlert && spent > (limit * 0.8) && spent <= limit) {
        final lastNearingNotifiedStr = prefs.getString('last_nearing_notified_$catName');
        bool shouldNearingNotify = false;
        if (lastNearingNotifiedStr == null) {
          shouldNearingNotify = true;
        } else {
          final lastNotified = DateTime.tryParse(lastNearingNotifiedStr);
          if (lastNotified == null || DateTime.now().difference(lastNotified).inHours >= 4) {
            shouldNearingNotify = true;
          }
        }

        if (shouldNearingNotify) {
          await prefs.setString('last_nearing_notified_$catName', DateTime.now().toIso8601String());
          NotificationService.instance.showNotification(
            id: (catName + '_nearing').hashCode,
            title: 'Budget Alert! ⚠️',
            body: 'You have spent over 80% of your $catName budget limit ($_currency ${spent.toStringAsFixed(0)} / $_currency ${limit.toStringAsFixed(0)}).',
          );
        }
      } else {
        await prefs.remove('last_nearing_notified_$catName');
      }

      result.add({
        'label': catName,
        'icon': cat?['icon'] ?? 'other',
        'colour': cat?['colour'] ?? '#1A5C4A',
        'spent': spent,
        'limit': limit,
      });
    }

    // 2. Process local custom budgets
    for (final b in customBudgets) {
      final catId = b['category_id'];
      final double spent = categorySpent[catId] ?? 0.0;
      final cat = b['categories'];
      final catName = cat?['name'] ?? 'Category';
      final limit = (b['budget_limit'] as num).toDouble();

      final bool notifBudgetAlert = prefs.getBool('notif_budget_alert') ?? true;
      final bool notifOverLimit = prefs.getBool('notif_over_limit') ?? true;

      if (notifOverLimit && spent > limit) {
        final lastNotifiedStr = prefs.getString('last_notified_$catName');
        bool shouldNotify = false;
        if (lastNotifiedStr == null) {
          shouldNotify = true;
        } else {
          final lastNotified = DateTime.tryParse(lastNotifiedStr);
          if (lastNotified == null || DateTime.now().difference(lastNotified).inHours >= 4) {
            shouldNotify = true;
          }
        }

        if (shouldNotify) {
          await prefs.setString('last_notified_$catName', DateTime.now().toIso8601String());
          NotificationService.instance.showNotification(
            id: catName.hashCode,
            title: 'Budget Exceeded! ⚠️',
            body: 'You have gone over your $catName budget limit of $_currency ${limit.toStringAsFixed(0)}.',
          );
        }
      } else {
        await prefs.remove('last_notified_$catName');
      }

      if (notifBudgetAlert && spent > (limit * 0.8) && spent <= limit) {
        final lastNearingNotifiedStr = prefs.getString('last_nearing_notified_$catName');
        bool shouldNearingNotify = false;
        if (lastNearingNotifiedStr == null) {
          shouldNearingNotify = true;
        } else {
          final lastNotified = DateTime.tryParse(lastNearingNotifiedStr);
          if (lastNotified == null || DateTime.now().difference(lastNotified).inHours >= 4) {
            shouldNearingNotify = true;
          }
        }

        if (shouldNearingNotify) {
          await prefs.setString('last_nearing_notified_$catName', DateTime.now().toIso8601String());
          NotificationService.instance.showNotification(
            id: (catName + '_nearing').hashCode,
            title: 'Budget Alert! ⚠️',
            body: 'You have spent over 80% of your $catName budget limit ($_currency ${spent.toStringAsFixed(0)} / $_currency ${limit.toStringAsFixed(0)}).',
          );
        }
      } else {
        await prefs.remove('last_nearing_notified_$catName');
      }

      result.add({
        'label': catName,
        'icon': cat?['icon'] ?? 'other',
        'colour': cat?['colour'] ?? '#1A5C4A',
        'spent': spent,
        'limit': limit,
      });
    }

    if (mounted) setState(() => _budgets = result);
  }

  Future<void> _checkAndShowWeeklyReport(SharedPreferences prefs) async {
    final bool notifWeekly = prefs.getBool('notif_weekly_report') ?? false;
    if (!notifWeekly) return;

    final lastWeeklyStr = prefs.getString('last_weekly_report_sent');
    bool shouldSend = false;
    DateTime now = DateTime.now();

    if (lastWeeklyStr == null) {
      await prefs.setString('last_weekly_report_sent', now.toIso8601String());
      return;
    } else {
      final lastWeekly = DateTime.tryParse(lastWeeklyStr);
      if (lastWeekly == null || now.difference(lastWeekly).inDays >= 7) {
        shouldSend = true;
      }
    }

    if (shouldSend) {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final sevenDaysAgo = now.subtract(const Duration(days: 7)).toIso8601String();
      try {
        final res = await _supabase
            .from('expenses')
            .select('amount')
            .eq('user_id', userId)
            .gte('expense_date', sevenDaysAgo);

        double totalSpent = 0.0;
        for (final e in res as List) {
          totalSpent += (e['amount'] as num).toDouble();
        }

        await prefs.setString('last_weekly_report_sent', now.toIso8601String());

        NotificationService.instance.showNotification(
          id: 999999,
          title: 'Weekly Spending Summary 📊',
          body: 'You spent a total of $_currency ${totalSpent.toStringAsFixed(2)} in the last 7 days.',
        );
      } catch (_) {}
    }
  }

  Future<void> _loadTransactions() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final res = await _supabase
        .from('expenses')
        .select(
          'expense_id, amount, description, expense_date, categories(name, icon, colour)',
        )
        .eq('user_id', userId)
        .order('expense_date', ascending: false)
        .limit(5);

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
      }
      processed.add(item);
    }

    if (mounted) {
      setState(
        () => _transactions = processed,
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _formatDate(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return 'Today, $h:$m $ampm';
    }
    return '${dt.day} ${_monthName(dt.month)}';
  }

  String _monthName(int m) {
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
    return months[m - 1];
  }

  Color _parseColour(String? hex) {
    try {
      if (hex == null || hex.isEmpty) return _primaryGreen;
      final cleaned = hex.replaceAll('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
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
      case 'salary':
      case 'income':
        return Icons.account_balance_wallet_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Future<void> _openAIChat() async {
    HapticFeedback.lightImpact();
    final isPremium = await SubscriptionService.instance.checkPremiumStatus();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isPremium
            ? AIChatScreen(isDarkMode: widget.isDarkMode)
            : PremiumScreen(
                onPremiumActivated: () {
                  setState(() {});
                },
              ),
      ),
    );
  }

  void _showNotifications() {
    final overList = _overBudgetCategories;
    final isDark = widget.isDarkMode;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
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
                'Notifications',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A5C4A),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (overList.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 48,
                                  color: Colors.green.shade300,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'All budgets are on track!',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...overList.map(
                          (cat) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.warning_rounded,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Budget exceeded: $cat',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.redAccent,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'You have gone over your $cat budget this month.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.9)
                                              : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── FIXED: Sign Out with parameters ────────────────────────────────────
  Future<void> _signOut() async {
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            onThemeToggle: widget.onThemeToggle,
            isDarkMode: widget.isDarkMode,
          ),
        ),
        (route) => false,
      );
    }
  }

  // ── TOUR OVERLAY METHODS ────────────────────────────────────────────────
  Future<void> _checkAndShowTour() async {
    final completed = await TourService.isTourCompleted();
    if (!completed && mounted) {
      _showTourOverlay();
    }
  }

  void _showTourOverlay() {
    if (_tourOverlayEntry != null) return;

    _tourOverlayEntry = OverlayEntry(
      builder: (context) => TourOverlay(
        steps: [
          TourStep(
            targetKey: _totalSpentCardKey,
            title: 'Total Spent Card',
            description: 'This shows your total spending this month at a glance.',
            icon: Icons.account_balance_wallet_rounded,
          ),
          TourStep(
            targetKey: _budgetOverviewKey,
            title: 'Budget Overview',
            description: 'Track how much you\'ve spent per category vs your budget limit.',
            icon: Icons.pie_chart_rounded,
          ),
          TourStep(
            targetKey: _notificationBellKey,
            title: 'Notification Bell',
            description: 'Tap here to see alerts when you exceed a budget.',
            borderRadius: 24,
            icon: Icons.notifications_rounded,
          ),
          TourStep(
            targetKey: _expensesTabKey,
            title: 'Expenses Tab',
            description: 'Log and manage all your daily expenses here.',
            icon: Icons.receipt_long_rounded,
          ),
          TourStep(
            targetKey: _budgetsTabKey,
            title: 'Budgets Tab',
            description: 'Set monthly spending limits for each category.',
            icon: Icons.savings_rounded,
          ),
          TourStep(
            targetKey: _reportsTabKey,
            title: 'Reports Tab',
            description: 'View charts and breakdowns of your spending.',
            icon: Icons.bar_chart_rounded,
          ),
          TourStep(
            targetKey: _settingsTabKey,
            title: 'Settings Tab',
            description: 'Edit your profile, change password, and manage preferences.',
            icon: Icons.settings_rounded,
          ),
          TourStep(
            isFullScreen: true,
            title: 'You\'re All Set! 🎉',
            description: 'Start tracking your spending with MyPocket. Good luck!',
          ),
        ],
        onStepChanged: (stepIndex) {
          int targetTab = 0;
          if (stepIndex == 3) targetTab = 1; // Expenses tab
          if (stepIndex == 4) targetTab = 2; // Budgets tab
          if (stepIndex == 5) targetTab = 3; // Reports tab
          if (stepIndex == 6) targetTab = 4; // Settings tab
          if (stepIndex == 7) targetTab = 0; // Home tab for congratulations

          if (_selectedTab != targetTab) {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(targetTab);
            }
            setState(() {
              _selectedTab = targetTab;
            });
          }
        },
        onCompleted: () async {
          _removeTourOverlay();
          await TourService.markTourCompleted();
          if (_selectedTab != 0) {
            _pageController.jumpToPage(0);
            setState(() => _selectedTab = 0);
          }
        },
        onSkipped: () async {
          _removeTourOverlay();
          await TourService.markTourCompleted();
          if (_selectedTab != 0) {
            _pageController.jumpToPage(0);
            setState(() => _selectedTab = 0);
          }
        },
      ),
    );

    Overlay.of(context).insert(_tourOverlayEntry!);
  }

  void _removeTourOverlay() {
    _tourOverlayEntry?.remove();
    _tourOverlayEntry = null;
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : _lightBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics:
                    const NeverScrollableScrollPhysics(), // Prevents swipe conflict with sliders/charts
                children: [
                  _buildHomeTab(),
                  ExpensesScreen(),
                  BudgetsScreen(),
                  ReportsScreen(),
                  SettingsScreen(
                    onThemeToggle: widget.onThemeToggle,
                    isDarkMode: isDark,
                  ),
                ],
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  // ── HOME TAB ──────────────────────────────────────────────────────────
  Widget _buildHomeTab() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _primaryGreen),
      );
    }

    return RefreshIndicator(
      color: _primaryGreen,
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSummaryCard(),
            _buildQuickStats(),
            _buildStudentSpecificWidget(),
            const SizedBox(height: 8),
            _buildSavingsGoalsOverview(),
            const SizedBox(height: 8),
            _buildRecurringOverview(),
            const SizedBox(height: 8),
            _buildBudgetOverview(),
            const SizedBox(height: 24),
            _buildRecentTransactions(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    final isDark = widget.isDarkMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
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
            Text(
              '📊 Quick Stats',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _quickStatItem(
                  'Today',
                  '$_currency ${_todaySpent.toStringAsFixed(2)}',
                  isDark,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
                _quickStatItem(
                  'This Week',
                  '$_currency ${_weekSpent.toStringAsFixed(2)}',
                  isDark,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
                _quickStatItem(
                  'This Month',
                  '$_currency ${_totalSpent.toStringAsFixed(2)}',
                  isDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickStatItem(String label, String value, bool isDark) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  void _showGoalDetails(Map<String, dynamic> goal) {
    final isDark = widget.isDarkMode;
    final double target =
        double.tryParse(goal['target']?.toString() ?? '0') ?? 0.0;
    final double current =
        double.tryParse(goal['current']?.toString() ?? '0') ?? 0.0;
    final double progress = target > 0
        ? (current / target).clamp(0.0, 1.0)
        : 0.0;
    final id = goal['goal_id'] ?? goal['id'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF16213E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
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
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        goal['title'] ?? 'Goal Detail',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A5C4A),
                        ),
                      ),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _accentGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 12,
                      backgroundColor: isDark
                          ? Colors.white10
                          : Colors.grey.shade100,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        _primaryGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Saved: $_currency ${current.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Target: $_currency ${target.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Add Funds Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text(
                        'Add Funds',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        final amountCtrl = TextEditingController();
                        final val = await showDialog<double>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Add Funds'),
                            content: TextField(
                              controller: amountCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Amount (RM)',
                              ),
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(
                                  c,
                                  double.tryParse(amountCtrl.text),
                                ),
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                        );
                        if (val != null && val > 0) {
                          final newCurrent = current + val;
                          final userId = _supabase.auth.currentUser?.id;
                          if (userId != null && id != null) {
                            try {
                              await _supabase
                                  .from('savings_goals')
                                  .update({'current': newCurrent})
                                  .eq('goal_id', id);
                            } catch (e) {}
                          }

                          final box = Hive.box('savings_goals');
                          final hiveGoal = Map<String, dynamic>.from(goal);
                          hiveGoal['current'] = newCurrent;
                          await box.put(
                            goal['id'] ?? goal['goal_id'],
                            hiveGoal,
                          );

                          Navigator.pop(ctx);
                          _loadSummary();
                          HapticFeedback.mediumImpact();
                        }
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Edit & Delete row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blueAccent,
                            side: const BorderSide(color: Colors.blueAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Update'),
                          onPressed: () async {
                            final titleCtrl = TextEditingController(
                              text: goal['title'],
                            );
                            final targetCtrl = TextEditingController(
                              text: target.toString(),
                            );
                            final currentCtrl = TextEditingController(
                              text: current.toString(),
                            );

                            final updated = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Update Goal'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: titleCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Title',
                                      ),
                                    ),
                                    TextField(
                                      controller: targetCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Target Amount',
                                      ),
                                    ),
                                    TextField(
                                      controller: currentCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Current Saved',
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                            );

                            if (updated == true) {
                              final newTitle = titleCtrl.text.trim();
                              final newTarget =
                                  double.tryParse(targetCtrl.text) ?? target;
                              final newCurrent =
                                  double.tryParse(currentCtrl.text) ?? current;

                              final userId = _supabase.auth.currentUser?.id;
                              if (userId != null && id != null) {
                                try {
                                  await _supabase
                                      .from('savings_goals')
                                      .update({
                                        'title': newTitle,
                                        'target': newTarget,
                                        'current': newCurrent,
                                      })
                                      .eq('goal_id', id);
                                } catch (e) {}
                              }

                              final box = Hive.box('savings_goals');
                              final hiveGoal = Map<String, dynamic>.from(goal);
                              hiveGoal['title'] = newTitle;
                              hiveGoal['target'] = newTarget;
                              hiveGoal['current'] = newCurrent;
                              await box.put(
                                goal['id'] ?? goal['goal_id'],
                                hiveGoal,
                              );

                              Navigator.pop(ctx);
                              _loadSummary();
                              HapticFeedback.mediumImpact();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.delete_rounded, size: 18),
                          label: const Text('Delete'),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete Goal'),
                                content: Text(
                                  'Are you sure you want to delete "${goal['title']}"?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                    ),
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              final userId = _supabase.auth.currentUser?.id;
                              if (userId != null && id != null) {
                                try {
                                  await _supabase
                                      .from('savings_goals')
                                      .delete()
                                      .eq('goal_id', id);
                                } catch (e) {}
                              }

                              final box = Hive.box('savings_goals');
                              await box.delete(goal['id'] ?? goal['goal_id']);

                              Navigator.pop(ctx);
                              _loadSummary();
                              HapticFeedback.mediumImpact();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSavingsGoalsOverview() {
    final isDark = widget.isDarkMode;
    if (!_isPremium) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '💰 Savings Goals',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF16213E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.lock_rounded, color: _primaryGreen, size: 36),
                  const SizedBox(height: 12),
                  const Text(
                    'Savings Goals is a Premium Feature',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Upgrade to Premium to track your savings goals and budget effectively.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PremiumScreen()),
                        ).then((_) => _loadAll());
                      },
                      child: const Text(
                        'Upgrade to Premium',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final box = Hive.box('savings_goals');
    final hiveGoals = box.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final goals = _savingsGoals.isNotEmpty ? _savingsGoals : hiveGoals;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '💰 Savings Goals',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SavingsScreen()),
                  ).then((_) => setState(() {}));
                },
                child: const Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 12,
                    color: _accentGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (goals.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF16213E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  'No savings goals set yet.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            )
          else
            ...goals.take(2).map((g) {
              final double target = (g['target'] as num?)?.toDouble() ?? 1.0;
              final double current = (g['current'] as num?)?.toDouble() ?? 0.0;
              final double progress = (current / target).clamp(0.0, 1.0);
              return AnimatedButton(
                onTap: () => _showGoalDetails(g),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF16213E) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            g['title'] ?? 'Goal',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF1A1A1A),
                            ),
                          ),
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _primaryGreen,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: isDark
                              ? Colors.white10
                              : Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            _primaryGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecurringOverview() {
    final isDark = widget.isDarkMode;
    final box = Hive.box('recurring_expenses');
    final subs = box.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final totalCost = subs.fold<double>(
      0.0,
      (sum, item) => sum + (item['amount'] ?? 0.0),
    );

    if (subs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: AnimatedButton(
        onTap: () {
          if (!_isPremium) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Recurring Bills is a Premium feature!'),
              ),
            );
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PremiumScreen()),
            ).then((_) => _loadAll());
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecurringScreen()),
          ).then((_) => setState(() {}));
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF16213E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _accentGreen.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.repeat_rounded,
                  color: _accentGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔁 Recurring Bills',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${subs.length} bills active · Total $_currency ${totalCost.toStringAsFixed(2)}/mo',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _editUniSavingsTracker() {
    final nameCtrl = TextEditingController(text: _uniSavingsGoalName);
    final targetCtrl = TextEditingController(text: _uniSavingsTarget.toStringAsFixed(0));
    final savedCtrl = TextEditingController(text: _uniSavingsSaved.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.savings_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Expanded(child: Text('Custom Savings Goal')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Savings Goal Name',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  hintText: 'e.g. Laptop Fund',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Target Goal (RM)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: targetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '3000',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Current Saved (RM)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: savedCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '1200',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              final newTarget = double.tryParse(targetCtrl.text) ?? 3000.0;
              final newSaved = double.tryParse(savedCtrl.text) ?? 1200.0;

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('uni_savings_name', newName);
              await prefs.setDouble('uni_savings_target', newTarget);
              await prefs.setDouble('uni_savings_saved', newSaved);

              setState(() {
                _uniSavingsGoalName = newName;
                _uniSavingsTarget = newTarget;
                _uniSavingsSaved = newSaved;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editUniJobTracker() {
    final rateCtrl = TextEditingController(text: _uniHourlyRate.toStringAsFixed(2));
    final hoursCtrl = TextEditingController(text: _uniHoursWorked.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
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
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editPostgradThesisTracker() {
    final projCtrl = TextEditingController(text: _postgradThesisProject);
    final budgetCtrl = TextEditingController(text: _postgradThesisBudget.toStringAsFixed(0));
    final spentCtrl = TextEditingController(text: _postgradThesisSpent.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.science_rounded, color: Colors.purpleAccent),
            SizedBox(width: 8),
            Expanded(child: Text('Thesis & Research Tracker')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Research Project',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: projCtrl,
                decoration: const InputDecoration(
                  hintText: 'e.g. Lab Supplies',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Total Grant / Budget (RM)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '1500',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Grant Spent (RM)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: spentCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '450',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryGreen),
            onPressed: () async {
              final newProj = projCtrl.text.trim();
              final newBudget = double.tryParse(budgetCtrl.text) ?? 1500.0;
              final newSpent = double.tryParse(spentCtrl.text) ?? 450.0;

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('postgrad_thesis_project', newProj);
              await prefs.setDouble('postgrad_thesis_budget', newBudget);
              await prefs.setDouble('postgrad_thesis_spent', newSpent);

              setState(() {
                _postgradThesisProject = newProj;
                _postgradThesisBudget = newBudget;
                _postgradThesisSpent = newSpent;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSpecificWidget() {
    final isDark = widget.isDarkMode;
    final cardBg = isDark ? const Color(0xFF16213E) : Colors.white;

    if (_studentType.toLowerCase().contains('school')) {
      // School Student: Daily Allowance Tracker
      final double dailyLimit = _dailyAllowanceLimit;
      final double remaining = (dailyLimit - _todaySpent).clamp(
        0.0,
        dailyLimit,
      );
      final double progress = dailyLimit > 0 ? (remaining / dailyLimit) : 0.0;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _primaryGreen.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🎒 School Pocket Money',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    '$_currency ${remaining.toStringAsFixed(2)} left',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _primaryGreen,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? Colors.white10
                      : Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress < 0.25 ? Colors.redAccent : _primaryGreen,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Daily budget: $_currency ${dailyLimit.toStringAsFixed(2)} · Spent today: $_currency ${_todaySpent.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    } else if (_studentType.toLowerCase().contains('postgrad')) {
      // Postgraduate Student: Thesis & Lab Research Budget Tracker
      final double thesisBudget = _postgradThesisBudget;
      final double thesisSpent = _postgradThesisSpent;
      final double remaining = (thesisBudget - thesisSpent).clamp(0.0, thesisBudget);
      final double progress = thesisBudget > 0 ? (remaining / thesisBudget) : 0.0;
      final double percent = (progress * 100).clamp(0.0, 100.0);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: GestureDetector(
          onTap: _editPostgradThesisTracker,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.purple.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.science_rounded, color: Colors.purple.shade400, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _postgradThesisProject,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      '${percent.toStringAsFixed(0)}% remaining',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: progress < 0.25 ? Colors.redAccent : Colors.purple.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white10 : Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress < 0.25 ? Colors.redAccent : Colors.purple.shade400,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Spent: $_currency ${thesisSpent.toStringAsFixed(2)} / Budget: $_currency ${thesisBudget.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                    const Icon(Icons.edit_note_rounded, size: 16, color: Colors.grey),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // University Student: Semester Savings Goal Tracker & Part-Time Job Tracker
      final List<Widget> widgets = [];
      
      final double target = _uniSavingsTarget;
      final double saved = _uniSavingsSaved;
      final double progress = target > 0 ? (saved / target).clamp(0.0, 1.0) : 0.0;
      final double percent = progress * 100;

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: GestureDetector(
            onTap: _editUniSavingsTracker,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.savings_rounded, color: Colors.blueAccent, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _uniSavingsGoalName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      Text(
                        '${percent.toStringAsFixed(0)}% saved',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: isDark ? Colors.white10 : Colors.grey.shade100,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Saved: $_currency ${saved.toStringAsFixed(2)} / Goal: $_currency ${target.toStringAsFixed(2)}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                      ),
                      const Icon(Icons.edit_note_rounded, size: 16, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (_uniFundingEnabled) {
        final double earnings = _uniHourlyRate * _uniHoursWorked;
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: GestureDetector(
              onTap: _editUniJobTracker,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.work_rounded, color: Colors.amber, size: 18),
                            const SizedBox(width: 6),
                            const Text(
                              '💼 Part-Time Job Earnings',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        Text(
                          '$_currency ${earnings.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Hours worked: ${_uniHoursWorked.toStringAsFixed(1)} hrs @ $_currency ${_uniHourlyRate.toStringAsFixed(2)}/hr',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                        ),
                        const Icon(Icons.edit_note_rounded, size: 16, color: Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: widgets,
      );
    }
  }

  // ── HEADER ────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    _userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('👋', style: TextStyle(fontSize: 20)),
                ],
              ),
            ],
          ),
          Row(
            children: [
              // ── AI Chat Button ──────────────────────────────────────
              GestureDetector(
                onTap: _openAIChat,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C00), Color(0xFFFFB800)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C00).withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // ── Notification Bell ───────────────────────────────────
              GestureDetector(
                key: _notificationBellKey,
                onTap: _showNotifications,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    if (_overBudgetCategories.isNotEmpty)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${_overBudgetCategories.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _changeProfilePicture,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFEAF4F0),
                        Color(0xFF2E9B78),
                        Color(0xFF1A5C4A),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF1A5C4A),
                    backgroundImage: _avatarPath != null
                        ? (_avatarPath!.startsWith('data:image') ||
                                  !_avatarPath!.contains('/')
                              ? MemoryImage(
                                      base64Decode(
                                        _avatarPath!.contains(',')
                                            ? _avatarPath!.split(',')[1]
                                            : _avatarPath!,
                                      ),
                                    )
                                    as ImageProvider
                              : NetworkImage(_avatarPath!) as ImageProvider)
                        : const NetworkImage(
                            'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=100&q=80',
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── SUMMARY CARD ──────────────────────────────────────────────────────
  Widget _buildSummaryCard() {
    final remaining = _totalBudget - _totalSpent;
    final isDark = widget.isDarkMode;

    return Transform.translate(
      offset: const Offset(0, -20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          key: _totalSpentCardKey,
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    colors: [Color(0xFF133E32), Color(0xFF1A5C4A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFF1A5C4A), Color(0xFF2E9B78)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0xFF1A5C4A))
                    .withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL SPENT THIS MONTH',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.8),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$_currency ${_totalSpent.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _summaryPill(
                    'Budget',
                    '$_currency ${_totalBudget.toStringAsFixed(0)}',
                  ),
                  const SizedBox(width: 10),
                  _summaryPill(
                    'Remaining',
                    '$_currency ${remaining.toStringAsFixed(0)}',
                  ),
                  const SizedBox(width: 10),
                  _summaryPill('Transactions', '$_transactionCount'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryPill(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── BUDGET OVERVIEW ───────────────────────────────────────────────────
  Widget _buildBudgetOverview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: _budgetOverviewKey,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Budget overview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              GestureDetector(
                onTap: () {
                  _pageController.animateToPage(
                    2,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                  );
                  setState(() => _selectedTab = 2);
                },
                child: Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 13,
                    color: _accentGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_budgets.isEmpty)
            _emptyState('No budgets set for this month')
          else
            ..._budgets.map((b) => _buildBudgetRow(b)),
        ],
      ),
    );
  }

  Widget _buildBudgetRow(Map<String, dynamic> b) {
    final double spent = b['spent'];
    final double limit = b['limit'];
    final bool over = spent > limit;
    final double progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0;
    final Color colour = _parseColour(b['colour']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _lightBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _categoryIcon(b['icon']),
              color: _primaryGreen,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      b['label'],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    over
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Over!',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                          )
                        : Text(
                            '$_currency ${spent.toStringAsFixed(0)}/$_currency ${limit.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.toDouble(),
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      over ? Colors.redAccent : colour,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── RECENT TRANSACTIONS ───────────────────────────────────────────────
  Widget _buildRecentTransactions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent transactions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              GestureDetector(
                onTap: () {
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                  );
                  setState(() => _selectedTab = 1);
                },
                child: Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 13,
                    color: _accentGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_transactions.isEmpty)
            _emptyState('No transactions yet')
          else
            ..._transactions.map((t) => _buildTransactionRow(t)),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> t) {
    final double amount = (t['amount'] as num).toDouble();
    final cat = t['categories'];
    final String name =
        (t['description'] != null && t['description'].toString().isNotEmpty)
        ? t['description']
        : (cat?['name'] ?? 'Expense');
    final String date = _formatDate(t['expense_date']);
    final Color colour = _parseColour(cat?['colour']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
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
    );
  }

  // ── EMPTY STATE ───────────────────────────────────────────────────────
  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.receipt_long_rounded, 'label': 'Expenses'},
      {'icon': Icons.pie_chart_rounded, 'label': 'Budgets'},
      {'icon': Icons.bar_chart_rounded, 'label': 'Reports'},
      {'icon': Icons.settings_rounded, 'label': 'Settings'},
    ];

    final isDark = widget.isDarkMode;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = _selectedTab == i;
              
              // Map indexes to the corresponding global keys
              Key? tabKey;
              if (i == 1) tabKey = _expensesTabKey;
              if (i == 2) tabKey = _budgetsTabKey;
              if (i == 3) tabKey = _reportsTabKey;
              if (i == 4) tabKey = _settingsTabKey;

              return Expanded(
                child: GestureDetector(
                  key: tabKey,
                  onTap: () {
                    _pageController.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOutCubic,
                    );
                    setState(() => _selectedTab = i);
                    _refreshData();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: selected
                                  ? (isDark ? _accentGreen.withValues(alpha: 0.15) : _primaryGreen.withValues(alpha: 0.1))
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              items[i]['icon'] as IconData,
                              color: selected
                                  ? (isDark ? _accentGreen : _primaryGreen)
                                  : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                              size: 24,
                            ),
                          ),
                          if (i == 0 && _overBudgetCategories.isNotEmpty)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i]['label'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: selected
                              ? (isDark ? _accentGreen : _primaryGreen)
                              : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
