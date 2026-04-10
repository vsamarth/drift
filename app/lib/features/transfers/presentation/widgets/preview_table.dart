import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';
import '../../application/manifest.dart';
import 'transfer_presentation_helpers.dart';

class PreviewTable extends StatelessWidget {
  const PreviewTable({
    super.key,
    required this.items,
    required this.footerSummary,
  });

  final List<TransferManifestItem> items;
  final String footerSummary;

  static final _divider = Divider(
    height: 1,
    thickness: 1,
    color: kBorder.withValues(alpha: 0.55),
  );

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No files', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    final headerStyle = driftSans(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: kInk.withValues(alpha: 0.8),
      letterSpacing: 0.15,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const SizedBox(width: 28),
              Expanded(child: Text('Name', style: headerStyle)),
              SizedBox(
                width: 76,
                child: Text(
                  'Size',
                  textAlign: TextAlign.right,
                  style: headerStyle,
                ),
              ),
            ],
          ),
        ),
        _divider,
        const SizedBox(height: 10),
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) _divider,
          _PreviewTableRow(item: items[i]),
        ],
        if (items.length > 1) ...[
          _divider,
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Row(
              children: [
                const SizedBox(width: 28),
                Expanded(
                  child: Text(
                    footerSummary,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: driftSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: kMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PreviewTableRow extends StatelessWidget {
  const _PreviewTableRow({required this.item});

  final TransferManifestItem item;

  @override
  Widget build(BuildContext context) {
    final name = _displayFileName(item.path);
    final sizeLabel = formatBytes(item.sizeBytes);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 28,
            child: Icon(
              Icons.insert_drive_file_outlined,
              size: 18,
              color: kMuted,
            ),
          ),
          Expanded(
            child: Tooltip(
              message: name,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: driftSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: kInk,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 116,
            child: Text(
              sizeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: kMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _displayFileName(String path) {
  final segments = path.split('/')..removeWhere((segment) => segment.isEmpty);
  return segments.isEmpty ? path : segments.last;
}
