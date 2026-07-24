// logo.dart
import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showText;

  const AppLogo({
    super.key,
    this.size = 200, // Default changed to 180
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Logo Image ──
        ClipRect(
          child: Align(
            alignment: Alignment.center,
            heightFactor: 0.55,
            widthFactor: 0.55,
            child: Image.asset(
              'assets/images/logo.png',
              width: size * 1.5,
              height: size * 1.5,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.pie_chart_outline_rounded,
                  color: Colors.white,
                  size: size * 0.4,
                ),
              ),
            ),
          ),
        ),
        if (showText) ...[
          const SizedBox(height: 8),
          const Text(
            'MyPocket',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36, // Bigger text
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Your personal finance companion',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 15, // Slightly bigger
            ),
          ),
        ],
      ],
    );
  }
}
