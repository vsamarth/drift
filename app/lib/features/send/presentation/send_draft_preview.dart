import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/drift_theme.dart';
import '../../transfers/presentation/widgets/transfer_presentation_helpers.dart';
import '../application/model.dart';

class SendDraftPreview extends StatelessWidget {
  const SendDraftPreview({
    super.key,
    required this.files,
  });

  final List<SendPickedFile> files;

  String _selectionSummaryLabel(List<SendPickedFile> files) {
    final count = files.length;
    final totalBytes = files.fold<BigInt>(
      BigInt.zero,
      (sum, item) => sum + (item.sizeBytes ?? BigInt.zero),
    );
    final fileLabel = count == 1 ? '1 file' : '$count files';
    if (count == 0 || totalBytes == BigInt.zero) {
      return count == 1 ? '1 file ready' : '$count files ready';
    }

    return '$fileLabel, ${formatBytes(totalBytes)}';
  }

  double _previewHeightFor(BuildContext context) {
    const tableTopPadding = 12.0;
    const tableHeaderHeight = 22.0;
    const dividerHeight = 1.0;
    const rowHeight = 38.0;
    const footerHeight = 28.0;

    final viewportCap = MediaQuery.sizeOf(context).height * 0.32;
    final itemCount = files.length;
    final dividerCount = itemCount > 0 ? itemCount : 0;
    final hasFooter = itemCount > 1;

    final contentHeight =
        tableTopPadding +
        tableHeaderHeight +
        (dividerCount * dividerHeight) +
        (itemCount * rowHeight) +
        (hasFooter ? footerHeight : 0);

    return contentHeight.clamp(0, viewportCap).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _selectionSummaryLabel(files);
    final previewHeight = _previewHeightFor(context);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Selected files',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to send this selection.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Container(
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
                      child: _PreviewTableViewport(
                        files: files,
                        maxHeight: previewHeight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewTableViewport extends StatelessWidget {
  const _PreviewTableViewport({
    required this.files,
    required this.maxHeight,
  });

  final List<SendPickedFile> files;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
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

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
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
          Divider(
            height: 1,
            thickness: 1,
            color: kBorder.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 10),
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
                        thickness: 1,
                        color: kBorder.withValues(alpha: 0.55),
                      ),
                    _PreviewTableRow(file: files[i]),
                  ],
                  if (files.length > 1) ...[
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: kBorder.withValues(alpha: 0.55),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 28),
                          Expanded(
                            child: Text(
                              '${files.length} files ready to preview',
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewTableRow extends StatelessWidget {
  const _PreviewTableRow({required this.file});

  final SendPickedFile file;

  @override
  Widget build(BuildContext context) {
    final sizeLabel = file.sizeBytes == null
        ? '—'
        : formatBytes(file.sizeBytes!);

    return SizedBox(
      height: 38,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF7F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.insert_drive_file_outlined,
              size: 13,
              color: Color(0xFF4F8B88),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: driftSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kInk,
              ),
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(
              sizeLabel,
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
