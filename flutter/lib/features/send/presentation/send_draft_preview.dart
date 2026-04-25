import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/drift_theme.dart';
import '../../../app/app_router.dart';
import '../application/controller.dart';
import '../../transfers/presentation/widgets/transfer_presentation_helpers.dart';
import '../application/model.dart';
import '../application/item_size.dart';
import '../application/send_selection_picker.dart';
import '../application/state.dart';
import 'widgets/send_destination_selector.dart';
import 'widgets/send_draft_file_list.dart';

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

class SendDraftPreview extends ConsumerWidget {
  const SendDraftPreview({super.key});

  Future<void> _appendSelection(
    WidgetRef ref,
    Future<List<SendPickedFile>> Function(SendSelectionPicker picker) pick,
  ) async {
    final picker = ref.read(sendSelectionPickerProvider);
    final selected = await pick(picker);
    if (selected.isEmpty) {
      return;
    }

    ref.read(sendControllerProvider.notifier).appendDraftItems(selected);
  }

  void _removeFile(WidgetRef ref, SendPickedFile file) {
    ref.read(sendControllerProvider.notifier).removeDraftItem(file.path);
  }

  List<SendPickedFile> _displayFilesFor(SendState state) {
    final (items, resolvedSizes) = switch (state) {
      SendStateDrafting(:final items, :final resolvedDirectorySizes) => (
        items,
        resolvedDirectorySizes,
      ),
      SendStateTransferring(:final items, :final resolvedDirectorySizes) => (
        items,
        resolvedDirectorySizes,
      ),
      SendStateResult(:final items, :final resolvedDirectorySizes) => (
        items,
        resolvedDirectorySizes,
      ),
      SendStateIdle() => (const <SendDraftItem>[], const <String, BigInt>{}),
    };

    return items
        .map((item) {
          final sizeBytes = effectiveDraftItemSize(item, resolvedSizes);
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
    const dividerHeight = 0.5;
    const rowHeight = 56.0;
    const verticalPadding = 0.0;

    final viewportCap = MediaQuery.sizeOf(context).height * 0.32;
    final itemCount = files.length;
    final dividerCount = itemCount > 0 ? itemCount - 1 : 0;

    final contentHeight =
        verticalPadding +
        (itemCount * rowHeight) +
        (dividerCount * dividerHeight);

    return contentHeight.clamp(0, viewportCap).toDouble();
  }

  bool _canStartSend(WidgetRef ref, SendState state) {
    return state is SendStateDrafting &&
        state.items.isNotEmpty &&
        ref.read(sendControllerProvider.notifier).canStartSend();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sendControllerProvider);
    ref.listen<SendState>(sendControllerProvider, (previous, next) {
      if (previous is SendStateDrafting && next is SendStateIdle) {
        context.pop();
      }
    });

    if (state is SendStateIdle) {
      return const _SendDraftIdleRecovery();
    }

    final files = _displayFilesFor(state);
    final summary = _selectionSummaryLabel(files);
    final previewHeight = _previewHeightFor(context, files);
    final controller = ref.read(sendControllerProvider.notifier);
    final canEditDraft = state is SendStateDrafting;
    final canStartSend = _canStartSend(ref, state);
    final actionLabel = switch (state) {
      SendStateResult() => 'Done',
      SendStateTransferring() => 'Sending...',
      _ => 'Send',
    };

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
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kBorder),
                      ),
                      child: SizedBox(
                        height: previewHeight,
                        child: SendDraftFileList(
                          files: files,
                          maxHeight: previewHeight,
                          onRemove: (SendPickedFile file) =>
                              _removeFile(ref, file),
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
                                    ref,
                                    (picker) => picker.pickFiles(),
                                  )
                                : null,
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add files'),
                          ),
                          TextButton.icon(
                            onPressed: canEditDraft
                                ? () => _appendSelection(
                                    ref,
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
                    SendDestinationSelector(controller: controller),
                    if (state is SendStateResult) ...[
                      const SizedBox(height: 18),
                      _SendResultCard(result: state.result),
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
                  onPressed: state is SendStateResult
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

class _SendDraftIdleRecovery extends StatelessWidget {
  const _SendDraftIdleRecovery();

  @override
  Widget build(BuildContext context) {
    void exitToHome() {
      if (Navigator.of(context).canPop()) {
        context.pop();
        return;
      }
      context.goHome();
    }

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
            onPressed: exitToHome,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No files selected',
                  textAlign: TextAlign.center,
                  style: driftSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start from home to pick files or folders, then try sending again.',
                  textAlign: TextAlign.center,
                  style: driftSans(fontSize: 13.5, color: kMuted, height: 1.35),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: exitToHome,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 44),
                    backgroundColor: kAccentCyanStrong,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Go to home'),
                ),
              ],
            ),
          ),
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
