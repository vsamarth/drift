import 'package:flutter/material.dart';
import '../../../../theme/drift_theme.dart';
import '../../application/manifest.dart';
import '../../application/state.dart';
import 'transfer_presentation_helpers.dart';

class ActiveTransferFileList extends StatefulWidget {
  const ActiveTransferFileList({
    super.key,
    required this.items,
    this.progress,
    this.initiallyExpanded = false,
  });

  final List<TransferManifestItem> items;
  final TransferTransferProgress? progress;
  final bool initiallyExpanded;

  @override
  State<ActiveTransferFileList> createState() => _ActiveTransferFileListState();
}

class _ActiveTransferFileListState extends State<ActiveTransferFileList> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final totalSize = widget.items.fold(
      BigInt.zero,
      (sum, item) => sum + item.sizeBytes,
    );

    final String summary;
    if (widget.progress != null) {
      final p = widget.progress!;
      summary = '${p.completedFiles}/${p.totalFiles} files · ${formatBytes(p.bytesTransferred)} of ${formatBytes(p.totalBytes)}';
    } else {
      summary = '${fileCountLabel(widget.items.length)} · ${formatBytes(totalSize)}';
    }

    final isSingleFile = widget.items.length == 1;

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isSingleFile ? 10 : 12,
              ),
              child: Row(
                children: [
                  Icon(
                    isSingleFile
                        ? Icons.insert_drive_file_rounded
                        : Icons.copy_all_rounded,
                    color: kMuted,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isSingleFile)
                          Text(
                            'Contents',
                            style: driftSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: kMuted,
                              letterSpacing: 0.4,
                            ),
                          ),
                        Text(
                          isSingleFile
                              ? widget.items.first.path.split('/').last
                              : summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: driftSans(
                            fontSize: 13,
                            fontWeight: isSingleFile
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: kInk,
                          ),
                        ),
                        if (isSingleFile)
                          Text(
                            widget.progress != null
                                ? '${formatBytes(widget.progress!.bytesTransferred)} / ${formatBytes(widget.items.first.sizeBytes)}'
                                : formatBytes(widget.items.first.sizeBytes),
                            style: driftSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: kMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isSingleFile)
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: kSubtle,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
          if (_isExpanded && !isSingleFile) ...[
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: widget.items.length,
                physics: const BouncingScrollPhysics(),
                separatorBuilder: (context, index) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final segments = item.path.split('/');
                  final fileName = segments.last;
                  final dirPath = segments.length > 1
                      ? segments.sublist(0, segments.length - 1).join('/')
                      : null;

                  double itemProgress = 0;
                  if (widget.progress != null) {
                    final p = widget.progress!;
                    if (p.activeFileIndex != null) {
                      if (index < p.activeFileIndex!) {
                        itemProgress = 1.0;
                      } else if (index == p.activeFileIndex!) {
                        if (item.sizeBytes > BigInt.zero) {
                          itemProgress = (p.activeFileBytesTransferred
                                      ?.toDouble() ??
                                  0) /
                              item.sizeBytes.toDouble();
                        } else {
                          itemProgress = 1.0;
                        }
                      }
                    } else if (p.completedFiles > index) {
                      itemProgress = 1.0;
                    }
                  }

                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: kFill.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                itemProgress >= 1.0
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.insert_drive_file_outlined,
                                size: 16,
                                color: itemProgress >= 1.0
                                    ? kAccentCyanStrong
                                    : kMuted,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: driftSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: kInk,
                                    ),
                                  ),
                                  if (dirPath != null && dirPath.isNotEmpty)
                                    Text(
                                      dirPath,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: driftSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: kSubtle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              formatBytes(item.sizeBytes),
                              style: driftSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: kMuted,
                              ),
                            ),
                          ],
                        ),
                        if (itemProgress > 0 && itemProgress < 1.0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 44),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: itemProgress,
                                minHeight: 2,
                                backgroundColor: kFill,
                                valueColor: const AlwaysStoppedAnimation(
                                    kAccentCyanStrong),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
