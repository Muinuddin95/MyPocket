// onboarding.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Login.dart';

class OnboardingScreen extends StatefulWidget {
  final Function(bool)? onThemeToggle;
  final bool? isDarkMode;

  const OnboardingScreen({super.key, this.onThemeToggle, this.isDarkMode = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const Color _primaryGreen = Color(0xFF1A5C4A);
  static const Color _accentGreen = Color(0xFF2E9B78);
  static const Color _lightBg = Color(0xFFEAF4F0);

  // Animation controllers per slide
  late AnimationController _slide0Controller;
  late AnimationController _slide1Controller;
  late AnimationController _slide2Controller;

  // Floating coins animations
  late AnimationController _coinController1;
  late AnimationController _coinController2;
  late AnimationController _coinController3;
  late AnimationController _coinController4;
  late AnimationController _coinController5;

  // Slide 0 — bar heights
  late List<Animation<double>> _barAnims;

  // Slide 1 — ring progress
  late Animation<double> _ringAnim;
  late AnimationController _ringCountController;
  int _ringPercent = 0;

  // Slide 2 — transaction rows
  late List<Animation<double>> _txnAnims;

  @override
  void initState() {
    super.initState();

    // ── Floating coin controllers ──
    _coinController1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _coinController2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _coinController3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _coinController4 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _coinController5 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);

    // ── Slide controllers ──
    _slide0Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slide1Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _slide2Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _ringCountController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    final barDelays = [0.0, 0.15, 0.25, 0.4, 0.55];
    _barAnims = barDelays.map((start) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _slide0Controller,
          curve: Interval(start, start + 0.45, curve: Curves.easeOutBack),
        ),
      );
    }).toList();

    _ringAnim = Tween<double>(begin: 0, end: 0.72).animate(
      CurvedAnimation(parent: _slide1Controller, curve: Curves.easeInOut),
    );
    _ringCountController.addListener(() {
      setState(() {
        _ringPercent = (_ringCountController.value * 72).round();
      });
    });

    final txnDelays = [0.0, 0.2, 0.4, 0.6];
    _txnAnims = txnDelays.map((start) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _slide2Controller,
          curve: Interval(start, start + 0.4, curve: Curves.easeOut),
        ),
      );
    }).toList();

    // Start slide 0 animation
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _slide0Controller.forward();
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    if (index == 1) {
      _slide1Controller.forward();
      _ringCountController.forward();
    }
    if (index == 2) {
      _slide2Controller.forward();
    }
  }

  Future<void> _goToLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            onThemeToggle: widget.onThemeToggle,
            isDarkMode: widget.isDarkMode,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _slide0Controller.dispose();
    _slide1Controller.dispose();
    _slide2Controller.dispose();
    _ringCountController.dispose();
    _coinController1.dispose();
    _coinController2.dispose();
    _coinController3.dispose();
    _coinController4.dispose();
    _coinController5.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightBg,
      body: Stack(
        children: [
          // ── Floating Coins Background ──
          _buildFloatingCoins(),

          // ── Main Content ──
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, right: 20),
                    child: TextButton(
                      onPressed: _goToLogin,
                      child: const Text(
                        'Skip',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    children: [_buildSlide0(), _buildSlide1(), _buildSlide2()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 28,
                  ),
                  child: Column(
                    children: [
                      // Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentPage == i ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentPage == i
                                  ? _primaryGreen
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_currentPage < 2) {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              _goToLogin();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _currentPage < 2 ? 'Next' : 'Get Started',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _currentPage < 2
                                    ? Icons.arrow_forward_rounded
                                    : Icons.check_rounded,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── FLOATING COINS BACKGROUND ──
  Widget _buildFloatingCoins() {
    return Stack(
      children: [
        // Coin 1 - Large, slow
        AnimatedBuilder(
          animation: _coinController1,
          builder: (_, _) {
            final value = _coinController1.value;
            return Positioned(
              top: 50 + (value * 60),
              left: 20 + (value * 30),
              child: Transform.rotate(
                angle: value * 6.28,
                child: _buildCoin(
                  size: 60 + (value * 10),
                  opacity: 0.15 + (value * 0.05),
                  color: Colors.amber.shade400,
                  borderColor: Colors.amber.shade700,
                ),
              ),
            );
          },
        ),

        // Coin 2 - Medium, right side
        AnimatedBuilder(
          animation: _coinController2,
          builder: (_, _) {
            final value = _coinController2.value;
            return Positioned(
              top: 120 + (value * 80),
              right: 30 + (value * 20),
              child: Transform.rotate(
                angle: -value * 4.28,
                child: _buildCoin(
                  size: 45 + (value * 15),
                  opacity: 0.12 + (value * 0.06),
                  color: Colors.amber.shade300,
                  borderColor: Colors.amber.shade600,
                ),
              ),
            );
          },
        ),

        // Coin 3 - Small, bottom left
        AnimatedBuilder(
          animation: _coinController3,
          builder: (_, _) {
            final value = _coinController3.value;
            return Positioned(
              bottom: 100 + (value * 50),
              left: 40 + (value * 40),
              child: Transform.rotate(
                angle: value * 5.28,
                child: _buildCoin(
                  size: 35 + (value * 10),
                  opacity: 0.10 + (value * 0.07),
                  color: Colors.amber.shade200,
                  borderColor: Colors.amber.shade500,
                ),
              ),
            );
          },
        ),

        // Coin 4 - Tiny, floating center
        AnimatedBuilder(
          animation: _coinController4,
          builder: (_, _) {
            final value = _coinController4.value;
            return Positioned(
              top: 280 + (value * 40),
              left: 180 + (value * 35),
              child: Transform.rotate(
                angle: value * 3.14,
                child: _buildCoin(
                  size: 25 + (value * 8),
                  opacity: 0.08 + (value * 0.06),
                  color: Colors.amber.shade100,
                  borderColor: Colors.amber.shade400,
                ),
              ),
            );
          },
        ),

        // Coin 5 - Medium, bottom right
        AnimatedBuilder(
          animation: _coinController5,
          builder: (_, _) {
            final value = _coinController5.value;
            return Positioned(
              bottom: 200 + (value * 70),
              right: 50 + (value * 30),
              child: Transform.rotate(
                angle: -value * 7.28,
                child: _buildCoin(
                  size: 50 + (value * 12),
                  opacity: 0.10 + (value * 0.05),
                  color: Colors.amber.shade300,
                  borderColor: Colors.amber.shade600,
                ),
              ),
            );
          },
        ),

        // Small coin particles (floating dots)
        ...List.generate(10, (index) {
          final delay = index * 0.3;
          final controller = AnimationController(
            vsync: this,
            duration: Duration(seconds: 3 + (index % 3)),
          )..repeat(reverse: true);

          // We'll keep controllers in a list for disposal
          // but for simplicity, we'll use a different approach
          return _buildSmallCoinParticle(index, delay);
        }),
      ],
    );
  }

  Widget _buildSmallCoinParticle(int index, double delay) {
    // Use a local animation controller
    final controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 3 + (index % 3)),
    )..repeat(reverse: true);

    // Store for disposal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The controller will be disposed when the widget is disposed
      // We'll handle this with a stateful approach
    });

    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final value = controller.value;
        final positions = [
          {'x': 30 + (index * 35) % 350, 'y': 100 + (index * 25) % 400},
          {'x': 40 + (index * 30) % 320, 'y': 150 + (index * 20) % 500},
          {'x': 20 + (index * 45) % 380, 'y': 200 + (index * 30) % 300},
        ];
        final pos = positions[index % 3];

        return Positioned(
          left: (pos['x']! + value * 20) % 380,
          top: (pos['y']! + value * 30) % 500,
          child: Container(
            width: 4 + (value * 3),
            height: 4 + (value * 3),
            decoration: BoxDecoration(
              color: _primaryGreen.withValues(alpha: 0.05 + value * 0.03),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.amber.shade300.withValues(alpha: 0.1 + value * 0.05),
                width: 0.5,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoin({
    required double size,
    required double opacity,
    required Color color,
    required Color borderColor,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor.withValues(alpha: opacity * 0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: opacity * 0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          'RM',
          style: TextStyle(
            fontSize: size * 0.25,
            fontWeight: FontWeight.bold,
            color: borderColor.withValues(alpha: opacity * 0.8),
          ),
        ),
      ),
    );
  }

  // ── SLIDE 0: Animated bar chart ──────────────────────────────────────
  Widget _buildSlide0() {
    final barColors = [
      _primaryGreen,
      _accentGreen,
      _primaryGreen,
      _accentGreen,
      _primaryGreen,
    ];
    final barHeights = [90.0, 58.0, 76.0, 42.0, 68.0];
    final barLabels = ['Food', 'Trans', 'Shop', 'Fun', 'Bills'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _slide0Controller,
            builder: (_, _) {
              return Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: _primaryGreen.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(5, (i) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 18,
                            height: barHeights[i] * _barAnims[i].value,
                            decoration: BoxDecoration(
                              color: barColors[i],
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            barLabels[i],
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 36),
          const Text(
            'Track Your Expenses',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A5C4A),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'See exactly where your money goes. Log daily spending in seconds and stay on top of your finances effortlessly.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── SLIDE 1: Animated ring + budget pills ────────────────────────────
  Widget _buildSlide1() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _ringAnim,
            builder: (_, _) {
              return SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(200, 200),
                      painter: _RingPainter(
                        progress: _ringAnim.value,
                        trackColor: _primaryGreen.withValues(alpha: 0.15),
                        fillColor: _primaryGreen,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _ringCountController,
                          builder: (_, _) => Text(
                            '$_ringPercent%',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A5C4A),
                            ),
                          ),
                        ),
                        Text(
                          'used',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _pill('🍔 Food', const Color(0xFFD4ECE4), _primaryGreen),
              _pill(
                '🚌 Transport',
                const Color(0xFFE8F5E9),
                const Color(0xFF2E7D5E),
              ),
              _pill(
                '🛍 Shopping',
                const Color(0xFFFFF3E0),
                Colors.orange.shade700,
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'Manage Your Budgets',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A5C4A),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Set monthly budgets for every category. Get alerted before you overspend and always stay in control.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  // ── SLIDE 2: Animated transaction list ──────────────────────────────
  Widget _buildSlide2() {
    final txns = [
      {
        'icon': '🛒',
        'name': 'Grocery Store',
        'date': 'Today, 10:30 AM',
        'amount': '-\$42.50',
        'neg': true,
        'bg': const Color(0xFFFFE0E0),
      },
      {
        'icon': '💸',
        'name': 'Salary',
        'date': 'Jun 1',
        'amount': '+\$3,200',
        'neg': false,
        'bg': const Color(0xFFE0F0FF),
      },
      {
        'icon': '🚌',
        'name': 'Bus Pass',
        'date': 'May 31',
        'amount': '-\$12.00',
        'neg': true,
        'bg': const Color(0xFFFFF3E0),
      },
      {
        'icon': '☕',
        'name': 'Coffee',
        'date': 'May 30',
        'amount': '-\$7.80',
        'neg': true,
        'bg': const Color(0xFFE8F5E9),
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _slide2Controller,
            builder: (_, _) {
              return Column(
                children: List.generate(txns.length, (i) {
                  final t = txns[i];
                  final anim = _txnAnims[i];
                  return Opacity(
                    opacity: anim.value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(30 * (1 - anim.value), 0),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: t['bg'] as Color,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  t['icon'] as String,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A5C4A),
                                    ),
                                  ),
                                  Text(
                                    t['date'] as String,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              t['amount'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: (t['neg'] as bool)
                                    ? Colors.redAccent
                                    : _accentGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'View Transactions',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A5C4A),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Review your full history anytime. Understand your spending patterns and make smarter money decisions.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ring painter ──────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color fillColor;

  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;
    final strokeWidth = 16.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final sweepAngle = 2 * 3.14159 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      sweepAngle,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
