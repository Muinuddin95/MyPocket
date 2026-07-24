// reports.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'subscription_service.dart';
import 'premium.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _accentGreen = Color(0xFF2E9B78);
  static const Color _lightBg = Color(0xFFEAF4F0);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get _cardBg => _isDark ? const Color(0xFF16213E) : Colors.white;
  Color get _scaffoldBg => _isDark ? const Color(0xFF1A1A2E) : _lightBg;

  final _supabase = Supabase.instance.client;

  int _tab = 0;
  bool _loading = true;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selectedWeekStart;
  DateTime? _customStart;
  DateTime? _customEnd;

  double _totalSpent = 0;
  double _prevMonthSpent = 0;
  int _activeDays = 0;
  List<Map<String, dynamic>> _chartData = [];
  List<Map<String, dynamic>> _categoryBreakdown = [];
  String _currency = 'RM';
  String? _selectedCategoryFilter;

  static const List<Color> _catColors = [
    Color(0xFF1A5C4A),
    Color(0xFF2E9B78),
    Color(0xFF8E44AD),
    Color(0xFFE67E22),
    Color(0xFFE74C3C),
    Color(0xFF2980B9),
    Color(0xFFF39C12),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedWeekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    _loadCurrency();
    _loadData();
  }

  Future<void> _loadCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currency = prefs.getString('currency') ?? 'RM';
      });
    }
  }

  DateTime get _rangeStart {
    if (_tab == 2) return _customStart ?? DateTime.now().subtract(const Duration(days: 30));
    if (_tab == 1) return _selectedWeekStart;
    return DateTime(_selectedMonth.year, _selectedMonth.month, 1);
  }

  DateTime get _rangeEnd {
    if (_tab == 2) {
      final end = _customEnd ?? DateTime.now();
      return DateTime(
        end.year,
        end.month,
        end.day,
        23,
        59,
        59,
      );
    }
    if (_tab == 1) {
      return _selectedWeekStart.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
    }
    return DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
      23,
      59,
      59,
    );
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final res = await _supabase
          .from('expenses')
          .select(
            'amount, expense_date, category_id, categories(name, icon, colour)',
          )
          .eq('user_id', userId)
          .gte('expense_date', _rangeStart.toIso8601String())
          .lte('expense_date', _rangeEnd.toIso8601String())
          .order('expense_date');

      final expenses = List<Map<String, dynamic>>.from(res as List);

      double total = 0;
      for (final e in expenses) {
        total += (e['amount'] as num).toDouble();
      }

      final Set<String> days = {};
      for (final e in expenses) {
        final dt = DateTime.tryParse(e['expense_date'] ?? '');
        if (dt != null) days.add('${dt.year}-${dt.month}-${dt.day}');
      }

      // Populate chart data based on selected tab type
      final List<Map<String, dynamic>> chartList;
      if (_tab == 0) {
        // Monthly - 5 Weeks
        chartList = [
          {'label': 'W1', 'value': 0.0},
          {'label': 'W2', 'value': 0.0},
          {'label': 'W3', 'value': 0.0},
          {'label': 'W4', 'value': 0.0},
          {'label': 'W5', 'value': 0.0},
        ];
        for (final e in expenses) {
          final dt = DateTime.tryParse(e['expense_date'] ?? '')?.toLocal();
          if (dt == null) continue;
          final weekIndex = ((dt.day - 1) ~/ 7).clamp(0, 4);
          chartList[weekIndex]['value'] = (chartList[weekIndex]['value'] as double) + (e['amount'] as num).toDouble();
        }
      } else if (_tab == 1) {
        // Weekly - Daily (Mon - Sun)
        chartList = [
          {'label': 'Mon', 'value': 0.0},
          {'label': 'Tue', 'value': 0.0},
          {'label': 'Wed', 'value': 0.0},
          {'label': 'Thu', 'value': 0.0},
          {'label': 'Fri', 'value': 0.0},
          {'label': 'Sat', 'value': 0.0},
          {'label': 'Sun', 'value': 0.0},
        ];
        for (final e in expenses) {
          final dt = DateTime.tryParse(e['expense_date'] ?? '')?.toLocal();
          if (dt == null) continue;
          final dayIndex = (dt.weekday - 1).clamp(0, 6);
          chartList[dayIndex]['value'] = (chartList[dayIndex]['value'] as double) + (e['amount'] as num).toDouble();
        }
      } else {
        // Custom Range
        final daysDiff = _rangeEnd.difference(_rangeStart).inDays;
        if (daysDiff <= 7) {
          // Short custom range: day-by-day
          chartList = List.generate(daysDiff + 1, (i) {
            final day = _rangeStart.add(Duration(days: i));
            return {
              'label': _formatDate(day),
              'value': 0.0,
              'date': day,
            };
          });
          for (final e in expenses) {
            final dt = DateTime.tryParse(e['expense_date'] ?? '')?.toLocal();
            if (dt == null) continue;
            for (final item in chartList) {
              final itemDate = item['date'] as DateTime;
              if (itemDate.year == dt.year && itemDate.month == dt.month && itemDate.day == dt.day) {
                item['value'] = (item['value'] as double) + (e['amount'] as num).toDouble();
              }
            }
          }
        } else {
          // Long custom range: group into up to 5 weekly chunks
          final numWeeks = (daysDiff / 7).ceil().clamp(1, 5);
          chartList = List.generate(numWeeks, (i) => {'label': 'W${i + 1}', 'value': 0.0});
          for (final e in expenses) {
            final dt = DateTime.tryParse(e['expense_date'] ?? '')?.toLocal();
            if (dt == null) continue;
            final daysSinceStart = dt.difference(_rangeStart).inDays;
            final weekIndex = (daysSinceStart ~/ 7).clamp(0, numWeeks - 1);
            chartList[weekIndex]['value'] = (chartList[weekIndex]['value'] as double) + (e['amount'] as num).toDouble();
          }
        }
      }

      final Map<String, Map<String, dynamic>> catMap = {};
      for (final e in expenses) {
        final cat = e['categories'];
        final catName = cat?['name'] ?? 'Other';
        final amount = (e['amount'] as num).toDouble();
        if (!catMap.containsKey(catName)) {
          catMap[catName] = {
            'name': catName,
            'icon': cat?['icon'],
            'colour': cat?['colour'],
            'amount': 0.0,
          };
        }
        catMap[catName]!['amount'] =
            (catMap[catName]!['amount'] as double) + amount;
      }

      final breakdown = catMap.values.toList()
        ..sort(
          (a, b) => (b['amount'] as double).compareTo(a['amount'] as double),
        );

      double prevTotal = 0;
      if (_tab == 0) {
        final prevStart = DateTime(
          _selectedMonth.year,
          _selectedMonth.month - 1,
          1,
        );
        final prevEnd = DateTime(
          _selectedMonth.year,
          _selectedMonth.month,
          0,
          23,
          59,
          59,
        );
        final prevRes = await _supabase
            .from('expenses')
            .select('amount')
            .eq('user_id', userId)
            .gte('expense_date', prevStart.toIso8601String())
            .lte('expense_date', prevEnd.toIso8601String());
        for (final e in prevRes as List) {
          prevTotal += (e['amount'] as num).toDouble();
        }
      }

      if (mounted) {
        setState(() {
          _totalSpent = total;
          _prevMonthSpent = prevTotal;
          _activeDays = days.length;
          _chartData = chartList;
          _categoryBreakdown = breakdown;
        });
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
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _monthLabel {
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
    return '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}';
  }

  double get _avgPerDay => _activeDays > 0 ? _totalSpent / _activeDays : 0;
  String get _topCategory =>
      _categoryBreakdown.isEmpty ? '—' : _categoryBreakdown.first['name'];
  double get _topCategoryPct => _categoryBreakdown.isEmpty || _totalSpent == 0
      ? 0
      : (_categoryBreakdown.first['amount'] as double) / _totalSpent * 100;
  double _pct(double amount) =>
      _totalSpent > 0 ? amount / _totalSpent * 100 : 0;
  
  int get _highestChartIndex {
    double mx = 0;
    int idx = 0;
    for (int i = 0; i < _chartData.length; i++) {
      final val = _chartData[i]['value'] as double;
      if (val > mx) {
        mx = val;
        idx = i;
      }
    }
    return idx;
  }

  Color _catColor(int i) => _catColors[i % _catColors.length];

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.month == now.month && _selectedMonth.year == now.year;
  }

  bool get _isCurrentWeek {
    final now = DateTime.now();
    final endOfWeek = _selectedWeekStart.add(const Duration(days: 7));
    return endOfWeek.isAfter(now);
  }

  void _prevMonth() {
    setState(
      () => _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month - 1,
      ),
    );
    _loadData();
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _selectedMonth = next);
    _loadData();
  }

  void _prevWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
    });
    _loadData();
  }

  void _nextWeek() {
    final next = _selectedWeekStart.add(const Duration(days: 7));
    final now = DateTime.now();
    if (next.isAfter(now)) return;
    setState(() {
      _selectedWeekStart = next;
    });
    _loadData();
  }

  Future<void> _pickCustomRange() async {
    final start = await showDatePicker(
      context: context,
      initialDate: _customStart ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _primaryGreen),
        ),
        child: child!,
      ),
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: _customEnd ?? DateTime.now(),
      firstDate: start,
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _primaryGreen),
        ),
        child: child!,
      ),
    );
    if (end == null) return;
    setState(() {
      _customStart = start;
      _customEnd = end;
    });
    _loadData();
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
    return '${dt.day} ${months[dt.month - 1]}';
  }
  Future<void> _downloadPdf() async {
    HapticFeedback.mediumImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generating PDF report…'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF1A5C4A),
        ),
      );
    }

    const primaryColor = PdfColor.fromInt(0xFF1A5C4A);
    const accentColor = PdfColor.fromInt(0xFF2E9B78);
    const lightBg = PdfColor.fromInt(0xFFEAF4F0);
    const greyText = PdfColor.fromInt(0xFF888888);
    const darkText = PdfColor.fromInt(0xFF1A1A1A);
    const white = PdfColors.white;

    final String periodLabel;
    if (_tab == 2 && _customStart != null && _customEnd != null) {
      periodLabel = '${_formatDate(_customStart!)} - ${_formatDate(_customEnd!)}';
    } else if (_tab == 1) {
      periodLabel = 'Weekly - $_monthLabel';
    } else {
      periodLabel = _monthLabel;
    }

    final List<List<String>> categoryRows = _categoryBreakdown.asMap().entries.map((entry) {
      final cat = entry.value;
      final amt = (cat['amount'] as double);
      final pct = _pct(amt);
      return [cat['name'] as String, '$_currency ${amt.toStringAsFixed(2)}', '${pct.toStringAsFixed(1)}%'];
    }).toList();

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: pw.BoxDecoration(color: primaryColor, borderRadius: pw.BorderRadius.circular(12)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('MyPocket', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: white)),
                    pw.SizedBox(height: 4),
                    pw.Text('Expense Report', style: pw.TextStyle(fontSize: 13, color: white)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text(periodLabel, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: white)),
                    pw.SizedBox(height: 4),
                    pw.Text('Generated: ${DateTime.now().toLocal().toString().split('.').first}',
                        style: pw.TextStyle(fontSize: 9, color: white)),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: darkText)),
            pw.SizedBox(height: 10),
            pw.Row(children: [
              pw.Expanded(child: _pdfSummaryCard('Total Spent', '$_currency ${_totalSpent.toStringAsFixed(2)}', primaryColor, white)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _pdfSummaryCard('Daily Average', '$_currency ${_avgPerDay.toStringAsFixed(2)}', accentColor, white)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: _pdfSummaryCard('Active Days', '$_activeDays days', lightBg, primaryColor)),
              if (_tab == 0) ...[
                pw.SizedBox(width: 10),
                pw.Expanded(child: _pdfSummaryCard(
                  'vs Last Month',
                  _prevMonthSpent > 0
                      ? '${((_totalSpent - _prevMonthSpent) / _prevMonthSpent * 100).abs().toStringAsFixed(0)}% ${_totalSpent > _prevMonthSpent ? "up" : "down"}'
                      : '--',
                  _totalSpent > _prevMonthSpent ? const PdfColor.fromInt(0xFFE74C3C) : accentColor,
                  white,
                )),
              ],
            ]),
            pw.SizedBox(height: 20),
            pw.Text(_tab == 1 ? 'Daily Breakdown' : 'Weekly Breakdown', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: darkText)),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(color: white, borderRadius: pw.BorderRadius.circular(10), border: pw.Border.all(color: lightBg)),
              child: pw.Column(
                children: List.generate(_chartData.length, (i) {
                  final item = _chartData[i];
                  final val = item['value'] as double;
                  final maxVal = _chartData.map((e) => e['value'] as double).reduce((a, b) => a > b ? a : b);
                  final pct = maxVal > 0 ? (val / maxVal).clamp(0.0, 1.0) : 0.0;
                  final isHigh = i == _highestChartIndex;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Row(children: [
                      pw.SizedBox(width: 50, child: pw.Text(item['label'] as String, style: pw.TextStyle(fontSize: 10, color: greyText))),
                      pw.Expanded(
                        child: pw.LayoutBuilder(
                          builder: (ctx, constraints) {
                            final maxW = constraints?.maxWidth ?? 0;
                            final barWidth = (maxW * pct).clamp(0.0, maxW);
                            return pw.Stack(children: [
                              pw.Container(height: 14, decoration: pw.BoxDecoration(color: lightBg, borderRadius: pw.BorderRadius.circular(7))),
                              pw.Container(
                                height: 14,
                                width: barWidth,
                                decoration: pw.BoxDecoration(
                                  color: isHigh ? primaryColor : accentColor,
                                  borderRadius: pw.BorderRadius.circular(7),
                                ),
                              ),
                            ]);
                          },
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.SizedBox(
                        width: 70,
                        child: pw.Text('$_currency ${val.toStringAsFixed(2)}',
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                                color: isHigh ? primaryColor : darkText)),
                      ),
                    ]),
                  );
                }),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Spending by Category', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: darkText)),
            pw.SizedBox(height: 10),
            if (categoryRows.isEmpty)
              pw.Center(child: pw.Text('No expense data for this period.', style: pw.TextStyle(color: greyText)))
            else
              pw.Table(
                border: pw.TableBorder.all(color: lightBg, width: 1),
                columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2), 2: const pw.FlexColumnWidth(1)},
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: primaryColor),
                    children: ['Category', 'Amount', '% of Total'].map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: white, fontSize: 11)),
                    )).toList(),
                  ),
                  ...categoryRows.asMap().entries.map((entry) {
                    final isEven = entry.key % 2 == 0;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: isEven ? white : lightBg),
                      children: entry.value.map((cell) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        child: pw.Text(cell, style: pw.TextStyle(fontSize: 11, color: darkText)),
                      )).toList(),
                    );
                  }),
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: accentColor),
                    children: ['TOTAL', '$_currency ${_totalSpent.toStringAsFixed(2)}', '100%'].map((cell) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: pw.Text(cell, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: white, fontSize: 11)),
                    )).toList(),
                  ),
                ],
              ),
            pw.SizedBox(height: 20),
            pw.Divider(color: lightBg),
            pw.SizedBox(height: 6),
            pw.Center(child: pw.Text('Generated by MyPocket - Smart Student Finance Tracker',
                style: pw.TextStyle(fontSize: 9, color: greyText))),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'MyPocket_Report_$periodLabel.pdf',
    );
  }

  pw.Widget _pdfSummaryCard(String label, String value, PdfColor bgColor, PdfColor textColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: bgColor, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9, color: textColor)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: textColor)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: _scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildTabBar(),
            if (_tab == 2) _buildCustomRangePicker(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primaryGreen),
                    )
                  : RefreshIndicator(
                      color: _primaryGreen,
                      onRefresh: _loadData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildSummaryCards(),
                            const SizedBox(height: 16),
                            _buildWeeklyChart(),
                            const SizedBox(height: 16),
                            _buildPieChart(),
                            const SizedBox(height: 16),
                            _buildAmountBreakdown(),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Text(
            'Reports',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          const Spacer(),
          if (_tab == 0) ...[
            GestureDetector(
              onTap: _prevMonth,
              child: const Icon(
                Icons.chevron_left_rounded,
                color: _primaryGreen,
                size: 22,
              ),
            ),
            Text(
              _monthLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _primaryGreen,
              ),
            ),
            GestureDetector(
              onTap: _isCurrentMonth ? null : _nextMonth,
              child: Icon(
                Icons.chevron_right_rounded,
                color: _isCurrentMonth ? Colors.grey.shade300 : _primaryGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 8),
          ] else if (_tab == 1) ...[
            GestureDetector(
              onTap: _prevWeek,
              child: const Icon(
                Icons.chevron_left_rounded,
                color: _primaryGreen,
                size: 22,
              ),
            ),
            Text(
              '${_formatDate(_rangeStart)} - ${_formatDate(_rangeEnd)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _primaryGreen,
              ),
            ),
            GestureDetector(
              onTap: _isCurrentWeek ? null : _nextWeek,
              child: Icon(
                Icons.chevron_right_rounded,
                color: _isCurrentWeek ? Colors.grey.shade300 : _primaryGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: GestureDetector(
              onTap: () {
                final isPremium = SubscriptionService.instance.isPremium;
                if (!isPremium) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('PDF Export is a Premium feature!'),
                      backgroundColor: Colors.orangeAccent,
                    ),
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PremiumScreen()),
                  );
                  return;
                }
                _downloadPdf();
              },
              child: const Icon(
                Icons.download_rounded,
                color: _primaryGreen,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = ['Monthly', 'Weekly', 'Custom'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final selected = _tab == i;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  final isPremium = SubscriptionService.instance.isPremium;
                  if (i > 0 && !isPremium) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Weekly and Custom reports are Premium features!'),
                        backgroundColor: Colors.orangeAccent,
                      ),
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PremiumScreen()),
                    );
                    return;
                  }
                  setState(() => _tab = i);
                  if (i != 2) _loadData();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? _primaryGreen : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tabs[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCustomRangePicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: GestureDetector(
        onTap: _pickCustomRange,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: _primaryGreen,
                size: 16,
              ),
              const SizedBox(width: 10),
              Text(
                _customStart != null && _customEnd != null
                    ? '${_formatDate(_customStart!)} → ${_formatDate(_customEnd!)}'
                    : 'Tap to select date range',
                style: TextStyle(
                  fontSize: 13,
                  color: _customStart != null
                      ? const Color(0xFF1A1A1A)
                      : Colors.grey.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.edit_calendar_rounded,
                color: Colors.grey.shade400,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final pctChange = _prevMonthSpent > 0
        ? ((_totalSpent - _prevMonthSpent) / _prevMonthSpent * 100)
        : 0.0;
    final isUp = pctChange >= 0;
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            label: 'Total spent',
            value: '$_currency ${_totalSpent.toStringAsFixed(0)}',
            sub: _tab == 0 && _prevMonthSpent > 0
                ? '${isUp ? '↑' : '↓'} ${pctChange.abs().toStringAsFixed(0)}% vs prev'
                : null,
            subColor: isUp ? Colors.redAccent : _accentGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            label: 'Avg/day',
            value: '$_currency ${_avgPerDay.toStringAsFixed(0)}',
            sub: '$_activeDays active days',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryCard(
            label: 'Top spend',
            value: _topCategory,
            sub: '${_topCategoryPct.toStringAsFixed(0)}%',
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    String? sub,
    Color? subColor,
  }) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              style: TextStyle(
                fontSize: 10,
                color: subColor ?? Colors.grey.shade400,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeeklyChart() {
    final maxVal = _chartData.isEmpty ? 0.0 : _chartData.map((e) => e['value'] as double).reduce((a, b) => a > b ? a : b);
    final highIdx = _highestChartIndex;
    final hasData = maxVal > 0;

    final String chartTitle;
    if (_tab == 0) {
      chartTitle = 'Weekly spending — $_monthLabel';
    } else if (_tab == 1) {
      chartTitle = 'Daily spending — ${_formatDate(_rangeStart)} - ${_formatDate(_rangeEnd)}';
    } else {
      chartTitle = 'Spending breakdown — Custom Range';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chartTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: hasData
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$_currency${maxVal.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          Text(
                            '$_currency${(maxVal * 0.75).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          Text(
                            '$_currency${(maxVal * 0.5).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          Text(
                            '$_currency${(maxVal * 0.25).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          Text(
                            '${_currency}0',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomPaint(
                          painter: _GridPainter(),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(_chartData.length, (i) {
                              final item = _chartData[i];
                              final val = item['value'] as double;
                              final ratio = maxVal > 0 ? val / maxVal : 0.0;
                              final isHigh = i == highIdx && val > 0;
                              return _Bar(
                                label: item['label'] as String,
                                ratio: ratio,
                                value: val,
                                isHighest: isHigh,
                                color: isHigh
                                    ? _primaryGreen
                                    : _primaryGreen.withValues(alpha: 0.3),
                                currency: _currency,
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Text(
                      'No spending data',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
          if (hasData && _chartData[highIdx]['value'] > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _lightBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: _accentGreen,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _tab == 0
                          ? 'Week ${highIdx + 1} was your highest spending week.'
                          : _tab == 1
                              ? '${_chartData[highIdx]['label']} was your highest spending day.'
                              : '${_chartData[highIdx]['label']} was your highest spending period.',
                      style: const TextStyle(fontSize: 11, color: _accentGreen),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPieChart() {
    if (_categoryBreakdown.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No category data',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spending by category',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: CustomPaint(
                  painter: _PiePainter(
                    sections: _categoryBreakdown
                        .asMap()
                        .entries
                        .map(
                          (e) {
                            final name = e.value['name'];
                            final isFiltered = _selectedCategoryFilter == null || _selectedCategoryFilter == name;
                            return _PieSection(
                              value: e.value['amount'] as double,
                              color: isFiltered ? _catColor(e.key) : _catColor(e.key).withValues(alpha: 0.15),
                            );
                          }
                        )
                        .toList(),
                    total: _totalSpent,
                    centerLabel: _selectedCategoryFilter == null
                        ? '$_currency${_totalSpent.toStringAsFixed(0)}'
                        : '$_currency${_categoryBreakdown.firstWhere((cat) => cat['name'] == _selectedCategoryFilter)['amount'].toStringAsFixed(0)}',
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _categoryBreakdown.asMap().entries.take(5).map((e) {
                    final pct = _pct(e.value['amount'] as double);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _catColor(e.key),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.value['name'],
                              style: TextStyle(
                                fontSize: 12,
                                color: _textColor,
                              ),
                            ),
                          ),
                          Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmountBreakdown() {
    if (_categoryBreakdown.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount breakdown',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 14),
          ..._categoryBreakdown.asMap().entries.map((e) {
            final name = e.value['name'];
            final amount = e.value['amount'] as double;
            final ratio = _totalSpent > 0 ? amount / _totalSpent : 0.0;
            final isFiltered = _selectedCategoryFilter == null || _selectedCategoryFilter == name;
            final color = isFiltered ? _catColor(e.key) : _catColor(e.key).withValues(alpha: 0.15);
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (_selectedCategoryFilter == name) {
                    _selectedCategoryFilter = null;
                  } else {
                    _selectedCategoryFilter = name;
                  }
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Opacity(
                opacity: isFiltered ? 1.0 : 0.4,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80,
                        child: Text(
                          e.value['name'],
                          style: TextStyle(
                            fontSize: 13,
                            color: _textColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$_currency ${amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                ),
              ),
              Text(
                '$_currency ${_totalSpent.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _primaryGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade100
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

class _Bar extends StatelessWidget {
  final String label;
  final double ratio;
  final double value;
  final bool isHighest;
  final Color color;
  final String currency;
  const _Bar({
    required this.label,
    required this.ratio,
    required this.value,
    required this.isHighest,
    required this.color,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isHighest && value > 0)
          Text(
            '$currency${value.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A5C4A),
            ),
          ),
        const SizedBox(height: 2),
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          width: 28,
          height: 100 * ratio,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

class _PieSection {
  final double value;
  final Color color;
  const _PieSection({required this.value, required this.color});
}

class _PiePainter extends CustomPainter {
  final List<_PieSection> sections;
  final double total;
  final String centerLabel;
  _PiePainter({
    required this.sections,
    required this.total,
    required this.centerLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 22.0;
    final innerRadius = radius - strokeWidth;
    double startAngle = -pi / 2;

    for (final section in sections) {
      if (total == 0) break;
      final sweep = 2 * pi * section.value / total;
      final paint = Paint()
        ..color = section.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: innerRadius),
        startAngle,
        sweep - 0.03,
        false,
        paint,
      );
      startAngle += sweep;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Total\n',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontFamily: 'Roboto',
            ),
          ),
          TextSpan(
            text: centerLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A5C4A),
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: radius * 1.2);
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.total != total || old.sections.length != sections.length;
}
