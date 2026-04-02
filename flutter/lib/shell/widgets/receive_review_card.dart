import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_providers.dart';
import 'preview_list.dart';
import 'sending_connection_strip.dart';
import 'transfer_flow_layout.dart';

class ReceiveReviewCard extends ConsumerWidget {
  const ReceiveReviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final summary = state.receiveSummary;
    final senderName = _displaySender(summary?.senderName);
    final itemCount = summary?.itemCount ?? state.receiveItems.length;
    final totalSize = summary?.totalSize ?? '';
    final itemSummary =
        '${_fileCountLabel(itemCount)}${totalSize.isEmpty ? '' : ' · $totalSize'}';
    final saveRoot = summary?.destinationLabel.trim() ?? 'Downloads';
    final senderDeviceType = state.receiveSenderDeviceType ?? 'laptop';
    final notifier = ref.read(driftAppNotifierProvider.notifier);

    const accentColor = Color(0xFF4B98AA);

    return TransferFlowLayout(
      statusLabel: 'Incoming',
      statusColor: accentColor,
      title: senderName,
      subtitle: _subtitle(itemCount, totalSize, saveRoot),
      explainer: Text(
        'Review the files and accept only if you trust the sender.',
        style: driftSans(fontSize: 12, color: kSubtle, height: 1.4),
      ),
      illustration: SendingConnectionStrip(
        localLabel: senderName,
        localDeviceType: senderDeviceType,
        remoteLabel: state.deviceName,
        remoteDeviceType: state.deviceType,
        animate: ref.watch(animateSendingConnectionProvider),
        mode: SendingStripMode.waitingOnRecipient,
      ),
      manifest: PreviewTable(
        items: state.receiveItems,
        footerSummary: itemSummary,
      ),
      footer: Row(
        children: [
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: notifier.acceptReceiveOffer,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4A8E9E),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Save to $saveRoot'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: TextButton(
              onPressed: notifier.declineReceiveOffer,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFCC3333),
                backgroundColor: const Color(0xFFCC3333).withValues(alpha: 0.08),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: const Color(0xFFCC3333).withValues(alpha: 0.15)),
                ),
              ),
              child: const Text('Decline'),
            ),
          ),
        ],
      ),
    );
  }
}

String _displaySender(String? rawValue) {
  final trimmed = rawValue?.trim() ?? '';
  if (trimmed.isEmpty) return 'Unknown sender';
  return trimmed;
}

String _subtitle(int itemCount, String totalSize, String saveRoot) {
  final fileWord = itemCount == 1 ? 'file' : 'files';
  final sizePart = totalSize.isEmpty ? '' : ' ($totalSize)';
  return 'Wants to send you $itemCount $fileWord$sizePart.';
}

String _fileCountLabel(int itemCount) {
  return itemCount == 1 ? '1 file' : '$itemCount files';
}
