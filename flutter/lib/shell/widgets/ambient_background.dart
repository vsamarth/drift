import 'package:flutter/material.dart';
import '../../theme/drift_theme.dart';

class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned(
              top: -100,
              right: -50,
              child: _GradientBlob(
                color: kAccentCyan.withValues(alpha: 0.05 + (_controller.value * 0.03)),
                scale: 1.0 + (_controller.value * 0.2),
              ),
            ),
            Positioned(
              bottom: 100,
              left: -80,
              child: _GradientBlob(
                color: kAccentWarm.withValues(alpha: 0.04 + (_controller.value * 0.04)),
                scale: 1.2 + (_controller.value * 0.1),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GradientBlob extends StatelessWidget {
  const _GradientBlob({required this.color, required this.scale});
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 400,
        height: 400,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
