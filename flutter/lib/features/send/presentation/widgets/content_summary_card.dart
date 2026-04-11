import 'package:flutter/material.dart';
import 'package:app/theme/drift_theme.dart';
import 'package:app/features/transfers/application/manifest.dart';
import 'package:app/features/transfers/presentation/widgets/transfer_presentation_helpers.dart';

class ContentSummaryCard extends StatefulWidget {
  const ContentSummaryCard({
    super.key,
    required this.items,
    this.initiallyExpanded = false,
  });

  final List<TransferManifestItem> items;
  final bool initiallyExpanded;

  @override
  State<ContentSummaryCard> createState() => _ContentSummaryCardState();
}

class _ContentSummaryCardState extends State<ContentSummaryCard> {
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
    final summary =
        '${fileCountLabel(widget.items.length)} · ${formatBytes(totalSize)}';

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder.withValues(alpha: 0.8)),
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
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.folder_open_rounded, color: kMuted, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      summary,
                      style: driftSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kInk,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: kSubtle,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: widget.items.length,
                separatorBuilder: (context, index) => const Divider(indent: 16, endIndent: 16, height: 1),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.path.split('/').last,
                            style: driftSans(fontSize: 13, color: kInk),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatBytes(item.sizeBytes),
                          style: driftSans(fontSize: 12, color: kMuted),
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
