import 'package:flutter/material.dart';

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

class SendScreen extends StatelessWidget {
  const SendScreen({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectedItemsSection(controller: controller),
          const SizedBox(height: 34),
          NearbyDevicesSection(controller: controller),
          const SizedBox(height: 34),
          ManualCodeSection(controller: controller),
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
    final items = controller.visibleSendItems;
    final hiddenItemCount = controller.hiddenSendItemCount;
    final count = controller.sendItems.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count == 1 ? '1 item' : '$count items',
          style: driftSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: kMuted,
          ),
        ),
        const SizedBox(height: 10),
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

class NearbyDevicesSection extends StatelessWidget {
  const NearbyDevicesSection({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final destinations = controller.nearbySendDestinations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Nearby devices',
              style: driftSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: kInk.withValues(alpha: 0.60),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kAccentWarmSurface,
                      kBorder.withValues(alpha: 0.82),
                      kBorder.withValues(alpha: 0.54),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (destinations.isEmpty)
          Text(
            'No nearby devices right now',
            style: driftSans(fontSize: 13, color: kMuted),
          )
        else
          Column(
            children: [
              for (int i = 0; i < destinations.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                NearbyDeviceRow(
                  rowKey: ValueKey<String>('send-destination-$i'),
                  destination: destinations[i],
                  onTap: () =>
                      controller.selectNearbyDestination(destinations[i]),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class NearbyDeviceRow extends StatelessWidget {
  const NearbyDeviceRow({
    super.key,
    required this.rowKey,
    required this.destination,
    required this.onTap,
  });

  final Key rowKey;
  final SendDestinationViewData destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: kAccentCyanHover,
        splashColor: kAccentCyanPressed,
        highlightColor: kAccentCyanHover,
        child: Ink(
          decoration: BoxDecoration(
            color: kSurface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder.withValues(alpha: 0.78)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: kSurface2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    _iconFor(destination.kind),
                    size: 15,
                    color: kMuted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    destination.name,
                    style: driftSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(SendDestinationKind kind) {
    return switch (kind) {
      SendDestinationKind.laptop => Icons.laptop_mac_outlined,
      SendDestinationKind.phone => Icons.smartphone_outlined,
      SendDestinationKind.tablet => Icons.tablet_mac_outlined,
    };
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
