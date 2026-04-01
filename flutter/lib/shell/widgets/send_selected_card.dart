import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
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
    final notifier = ref.read(driftAppNotifierProvider.notifier);

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
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SelectedItemsSection(),
                  const SizedBox(height: 12),
                  const NearbyDevicesSection(),
                  const SizedBox(height: 16),
                  const ManualCodeSection(),
                ],
              ),
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
    final ref = this.ref;
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final isInspecting = state.isInspectingSendItems;
    final items = state.sendItems;
    final count = items.length;
    final canCollapse = count > _collapsedVisibleCount;
    if (!canCollapse && _expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _expanded = false);
        }
      });
    }
    final visibleItems = canCollapse && !_expanded
        ? items.take(_collapsedVisibleCount).toList(growable: false)
        : items;
    final hiddenCount = count - visibleItems.length;
    final totalBytes = items.fold<int>(
      0,
      (sum, item) => sum + (item.sizeBytes ?? 0),
    );
    final itemLabel = _selectionSummaryLabel(
      count: count,
      totalBytes: totalBytes,
    );
    final headline = isInspecting && count == 0
        ? 'Preparing files'
        : 'Selected files';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: driftSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                      letterSpacing: -0.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: kSurface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kBorder),
              ),
              child: Text(
                isInspecting && count == 0 ? 'Preparing' : itemLabel,
                style: driftSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: kMuted,
                  letterSpacing: 0.15,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: kSurface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder.withValues(alpha: 0.9)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isInspecting && count == 0) ...[
                  const _SelectedItemSkeleton(),
                  const Divider(height: 1, thickness: 1, indent: 36),
                  const _SelectedItemSkeleton(),
                  const Divider(height: 1, thickness: 1, indent: 36),
                  const _SelectedItemSkeleton(),
                ] else ...[
                  for (int i = 0; i < visibleItems.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, thickness: 1, indent: 36),
                    SelectedItemRow(item: visibleItems[i]),
                  ],
                  if (hiddenCount > 0) ...[
                    const Divider(height: 1, thickness: 1, indent: 36),
                    _SelectedItemsOverflowRow(
                      hiddenCount: hiddenCount,
                      trailing: canCollapse
                          ? TextButton(
                              onPressed: () =>
                                  setState(() => _expanded = !_expanded),
                              style: TextButton.styleFrom(
                                foregroundColor: kMuted,
                                minimumSize: const Size(0, 0),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                _expanded ? 'Show less' : 'Show all',
                                style: driftSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: kMuted,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ] else if (canCollapse) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        style: TextButton.styleFrom(
                          foregroundColor: kMuted,
                          minimumSize: const Size(0, 0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _expanded ? 'Show less' : 'Show all',
                          style: driftSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: kMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Spacer(),
            TextButton(
              onPressed: notifier.appendSendItemsFromPicker,
              style: TextButton.styleFrom(
                foregroundColor: kInk,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              child: Text(
                'Add more',
                style: driftSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _selectionSummaryLabel({required int count, required int totalBytes}) {
    final fileLabel = count == 1 ? '1 file' : '$count files';
    if (count == 0 || totalBytes <= 0) {
      return count == 1 ? '1 file ready' : '$count files ready';
    }
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

    final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
    final formatted = value.toStringAsFixed(decimals);
    return '$formatted ${units[unitIndex]}';
  }
}

class _SelectedItemsOverflowRow extends StatelessWidget {
  const _SelectedItemsOverflowRow({required this.hiddenCount, this.trailing});

  final int hiddenCount;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = hiddenCount == 1
        ? '+1 more file'
        : '+$hiddenCount more files';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 27),
              child: Text(
                label,
                style: driftSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: kMuted,
                ),
              ),
            ),
          ),
          ..._buildTrailingWidgets(trailing),
        ],
      ),
    );
  }
}

List<Widget> _buildTrailingWidgets(Widget? trailing) {
  return switch (trailing) {
    final widget? => [widget],
    null => const [],
  };
}

