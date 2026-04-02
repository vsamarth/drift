import 'package:flutter/material.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';

const double _kPreviewTableSizeColumnWidth = 76;

/// Table-style list: columns + hairline dividers only (no panel border/fill).
class PreviewTable extends StatelessWidget {
  const PreviewTable({
    super.key,
    required this.items,
    required this.footerSummary,
  });

  final List<TransferItemViewData> items;
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
      fontWeight: FontWeight.w600,
      color: kMuted,
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
                width: _kPreviewTableSizeColumnWidth,
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

class PreviewTableViewport extends StatefulWidget {
  const PreviewTableViewport({
    super.key,
    required this.items,
    this.footerSummary,
    this.maxHeight,
    this.padding = EdgeInsets.zero,
  });

  final List<TransferItemViewData> items;
  final String? footerSummary;
  final double? maxHeight;
  final EdgeInsetsGeometry padding;

  @override
  State<PreviewTableViewport> createState() => _PreviewTableViewportState();
}

class _PreviewTableViewportState extends State<PreviewTableViewport> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = _PreviewTableViewportBody(
      controller: _scrollController,
      items: widget.items,
      footerSummary: widget.footerSummary,
    );

    if (widget.maxHeight != null) {
      child = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight!),
        child: child,
      );
    }

    return Padding(padding: widget.padding, child: child);
  }
}

class _PreviewTableViewportBody extends StatelessWidget {
  const _PreviewTableViewportBody({
    required this.controller,
    required this.items,
    required this.footerSummary,
  });

  final ScrollController controller;
  final List<TransferItemViewData> items;
  final String? footerSummary;

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
      fontWeight: FontWeight.w600,
      color: kMuted,
      letterSpacing: 0.15,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
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
                width: _kPreviewTableSizeColumnWidth,
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
        Flexible(
          child: Scrollbar(
            controller: controller,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: controller,
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i > 0) _divider,
                    _PreviewTableRow(item: items[i]),
                  ],
                  if (items.length > 1 && footerSummary != null) ...[
                    _divider,
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 28),
                          Expanded(
                            child: Text(
                              footerSummary!,
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
        ),
      ],
    );
  }
}

class _PreviewTableRow extends StatelessWidget {
  const _PreviewTableRow({required this.item});

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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 28, child: Icon(icon, size: 18, color: kMuted)),
          Expanded(
            child: Text(
              item.name,
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
            width: _kPreviewTableSizeColumnWidth,
            child: Text(
              item.size,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: driftSans(fontSize: 12, color: kMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class PreviewList extends StatelessWidget {
  const PreviewList({super.key, required this.items});

  final List<TransferItemViewData> items;

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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: driftSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kInk,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(item.size, style: driftSans(fontSize: 12, color: kMuted)),
        ],
      ),
    );
  }
}
