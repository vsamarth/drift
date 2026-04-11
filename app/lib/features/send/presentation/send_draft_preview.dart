import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/drift_theme.dart';
import '../../receive/application/service.dart';
import '../../receive/application/state.dart';
import '../../transfers/presentation/widgets/transfer_presentation_helpers.dart';
import '../application/model.dart';
import '../application/send_selection_picker.dart';
import 'receive_code_field.dart';

class SendDraftPreview extends ConsumerStatefulWidget {
  const SendDraftPreview({
    super.key,
    required this.files,
  });

  final List<SendPickedFile> files;

  @override
  ConsumerState<SendDraftPreview> createState() => _SendDraftPreviewState();
}

class _SendDraftPreviewState extends ConsumerState<SendDraftPreview> {
  late List<SendPickedFile> _files;
  String _code = '';

  @override
  void initState() {
    super.initState();
    _files = List<SendPickedFile>.of(widget.files);
  }

  @override
  void didUpdateWidget(covariant SendDraftPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.files, widget.files)) {
      _files = List<SendPickedFile>.of(widget.files);
    }
  }

  Future<void> _appendSelection(
    Future<List<SendPickedFile>> Function(SendSelectionPicker picker) pick,
  ) async {
    final picker = ref.read(sendSelectionPickerProvider);
    final selected = await pick(picker);
    if (selected.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _files = [..._files, ...selected];
    });
  }

  void _updateCode(String value) {
    setState(() {
      _code = value;
    });
  }

  String _selectionSummaryLabel(List<SendPickedFile> files) {
    final count = files.length;
    final totalBytes = files.fold<BigInt>(
      BigInt.zero,
      (sum, item) => sum + (item.sizeBytes ?? BigInt.zero),
    );
    if (count == 0 || totalBytes == BigInt.zero) {
      return count == 1 ? '1 item ready' : '$count items ready';
    }

    return '${count == 1 ? '1 item' : '$count items'}, ${formatBytes(totalBytes)}';
  }

  double _previewHeightFor(BuildContext context, List<SendPickedFile> files) {
    const tableTopPadding = 12.0;
    const tableHeaderHeight = 22.0;
    const dividerHeight = 1.0;
    const rowHeight = 38.0;

    final viewportCap = MediaQuery.sizeOf(context).height * 0.32;
    final itemCount = files.length;
    final dividerCount = itemCount > 0 ? itemCount : 0;

    final contentHeight =
        tableTopPadding +
        tableHeaderHeight +
        (dividerCount * dividerHeight) +
        (itemCount * rowHeight);

    return contentHeight.clamp(0, viewportCap).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _selectionSummaryLabel(_files);
    final previewHeight = _previewHeightFor(context, _files);

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
              const SizedBox(height: 12),
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
                        files: _files,
                        maxHeight: previewHeight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _appendSelection(
                        (picker) => picker.pickFiles(),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add files'),
                    ),
                    TextButton.icon(
                      onPressed: () => _appendSelection(
                        (picker) => picker.pickFolder(),
                      ),
                      icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                      label: const Text('Add folders'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SendDraftExtras(
                code: _code,
                onCodeChanged: _updateCode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendDraftExtras extends ConsumerStatefulWidget {
  const _SendDraftExtras({
    required this.code,
    required this.onCodeChanged,
  });

  final String code;
  final ValueChanged<String> onCodeChanged;

  @override
  ConsumerState<_SendDraftExtras> createState() => _SendDraftExtrasState();
}

class _SendDraftExtrasState extends ConsumerState<_SendDraftExtras> {
  List<NearbyReceiver> _nearbyDevices = const [];
  bool _isScanningNearby = false;
  bool _nearbyScanCompletedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_scanNearby());
      }
    });
  }

  Future<void> _scanNearby() async {
    setState(() {
      _isScanningNearby = true;
    });

    try {
      final devices = await ref
          .read(receiverServiceProvider.notifier)
          .scanNearby(timeout: const Duration(seconds: 4));
      if (!mounted) {
        return;
      }
      setState(() {
        _nearbyDevices = devices;
        _isScanningNearby = false;
        _nearbyScanCompletedOnce = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nearbyDevices = const [];
        _isScanningNearby = false;
        _nearbyScanCompletedOnce = true;
      });
    }
  }

  String _normalizedCode(String code) {
    return code.replaceAll(' ', '').trim().toUpperCase();
  }

  IconData _iconFor(NearbyReceiver receiver) {
    final label = '${receiver.label} ${receiver.fullname}'.toLowerCase();
    if (label.contains('phone')) {
      return Icons.smartphone_rounded;
    }
    if (label.contains('tablet')) {
      return Icons.tablet_mac_rounded;
    }
    return Icons.laptop_mac_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'NEARBY DEVICES',
                    style: driftSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: kMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: _isScanningNearby
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  kMuted,
                                ),
                              ),
                            )
                          : IconButton(
                              onPressed: _scanNearby,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: kMuted,
                              tooltip: 'Scan again',
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_nearbyDevices.isEmpty)
                Text(
                  _isScanningNearby && !_nearbyScanCompletedOnce
                      ? ' '
                      : 'No nearby devices found yet.',
                  style: driftSans(fontSize: 13, color: kMuted, height: 1.4),
                ),
              if (_nearbyDevices.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 94,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _nearbyDevices.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final receiver = _nearbyDevices[index];
                      final selected =
                          _normalizedCode(widget.code) ==
                          _normalizedCode(receiver.code);
                      return _NearbyDeviceTile(
                        receiver: receiver,
                        isSelected: selected,
                        icon: _iconFor(receiver),
                        onTap: () => widget.onCodeChanged(receiver.code),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card.outlined(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send with code',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter the six-character receiver code to start the transfer.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                ReceiveCodeField(
                  code: widget.code,
                  onChanged: widget.onCodeChanged,
                  hintText: 'Receiver code',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NearbyDeviceTile extends StatelessWidget {
  const _NearbyDeviceTile({
    required this.receiver,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  final NearbyReceiver receiver;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 92,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? kAccentCyanHover : kSurface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? kAccentCyanStrong : kBorder,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? kAccentCyanStrong
                  : kMuted.withValues(alpha: 0.9),
            ),
            const SizedBox(height: 8),
            Text(
              receiver.label,
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kInk,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
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
    final isDirectory = file.kind == SendPickedFileKind.directory;
    final sizeLabel = isDirectory || file.sizeBytes == null
        ? ''
        : formatBytes(file.sizeBytes!);
    final rowIcon = isDirectory
        ? Icons.folder_outlined
        : Icons.insert_drive_file_outlined;

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
            child: Icon(
              rowIcon,
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
