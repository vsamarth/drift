import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
import '../../state/drift_app_state.dart';
import '../../state/drift_providers.dart';
import 'preview_list.dart';
import 'sending_connection_strip.dart';
import 'transfer_flow_layout.dart';

class SendCodeCard extends ConsumerWidget {
  const SendCodeCard({
    super.key,
    required this.title,
    required this.status,
    this.primaryLabel,
    this.onPrimary,
    this.fillBody = false,
  });

  final String title;
  final String status;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool fillBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);
    final summary = state.sendSummary;
    final itemCount = summary?.itemCount ?? state.sendItems.length;
    final totalSize = summary?.totalSize ?? '';
    final destinationLabel = _displayRecipient(summary?.destinationLabel);
    final stage = state.sendStage;
    final dotColor = _dotColorFor(stage);
    final itemSummary =
        '${_fileCountLabel(itemCount)}${totalSize.isEmpty ? '' : ' · $totalSize'}';

    if (!fillBody) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: driftSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: kInk,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              style: driftSans(fontSize: 13, color: kMuted, height: 1.45),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _RecipientRow(
              destinationLabel: destinationLabel,
              itemSummary: itemSummary,
              dotColor: dotColor,
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: PreviewList(items: state.sendItems),
              ),
            ),
            if (primaryLabel != null && onPrimary != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4A8E9E),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(primaryLabel!),
              ),
            ],
          ],
        ),
      );
    }

    return TransferFlowLayout(
      statusLabel: title,
      statusColor: dotColor,
      title: destinationLabel,
      subtitle: status,
      explainer: (stage == TransferStage.waiting && !state.hasSendPayloadProgress)
          ? Text(
              'The receiver must accept before files start transferring.',
              style: driftSans(fontSize: 12, color: kSubtle, height: 1.4),
            )
          : null,
      illustration: SendingConnectionStrip(
        localLabel: state.deviceName,
        localDeviceType: state.deviceType,
        remoteLabel: destinationLabel,
        remoteDeviceType: state.sendRemoteDeviceType,
        animate: state.animateSendingConnection,
        mode: _sendingStripMode(state),
        transferProgress: _transferProgressForStrip(state),
      ),
      manifest: PreviewTable(
        items: state.sendItems,
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
        content: const Text('Stop waiting and cancel send?'),
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
      ref.read(driftAppNotifierProvider.notifier).cancelSendInProgress();
    }
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.destinationLabel,
    required this.itemSummary,
    required this.dotColor,
  });

  final String destinationLabel;
  final String itemSummary;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                destinationLabel,
                style: driftSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(itemSummary, style: driftSans(fontSize: 12, color: kMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

Color _dotColorFor(TransferStage stage) {
  return switch (stage) {
    TransferStage.ready => const Color(0xFF4B98AA),
    TransferStage.waiting => const Color(0xFFD4A824),
    TransferStage.completed => const Color(0xFF49B36C),
    TransferStage.error => const Color(0xFFCC3333),
    _ => const Color(0xFF4B98AA),
  };
}

SendingStripMode _sendingStripMode(DriftAppState state) {
  if (state.hasSendPayloadProgress) {
    return SendingStripMode.transferring;
  }
  if (state.sendStage == TransferStage.waiting) {
    return SendingStripMode.waitingOnRecipient;
  }
  return SendingStripMode.looping;
}

double _transferProgressForStrip(DriftAppState state) {
  if (!state.hasSendPayloadProgress) {
    return 0;
  }
  final total = state.sendPayloadTotalBytes ?? 0;
  if (total <= 0) {
    return 0;
  }
  final sent = state.sendPayloadBytesSent ?? 0;
  return (sent / total).clamp(0.0, 1.0);
}

String _displayRecipient(String? rawValue) {
  final trimmed = rawValue?.trim() ?? '';
  if (trimmed.isEmpty) return 'Recipient device';

  final normalized = trimmed
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final lowercase = normalized.toLowerCase();
  if (lowercase.isEmpty ||
      lowercase == 'unknown device' ||
      lowercase == 'unknown-device' ||
      lowercase == 'unknown') {
    return 'Recipient device';
  }
  return normalized;
}

String _fileCountLabel(int itemCount) {
  return itemCount == 1 ? '1 file' : '$itemCount files';
}
