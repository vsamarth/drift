import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';
import '../../../transfers/presentation/widgets/transfer_presentation_helpers.dart';
import '../../application/model.dart';

class SendDraftFileList extends StatelessWidget {
  const SendDraftFileList({
    super.key,
    required this.files,
    required this.maxHeight,
    required this.onRemove,
  });

  final List<SendPickedFile> files;
  final double maxHeight;
  final ValueChanged<SendPickedFile> onRemove;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No files', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < files.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: kBorder.withValues(alpha: 0.3),
                      ),
                    _PreviewTableRow(
                      key: ValueKey(files[i].path),
                      file: files[i],
                      onRemove: () => onRemove(files[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewTableRow extends StatelessWidget {
  const _PreviewTableRow({
    super.key,
    required this.file,
    required this.onRemove,
  });

  final SendPickedFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isDirectory = file.kind == SendPickedFileKind.directory;
    final sizeLabel = isDirectory
        ? (file.sizeBytes == null
              ? 'Calculating...'
              : formatBytes(file.sizeBytes!))
        : (file.sizeBytes == null ? '' : formatBytes(file.sizeBytes!));
    final rowIcon = isDirectory
        ? Icons.folder_rounded
        : Icons.description_rounded;
    final iconColor = isDirectory ? const Color(0xFF4A8E9E) : kMuted;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(width: 28, child: Icon(rowIcon, size: 20, color: iconColor)),
          const SizedBox(width: 12),
          Expanded(
            child: Tooltip(
              message: file.name,
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: driftSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
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
          const SizedBox(width: 10),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            visualDensity: VisualDensity.compact,
            color: kMuted.withValues(alpha: 0.5),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}
