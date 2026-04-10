import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';
import '../../application/identity.dart';
import '../../application/manifest.dart';
import '../../application/state.dart';

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.animate,
    required this.onAccept,
    required this.onDecline,
  });

  final TransferIncomingOffer offer;
  final bool animate;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final senderName = _displaySender(offer.sender.displayName);
    final itemCount = offer.manifest.itemCount;
    final totalSize = formatBytes(offer.manifest.totalSizeBytes);
    final itemSummary = '${_fileCountLabel(itemCount)} · $totalSize';

    return SizedBox.expand(
      child: TransferFlowLayout(
        statusLabel: 'Incoming',
        statusColor: const Color(0xFF4B98AA),
        title: senderName,
        subtitle: _subtitle(itemCount, totalSize),
        explainer: Text(
          'Review the files and accept only if you trust the sender.',
          style: driftSans(fontSize: 12, color: kSubtle, height: 1.4),
        ),
        illustration: SendingConnectionStrip(
          localLabel: senderName,
          localDeviceType: _deviceTypeLabel(offer.sender.deviceType),
          remoteLabel: 'Drift',
          remoteDeviceType: 'laptop',
          animate: animate,
          mode: SendingStripMode.waitingOnRecipient,
        ),
        manifest: PreviewTable(
          items: offer.manifest.items,
          footerSummary: itemSummary,
        ),
        footer: Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4A8E9E),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Save to ${offer.saveRootLabel}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: TextButton(
                onPressed: onDecline,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFCC3333),
                  backgroundColor: const Color(0xFFCC3333).withValues(
                    alpha: 0.08,
                  ),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: const Color(0xFFCC3333).withValues(alpha: 0.15),
                    ),
                  ),
                ),
                child: const Text('Decline'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _displaySender(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Unknown sender' : trimmed;
}

String _subtitle(int itemCount, String totalSize) {
  final fileWord = itemCount == 1 ? 'file' : 'files';
  return 'wants to send you $itemCount $fileWord ($totalSize).';
}

String _fileCountLabel(int itemCount) {
  return itemCount == 1 ? '1 file' : '$itemCount files';
}

String _deviceTypeLabel(DeviceType type) {
  return switch (type) {
    DeviceType.phone => 'phone',
    DeviceType.laptop => 'laptop',
  };
}

String formatBytes(BigInt bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
  final formatted = value.toStringAsFixed(decimals);
  return '$formatted ${units[unitIndex]}';
}

class TransferFlowLayout extends StatelessWidget {
  const TransferFlowLayout({
    super.key,
    required this.statusLabel,
    required this.statusColor,
    required this.title,
    required this.subtitle,
    this.explainer,
    required this.illustration,
    this.manifest,
    required this.footer,
  });

  final String statusLabel;
  final Color statusColor;
  final String title;
  final String subtitle;
  final Widget? explainer;
  final Widget illustration;
  final Widget? manifest;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusLabel,
                            style: driftSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: driftSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  subtitle,
                  style: driftSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: kMuted,
                    height: 1.4,
                  ),
                ),
                if (explainer != null) ...[
                  const SizedBox(height: 12),
                  explainer!,
                ],
                const SizedBox(height: 20),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 100),
                    child: illustration,
                  ),
                ),
                const SizedBox(height: 24),
                if (manifest != null) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: kSurface2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kBorder.withValues(alpha: 0.8)),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                          child: manifest!,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: kBg,
            border: Border(
              top: BorderSide(color: kBorder.withValues(alpha: 0.5)),
            ),
          ),
          child: footer,
        ),
      ],
    );
  }
}

class PreviewTable extends StatelessWidget {
  const PreviewTable({
    super.key,
    required this.items,
    required this.footerSummary,
  });

  final List<TransferManifestItem> items;
  final String footerSummary;

