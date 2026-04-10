import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/drift_theme.dart';
import '../../../features/send/send_providers.dart';
import '../../../features/send/send_state.dart';
import '../receive_code_field.dart';
import 'nearby_devices_section.dart';
import 'selected_files_preview.dart';

class MobileSendDraftView extends ConsumerWidget {
  const MobileSendDraftView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(sendStateProvider);
    final notifier = ref.read(sendControllerProvider.notifier);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                'Selected files',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to send this selection.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              SelectedFilesPreview(items: state.sendItems),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: state.isInspectingSendItems
                      ? null
                      : notifier.appendSendItemsFromPicker,
                  child: const Text('Add more'),
                ),
              ),
              const SizedBox(height: 16),
              NearbyDevicesSection(
                devices: state.nearbySendDestinations,
                selectedDevice: null,
                isScanning: state.nearbyScanInProgress,
                onSelect: notifier.selectNearbyDestination,
                onScan: notifier.rescanNearbySendDestinations,
              ),
              const SizedBox(height: 16),
              Card.outlined(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send with code',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Enter the six-character receiver code to start the transfer.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      ReceiveCodeField(
                        code: state.sendDestinationCode,
                        onChanged: notifier.updateSendDestinationCode,
                        hintText: 'Receiver code',
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
