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
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: SelectedItemsSection(controller: controller),
                  ),
                ),
                const SizedBox(height: 18),
                ManualCodeSection(controller: controller),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_dropHovering,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                opacity: _dropHovering ? 1 : 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: kAccentCyan.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: kAccentCyanStrong.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_circle_outline_rounded,
                        size: 24,
                        color: kAccentCyanStrong,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Drop to add files',
                        style: driftSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kAccentCyanStrong,
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
        const SizedBox(height: 8),
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
    final icon =
        isFolder ? Icons.folder_outlined : Icons.insert_drive_file_outlined;

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
        const SizedBox(height: 10),
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
