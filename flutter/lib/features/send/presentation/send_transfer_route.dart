import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/drift_theme.dart';
import '../../transfers/presentation/widgets/sending_connection_strip.dart';
import '../../transfers/presentation/widgets/transfer_flow_layout.dart';
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

    return PopScope(
      canPop: true,
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
        appBar: AppBar(
          backgroundColor: kBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Send'),
        ),
        body: SizedBox.expand(
          child: _TransferStateCard(
            state: state,
            viewData: viewData,
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
  });

  final SendState state;
  final SendTransferPageData viewData;

  @override
  Widget build(BuildContext context) {
    final accent = viewData.visual.accentColor;
    final showConnectionStrip = viewData.stripMode != null;
    final showFooterButton =
        state is SendStateTransferring || state is SendStateResult;

    return TransferFlowLayout(
      statusLabel: viewData.visual.statusLabel,
      statusColor: accent,
      title: viewData.visual.title,
      subtitle: viewData.visual.subtitle,
      explainer: _buildExplainer(viewData),
      illustration: showConnectionStrip
          ? SendingConnectionStrip(
              localLabel: viewData.localLabel,
              localDeviceType: viewData.localDeviceType,
              remoteLabel: viewData.remoteLabel,
              remoteDeviceType: viewData.remoteDeviceType,
              animate: viewData.visual.showSpinner,
              mode: viewData.stripMode!,
              transferProgress: viewData.progressFraction ?? 0.0,
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(viewData.visual.icon, size: 42, color: accent),
              ),
            ),
      manifest: _SendManifest(viewData: viewData),
      footer: Row(
        children: [
          Expanded(
            child: showFooterButton
                ? (state is SendStateResult
                    ? FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Done'),
                      )
                    : TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB34A4A),
                          backgroundColor: const Color(0xFFB34A4A)
                              .withValues(alpha: 0.08),
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
    final metrics = <Widget>[];
    if (viewData.progressLabel != null ||
        viewData.speedLabel != null ||
        viewData.etaLabel != null) {
      final extras = <String>[
        if (viewData.speedLabel != null) viewData.speedLabel!,
        if (viewData.etaLabel != null) viewData.etaLabel!,
      ];
      metrics.add(
        _TransferProgressPanel(
          progressLabel: viewData.progressLabel,
          progressFraction: viewData.progressFraction,
          extras: extras,
          accent: viewData.visual.accentColor,
        ),
      );
      metrics.add(const SizedBox(height: 16));
    }

    if (viewData.metrics.isNotEmpty) {
      metrics.add(_MetricList(metrics: viewData.metrics));
      metrics.add(const SizedBox(height: 16));
    }

    if (viewData.files.isNotEmpty) {
      metrics.add(_FileList(files: viewData.files));
    }

    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: metrics,
    );
  }
}

Widget? _buildExplainer(SendTransferPageData viewData) {
  final parts = <String>[];
  if (viewData.progressLabel != null) {
    parts.add(viewData.progressLabel!);
  }
  if (viewData.speedLabel != null) {
    parts.add(viewData.speedLabel!);
  }
  if (viewData.etaLabel != null) {
    parts.add(viewData.etaLabel!);
  }
  if (parts.isEmpty) {
    return null;
  }

  return Text(
    parts.join(' · '),
    style: driftSans(fontSize: 12, color: kMuted, height: 1.4),
  );
}

class _TransferProgressPanel extends StatelessWidget {
  const _TransferProgressPanel({
    required this.progressLabel,
    required this.progressFraction,
    required this.extras,
    required this.accent,
  });

  final String? progressLabel;
  final double? progressFraction;
  final List<String> extras;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progressLabel != null) ...[
            Text(
              progressLabel!,
              style: driftSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kInk,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
          ],
          LinearProgressIndicator(
            value: progressFraction?.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: accent.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
            borderRadius: BorderRadius.circular(999),
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              extras.join(' · '),
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: kMuted,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricList extends StatelessWidget {
  const _MetricList({required this.metrics});

  final List<SendTransferMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final labelStyle = driftSans(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: kMuted,
    );
    final valueStyle = driftSans(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: kInk,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: Text(metrics[i].label, style: labelStyle)),
              Expanded(
                flex: 3,
                child: Text(
                  metrics[i].value,
                  textAlign: TextAlign.end,
                  style: valueStyle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({required this.files});

  final List<SendTransferFileViewData> files;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Text(
              'Files',
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kMuted,
                letterSpacing: 0.15,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                for (int index = 0; index < files.length; index++) ...[
                  _FileRow(file: files[index]),
                  if (index < files.length - 1)
                    Divider(
                      height: 20,
                      thickness: 1,
                      color: kBorder.withValues(alpha: 0.55),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
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
                  const SizedBox(height: 4),
                  Text(
                    file.path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: driftMono(fontSize: 11.5, color: kMuted),
                  ),
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
