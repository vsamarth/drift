import 'dart:math' show max, min;

import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';

/// How the lane between laptop and phone should behave.
enum SendingStripMode {
  /// Still handshaking: dotted lane + looping “packets”.
  looping,

  /// Waiting for the recipient to accept: same **bouncing** lane as [looping].
  waitingOnRecipient,

  /// Payload streaming: **determinate** bar grows along the lane (`transferProgress` 0…1).
  transferring,
}

/// Laptop → phone metaphor with a dotted path between devices.
///
/// Use [SendingStripMode.looping] while negotiating and [SendingStripMode.waitingOnRecipient]
/// while waiting for acceptance—both show the looping “packets” when [animate] is true.
/// Use [SendingStripMode.transferring] with [transferProgress] while bytes are moving.
class SendingConnectionStrip extends StatefulWidget {
  const SendingConnectionStrip({
    super.key,
    required this.localLabel,
    required this.localDeviceType,
    required this.remoteLabel,
    this.animate = true,
    required this.mode,
    this.remoteDeviceType,
    this.transferProgress = 0.0,
  });

  final String localLabel;
  /// `"phone"` or `"laptop"`.
  final String localDeviceType;

  /// Shown under the phone icon (e.g. the receiver’s device name).
  final String remoteLabel;
  final bool animate;

  final SendingStripMode mode;

  /// `"phone"` or `"laptop"`.
  /// When null (early phases), defaults to `"phone"`.
  final String? remoteDeviceType;

  /// Meaningful when [mode] is [SendingStripMode.transferring].
  final double transferProgress;

  @override
  State<SendingConnectionStrip> createState() => _SendingConnectionStripState();
}

class _SendingConnectionStripState extends State<SendingConnectionStrip>
    with SingleTickerProviderStateMixin {
  AnimationController? _loopController;

  static const double _laneHeight = 40;
  static const double _iconSize = 32;

  bool get _needsLoop =>
      widget.animate &&
      (widget.mode == SendingStripMode.looping ||
          widget.mode == SendingStripMode.waitingOnRecipient);

  void _syncLoopController() {
    if (!_needsLoop) {
      _loopController?.dispose();
      _loopController = null;
      return;
    }
    _loopController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat();
  }

  @override
  void initState() {
    super.initState();
    _syncLoopController();
  }

  @override
  void didUpdateWidget(SendingConnectionStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode || oldWidget.animate != widget.animate) {
      _syncLoopController();
    }
  }

  @override
  void dispose() {
    _loopController?.dispose();
    super.dispose();
  }

  Widget _buildStrip(double loopPhase) {
    final captionStyle = driftSans(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: kMuted,
      letterSpacing: -0.1,
    );

    final style = switch (widget.mode) {
      SendingStripMode.looping => _LaneStyle.looping,
      SendingStripMode.waitingOnRecipient => _LaneStyle.looping,
      SendingStripMode.transferring => _LaneStyle.transfer,
    };

    final t = widget.mode == SendingStripMode.transferring
        ? widget.transferProgress.clamp(0.0, 1.0)
        : 0.0;

    final localIsPhone = widget.localDeviceType.toLowerCase() == 'phone';
    final remoteIsPhone =
        (widget.remoteDeviceType ?? 'phone').toLowerCase() == 'phone';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                localIsPhone ? Icons.smartphone_rounded : Icons.laptop_mac_rounded,
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
                  painter: _LaptopPhoneLanePainter(
                    loopPhase: loopPhase,
                    style: style,
                    transferProgress: t,
                    lineColor: kMuted.withValues(alpha: 0.3),
                    accentColor: kAccentCyanStrong,
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
                remoteIsPhone ? Icons.smartphone_rounded : Icons.laptop_mac_rounded,
                size: _iconSize,
                color: kInk.withValues(alpha: 0.88),
              ),
              const SizedBox(height: 6),
              Text(
                widget.remoteLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    if (_needsLoop) {
      return AnimatedBuilder(
        animation: _loopController!,
        builder: (context, child) => _buildStrip(_loopController!.value),
      );
    }
    final loopPhase = !widget.animate &&
            (widget.mode == SendingStripMode.looping ||
                widget.mode == SendingStripMode.waitingOnRecipient)
        ? 0.41
        : 0.0;
    return _buildStrip(loopPhase);
  }
}

enum _LaneStyle { looping, transfer }

class _LaptopPhoneLanePainter extends CustomPainter {
  _LaptopPhoneLanePainter({
    required this.loopPhase,
    required this.style,
    required this.transferProgress,
    required this.lineColor,
    required this.accentColor,
  });

  final double loopPhase;
  final _LaneStyle style;
  final double transferProgress;
  final Color lineColor;
  final Color accentColor;

  static const double _margin = 8;

  void _paintDots(Canvas canvas, double y, double w) {
    final dot = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    for (double x = 0; x < w; x += 5) {
      canvas.drawCircle(Offset(x + 0.5, y), 0.85, dot);
    }
  }

  void _paintLoopingPackets(
    Canvas canvas,
    double y,
    double w,
    double travel,
    double margin,
  ) {
    const packetCount = 3;
    final pulse = accentColor.withValues(alpha: 0.62);
    for (var i = 0; i < packetCount; i++) {
      final t = ((loopPhase + i / packetCount) % 1.0 + 1.0) % 1.0;
      final px = margin + t * travel;
      final headBoost =
          (1.0 - ((t - 0.15).abs() * 1.1).clamp(0.0, 1.0)) * 0.25;
      final alpha = (0.22 + 0.5 * headBoost + 0.26 * (1 - i / packetCount))
          .clamp(0.12, 0.85);
      final r = 2.9 - i * 0.42;

      canvas.drawCircle(
        Offset(px, y),
        r + 3.2,
        Paint()..color = pulse.withValues(alpha: alpha * 0.12),
      );
      canvas.drawCircle(
        Offset(px, y),
        r,
        Paint()
          ..color = pulse.withValues(alpha: alpha)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _paintTransferFill(
    Canvas canvas,
    double y,
    double travel,
    double margin,
  ) {
    if (travel <= 0 || transferProgress <= 0) {
      return;
    }
    final fillW =
        max(3.0, min(transferProgress * travel, travel));
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(margin, y - 2.5, fillW, 5),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = accentColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.fill,
    );

    final headX = margin + fillW;
    canvas.drawCircle(
      Offset(headX, y),
      4.2,
      Paint()..color = accentColor.withValues(alpha: 0.12),
    );
    canvas.drawCircle(
      Offset(headX, y),
      3.1,
      Paint()
        ..color = accentColor.withValues(alpha: 0.92)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final w = size.width;
    if (w <= 0) {
      return;
    }

    _paintDots(canvas, y, w);

    final travel = (w - 2 * _margin).clamp(0.0, double.infinity);
    if (travel <= 0) {
      return;
    }

    switch (style) {
      case _LaneStyle.looping:
        _paintLoopingPackets(canvas, y, w, travel, _margin);
      case _LaneStyle.transfer:
        _paintTransferFill(canvas, y, travel, _margin);
    }
  }

  @override
  bool shouldRepaint(covariant _LaptopPhoneLanePainter old) =>
      old.loopPhase != loopPhase ||
      old.style != style ||
      old.transferProgress != transferProgress ||
      old.lineColor != lineColor ||
      old.accentColor != accentColor;
}
