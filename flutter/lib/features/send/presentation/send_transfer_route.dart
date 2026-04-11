import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/drift_theme.dart';
import '../../transfers/application/manifest.dart';
import '../../transfers/application/state.dart' as transfer_state;
import '../../transfers/presentation/widgets/sending_connection_strip.dart';
import '../../transfers/presentation/widgets/transfer_flow_layout.dart';
import '../../transfers/presentation/widgets/transfer_presentation_helpers.dart';
import '../application/controller.dart';
import '../application/model.dart';
import '../application/state.dart';
import '../application/transfer_state.dart';
import 'send_transfer_view_data.dart';
import 'package:app/features/transfers/presentation/widgets/manifest_tree_card.dart';
import 'package:app/features/send/presentation/widgets/recipient_avatar.dart';

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
    final transfer = switch (state) {
      SendStateTransferring(:final transfer) => transfer,
      SendStateResult(:final transfer) => transfer,
      _ => null,
    };
    final primary = Theme.of(context).colorScheme.primary;
    final isSuccessResult =
        state is SendStateResult &&
        viewData.visual.statusLabel.toLowerCase().trim() == 'success';

    final progress = _buildSharedTransferProgress(
      transfer,
      viewData.files.length,
    );
    final manifestItems = viewData.files
        .map(
          (file) =>
              TransferManifestItem(path: file.path, sizeBytes: file.sizeBytes),
        )
        .toList(growable: false);
    final stripMode =
        viewData.stripMode ??
        (isSuccessResult
            ? SendingStripMode.transferring
            : SendingStripMode.waitingOnRecipient);

    String subtitle = viewData.visual.subtitle;
    if (progress != null && state is SendStateTransferring) {
      final extras = <String>[
        if (progress.speedLabel != null) progress.speedLabel!,
        if (progress.etaLabel != null) progress.etaLabel!,
      ];
      if (extras.isNotEmpty) {
        subtitle = extras.join(' | ');
      }
    }

    return TransferFlowLayout(
      statusLabel: viewData.visual.statusLabel,
      statusColor: accent,
      subtitle: subtitle,
      explainer: null,
      illustration: RecipientAvatar(
        deviceName: viewData.remoteLabel,
        deviceType: viewData.remoteDeviceType ?? 'phone',
        mode: stripMode,
        progress: (viewData.progressFraction ?? 0.0).clamp(0.0, 1.0),
        animate: viewData.visual.showSpinner,
      ),
      manifest: manifestItems.isEmpty
          ? null
          : ManifestTreeCard(items: manifestItems),
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
                            backgroundColor: const Color(
                              0xFFB34A4A,
                            ).withValues(alpha: 0.08),
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: const Color(
                                  0xFFB34A4A,
                                ).withValues(alpha: 0.15),
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

transfer_state.TransferTransferProgress? _buildSharedTransferProgress(
  SendTransferState? transfer,
  int fallbackFileCount,
) {
  if (transfer == null || transfer.totalBytes == BigInt.zero) {
    return null;
  }

  final snapshot = transfer.snapshot;
  return transfer_state.TransferTransferProgress(
    bytesTransferred: transfer.bytesSent,
    totalBytes: transfer.totalBytes,
    completedFiles: snapshot?.completedFiles ?? 0,
    totalFiles: snapshot?.totalFiles ?? fallbackFileCount,
    speedLabel: viewSpeedLabel(transfer),
    etaLabel: viewEtaLabel(transfer),
  );
}

String? viewSpeedLabel(SendTransferState transfer) {
  final speed = transfer.snapshot?.bytesPerSec;
  if (speed == null || speed <= BigInt.zero) {
    return null;
  }
  return '${formatBytes(speed)}/s';
}

String? viewEtaLabel(SendTransferState transfer) {
  final eta = transfer.snapshot?.etaSeconds;
  if (eta == null || eta <= BigInt.zero) {
    return null;
  }

  final seconds = eta.toInt();
  if (seconds < 60) {
    return '$seconds s left';
  }

  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return remainingSeconds == 0
        ? '$minutes m left'
        : '$minutes m $remainingSeconds s left';
  }

  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return remainingMinutes == 0
      ? '$hours h left'
      : '$hours h $remainingMinutes m left';
}
