import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';
import 'receive_code_field.dart';

class SendSelectedCard extends StatelessWidget {
  const SendSelectedCard({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    return SendScreen(controller: controller);
  }
}

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.controller});

  final DriftController controller;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  bool _dropHovering = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dropHovering = true),
      onDragExited: (_) => setState(() => _dropHovering = false),
      onDragDone: (details) {
        setState(() => _dropHovering = false);
        final paths = details.files
            .map((file) => file.path)
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
        controller.appendDroppedSendItems(paths);
      },
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: _dropHovering ? kSurface.withValues(alpha: 0.16) : null,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _dropHovering
                    ? kBorder.withValues(alpha: 0.88)
                    : Colors.transparent,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectedItemsSection(controller: controller),
                  const SizedBox(height: 34),
                  ManualCodeSection(controller: controller),
                ],
              ),
            ),
          ),
          IgnorePointer(
            ignoring: !_dropHovering,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              opacity: _dropHovering ? 1 : 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.52),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFFD7D7D7),
                              width: 1.2,
                            ),
                          ),
                          child: CustomPaint(
                            painter: _DropOverlayBorderPainter(),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF8F8F8,
                          ).withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2E2E2)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: Color(0xFF49B36C),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Drop to add files',
                                  style: driftSans(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w600,
                                    color: kInk,
                                    letterSpacing: -0.35,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'They’ll be appended to this transfer',
                                  style: driftSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: kMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropOverlayBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final insetRect = rect.deflate(10);
    final rrect = RRect.fromRectAndRadius(insetRect, const Radius.circular(18));
    final paint = Paint()
      ..color = const Color(0xFFCFCFCF)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const dashWidth = 9.0;
    const dashGap = 7.0;
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SelectedItemsSection extends StatelessWidget {
  const SelectedItemsSection({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final isInspecting = controller.isInspectingSendItems;
    final items = controller.visibleSendItems;
    final hiddenItemCount = controller.hiddenSendItemCount;
    final count = controller.sendItems.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isInspecting && count == 0
              ? 'Inspecting files'
              : count == 1
              ? '1 item'
              : '$count items',
          style: driftSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: kMuted,
          ),
        ),
        const SizedBox(height: 10),
        if (isInspecting && count == 0) ...[
          const _SelectedItemSkeleton(),
          const Divider(height: 1, thickness: 1, indent: 36),
          const _SelectedItemSkeleton(),
          const Divider(height: 1, thickness: 1, indent: 36),
          const _SelectedItemSkeleton(),
        ] else ...[
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, indent: 36),
            SelectedItemRow(item: items[i]),
          ],
          if (hiddenItemCount > 0) ...[
            const Divider(height: 1, thickness: 1, indent: 36),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '+$hiddenItemCount more ${hiddenItemCount == 1 ? 'item' : 'items'}',
                style: driftSans(fontSize: 12.5, color: kMuted),
              ),
            ),
          ],
        ],
        if (isInspecting && count > 0) ...[
          const SizedBox(height: 10),
          Text(
            'Inspecting added files...',
            style: driftSans(fontSize: 12.5, color: kMuted),
          ),
          const SizedBox(height: 10),
          const _SelectedItemSkeleton(),
        ],
      ],
    );
  }
}

class SelectedItemRow extends StatelessWidget {
  const SelectedItemRow({super.key, required this.item});

  final TransferItemViewData item;

  @override
  Widget build(BuildContext context) {
    final isFolder = item.kind == TransferItemKind.folder;
    final icon = isFolder
        ? Icons.folder_outlined
        : Icons.insert_drive_file_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: kMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.name,
              style: driftSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kInk,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(item.size, style: driftSans(fontSize: 12.5, color: kMuted)),
        ],
      ),
    );
  }
}

class _SelectedItemSkeleton extends StatelessWidget {
  const _SelectedItemSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 54,
            height: 12,
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

class ManualCodeSection extends StatelessWidget {
  const ManualCodeSection({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Or enter a code',
          style: driftSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: kInk.withValues(alpha: 0.56),
          ),
        ),
        const SizedBox(height: 14),
        ReceiveCodeField(
          fieldKey: const ValueKey<String>('send-code-field'),
          code: controller.sendDestinationCode,
          onChanged: controller.updateSendDestinationCode,
          understated: true,
        ),
      ],
    );
  }
}
