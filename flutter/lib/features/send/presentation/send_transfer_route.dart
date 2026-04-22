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
import 'package:app/features/transfers/presentation/widgets/active_transfer_file_list.dart';
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

    final Widget subtitle;
    if (progress != null && state is SendStateTransferring) {
      subtitle = buildSpeedLine(
        speedLabel: progress.speedLabel ?? '',
        etaLabel: progress.etaLabel,
      );
    } else {
      subtitle = buildSubtitleText(viewData.visual.subtitle);
    }

    return TransferFlowLayout(
      statusLabel: viewData.visual.statusLabel,
      statusColor: accent,
      subtitle: subtitle,
      explainer: state is SendStateResult ? _SendStatsGrid(viewData: viewData) : null,
      illustration: RecipientAvatar(
        deviceName: viewData.remoteLabel,
        deviceType: viewData.remoteDeviceType ?? 'phone',
        mode: stripMode,
        progress: (viewData.progressFraction ?? 0.0).clamp(0.0, 1.0),
        animate: viewData.visual.showSpinner,
      ),
      manifest: manifestItems.isEmpty
          ? null
          : (state is SendStateTransferring
              ? ActiveTransferFileList(
                  items: manifestItems,
                  progress: progress,
                )
              : ManifestTreeCard(
                  items: manifestItems,
                  initiallyExpanded: state is SendStateResult,
                )),
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

class _SendStatsGrid extends StatelessWidget {
  const _SendStatsGrid({required this.viewData});

  final SendTransferPageData viewData;

  @override
  Widget build(BuildContext context) {
    // Only show stats if we have at least one valid metric
    final displayStats = <_StatItem>[
      if (viewData.durationLabel != null)
        _StatItem(label: 'TIME', value: viewData.durationLabel!),
      if (viewData.averageSpeedLabel != null)
        _StatItem(label: 'SPEED', value: viewData.averageSpeedLabel!),
    ];

    if (displayStats.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: kFill.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (int i = 0; i < displayStats.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 24,
                color: kBorder.withValues(alpha: 0.5),
              ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    displayStats[i].label,
                    style: driftSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: kMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayStats[i].value,
                    style: driftSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;
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

  return formatEta(eta);
}
