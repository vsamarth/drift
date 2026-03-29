import 'package:flutter/material.dart';

/// Dashed rounded rect behind drop-zone content.
class DropZoneBorderPainter extends CustomPainter {
  const DropZoneBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final half = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(half, half, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var drawing = true;
      while (distance < metric.length) {
        final segLen = drawing ? dashLength : gapLength;
        final end = (distance + segLen).clamp(0.0, metric.length);
        if (drawing) {
          canvas.drawPath(metric.extractPath(distance, end), paint);
        }
        distance = end;
        drawing = !drawing;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DropZoneBorderPainter old) =>
      color != old.color ||
      strokeWidth != old.strokeWidth ||
      dashLength != old.dashLength ||
      gapLength != old.gapLength ||
      radius != old.radius;
}
