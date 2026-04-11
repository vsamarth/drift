import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/drift_theme.dart';
import '../../../app/app_router.dart';
import '../application/controller.dart';
import '../../receive/application/service.dart';
import '../../receive/application/state.dart';
import '../../transfers/presentation/widgets/transfer_presentation_helpers.dart';
import '../application/model.dart';
import '../application/directory_size.dart';
import '../application/send_selection_picker.dart';
import '../application/state.dart';
import 'receive_code_field.dart';

class SendDraftRoutePage extends ConsumerStatefulWidget {
  const SendDraftRoutePage({super.key, required this.files});

  final List<SendPickedFile> files;

  @override
  ConsumerState<SendDraftRoutePage> createState() => _SendDraftRoutePageState();
}

class _SendDraftRoutePageState extends ConsumerState<SendDraftRoutePage> {
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.files.isNotEmpty) {
        ref.read(sendControllerProvider.notifier).beginDraft(widget.files);
      }
      setState(() {
        _seeded = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_seeded) {
      return const SizedBox.shrink();
    }
    return const SendDraftPreview();
  }
}

class SendDraftPreview extends ConsumerStatefulWidget {
  const SendDraftPreview({super.key});

  @override
  ConsumerState<SendDraftPreview> createState() => _SendDraftPreviewState();
}

