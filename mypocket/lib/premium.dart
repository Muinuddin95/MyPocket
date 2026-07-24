// lib/premium.dart
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'widgets/paypal/paypal_checkout_view.dart';
import 'subscription_service.dart';


class PremiumScreen extends StatefulWidget {
  final VoidCallback? onPremiumActivated;
  const PremiumScreen({super.key, this.onPremiumActivated});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen>
    with TickerProviderStateMixin {
  late ConfettiController _confettiController;
  late AnimationController _shimmerController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isPremium = false;
  bool _isLoading = true;
  bool _processingPayment = false;
  bool _paypalSandboxMode = true;
  String _paypalClientId = '';
  String _paypalSecretKey = '';
  String _paypalCurrency = 'USD';
  double _paypalAmount = 2.20;
  String _currency = 'RM';

  static const Color _gold = Color(0xFF2E9B78);
  static const Color _goldDark = Color(0xFF1A5C4A);
  static const Color _primaryGreen = Color(0xFF1A5C4A);

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 4));
    _shimmerController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 1.0, end: 1.06).animate(_pulseController);
    _initData();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _shimmerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    final localCurrency = prefs.getString('currency') ?? 'RM';
    final status = await SubscriptionService.instance.checkPremiumStatus();
    final payPalSettings = await SubscriptionService.instance.getPayPalSettings();
    if (mounted) {
      setState(() {
        _isPremium = status;
        _paypalSandboxMode = payPalSettings['sandboxMode'] ?? true;
        _paypalClientId = payPalSettings['clientId'] ?? '';
        _paypalSecretKey = payPalSettings['secretKey'] ?? '';
        _paypalCurrency = payPalSettings['currency'] ?? 'USD';
        _paypalAmount = payPalSettings['amount'] ?? 2.20;
        _paypalAmount = payPalSettings['amount'] ?? 2.20;
        _currency = localCurrency;
        _isLoading = false;
      });
    }
  }

  Future<void> _startPayPalCheckout() async {
    if (_processingPayment) return;
    HapticFeedback.mediumImpact();

    if (_paypalClientId.isEmpty || _paypalSecretKey.isEmpty || _paypalClientId == 'YOUR_PAYPAL_SANDBOX_CLIENT_ID') {
      _showPlaceholderPaymentDialog();
      return;
    }

    setState(() => _processingPayment = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) => PaypalCheckoutView(
            sandboxMode: _paypalSandboxMode,
            clientId: _paypalClientId,
            secretKey: _paypalSecretKey,
            transactions: [
              {
                "amount": {
                  "total": _paypalAmount.toStringAsFixed(2),
                  "currency": _paypalCurrency,
                  "details": {
                    "subtotal": _paypalAmount.toStringAsFixed(2),
                    "shipping": '0',
                    "shipping_discount": 0
                  }
                },
                "description":
                    "MyPocket Premium - 1 month ($_paypalCurrency ${_paypalAmount.toStringAsFixed(2)})",
                "item_list": {
                  "items": [
                    {
                      "name": "MyPocket Premium",
                      "quantity": 1,
                      "price": _paypalAmount.toStringAsFixed(2),
                      "currency": _paypalCurrency
                    }
                  ],
                }
              }
            ],
            note: "Thank you for subscribing to MyPocket Premium!",
            onSuccess: (Map params) async {
              debugPrint("PayPal success: $params");
              if (mounted) Navigator.of(context).pop(); // Close checkout webview
              
              final activated =
                  await SubscriptionService.instance.activatePremium();
              if (activated && mounted) {
                setState(() => _isPremium = true);
                _confettiController.play();
                widget.onPremiumActivated?.call();
                HapticFeedback.heavyImpact();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🎉 Welcome to MyPocket Premium!'),
                      backgroundColor: Color(0xFF1A5C4A),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            onError: (error) {
              debugPrint("PayPal error: $error");
              if (mounted) Navigator.of(context).pop(); // Close checkout webview
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment failed. Please try again.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            onCancel: () {
              debugPrint('PayPal cancelled');
              if (mounted) Navigator.of(context).pop(); // Close checkout webview
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _processingPayment = false);
    }
  }

  void _showPlaceholderPaymentDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF1A5C4A)),
            SizedBox(width: 8),
            Text('PayPal Setup Required',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'To enable PayPal payments, configure your credentials in the Admin Panel:\n\n'
          '1. Log in as admin (e.g. admin95@gmail.com)\n'
          '2. Click the PayPal settings icon in the top right of the Admin screen\n'
          '3. Input your Client ID & Secret Key\n'
          '4. Click Save to enable payments instantly!',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it',
                style: TextStyle(color: Color(0xFF1A5C4A))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A5C4A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              // Simulate premium activation for testing
              final activated =
                  await SubscriptionService.instance.activatePremium();
              if (activated && mounted) {
                setState(() => _isPremium = true);
                _confettiController.play();
                widget.onPremiumActivated?.call();
                HapticFeedback.heavyImpact();
              }
            },
            child: const Text('Test Premium',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: Stack(
        children: [
          // Background radial glow
          Positioned(
            top: -80,
            left: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _gold.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -40,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _primaryGreen.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Confetti
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: pi / 2,
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              gravity: 0.1,
              colors: const [
                Color(0xFF2E9B78),
                Color(0xFF1A5C4A),
                Colors.white,
                Color(0xFF2E9B78),
              ],
            ),
          ),
          // Main content
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _gold))
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildHeader(),
                        if (_isPremium)
                          _buildAlreadyPremiumCard()
                        else ...[
                          _buildPriceSection(),
                          _buildComparisonTable(),
                          _buildPayPalButton(),
                          const SizedBox(height: 16),
                          _buildSecurityNote(),
                          const SizedBox(height: 32),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const Spacer(),
              if (_isPremium)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_gold, _goldDark]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.star_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('ACTIVE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF4EE2B6), _gold, _goldDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.45),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 46),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'MyPocket Premium',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isPremium
                ? 'You\'re enjoying all premium features!'
                : 'Unlock the full power of your finances',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    final showEstimate = _paypalCurrency == 'USD';
    final amountText = '$_paypalCurrency ${_paypalAmount.toStringAsFixed(2)}';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_goldDark, _gold],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _goldDark.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Premium Plan',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Billed monthly · Cancel anytime',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(amountText,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              if (showEstimate) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('≈ $_currency ${(_paypalAmount * 4.5).toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonTable() {
    const features = [
      _Feature('Budget categories', '3 max', 'Unlimited', Icons.pie_chart_rounded),
      _Feature('Transaction history', 'Last 30 days', 'All time', Icons.history_rounded),
      _Feature('Reports', 'Basic monthly', 'Full + yearly', Icons.bar_chart_rounded),
      _Feature('Export to PDF', false, true, Icons.picture_as_pdf_rounded),
      _Feature('Export to CSV', false, true, Icons.table_chart_rounded),
      _Feature('Bill reminders', false, true, Icons.alarm_rounded),
      _Feature('Savings goals', false, true, Icons.savings_rounded),
      _Feature('AI Chat Assistant', false, true, Icons.smart_toy_rounded),
    ];

    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2235),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                    flex: 4,
                    child: Text('Feature',
                        style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5))),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text('Free',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [_gold, _goldDark]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Premium',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF2A3548)),
          ...features.asMap().entries.map((entry) {
            final i = entry.key;
            final f = entry.value;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(f.icon,
                                  color: _gold, size: 14),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(f.name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Center(child: _featureValue(f.freeValue, false)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Center(
                            child: _featureValue(f.premiumValue, true)),
                      ),
                    ],
                  ),
                ),
                if (i < features.length - 1)
                  const Divider(
                      height: 1, color: Color(0xFF2A3548), indent: 16),
              ],
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _featureValue(dynamic value, bool isPremiumCol) {
    if (value is bool) {
      return Icon(
        value ? Icons.check_circle_rounded : Icons.cancel_rounded,
        color: value
            ? (isPremiumCol ? _gold : Colors.white38)
            : Colors.white24,
        size: 20,
      );
    }
    return Text(
      value.toString(),
      style: TextStyle(
        color: isPremiumCol ? _gold : Colors.white54,
        fontSize: 11,
        fontWeight:
            isPremiumCol ? FontWeight.bold : FontWeight.normal,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildPayPalButton() {
    final buttonText = 'Pay with PayPal · $_paypalCurrency ${_paypalAmount.toStringAsFixed(2)}';
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: GestureDetector(
              onTap: _processingPayment ? null : _startPayPalCheckout,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _processingPayment
                        ? [Colors.grey.shade600, Colors.grey.shade700]
                        : [const Color(0xFF003087), const Color(0xFF009CDE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF003087).withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: _processingPayment
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            buttonText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Text(
              'Maybe later',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_rounded,
              color: Colors.white.withValues(alpha: 0.35), size: 14),
          const SizedBox(width: 6),
          Text(
            'Secured by PayPal · Auto-renews monthly',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyPremiumCard() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A5C4A), Color(0xFF2E9B78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A5C4A).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_rounded, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          const Text(
            'You\'re Premium! 🎉',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enjoy unlimited budgets, AI chat, full reports, and all premium features.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Back to App',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature {
  final String name;
  final dynamic freeValue;
  final dynamic premiumValue;
  final IconData icon;
  const _Feature(this.name, this.freeValue, this.premiumValue, this.icon);
}
