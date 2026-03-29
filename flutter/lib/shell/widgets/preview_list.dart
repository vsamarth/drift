import 'package:flutter/material.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';

class PreviewList extends StatelessWidget {
  const PreviewList({
    super.key,
    required this.items,
    required this.hiddenItemCount,
  });

  final List<TransferItemViewData> items;
  final int hiddenItemCount;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text('No files', style: Theme.of(context).textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1, thickness: 1, indent: 42),
          PreviewRow(item: items[i]),
        ],
        if (hiddenItemCount > 0) ...[
          const Divider(height: 1, thickness: 1, indent: 42),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Text(
              '+$hiddenItemCount more ${hiddenItemCount == 1 ? 'item' : 'items'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

class PreviewRow extends StatelessWidget {
  const PreviewRow({super.key, required this.item});

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
          Icon(icon, size: 18, color: kMuted),
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
          Text(item.size, style: driftSans(fontSize: 12, color: kMuted)),
        ],
      ),
    );
  }
}
