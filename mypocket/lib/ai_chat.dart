// lib/ai_chat.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'subscription_service.dart';
import 'premium.dart';
import 'demo.dart';

// The Gemini key must stay on a server (Supabase Edge Function), never in the app.
const String _kGeminiApiKey = '';
const String _kGeminiModel = 'gemini-2.5-flash';
const String _kGeminiUrl =
    'https://generativelanguage.googleapis.com/v1beta/models/$_kGeminiModel:generateContent';

class AIChatScreen extends StatefulWidget {
  final bool isDarkMode;
  const AIChatScreen({super.key, this.isDarkMode = false});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _supabase = Supabase.instance.client;
  final List<_ChatMessage> _messages = [];
  final List<Map<String, dynamic>> _geminiHistory = [];

  bool _isPremium = false;
  bool _isLoading = true;
  bool _isTyping = false;
  String _systemPrompt = '';
  String _currency = 'RM';

  late AnimationController _typingAnimController;

  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _accentGreen = Color(0xFF2E9B78);

  static const List<String> _quickQuestions = [
    '📊 How much did I spend this month?',
    '🎯 Am I on track with my budget?',
    '🍔 What is my biggest expense category?',
    '💡 Give me 3 savings tips',
    '⚠️ Which budget am I closest to exceeding?',
    '📅 Compare this week vs last week',
  ];

