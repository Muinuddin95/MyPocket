import 'package:flutter/material.dart';

class TourStep {
  final GlobalKey? targetKey;
  final String title;
  final String description;
  final double borderRadius;
  final bool isFullScreen;
  final IconData icon;

  TourStep({
    this.targetKey,
    required this.title,
    required this.description,
    this.borderRadius = 16.0,
    this.isFullScreen = false,
    this.icon = Icons.info_outline_rounded,
  });
}

class TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  final VoidCallback onCompleted;
  final VoidCallback onSkipped;
  final ValueChanged<int>? onStepChanged;

  const TourOverlay({
    super.key,
    required this.steps,
    required this.onCompleted,
    required this.onSkipped,
    this.onStepChanged,
  });

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStepIndex = 0;
  Rect? _highlightRect;
  bool _overlayVisible = false; // Only show overlay once rect is found

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateHighlightRect();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _calculateHighlightRect({int retries = 0}) {
    if (!mounted) return;
    if (_currentStepIndex >= widget.steps.length) return;

    final step = widget.steps[_currentStepIndex];

    // Full-screen step: show immediately with no highlight
    if (step.isFullScreen || step.targetKey == null) {
      if (mounted) {
        setState(() {
          _highlightRect = null;
          _overlayVisible = true;
        });
        if (!_animationController.isAnimating && !_animationController.isCompleted) {
          _animationController.forward();
        }
      }
      return;
    }

    final context = step.targetKey!.currentContext;
    final renderObj = context?.findRenderObject();

    if (context == null || renderObj == null || renderObj is! RenderBox || !renderObj.hasSize) {
      if (retries < 20) {
        // Retry every 100ms for up to 2 seconds
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _calculateHighlightRect(retries: retries + 1);
        });
        return;
      }
      // After 2 seconds, show tooltip card without any highlight overlay
      if (mounted) {
        setState(() {
          _highlightRect = null;
          _overlayVisible = true;
        });
        if (!_animationController.isAnimating && !_animationController.isCompleted) {
          _animationController.forward();
        }
      }
      return;
    }

    try {
      final position = renderObj.localToGlobal(Offset.zero);
      final size = renderObj.size;

      if (mounted) {
        setState(() {
          _highlightRect = Rect.fromLTWH(
            position.dx - 8,
            position.dy - 8,
            size.width + 16,
            size.height + 16,
          );
          _overlayVisible = true;
        });
        if (!_animationController.isAnimating && !_animationController.isCompleted) {
          _animationController.forward();
        }
      }
    } catch (_) {
      // On any error, show without highlight rather than crash
      if (mounted) {
        setState(() {
          _highlightRect = null;
          _overlayVisible = true;
        });
        if (!_animationController.isAnimating && !_animationController.isCompleted) {
          _animationController.forward();
        }
      }
    }
  }

  void _nextStep() {
    if (_currentStepIndex < widget.steps.length - 1) {
      _animationController.reverse().then((_) {
        if (!mounted) return;
        setState(() {
          _currentStepIndex++;
          _highlightRect = null;
          _overlayVisible = false; // Hide overlay while finding next widget
        });
        if (widget.onStepChanged != null) {
          widget.onStepChanged!(_currentStepIndex);
        }
        // Give the new tab/page time to render before measuring
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _calculateHighlightRect();
        });
      });
    } else {
      widget.onCompleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStepIndex >= widget.steps.length) return const SizedBox.shrink();

    final step = widget.steps[_currentStepIndex];
    final screenSize = MediaQuery.of(context).size;

    // Show nothing until the overlay is ready — this prevents the white screen
    if (!_overlayVisible) return const SizedBox.shrink();

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // ── Dark overlay with highlight cutout ──────────────────────────
          // Uses 4 containers instead of CustomPaint — immune to Impeller bugs
          if (!step.isFullScreen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _nextStep,
                child: _buildHighlightOverlay(screenSize),
              ),
            ),

          // Full black background for final congratulations step
          if (step.isFullScreen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _nextStep,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.75),
                ),
              ),
            ),

          // ── Skip button ─────────────────────────────────────────────────
          if (!step.isFullScreen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: SafeArea(
                child: GestureDetector(
                  onTap: widget.onSkipped,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A5C4A),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Skip Tour',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Tooltip card (dynamically positioned relative to highlight) ──
          _positionTooltip(
            SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: step.isFullScreen
                    ? _buildCongratulationsCard(step)
                    : _buildTooltipCard(step),
              ),
            ),
            screenSize,
            step.isFullScreen,
          ),
        ],
      ),
    );
  }

  Widget _positionTooltip(Widget tooltip, Size screenSize, bool isFullScreen) {
    if (isFullScreen || _highlightRect == null) {
      // Pin to bottom for full screen or fallback
      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          top: false,
          child: tooltip,
        ),
      );
    }

    final double holeTop = _highlightRect!.top;
    final double holeBottom = _highlightRect!.bottom;

    final double spaceAbove = holeTop;
    final double spaceBelow = screenSize.height - holeBottom;

    if (spaceAbove > spaceBelow) {
      // Place tooltip above the highlighted widget (e.g., bottom navigation tabs)
      return Positioned(
        bottom: (screenSize.height - holeTop) + 12.0,
        left: 0,
        right: 0,
        child: SafeArea(
          top: false,
          child: tooltip,
        ),
      );
    } else {
      // Place tooltip below the highlighted widget (e.g., top summary cards)
      return Positioned(
        top: holeBottom + 12.0,
        left: 0,
        right: 0,
        child: SafeArea(
          top: false,
          bottom: false,
          child: tooltip,
        ),
      );
    }
  }

  /// Builds the 4-block dark overlay with a transparent cutout.
  /// No CustomPaint = no Impeller rendering bugs = no white screen.
  Widget _buildHighlightOverlay(Size screenSize) {
    const overlayColor = Color(0xBF000000); // black at 75% opacity

    // If we don't have a rect yet, show nothing (no white, no grey)
    if (_highlightRect == null) {
      return const SizedBox.shrink();
    }

    final rect = _highlightRect!;

    return Stack(
      children: [
        // Top block
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: rect.top.clamp(0.0, screenSize.height),
          child: const ColoredBox(color: overlayColor),
        ),
        // Bottom block
        Positioned(
          top: rect.bottom.clamp(0.0, screenSize.height),
          left: 0,
          right: 0,
          bottom: 0,
          child: const ColoredBox(color: overlayColor),
        ),
        // Left block
        Positioned(
          top: rect.top.clamp(0.0, screenSize.height),
          left: 0,
          width: rect.left.clamp(0.0, screenSize.width),
          height: rect.height.clamp(0.0, screenSize.height),
          child: const ColoredBox(color: overlayColor),
        ),
        // Right block
        Positioned(
          top: rect.top.clamp(0.0, screenSize.height),
          left: rect.right.clamp(0.0, screenSize.width),
          right: 0,
          height: rect.height.clamp(0.0, screenSize.height),
          child: const ColoredBox(color: overlayColor),
        ),
        // Green glowing border around the highlighted widget
        Positioned(
          top: rect.top,
          left: rect.left,
          width: rect.width,
          height: rect.height,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF2E9B78),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E9B78).withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTooltipCard(TourStep step) {
    final nonFullSteps = widget.steps.where((s) => !s.isFullScreen).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF1A5C4A).withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress dots
          Row(
            children: List.generate(nonFullSteps, (i) {
              final isActive = i == _currentStepIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(right: 5),
                width: isActive ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF1A5C4A)
                      : const Color(0xFF1A5C4A).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),

          // Icon + Title
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A5C4A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  step.icon,
                  color: const Color(0xFF1A5C4A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  step.title,
                  style: const TextStyle(
                    color: Color(0xFF1A5C4A),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            step.description,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${_currentStepIndex + 1} of ${widget.steps.length}',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
              ),
              ElevatedButton(
                onPressed: _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A5C4A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _currentStepIndex == widget.steps.length - 2
                      ? 'Finish 🎉'
                      : 'Next →',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCongratulationsCard(TourStep step) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A5C4A), Color(0xFF2E9B78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A5C4A).withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.stars_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            step.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onCompleted,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1A5C4A),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                "Let's Go! 🚀",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
