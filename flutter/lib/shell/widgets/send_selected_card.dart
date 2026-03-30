import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
import '../../state/drift_providers.dart';
import 'receive_code_field.dart';
import 'shell_surface_card.dart';

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
                  const SizedBox(height: 18),
                  const NearbyDevicesSection(),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: kBorder.withValues(alpha: 0.75),
                  ),
                  const SizedBox(height: 12),
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

class SelectedItemsSection extends ConsumerWidget {
  const SelectedItemsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);
    final isInspecting = state.isInspectingSendItems;
    final items = state.sendItems;
    final count = items.length;
    final itemLabel = count == 1 ? '1 item ready' : '$count items ready';
    final headline = isInspecting && count == 0
        ? 'Preparing files'
        : 'Selected files';
    final helper = isInspecting && count == 0
        ? 'We are checking your selection before receivers become available.'
        : 'Everything in this set will be sent together.';

    return ShellSurfaceCard(
      child: Column(
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
                    const SizedBox(height: 5),
                    Text(
                      helper,
                      style: driftSans(
                        fontSize: 13,
                        color: kInk.withValues(alpha: 0.72),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: kSurface2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: kBorder),
                ),
                child: Text(
                  isInspecting && count == 0 ? 'Working' : itemLabel,
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
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kBorder.withValues(alpha: 0.9)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
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
                    for (int i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, thickness: 1, indent: 36),
                      SelectedItemRow(item: items[i]),
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
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tip: drag more files anywhere in this view to add them.',
                  style: driftSans(fontSize: 12, color: kMuted, height: 1.35),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: notifier.pickSendItems,
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
      ),
    );
  }
}

class SelectedItemRow extends StatelessWidget {
  const SelectedItemRow({super.key, required this.item});

  final TransferItemViewData item;

  @override
  Widget build(BuildContext context) {
    final icon = item.kind == TransferItemKind.folder
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

class NearbyDevicesSection extends ConsumerWidget {
  const NearbyDevicesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final destinations = state.nearbySendDestinations;
    final canScan = state.canBrowseNearbyReceivers;

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
        const SizedBox(height: 4),
        Text(
          'Pick a receiver on your local network.',
          style: driftSans(fontSize: 13, color: kInk.withValues(alpha: 0.74)),
        ),
        const SizedBox(height: 12),
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
                ? 'Finishing file prep'
                : 'Add files to discover receivers',
            message: state.isInspectingSendItems
                ? 'Nearby receivers appear here once your items are ready.'
                : 'Choose files first, then nearby devices will appear here.',
          )
        else
          const _NearbyStatusPanel(
            icon: Icons.radar_outlined,
            title: 'No nearby devices found.',
            message: 'Try again in a moment, or send with a code below.',
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
        const SizedBox(height: 4),
        Text(
          'Enter the 6-character code from the receiving device.',
          style: driftSans(fontSize: 13, color: kInk.withValues(alpha: 0.74)),
        ),
        const SizedBox(height: 10),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder),
            ),
            child: Icon(icon, size: 18, color: kMuted),
          ),
          const SizedBox(width: 12),
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
                  style: driftSans(fontSize: 12.5, color: kMuted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