  @override
  void initState() {
    super.initState();
    _typingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _typingAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      
      final prefs = await SharedPreferences.getInstance();
      final historyStr = prefs.getString('chat_history_$userId');
      final geminiHistoryStr = prefs.getString('gemini_history_$userId');
      
      if (historyStr != null && historyStr.isNotEmpty) {
        final List decoded = jsonDecode(historyStr);
        if (mounted) {
          setState(() {
            _messages.clear();
            _messages.addAll(decoded.map((m) => _ChatMessage(
              text: m['text'],
              isUser: m['isUser'] == true,
            )));
          });
        }
      }
      
      if (geminiHistoryStr != null && geminiHistoryStr.isNotEmpty) {
        final List decoded = jsonDecode(geminiHistoryStr);
        if (mounted) {
          setState(() {
            _geminiHistory.clear();
            _geminiHistory.addAll(List<Map<String, dynamic>>.from(decoded));
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading chat history: $e');
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      
      final prefs = await SharedPreferences.getInstance();
      final historyList = _messages.map((m) => {
        'text': m.text,
        'isUser': m.isUser,
      }).toList();
      
      await prefs.setString('chat_history_$userId', jsonEncode(historyList));
      await prefs.setString('gemini_history_$userId', jsonEncode(_geminiHistory));
    } catch (e) {
      debugPrint('Error saving chat history: $e');
    }
  }

  Future<void> _initialize() async {
    final isPremium = await SubscriptionService.instance.checkPremiumStatus();
    if (!mounted) return;
    setState(() { _isPremium = isPremium; });

    if (isPremium) {
      final prefs = await SharedPreferences.getInstance();
      _currency = prefs.getString('currency') ?? 'RM';
      await _loadFinancialDataAndBuildPrompt();
      await _loadChatHistory();
      if (_messages.isEmpty) {
        _addBotMessage(
          '👋 Hi! I\'m FinBot, your AI finance buddy!\n\n'
          'I\'ve loaded your spending data and I\'m ready to help. '
          'You can ask me anything about your budget, expenses, or how to save more money. Jom! 🚀',
        );
        await _saveChatHistory();
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadFinancialDataAndBuildPrompt() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
      final monthEnd =
          DateTime(now.year, now.month + 1, 0, 23, 59, 59).toIso8601String();

      // Fetch user info
      final userRes = await _supabase
          .from('users')
          .select('name, student_type')
          .eq('user_id', userId)
          .maybeSingle();

      final userName = userRes?['name'] ?? 'Student';
      final studentType = userRes?['student_type'] ?? 'Student';

      // Fetch expenses this month
      final expRes = await _supabase
          .from('expenses')
          .select('amount, description, expense_date, categories(name)')
          .eq('user_id', userId)
          .gte('expense_date', monthStart)
          .lte('expense_date', monthEnd)
          .order('expense_date', ascending: false);

      double totalSpent = 0;
      for (final e in expRes as List) {
        totalSpent += (e['amount'] as num).toDouble();
      }

      // Fetch budgets
      final budgetRes = await _supabase
          .from('budgets')
          .select('budget_limit, category_id, categories(name)')
          .eq('user_id', userId)
          .eq('month', now.month)
          .eq('year', now.year);

      double totalBudget = 0;
      final budgetLines = StringBuffer();
      for (final b in budgetRes as List) {
        final limit = (b['budget_limit'] as num).toDouble();
        totalBudget += limit;
        final catId = b['category_id'];

        final spentRes = await _supabase
            .from('expenses')
            .select('amount')
            .eq('user_id', userId)
            .eq('category_id', catId)
            .gte('expense_date', monthStart)
            .lte('expense_date', monthEnd);

        double catSpent = 0;
        for (final e in spentRes as List) {
          catSpent += (e['amount'] as num).toDouble();
        }

        final catName = b['categories']?['name'] ?? 'Category';
        final pct = limit > 0 ? (catSpent / limit * 100).toStringAsFixed(1) : '0';
        final status = catSpent > limit ? '⚠️ OVER BUDGET' : '✅ within budget';
        budgetLines.writeln(
            '  - $catName: spent $_currency ${catSpent.toStringAsFixed(2)} / $_currency ${limit.toStringAsFixed(2)} ($pct% - $status)');
      }

      // Recent transactions summary
      final txLines = StringBuffer();
      for (final e in (expRes as List).take(8)) {
        final amt = (e['amount'] as num).toDouble();
        final desc = e['description'] ?? 'Expense';
        final cat = e['categories']?['name'] ?? 'Other';
        final date = (e['expense_date'] as String?)?.split('T').first ?? '';
        txLines.writeln('  - $date: $desc [$cat] $_currency ${amt.toStringAsFixed(2)}');
      }

      final remaining = totalBudget - totalSpent;
      final monthName = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December'
      ][now.month - 1];

      _systemPrompt = '''You are FinBot, a friendly AI personal finance assistant embedded in the MyPocket app for Malaysian students.

YOUR PERSONALITY:
- Warm, encouraging, and supportive like a good kakak/abang senior
- Use simple English; you can sprinkle a little Malaysian flavour ("lah", "wah", "boleh") but don't overdo it
- Use emojis to make your responses feel lively and approachable
- Always be motivating — never shame the user for overspending, instead offer constructive advice
- Keep answers concise and actionable (max 3-4 paragraphs)

USER PROFILE:
- Name: $userName
- Student Type: $studentType
- Month: $monthName ${now.year}

REAL-TIME FINANCIAL DATA (loaded right now from the app):
- Total spent this month: $_currency ${totalSpent.toStringAsFixed(2)}
- Total monthly budget: $_currency ${totalBudget.toStringAsFixed(2)}
- Remaining budget: $_currency ${remaining.toStringAsFixed(2)}
- Budget used: ${totalBudget > 0 ? (totalSpent / totalBudget * 100).toStringAsFixed(1) : '0'}%

BUDGET BREAKDOWN:
${budgetLines.toString().trim().isEmpty ? '  (No budgets set yet)' : budgetLines.toString().trim()}

RECENT TRANSACTIONS:
${txLines.toString().trim().isEmpty ? '  (No transactions this month)' : txLines.toString().trim()}

INSTRUCTIONS:
- Base your answers on the REAL data above
- If asked about specific numbers, quote exact figures from the data
- If the user has no budget set, encourage them to set one
- Give 2-3 specific, actionable tips when asked for advice
- Currency is Malaysian Ringgit (RM)
- Always end with an encouraging line or emoji''';
    } catch (e) {
      debugPrint('AIChatScreen._loadFinancialDataAndBuildPrompt error: $e');
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isTyping) return;
    HapticFeedback.lightImpact();

    final userText = text.trim();
    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(text: userText, isUser: true));
      _isTyping = true;
    });
    _saveChatHistory();
    _scrollToBottom();

    try {
      // Add to Gemini history
      _geminiHistory.add({
        'role': 'user',
        'parts': [
          {'text': userText}
        ]
      });

      final requestBody = {
        'systemInstruction': {
          'parts': [
            {'text': _systemPrompt}
          ]
        },
        'contents': _geminiHistory,
        'generationConfig': {
          'temperature': 0.8,
          'topK': 40,
          'topP': 0.9,
          'maxOutputTokens': 600,
        },
      };

      final apiKey = _kGeminiApiKey;
      if (apiKey.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 800));
        const mockReply = kDemoMode
            ? 'AI chat is turned off in this web demo.'
            : 'AI chat is temporarily unavailable. Please try again later.';
        _addBotMessage(mockReply);
        return;
      }