class SelectedItemRow extends StatelessWidget {
  const SelectedItemRow({super.key, required this.item});

  final TransferItemViewData item;

  @override
  Widget build(BuildContext context) {
    final icon = item.kind == TransferItemKind.folder
        ? Icons.folder_outlined
        : Icons.insert_drive_file_outlined;
    final notifier = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(driftAppNotifierProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
          const SizedBox(width: 4),
          IconButton(
            key: ValueKey<String>('remove-send-item-${item.path}'),
            onPressed: () => notifier.removeSendItem(item.path),
            tooltip: 'Remove',
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: kMuted.withValues(alpha: 0.9),
            ),
          ),
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

class NearbyDevicesSection extends ConsumerWidget {
  const NearbyDevicesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final destinations = state.nearbySendDestinations;
    final canScan = state.canBrowseNearbyReceivers;
    final scanInProgress = state.nearbyScanInProgress;
    final scanCompletedOnce = state.nearbyScanHasCompletedOnce;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nearby devices',
          style: driftSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kMuted,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        if (destinations.isNotEmpty)
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: destinations.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, index) =>
                  _NearbyDeviceTile(destination: destinations[index]),
            ),
          )
        else if (!canScan)
          _NearbyStatusPanel(
            icon: Icons.folder_outlined,
            title: state.isInspectingSendItems
                ? 'Preparing selection'
                : 'Add files to discover receivers',
            message: state.isInspectingSendItems
                ? 'Nearby devices will appear here once your files are ready.'
                : 'Nearby devices will appear here after you add files.',
          )
        else if (scanInProgress && !scanCompletedOnce)
          const _NearbyStatusPanel(
            icon: Icons.radar_outlined,
            title: 'Scanning nearby devices...',
            message:
                'Looking for receivers on your current network. This should only take a few seconds.',
          )
        else
          const _NearbyStatusPanel(
            icon: Icons.radar_outlined,
            title: 'No nearby devices found.',
            message:
                'Ensure that your device is on the same network, or send with a code below.',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Send with code',
          style: driftSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kMuted,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Enter the 6-character code shown on the receiving device.',
          style: driftSans(fontSize: 13, color: kInk.withValues(alpha: 0.74)),
        ),
        const SizedBox(height: 8),
        ReceiveCodeField(
          fieldKey: const ValueKey<String>('send-code-field'),
          code: state.sendDestinationCode,
          onChanged: notifier.updateSendDestinationCode,
          understated: true,
        ),
      ],
    );
  }
}

class _NearbyDeviceTile extends ConsumerWidget {
  const _NearbyDeviceTile({required this.destination});

  final SendDestinationViewData destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 78,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>(
            'nearby-tile-${destination.lanFullname ?? destination.name}',
          ),
          borderRadius: BorderRadius.circular(18),
          onTap: () => ref
              .read(driftAppNotifierProvider.notifier)
              .selectNearbyDestination(destination),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: kSurface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: kBorder),
                  ),
                  child: Icon(
                    _iconForDestination(destination.kind),
                    size: 22,
                    color: kInk.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 6),
                Tooltip(
                  message: [
                    destination.name,
                    if ((destination.hint ?? '').trim().isNotEmpty)
                      destination.hint!.trim(),
                  ].join('\n'),
                  child: Text(
                    destination.name,
                    style: driftSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: kInk,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconForDestination(SendDestinationKind kind) {
    return switch (kind) {
      SendDestinationKind.laptop => Icons.laptop_mac_outlined,
      SendDestinationKind.phone => Icons.smartphone_outlined,
      SendDestinationKind.tablet => Icons.tablet_mac_outlined,
    };
  }
}

class _NearbyStatusPanel extends StatelessWidget {
  const _NearbyStatusPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder),
            ),
            child: Icon(icon, size: 16, color: kMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: driftSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: kInk.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: driftSans(fontSize: 12.5, color: kMuted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