class _SendDraftPreviewState extends ConsumerState<SendDraftPreview> {
  final Set<String> _pendingDirectorySizes = <String>{};
  final Map<String, BigInt> _resolvedDirectorySizes = <String, BigInt>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _hydrateDirectorySizes();
      }
    });
  }

  Future<void> _appendSelection(
    Future<List<SendPickedFile>> Function(SendSelectionPicker picker) pick,
  ) async {
    final picker = ref.read(sendSelectionPickerProvider);
    final selected = await pick(picker);
    if (selected.isEmpty || !mounted) {
      return;
    }

    ref.read(sendControllerProvider.notifier).appendDraftItems(selected);
  }

  void _removeFile(SendPickedFile file) {
    ref.read(sendControllerProvider.notifier).removeDraftItem(file.path);
  }

  void _hydrateDirectorySizes() {
    final state = ref.read(sendControllerProvider);
    for (final item in state.items) {
      if (item.kind != SendPickedFileKind.directory) {
        continue;
      }
      if (_resolvedDirectorySizes.containsKey(item.path) ||
          _pendingDirectorySizes.contains(item.path)) {
        continue;
      }
      _pendingDirectorySizes.add(item.path);
      unawaited(_resolveDirectorySize(item.path));
    }
  }

  Future<void> _resolveDirectorySize(String path) async {
    try {
      final sizeBytes = await ref
          .read(directorySizeCalculatorProvider)
          .sizeOfDirectory(path);
      if (!mounted) {
        return;
      }

      final state = ref.read(sendControllerProvider);
      final exists = state.items.any(
        (item) =>
            item.path == path && item.kind == SendPickedFileKind.directory,
      );
      if (!exists) {
        return;
      }

      setState(() {
        _resolvedDirectorySizes[path] = sizeBytes;
      });
    } finally {
      _pendingDirectorySizes.remove(path);
    }
  }

  List<SendPickedFile> _displayFilesFor(SendState state) {
    return state.items
        .map((item) {
          final sizeBytes = item.kind == SendPickedFileKind.directory
              ? (_resolvedDirectorySizes[item.path] ?? item.sizeBytes)
              : item.sizeBytes;
          return SendPickedFile(
            path: item.path,
            name: item.name,
            kind: item.kind,
            sizeBytes: sizeBytes,
          );
        })
        .toList(growable: false);
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
    const dividerHeight = 1.0;
    const rowHeight = 38.0;
    const verticalPadding = 12.0;

    final viewportCap = MediaQuery.sizeOf(context).height * 0.32;
    final itemCount = files.length;
    final dividerCount = itemCount > 0 ? itemCount - 1 : 0;

    final contentHeight =
        verticalPadding +
        (itemCount * rowHeight) +
        (dividerCount * dividerHeight);

    return contentHeight.clamp(0, viewportCap).toDouble();
  }

  bool _canStartSend(SendState state) {
    return state.phase == SendSessionPhase.drafting &&
        state.items.isNotEmpty &&
        ref.read(sendControllerProvider.notifier).canStartSend();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sendControllerProvider);
    ref.listen<SendState>(sendControllerProvider, (previous, next) {
      if (previous?.items != next.items) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _hydrateDirectorySizes();
          }
        });
      }
      if (previous?.phase == SendSessionPhase.drafting &&
          next.phase == SendSessionPhase.idle &&
          mounted) {
        context.pop();
      }
    });

    if (state.phase == SendSessionPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          context.pop();
        }
      });
      return const SizedBox.shrink();
    }

    final files = _displayFilesFor(state);
    final summary = _selectionSummaryLabel(files);
    final previewHeight = _previewHeightFor(context, files);
    final controller = ref.read(sendControllerProvider.notifier);
    final canEditDraft = state.phase == SendSessionPhase.drafting;
    final canStartSend = _canStartSend(state);
    final actionLabel = state.phase == SendSessionPhase.result
        ? 'Done'
        : (state.phase == SendSessionPhase.transferring ? 'Sending...' : 'Send');

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Selected files',
                          style: driftSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: kInk,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: kSurface,
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kBorder),
                      ),
                      child: SizedBox(
                        height: previewHeight,
                        child: _PreviewTableViewport(
                          files: files,
                          maxHeight: previewHeight,
                          onRemove: _removeFile,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: canEditDraft
                                ? () => _appendSelection(
                                    (picker) => picker.pickFiles(),
                                  )
                                : null,
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add files'),
                          ),
                          TextButton.icon(
                            onPressed: canEditDraft
                                ? () => _appendSelection(
                                    (picker) => picker.pickFolder(),
                                  )
                                : null,
                            icon: const Icon(
                              Icons.create_new_folder_outlined,
                              size: 16,
                            ),
                            label: const Text('Add folders'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SendDraftExtras(controller: controller),
                    if (state.phase == SendSessionPhase.result) ...[
                      const SizedBox(height: 18),
                      _SendResultCard(result: state.result!),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                decoration: BoxDecoration(
                  color: kBg,
                  border: Border(
                    top: BorderSide(color: kBorder.withValues(alpha: 0.5)),
                  ),
                ),
                child: FilledButton(
                  onPressed: state.phase == SendSessionPhase.result
                      ? controller.clearDraft
                      : (canStartSend
                            ? () {
                                final request = controller.buildSendRequest();
                                if (request == null) {
                                  return;
                                }
                                context.pushSendTransfer(request: request);
                              }
                            : null),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: kAccentCyanStrong,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(actionLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendResultCard extends StatelessWidget {
  const _SendResultCard({required this.result});

  final SendTransferResult result;

  @override
  Widget build(BuildContext context) {
    final accent = switch (result.outcome) {
      SendTransferOutcome.success => const Color(0xFF1F7A57),
      SendTransferOutcome.cancelled => const Color(0xFF8B6B20),
      SendTransferOutcome.declined => const Color(0xFF8B4B20),
      SendTransferOutcome.failed => const Color(0xFFB42318),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.title,
            style: driftSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kInk,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            result.message,
            style: driftSans(fontSize: 13.5, color: kMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _SendDraftExtras extends ConsumerStatefulWidget {
  const _SendDraftExtras({required this.controller});

  final SendController controller;

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sendControllerProvider);
    final titleStyle = driftSans(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: kInk,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Nearby devices', style: titleStyle),
            const Spacer(),
            _ScanAction(isScanning: _isScanningNearby, onPressed: _scanNearby),
          ],
        ),
        const SizedBox(height: 12),
        if (_nearbyDevices.isEmpty)
          _NearbyStatusCard(
            isScanning: _isScanningNearby && !_nearbyScanCompletedOnce,
          )
        else
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _nearbyDevices.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final receiver = _nearbyDevices[index];
                final selected =
                    state.destination.mode == SendDestinationMode.nearby &&
                    state.destination.ticket == receiver.ticket;
                return _NearbyDeviceTile(
                  receiver: receiver,
                  isSelected: selected,
                  icon: Icons.devices_rounded,
                  onTap: () => widget.controller.selectNearbyReceiver(receiver),
                );
              },
            ),
          ),
        const SizedBox(height: 18),
        Text('Send with code', style: titleStyle),
        const SizedBox(height: 6),
        Text(
          'Use the 6 characters shown on the receiver.',
          style: driftSans(fontSize: 13.5, color: kMuted, height: 1.4),
        ),
        const SizedBox(height: 16),
        ReceiveCodeField(
          code: state.destination.mode == SendDestinationMode.code
              ? state.destination.code ?? ''
              : '',
          onChanged: widget.controller.updateDestinationCode,
          hintText: 'AB12CD',
          understated: true,
        ),
      ],
    );
  }
}

class _ScanAction extends StatelessWidget {
  const _ScanAction({required this.isScanning, required this.onPressed});

  final bool isScanning;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (isScanning) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FB9CA)),
        ),
      );
    }

    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: Text(
        'Rescan',
        style: driftSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF7AAFC9),
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF7AAFC9),
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _NearbyStatusCard extends StatelessWidget {
  const _NearbyStatusCard({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final title = isScanning
        ? 'Scanning for nearby receivers...'
        : 'No nearby devices found';
    final subtitle = isScanning
        ? 'Make sure both devices are on the same Wi-Fi.'
        : 'Make sure both devices are on the same Wi-Fi. Local network access may be required.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 22,
              height: 22,
              child: Icon(
                isScanning ? Icons.radar_rounded : Icons.wifi_off_rounded,
                size: 20,
                color: const Color(0xFF8E8E8E),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: driftSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: driftSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: kMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
        width: 106,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF4F8FA) : kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF8DBED4) : kBorder,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? const Color(0xFF7AAFC9) : kMuted,
            ),
            const SizedBox(height: 10),
            Text(
              receiver.label,
              style: driftSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: kInk,
                height: 1.18,
              ),
              maxLines: 2,
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
                        thickness: 1,
                        color: kBorder.withValues(alpha: 0.55),
                      ),
                    _PreviewTableRow(
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
  const _PreviewTableRow({required this.file, required this.onRemove});

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
        ? Icons.folder_outlined
        : Icons.insert_drive_file_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Icon(rowIcon, size: 18, color: Color(0xFF7A7A7A)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: file.name,
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
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            visualDensity: VisualDensity.compact,
            color: kMuted,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}