      final response = await http
          .post(
            Uri.parse('$_kGeminiUrl?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['candidates']?[0]?['content']?['parts']?[0]?['text']
            as String?;

        if (reply != null && reply.isNotEmpty) {
          _geminiHistory.add({
            'role': 'model',
            'parts': [
              {'text': reply}
            ]
          });
          _addBotMessage(reply);
        } else {
          _addBotMessage(
              'Hmm, I didn\'t get a proper response. Please try again! 🙏');
        }
      } else {
        final err = jsonDecode(response.body);
        final errMsg = err['error']?['message'] ?? 'Unknown error';
        _addBotMessage('Oops! API error: $errMsg\n\nPlease try again.');
      }
    } catch (e) {
      _addBotMessage(
          'Sorry, I\'m having trouble connecting right now. Check your internet connection and try again! 🌐');
      debugPrint('AIChatScreen._sendMessage error: $e');
    } finally {
      if (mounted) setState(() => _isTyping = false);
      _scrollToBottom();
    }
  }

  void _addBotMessage(String text) {
    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(text: text, isUser: false));
      });
      _saveChatHistory();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F4F8),
      appBar: _buildAppBar(isDark),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: _primaryGreen))
          : !_isPremium
              ? _buildPremiumGate(isDark)
              : Column(
                  children: [
                    _buildQuickQuestions(isDark),
                    Expanded(child: _buildMessageList(isDark)),
                    _buildInputBar(isDark),
                  ],
                ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A5C4A), Color(0xFF2E9B78)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.smart_toy_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FinBot',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    Text('AI Finance Assistant',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, color: Color(0xFF4ADE80), size: 8),
                      SizedBox(width: 4),
                      Text('Online',
                          style:
                              TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumGate(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB800), Color(0xFFE09600)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.3),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 52),
            ),
            const SizedBox(height: 24),
            Text(
              'AI Chat is Premium',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Upgrade to Premium to chat with FinBot and get personalised advice based on your real spending data.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PremiumScreen(
                      onPremiumActivated: () {
                        setState(() => _isPremium = true);
                        _initialize();
                      },
                    ),
                  ),
                );
                // Re-check after returning
                final updated =
                    await SubscriptionService.instance.checkPremiumStatus();
                if (mounted && updated) {
                  setState(() => _isPremium = true);
                  _initialize();
                }
              },
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB800), Color(0xFFE09600)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium_rounded,
                          color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Upgrade to Premium',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('$_currency 9.90/month · Cancel anytime',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickQuestions(bool isDark) {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _quickQuestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final q = _quickQuestions[i];
          return GestureDetector(
            onTap: () => _sendMessage(q),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF16213E)
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2A3548)
                      : Colors.grey.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                q,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageList(bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (_, i) {
        if (_isTyping && i == _messages.length) {
          return _buildTypingIndicator(isDark);
        }
        return _buildBubble(_messages[i], isDark);
      },
    );
  }

  Widget _buildBubble(_ChatMessage msg, bool isDark) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 8, bottom: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A5C4A), Color(0xFF2E9B78)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 16),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? _primaryGreen
                    : (isDark
                        ? const Color(0xFF1E2A3A)
                        : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isUser
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  color: isUser
                      ? Colors.white
                      : (isDark ? Colors.white : const Color(0xFF1A1A1A)),
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(left: 8, bottom: 4),
              decoration: const BoxDecoration(
                color: _accentGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded,
                  color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 8, bottom: 4),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A5C4A), Color(0xFF2E9B78)],
              ),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 16),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2A3A) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _typingAnimController,
                  builder: (_, _) {
                    final delay = i * 0.33;
                    final t = (_typingAnimController.value - delay).clamp(0.0, 1.0);
                    final opacity = (0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2)).clamp(0.3, 1.0);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _primaryGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16213E) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1A2235)
                      : const Color(0xFFF4F6F8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2A3548)
                        : Colors.grey.shade200,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask FinBot anything...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: _sendMessage,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _sendMessage(_controller.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_primaryGreen, _accentGreen],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _primaryGreen.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _ChatMessage({required this.text, required this.isUser})
      : timestamp = DateTime.now();
}
