import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/drift_theme.dart';
import '../../../features/send/send_providers.dart';
import '../../../state/drift_providers.dart';
import '../receive_code_field.dart';

class SendBottomSheet extends ConsumerWidget {
  const SendBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sendStateProvider);
    final notifier = ref.read(sendControllerProvider.notifier);
    final appNotifier = ref.read(driftAppNotifierProvider.notifier);
    final destinations = state.nearbySendDestinations;
    final items = state.sendItems;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Send ${items.length} ${items.length == 1 ? 'file' : 'files'}',
                style: driftSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: appNotifier.resetShell,
                child: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'NEARBY DEVICES',
            style: driftSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: kMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          if (destinations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Searching for devices...',
                      style: driftSans(fontSize: 14, color: kMuted),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: destinations.length,
                separatorBuilder: (context, index) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final dest = destinations[index];
                  return Column(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => notifier.selectNearbyDestination(dest),
                        icon: const Icon(Icons.devices_rounded),
                        iconSize: 32,
                        padding: const EdgeInsets.all(16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dest.name,
                        style: driftSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: kInk,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          Text(
            'OR ENTER CODE',
            style: driftSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: kMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ReceiveCodeField(
            code: state.sendDestinationCode,
            onChanged: notifier.updateSendDestinationCode,
            hintText: 'Receiver code',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
