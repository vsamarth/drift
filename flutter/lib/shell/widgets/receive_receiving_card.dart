import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_app_state.dart';
import '../../state/drift_providers.dart';
import 'preview_list.dart';
import 'sending_connection_strip.dart';
import 'transfer_flow_layout.dart';

class ReceiveReceivingCard extends ConsumerWidget {
  const ReceiveReceivingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final summary = state.receiveSummary;
    final senderName = _displaySender(summary?.senderName);
    final itemCount = summary?.itemCount ?? state.receiveItems.length;
    final totalSize = summary?.totalSize ?? '';
    final itemSummary =
        '${_fileCountLabel(itemCount)}${totalSize.isEmpty ? '' : ' · $totalSize'}';
    final senderDeviceType = state.receiveSenderDeviceType ?? 'laptop';

    final transferProgress = _transferProgressForStrip(state);
    final mode = _receivingStripMode(state);

    const accentColor = Color(0xFFD4A824);

    return TransferFlowLayout(
      statusLabel: 'Receiving',
      statusColor: accentColor,
      title: senderName,
      subtitle: state.receiveSummary?.statusMessage ?? 'Receiving files...',
      illustration: SendingConnectionStrip(
        localLabel: senderName,
        localDeviceType: senderDeviceType,
        remoteLabel: state.deviceName,
        remoteDeviceType: state.deviceType,
        animate: ref.watch(animateSendingConnectionProvider),
        mode: mode,
        transferProgress: transferProgress,
      ),
      manifest: PreviewTable(
        items: state.receiveItems,
        footerSummary: itemSummary,
      ),
      footer: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => _confirmCancel(context, ref),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFCC3333),
                backgroundColor: const Color(0xFFCC3333).withValues(alpha: 0.08),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: const Color(0xFFCC3333).withValues(alpha: 0.15)),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Transfer?'),
        content: const Text('Stop receiving and cancel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFCC3333)),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(driftAppNotifierProvider.notifier).declineReceiveOffer();
    }
  }
}

SendingStripMode _receivingStripMode(DriftAppState state) {
  if (!state.hasReceivePayloadProgress) {
    return SendingStripMode.waitingOnRecipient;
  }
  return SendingStripMode.transferring;
}

double _transferProgressForStrip(DriftAppState state) {
  if (!state.hasReceivePayloadProgress) {
    return 0.0;
  }
  final total = state.receivePayloadTotalBytes ?? 0;
  final received = state.receivePayloadBytesReceived ?? 0;
  if (total <= 0) {
    return 0.0;
  }
  return (received / total).clamp(0.0, 1.0);
}

String _displaySender(String? rawValue) {
  final trimmed = rawValue?.trim() ?? '';
  if (trimmed.isEmpty) return 'Unknown sender';
  return trimmed;
}

String _fileCountLabel(int itemCount) {
  return itemCount == 1 ? '1 file' : '$itemCount files';
}
