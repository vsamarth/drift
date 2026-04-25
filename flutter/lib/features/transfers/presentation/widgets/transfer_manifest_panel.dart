import 'package:flutter/material.dart';

import '../../application/manifest.dart';
import '../../application/state.dart';
import 'active_transfer_file_list.dart';
import 'manifest_tree_card.dart';

enum TransferManifestPanelMode { previewTree, liveList }

class TransferManifestPanel extends StatelessWidget {
  const TransferManifestPanel({
    super.key,
    required this.mode,
    required this.items,
    this.progress,
    this.initiallyExpanded = false,
  });

  final TransferManifestPanelMode mode;
  final List<TransferManifestItem> items;
  final TransferTransferProgress? progress;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      TransferManifestPanelMode.previewTree => ManifestTreeCard(
        items: items,
        initiallyExpanded: initiallyExpanded,
      ),
      TransferManifestPanelMode.liveList => ActiveTransferFileList(
        items: items,
        progress: progress,
        initiallyExpanded: initiallyExpanded,
      ),
    };
  }
}
