import 'package:flutter/material.dart';
import '../../../core/models/transfer_models.dart';
import '../../../core/theme/drift_theme.dart';
import '../preview_list.dart';

class SelectedFilesPreview extends StatelessWidget {
  static const double _kPreviewTableTopPadding = 12;
  static const double _kPreviewTableHeaderHeight = 22;
  static const double _kPreviewDividerHeight = 1;
  static const double _kPreviewRowHeight = 38;
  static const double _kPreviewFooterHeight = 28;

  final List<TransferItemViewData> items;
  const SelectedFilesPreview({
    super.key,
    required this.items,
  });

  String _selectionSummaryLabel(List<TransferItemViewData> items) {
    final count = items.length;
    final totalBytes = items.fold<int>(
      0,
      (sum, item) => sum + (item.sizeBytes ?? 0),
    );
    final fileLabel = count == 1 ? '1 file' : '$count files';
    if (count == 0 || totalBytes <= 0) {
      return count == 1 ? '1 file ready' : '$count files ready';
    }

    return '$fileLabel, ${_formatBytes(totalBytes)}';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }

    final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
    final formatted = value.toStringAsFixed(decimals);
    return '$formatted ${units[unitIndex]}';
  }

  double _previewHeightFor(BuildContext context) {
    final viewportCap = MediaQuery.sizeOf(context).height * 0.32;
    final itemCount = items.length;
    final dividerCount = itemCount > 0 ? itemCount : 0;
    final hasFooter = itemCount > 1;

    final contentHeight =
        _kPreviewTableTopPadding +
        _kPreviewTableHeaderHeight +
        (dividerCount * _kPreviewDividerHeight) +
        (itemCount * _kPreviewRowHeight) +
        (hasFooter ? _kPreviewFooterHeight : 0);

    return contentHeight.clamp(0, viewportCap).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _selectionSummaryLabel(items);
    final previewHeight = _previewHeightFor(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Selected files',
                style: driftSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: kSurface2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: kBorder),
                ),
                child: Text(
                  summary,
                  style: driftSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: kMuted,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: previewHeight,
            child: PreviewTableViewport(
              items: plainTransferDisplayItems(items),
              maxHeight: previewHeight,
            ),
          ),
        ],
      ),
    );
  }
}
