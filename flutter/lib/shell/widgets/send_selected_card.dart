import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
import '../../state/drift_app_state.dart';
import '../../state/drift_providers.dart';
import 'receive_code_field.dart';

class SendSelectedCard extends ConsumerStatefulWidget {
  const SendSelectedCard({super.key});

  @override
  ConsumerState<SendSelectedCard> createState() => _SendSelectedCardState();
}

class _SendSelectedCardState extends ConsumerState<SendSelectedCard> {
  bool _dropHovering = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);

    final canSend = state.sendItems.isNotEmpty &&
        !state.isInspectingSendItems &&
        (state.selectedSendDestination != null ||
            state.sendDestinationCode.length == 6);

    return DropTarget(
      onDragEntered: (_) => setState(() => _dropHovering = true),
      onDragExited: (_) => setState(() => _dropHovering = false),
      onDragDone: (details) {
        setState(() => _dropHovering = false);
        final paths = details.files
            .map((file) => file.path)
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
        notifier.appendDroppedSendItems(paths);
      },
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SelectedItemsSection(),
                      const SizedBox(height: 24),
                      const NearbyDevicesSection(),
                      const SizedBox(height: 32),
                      const ManualCodeSection(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // Sticky Footer
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: BoxDecoration(
                  color: kBg,
                  border: Border(top: BorderSide(color: kBorder.withValues(alpha: 0.5))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: canSend ? notifier.startSend : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4A8E9E), // Slightly darker cyan
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF4A8E9E).withValues(alpha: 0.4),
                          disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Drop Overlay
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_dropHovering,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                opacity: _dropHovering ? 1 : 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: kAccentCyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: kAccentCyanStrong.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_circle_outline_rounded,
                        size: 32,
                        color: kAccentCyanStrong,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Drop to add files',
                        style: driftSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
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

class SelectedItemsSection extends ConsumerStatefulWidget {
  const SelectedItemsSection({super.key});

  @override
  ConsumerState<SelectedItemsSection> createState() =>
      _SelectedItemsSectionState();
}

class _SelectedItemsSectionState extends ConsumerState<SelectedItemsSection> {
  static const int _collapsedVisibleCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final isInspecting = state.isInspectingSendItems;
    final items = state.sendItems;
    final count = items.length;
    
    final canCollapse = count > _collapsedVisibleCount;
    final visibleItems = canCollapse && !_expanded
        ? items.take(_collapsedVisibleCount).toList(growable: false)
        : items;
    final hiddenCount = count - visibleItems.length;

    final totalBytes = items.fold<int>(0, (sum, item) => sum + (item.sizeBytes ?? 0));
    final itemLabel = _selectionSummaryLabel(count: count, totalBytes: totalBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isInspecting && count == 0 ? 'Preparing files' : 'Selected files',
                style: driftSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kBorder),
              ),
              child: Text(
                isInspecting && count == 0 ? 'Preparing' : itemLabel,
                style: driftSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: kSurface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder.withValues(alpha: 0.8)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                if (isInspecting && count == 0) ...[
                  const _SelectedItemSkeleton(),
                  const Divider(height: 1, indent: 32),
                  const _SelectedItemSkeleton(),
                ] else ...[
                  for (int i = 0; i < visibleItems.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 32),
                    SelectedItemRow(item: visibleItems[i]),
                  ],
                  if (hiddenCount > 0) ...[
                    const Divider(height: 1, indent: 32),
                    _SelectedItemsOverflowRow(
                      hiddenCount: hiddenCount,
                      onToggle: () => setState(() => _expanded = true),
                    ),
                  ] else if (canCollapse && _expanded) ...[
                    const Divider(height: 1, indent: 32),
                    TextButton(
                      onPressed: () => setState(() => _expanded = false),
                      child: Text('Show less', style: driftSans(fontSize: 12, color: kMuted)),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: notifier.appendSendItemsFromPicker,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text('Add files', style: driftSans(fontSize: 12.5, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: kMuted),
          ),
        ),
      ],
    );
  }

  String _selectionSummaryLabel({required int count, required int totalBytes}) {
    final fileLabel = count == 1 ? '1 file' : '$count files';
    if (count == 0 || totalBytes <= 0) return fileLabel;
    return '$fileLabel, ${_formatBytes(totalBytes)}';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unitIndex]}';
  }
}

