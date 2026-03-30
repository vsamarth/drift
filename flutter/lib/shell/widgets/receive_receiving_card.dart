import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';
import 'preview_list.dart';
import 'sending_connection_strip.dart';

class ReceiveReceivingCard extends StatelessWidget {
  const ReceiveReceivingCard({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final summary = controller.receiveSummary;
    final senderName = _displaySender(summary?.senderName);
    final itemCount = summary?.itemCount ?? controller.receiveItems.length;
    final totalSize = summary?.totalSize ?? '';
    final itemSummary =
        '$itemCount${totalSize.isEmpty ? '' : ' · $totalSize'}';

    final transferProgress = _transferProgressForStrip(controller);
    final mode = _receivingStripMode(controller);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFFD4A824),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Incoming',
                style: driftSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: kMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            senderName,
            style: driftSans(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: kInk,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            controller.receiveSummary?.statusMessage ?? 'Receiving files…',
            style: driftSans(fontSize: 13, color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SendingConnectionStrip(
                        localLabel: senderName,
                        localDeviceType: 'laptop',
                        remoteLabel: controller.deviceName,
                        remoteDeviceType: controller.deviceType,
                        animate: true,
                        mode: mode,
                        transferProgress: transferProgress,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: PreviewTable(
                      items: controller.receiveItems,
                      footerSummary: itemSummary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

SendingStripMode _receivingStripMode(DriftController controller) {
  if (!controller.hasReceivePayloadProgress) {
    return SendingStripMode.waitingOnRecipient;
  }
  return SendingStripMode.transferring;
}

double _transferProgressForStrip(DriftController controller) {
  if (!controller.hasReceivePayloadProgress) {
    return 0.0;
  }
  final total = controller.receivePayloadTotalBytes ?? 0;
  final received = controller.receivePayloadBytesReceived ?? 0;
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