  static final _divider = Divider(
    height: 1,
    thickness: 1,
    color: kBorder.withValues(alpha: 0.55),
  );

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No files', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    final headerStyle = driftSans(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: kInk.withValues(alpha: 0.8),
      letterSpacing: 0.15,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const SizedBox(width: 28),
              Expanded(child: Text('Name', style: headerStyle)),
              SizedBox(
                width: 76,
                child: Text(
                  'Size',
                  textAlign: TextAlign.right,
                  style: headerStyle,
                ),
              ),
            ],
          ),
        ),
        _divider,
        const SizedBox(height: 10),
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) _divider,
          _PreviewTableRow(item: items[i]),
        ],
        if (items.length > 1) ...[
          _divider,
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Row(
              children: [
                const SizedBox(width: 28),
                Expanded(
                  child: Text(
                    footerSummary,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: driftSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: kMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PreviewTableRow extends StatelessWidget {
  const _PreviewTableRow({required this.item});

  final TransferManifestItem item;

  @override
  Widget build(BuildContext context) {
    final name = _displayFileName(item.path);
    final sizeLabel = formatBytes(item.sizeBytes);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 28,
            child: Icon(Icons.insert_drive_file_outlined, size: 18, color: kMuted),
          ),
          Expanded(
            child: Tooltip(
              message: name,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: driftSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: kInk,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 116,
            child: Text(
              sizeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: kMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _displayFileName(String path) {
  final segments = path.split('/')..removeWhere((segment) => segment.isEmpty);
  return segments.isEmpty ? path : segments.last;
}

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
  final String localDeviceType;
  final String remoteLabel;
  final bool animate;
  final SendingStripMode mode;
  final String? remoteDeviceType;
  final double transferProgress;

  @override
  State<SendingConnectionStrip> createState() => _SendingConnectionStripState();
}

class _SendingConnectionStripState extends State<SendingConnectionStrip>
    with TickerProviderStateMixin {
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
      color: kInk.withValues(alpha: 0.9),
      height: 1.2,
      letterSpacing: -0.1,
    );

    final localIsPhone = widget.localDeviceType.toLowerCase() == 'phone';
    final remoteIsPhone =
        (widget.remoteDeviceType ?? 'phone').toLowerCase() == 'phone';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 100,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                localIsPhone
                    ? Icons.smartphone_rounded
                    : Icons.laptop_mac_rounded,
                size: _iconSize,
                color: kInk.withValues(alpha: 0.88),
              ),
              const SizedBox(height: 6),
              Tooltip(
                message: widget.localLabel,
                child: Text(
                  widget.localLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: captionStyle,
                ),
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
                    lineColor: kBorder.withValues(alpha: 0.65),
                    accentColor: kAccentCyan,
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(
          width: 100,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                remoteIsPhone
                    ? Icons.smartphone_rounded
                    : Icons.laptop_mac_rounded,
                size: _iconSize,
                color: kInk.withValues(alpha: 0.88),
              ),
              const SizedBox(height: 6),
              Tooltip(
                message: widget.remoteLabel,
                child: Text(
                  widget.remoteLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: captionStyle,
                ),
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
    final loopPhase =
        !widget.animate &&
            (widget.mode == SendingStripMode.looping ||
                widget.mode == SendingStripMode.waitingOnRecipient)
        ? 0.41
        : 0.0;
    return _buildStrip(loopPhase);
  }
}

enum SendingStripMode { looping, waitingOnRecipient, transferring }

class _LaptopPhoneLanePainter extends CustomPainter {
  _LaptopPhoneLanePainter({
    required this.loopPhase,
    required this.lineColor,
    required this.accentColor,
  });

  final double loopPhase;
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
    final pulse = accentColor.withValues(alpha: 0.56);
    for (var i = 0; i < packetCount; i++) {
      final t = ((loopPhase + i / packetCount) % 1.0 + 1.0) % 1.0;
      final px = margin + t * travel;
      final headBoost = (1.0 - ((t - 0.15).abs() * 1.1).clamp(0.0, 1.0)) * 0.25;
      final alpha =
          (0.2 + 0.42 * headBoost + 0.22 * (1 - i / packetCount)).clamp(
            0.1,
            0.72,
          );
      final radius = 2.9 - i * 0.42;

      canvas.drawCircle(
        Offset(px, y),
        radius + 3.2,
        Paint()..color = pulse.withValues(alpha: alpha * 0.1),
      );
      canvas.drawCircle(
        Offset(px, y),
        radius,
        Paint()
          ..color = pulse.withValues(alpha: alpha)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final laneY = size.height / 2;
    final travel = max(size.width - _margin * 2, 1.0);
    final dotColor = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    _paintDots(canvas, laneY, size.width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_margin, laneY - 1.3, travel, 2.6),
        const Radius.circular(2),
      ),
      Paint()..color = lineColor.withValues(alpha: 0.3),
    );
    _paintLoopingPackets(canvas, laneY, size.width, travel, _margin);

    final dotRadius = 1.4;
    for (var i = 0; i <= 6; i++) {
      final x = _margin + (travel / 6) * i;
      canvas.drawCircle(
        Offset(x, laneY),
        dotRadius,
        dotColor,
      );
    }
    canvas.drawCircle(
      Offset(_margin + travel / 2, laneY),
      2.0,
      Paint()..color = accentColor.withValues(alpha: 0.05),
    );
  }

  @override
  bool shouldRepaint(covariant _LaptopPhoneLanePainter oldDelegate) {
    return oldDelegate.loopPhase != loopPhase ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.accentColor != accentColor;
  }
}