class NearbyDevicesSection extends ConsumerWidget {
  const NearbyDevicesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final destinations = state.nearbySendDestinations;
    final isScanning = state.nearbyScanInProgress;
    final hasFound = destinations.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Nearby devices',
                style: driftSans(fontSize: 15, fontWeight: FontWeight.w700, color: kInk),
              ),
            ),
            if (isScanning)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: kAccentCyanStrong),
              ),
            TextButton(
              onPressed: notifier.rescanNearbySendDestinations,
              child: Text('Rescan', style: driftSans(fontSize: 12, color: kAccentCyanStrong)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (hasFound)
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: destinations.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final d = destinations[index];
                final isSelected = state.selectedSendDestination == d;
                return _NearbyDeviceTile(destination: d, isSelected: isSelected);
              },
            ),
          )
        else if (isScanning && !state.nearbyScanHasCompletedOnce)
          _NearbyStatusPanel(
            icon: Icons.radar_rounded,
            title: 'Scanning for nearby receivers...',
            message: 'Make sure both devices are on the same Wi-Fi.',
            isScanning: true,
          )
        else
          _NearbyStatusPanel(
            icon: Icons.wifi_off_rounded,
            title: 'No nearby devices found',
            message: 'Make sure both devices are on the same Wi-Fi. Local network access may be required.',
            action: TextButton(
              onPressed: notifier.rescanNearbySendDestinations,
              child: const Text('Try again'),
            ),
          ),
      ],
    );
  }
}

class ManualCodeSection extends ConsumerWidget {
  const ManualCodeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final hasCode = state.sendDestinationCode.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Send with code',
                style: driftSans(fontSize: 15, fontWeight: FontWeight.w700, color: kInk),
              ),
            ),
            if (hasCode)
              TextButton(
                onPressed: notifier.clearSendDestinationCode,
                child: Text('Clear', style: driftSans(fontSize: 12, color: kMuted)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Use the 6 characters shown on the receiver.',
          style: driftSans(fontSize: 13, color: kMuted),
        ),
        const SizedBox(height: 16),
        ReceiveCodeField(
          fieldKey: const ValueKey<String>('send-code-field'),
          code: state.sendDestinationCode,
          hintText: 'AB12CD',
          onChanged: notifier.updateSendDestinationCode,
          onSubmitted: (_) => notifier.startSend(),
          understated: true,
        ),
      ],
    );
  }
}

class SelectedItemRow extends StatelessWidget {
  const SelectedItemRow({super.key, required this.item});
  final TransferItemViewData item;

  @override
  Widget build(BuildContext context) {
    final notifier = ProviderScope.containerOf(context, listen: false).read(driftAppNotifierProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            item.kind == TransferItemKind.folder ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
            size: 16,
            color: kMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: item.name,
              child: Text(
                item.name,
                style: driftSans(fontSize: 13.5, fontWeight: FontWeight.w600, color: kInk),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(item.size, style: driftSans(fontSize: 11.5, color: kMuted)),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => notifier.removeSendItem(item.path),
            icon: const Icon(Icons.close_rounded, size: 14),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            color: kMuted.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

class _NearbyDeviceTile extends ConsumerWidget {
  const _NearbyDeviceTile({required this.destination, required this.isSelected});
  final SendDestinationViewData destination;
  final bool isSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    return InkWell(
      onTap: () => notifier.selectNearbyDestination(destination),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 84,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? kAccentCyan.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? kAccentCyanStrong : Colors.transparent, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? kAccentCyanStrong : kSurface2,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconFor(destination.kind),
                size: 20,
                color: isSelected ? Colors.white : kInk.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              destination.name,
              style: driftSans(fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: kInk),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(SendDestinationKind kind) => switch (kind) {
    SendDestinationKind.laptop => Icons.laptop_mac_rounded,
    SendDestinationKind.phone => Icons.smartphone_rounded,
    SendDestinationKind.tablet => Icons.tablet_mac_rounded,
  };
}

class _NearbyStatusPanel extends StatelessWidget {
  const _NearbyStatusPanel({required this.icon, required this.title, required this.message, this.isScanning = false, this.action});
  final IconData icon;
  final String title;
  final String message;
  final bool isScanning;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: kMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: driftSans(fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
                const SizedBox(height: 2),
                Text(message, style: driftSans(fontSize: 12, color: kMuted)),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _SelectedItemsOverflowRow extends StatelessWidget {
  const _SelectedItemsOverflowRow({required this.hiddenCount, required this.onToggle});
  final int hiddenCount;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            const SizedBox(width: 28),
            Text('+$hiddenCount more files', style: driftSans(fontSize: 12, fontWeight: FontWeight.w600, color: kMuted)),
            const Spacer(),
            Icon(Icons.expand_more_rounded, size: 16, color: kMuted),
          ],
        ),
      ),
    );
  }
}

class _SelectedItemSkeleton extends StatelessWidget {
  const _SelectedItemSkeleton();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(width: 16, height: 16, decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 10),
          Container(width: 120, height: 10, decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(5))),
          const Spacer(),
          Container(width: 40, height: 10, decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(5))),
        ],
      ),
    );
  }
}
