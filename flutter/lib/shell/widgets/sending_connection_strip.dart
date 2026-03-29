import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';

/// Laptop → phone metaphor with a dotted path and soft packets moving along it.
class SendingConnectionStrip extends StatefulWidget {
  const SendingConnectionStrip({
    super.key,
    required this.localLabel,
    this.animate = true,
  });

  final String localLabel;
  final bool animate;

  @override
  State<SendingConnectionStrip> createState() => _SendingConnectionStripState();
}

class _SendingConnectionStripState extends State<SendingConnectionStrip>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  static const double _laneHeight = 40;
  static const double _iconSize = 32;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 3400),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildStrip(double progress) {
    final captionStyle = driftSans(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: kMuted,
      letterSpacing: -0.1,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.laptop_mac_rounded,
                size: _iconSize,
                color: kInk.withValues(alpha: 0.88),
              ),
              const SizedBox(height: 6),
              Text(
                widget.localLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: captionStyle,
              ),
            ],
          ),
        ),
        Expanded(
          child: SizedBox(
            height: _laneHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, _laneHeight),
                  painter: _LaptopPhoneTransmitPainter(
                    progress: progress,
                    lineColor: kMuted.withValues(alpha: 0.3),
                    pulseColor: kAccentCyanStrong.withValues(alpha: 0.62),
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(
          width: 92,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smartphone_rounded,
                size: _iconSize,
                color: kInk.withValues(alpha: 0.88),
              ),
              const SizedBox(height: 6),
              Text(
                'Recipient',
                textAlign: TextAlign.center,
                style: captionStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return _buildStrip(0.41);
    }
    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, child) => _buildStrip(_controller!.value),
    );
  }
}

class _LaptopPhoneTransmitPainter extends CustomPainter {
  _LaptopPhoneTransmitPainter({
    required this.progress,
    required this.lineColor,
    required this.pulseColor,
  });

  final double progress;
  final Color lineColor;
  final Color pulseColor;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final w = size.width;
    if (w <= 0) {
      return;
    }

    final track = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    for (double x = 0; x < w; x += 5) {
      canvas.drawCircle(Offset(x + 0.5, y), 0.85, track);
    }

    const margin = 8.0;
    final travel = (w - 2 * margin).clamp(0.0, double.infinity);
    if (travel <= 0) {
      return;
    }

    const packetCount = 3;
    for (var i = 0; i < packetCount; i++) {
      final t = ((progress + i / packetCount) % 1.0 + 1.0) % 1.0;
      final px = margin + t * travel;
      final headBoost = (1.0 - ((t - 0.15).abs() * 1.1).clamp(0.0, 1.0)) * 0.25;
      final alpha = (0.22 + 0.5 * headBoost + 0.26 * (1 - i / packetCount))
          .clamp(0.12, 0.85);
      final r = 2.9 - i * 0.42;

      canvas.drawCircle(
        Offset(px, y),
        r + 3.2,
        Paint()..color = pulseColor.withValues(alpha: alpha * 0.12),
      );
      canvas.drawCircle(
        Offset(px, y),
        r,
        Paint()
          ..color = pulseColor.withValues(alpha: alpha)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LaptopPhoneTransmitPainter old) =>
      old.progress != progress ||
      old.lineColor != lineColor ||
      old.pulseColor != pulseColor;
}
