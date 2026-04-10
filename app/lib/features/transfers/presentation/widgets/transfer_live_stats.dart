import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';
import '../../application/state.dart';
import 'transfer_presentation_helpers.dart';

class TransferLiveStats extends StatelessWidget {
  const TransferLiveStats({super.key, required this.progress});

  final TransferTransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final progressLabel =
        '${formatBytes(progress.bytesTransferred)} of ${formatBytes(progress.totalBytes)}';
    final extras = <String>[
      if (progress.speedLabel != null) progress.speedLabel!,
      if (progress.etaLabel != null) progress.etaLabel!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          progressLabel,
          style: driftSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: kInk,
            height: 1.3,
          ),
        ),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            extras.join(' · '),
            style: driftSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: kMuted,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}
