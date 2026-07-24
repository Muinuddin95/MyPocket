// lib/premium_analytics.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'subscription_service.dart';

class PremiumAnalyticsScreen extends StatefulWidget {
  final bool isDarkMode;
  const PremiumAnalyticsScreen({super.key, this.isDarkMode = false});

  @override
  State<PremiumAnalyticsScreen> createState() => _PremiumAnalyticsScreenState();
}

class _PremiumAnalyticsScreenState extends State<PremiumAnalyticsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _allPremiumUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  double _premiumPrice = 2.20;
  String _currency = 'USD';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _lightBg = Color(0xFFEAF4F0);
  static const Color _gold = Color(0xFFFFB800);

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _filterUsers();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1. Load users with active premium status
      final usersRes = await _supabase
          .from('users')
          .select('*')
          .eq('is_premium', true);
      
      _allPremiumUsers = List<Map<String, dynamic>>.from(usersRes as List);

      // 2. Load PayPal Settings for current price & currency
      final payPalSettings = await SubscriptionService.instance.getPayPalSettings();
      _premiumPrice = payPalSettings['amount'] ?? 2.20;
      _currency = payPalSettings['currency'] ?? 'USD';

      _filterUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading analytics: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _filterUsers() {
    if (_searchQuery.isEmpty) {
      _filteredUsers = List.from(_allPremiumUsers);
    } else {
      _filteredUsers = _allPremiumUsers.where((u) {
        final name = (u['name'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        return name.contains(_searchQuery) || email.contains(_searchQuery);
      }).toList();
    }
  }

  String _getCurrencySymbol() {
    switch (_currency.toUpperCase()) {
      case 'MYR':
        return 'RM ';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'USD':
      default:
        return '\$';
    }
  }

  int _calculateDaysLeft(String? expiryStr) {
    if (expiryStr == null) return 0;
    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null) return 0;
    final diff = expiry.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  @override
  Widget build(BuildContext context) {
    final double totalEarnings = _allPremiumUsers.length * _premiumPrice;
    final currencySymbol = _getCurrencySymbol();
    final isDark = widget.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : _lightBg,
      appBar: AppBar(
        title: const Text('Premium Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadData,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryGreen))
          : Column(
              children: [
                // Top Earnings Summary Card
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 4,
                    shadowColor: Colors.black.withValues(alpha: 0.1),
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark 
                              ? [const Color(0xFF2A3D30), const Color(0xFF1E1E1E)] 
                              : [const Color(0xFFEAF5F0), Colors.white],
                        ),
                      ),
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _gold.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.stars_rounded, color: _gold, size: 32),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Projected Earnings',
                                      style: TextStyle(
                                        fontSize: 14, 
                                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$currencySymbol${totalEarnings.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 28, 
                                        fontWeight: FontWeight.w800, 
                                        color: isDark ? Colors.white : _primaryGreen,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 0.8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildSummaryItem(
                                'Active Subscribers', 
                                '${_allPremiumUsers.length}', 
                                Icons.people_alt_rounded,
                                isDark,
                              ),
                              Container(width: 1, height: 40, color: Colors.grey.withValues(alpha: 0.3)),
                              _buildSummaryItem(
                                'Subscription Price', 
                                '$currencySymbol${_premiumPrice.toStringAsFixed(2)}/mo', 
                                Icons.sell_rounded,
                                isDark,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          spreadRadius: 1,
                          blurRadius: 10,
                        )
                      ]
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Search premium users...',
                        hintStyle: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade400),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Premium Users List Section Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        'Premium Subscribers (${_filteredUsers.length})',
                        style: TextStyle(
                          fontSize: 15, 
                          fontWeight: FontWeight.bold, 
                          color: isDark ? Colors.grey.shade300 : _primaryGreen.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),

                // Premium Users List
                Expanded(
                  child: _filteredUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isEmpty 
                                    ? 'No premium users found.' 
                                    : 'No matching users found.',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = _filteredUsers[index];
                            final daysLeft = _calculateDaysLeft(user['premium_expires_at']);
                            
                            // Colors for visual indicators on expiry time
                            Color statusColor;
                            String statusText;
                            if (daysLeft > 7) {
                              statusColor = Colors.green;
                              statusText = '$daysLeft days left';
                            } else if (daysLeft > 0) {
                              statusColor = Colors.orange;
                              statusText = '$daysLeft days left';
                            } else {
                              statusColor = Colors.red;
                              statusText = 'Expires today';
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: _primaryGreen.withValues(alpha: 0.1),
                                      child: Text(
                                        (user['name'] ?? 'U')[0].toUpperCase(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold, 
                                          color: _primaryGreen,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user['name'] ?? 'Unnamed User',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold, 
                                              fontSize: 15,
                                              color: isDark ? Colors.white : Colors.black,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            user['email'] ?? '',
                                            style: TextStyle(
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, 
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(Icons.schedule_rounded, size: 12, color: statusColor),
                                              const SizedBox(width: 4),
                                              Text(
                                                statusText,
                                                style: TextStyle(
                                                  fontSize: 11, 
                                                  color: statusColor, 
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          )
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Subscription badge or crown icon
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: _gold.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.workspace_premium_rounded, color: _gold, size: 20),
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

  Widget _buildSummaryItem(String label, String value, IconData icon, bool isDark) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(
              label, 
              style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value, 
          style: TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.bold, 
            color: isDark ? Colors.white : _primaryGreen,
          ),
        ),
      ],
    );
  }
}
