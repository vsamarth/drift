import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/drift_theme.dart';
import '../../transfers/presentation/widgets/sending_connection_strip.dart';
import '../../transfers/presentation/widgets/utility_transfer_flow_layout.dart';
import '../application/controller.dart';
import '../application/model.dart';
import '../application/state.dart';
import 'send_transfer_view_data.dart';

class SendTransferRoutePage extends ConsumerStatefulWidget {
  const SendTransferRoutePage({super.key, required this.request});

  final SendRequestData request;

  @override
  ConsumerState<SendTransferRoutePage> createState() =>
      _SendTransferRoutePageState();
}

class _SendTransferRoutePageState extends ConsumerState<SendTransferRoutePage> {
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(sendControllerProvider.notifier).startTransfer(widget.request);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sendControllerProvider);
    final controller = ref.read(sendControllerProvider.notifier);
    final viewData = buildSendTransferPageData(
      state: state,
      request: widget.request,
    );

    void exitRoute() {
      if (!mounted) {
        return;
      }

      setState(() {
        _allowPop = true;
      });
      Navigator.of(context).pop();
    }

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          return;
        }

        final currentState = ref.read(sendControllerProvider);
        switch (currentState) {
          case SendStateTransferring():
            controller.cancelTransfer();
          case SendStateResult():
            controller.clearDraft();
          case SendStateIdle() || SendStateDrafting():
            break;
        }
      },
      child: Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: SizedBox.expand(
            child: _TransferStateCard(
              state: state,
              viewData: viewData,
              onExit: exitRoute,
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferStateCard extends StatelessWidget {
  const _TransferStateCard({
    required this.state,
    required this.viewData,
    required this.onExit,
  });

  final SendState state;
  final SendTransferPageData viewData;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final accent = viewData.visual.accentColor;
    final showFooterButton =
        state is SendStateTransferring || state is SendStateResult;
    final primary = Theme.of(context).colorScheme.primary;
    final isSuccessResult = state is SendStateResult &&
        viewData.visual.statusLabel.toLowerCase().trim() == 'success';

    final heroText = viewData.etaLabel ??
        (viewData.progressFraction != null
            ? '${(viewData.progressFraction! * 100).toInt()}%'
            : viewData.visual.statusLabel);

    return UtilityTransferFlowLayout(
      statusLabel: viewData.visual.statusLabel,
      statusColor: accent,
      heroText: heroText,
      subtitle: 'Sending to ${viewData.remoteLabel}',
      utilityBar: Row(
        children: [
          if (viewData.speedLabel != null)
            Text(
              viewData.speedLabel!,
              style: driftSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kInk,
              ),
            ),
          if (viewData.speedLabel != null && viewData.progressLabel != null)
            Text('  ·  ', style: driftSans(color: kMuted)),
          if (viewData.progressLabel != null)
            Text(
              viewData.progressLabel!,
              style: driftSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kMuted,
              ),
            ),
        ],
      ),
      progressBar: LinearProgressIndicator(
        value: viewData.progressFraction?.clamp(0.0, 1.0),
        minHeight: 12,
        backgroundColor: accent.withValues(alpha: 0.1),
        valueColor: AlwaysStoppedAnimation<Color>(accent),
        borderRadius: BorderRadius.circular(999),
      ),
      activityLine: viewData.files.any((f) => f.state == SendTransferFileState.active)
          ? Text(
              'Now: ${viewData.files.firstWhere((f) => f.state == SendTransferFileState.active).name}',
              style: driftSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kInk,
              ),
            )
          : null,
      manifest: _SendManifest(viewData: viewData),
      footer: Row(
        children: [
          Expanded(
            child: showFooterButton
                ? (state is SendStateResult
                    ? FilledButton(
                        onPressed: onExit,
                        style: FilledButton.styleFrom(
                          backgroundColor: isSuccessResult ? primary : accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Done'),
                      )
                    : TextButton(
                        onPressed: onExit,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB34A4A),
                          backgroundColor:
                              const Color(0xFFB34A4A).withValues(alpha: 0.08),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: const Color(0xFFB34A4A)
                                  .withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        child: const Text('Cancel transfer'),
                      ))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SendManifest extends StatelessWidget {
  const _SendManifest({required this.viewData});

  final SendTransferPageData viewData;

  @override
  Widget build(BuildContext context) {
    if (viewData.files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FileList(files: viewData.files),
      ],
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({required this.files});

  final List<SendTransferFileViewData> files;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'FILES',
          style: driftSans(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: kMuted,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 16),
        for (int index = 0; index < files.length; index++) ...[
          _FileRow(file: files[index]),
          if (index < files.length - 1) const SizedBox(height: 20),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final SendTransferFileViewData file;

  @override
  Widget build(BuildContext context) {
    final accent = switch (file.state) {
      SendTransferFileState.pending => kMuted,
      SendTransferFileState.active => kAccentCyanStrong,
      SendTransferFileState.completed => const Color(0xFF49B36C),
    };

    final icon = switch (file.state) {
      SendTransferFileState.pending => Icons.radio_button_unchecked_rounded,
      SendTransferFileState.active => Icons.sync_rounded,
      SendTransferFileState.completed => Icons.check_circle_rounded,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: driftSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: kInk,
                    ),
                  ),
                  if (file.state == SendTransferFileState.active) ...[
                    const SizedBox(height: 4),
                    Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: driftMono(fontSize: 11, color: kMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              file.sizeLabel,
              style: driftSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: kMuted,
              ),
            ),
          ],
        ),
        if (file.state == SendTransferFileState.active &&
            file.progressFraction != null) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: file.progressFraction!.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: accent.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
            borderRadius: BorderRadius.circular(999),
          ),
        ],
        if (file.statusLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            file.statusLabel!,
            style: driftSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ],
    );
  }
}

