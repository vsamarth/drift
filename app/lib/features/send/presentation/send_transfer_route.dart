import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/drift_theme.dart';
import '../../transfers/presentation/widgets/sending_connection_strip.dart';
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
        if (currentState.phase == SendSessionPhase.transferring) {
          controller.cancelTransfer();
        } else if (currentState.phase == SendSessionPhase.result) {
          controller.clearDraft();
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
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            _SummarySection(
              title: 'Destination',
              children: [
                Text(
                  switch (widget.request.destinationMode) {
                    SendDestinationMode.code => 'Code',
                    SendDestinationMode.nearby => 'Nearby',
                    SendDestinationMode.none => 'Unknown',
                  },
                  style: driftSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: kMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  switch (widget.request.destinationMode) {
                    SendDestinationMode.code =>
                      widget.request.code ?? 'No code',
                    SendDestinationMode.nearby =>
                      widget.request.lanDestinationLabel ??
                          widget.request.ticket ??
                          'No ticket',
                    SendDestinationMode.none => 'No destination',
                  },
                  style: driftSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kInk,
                  ),
                ),
                if (widget.request.ticket != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.request.ticket!,
                    style: driftMono(fontSize: 12.5, color: kMuted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _SummarySection(
              title: 'Files',
              children: [
                for (final path in widget.request.paths) ...[
                  Text(path, style: driftMono(fontSize: 13.5, color: kInk)),
                  const SizedBox(height: 6),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _SummarySection(
              title: 'Local device',
              children: [
                Text(
                  widget.request.deviceName,
                  style: driftSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.request.deviceType,
                  style: driftSans(fontSize: 13.5, color: kMuted),
                ),
              ],
            ),
            if (widget.request.serverUrl != null) ...[
              const SizedBox(height: 14),
              _SummarySection(
                title: 'Server',
                children: [
                  Text(
                    widget.request.serverUrl!,
                    style: driftMono(fontSize: 12.5, color: kMuted),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            _TransferStateCard(
              state: state,
              viewData: viewData,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: driftSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: kMuted,
              letterSpacing: 0.18,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
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
    final showFooterButton = state.phase == SendSessionPhase.transferring ||
        state.phase == SendSessionPhase.result;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      viewData.visual.statusLabel,
                      style: driftSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            viewData.visual.title,
            style: driftSans(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: kInk,
              letterSpacing: -0.6,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            viewData.visual.subtitle,
            style: driftSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: kMuted,
              height: 1.4,
            ),
          ),
          if (showConnectionStrip) ...[
            const SizedBox(height: 18),
            SendingConnectionStrip(
              localLabel: viewData.localLabel,
              localDeviceType: viewData.localDeviceType,
              remoteLabel: viewData.remoteLabel,
              remoteDeviceType: viewData.remoteDeviceType,
              animate: viewData.visual.showSpinner,
              mode: viewData.stripMode!,
              transferProgress: viewData.progressFraction ?? 0.0,
            ),
          ] else ...[
            const SizedBox(height: 18),
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Icon(viewData.visual.icon, size: 42, color: accent),
                ),
              ),
            ),
          ],
          if (viewData.progressLabel != null ||
              viewData.speedLabel != null ||
              viewData.etaLabel != null) ...[
            const SizedBox(height: 18),
            _ProgressPanel(
              progressLabel: viewData.progressLabel,
              progressFraction: viewData.progressFraction,
              speedLabel: viewData.speedLabel,
              etaLabel: viewData.etaLabel,
              accent: accent,
            ),
          ],
          if (viewData.metrics.isNotEmpty) ...[
            const SizedBox(height: 18),
            _MetricGrid(metrics: viewData.metrics),
          ],
          if (viewData.files.isNotEmpty) ...[
            const SizedBox(height: 18),
            _FileList(files: viewData.files),
          ],
          if (showFooterButton) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: state.phase == SendSessionPhase.result
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
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({
    required this.progressLabel,
    required this.progressFraction,
    required this.speedLabel,
    required this.etaLabel,
    required this.accent,
  });

  final String? progressLabel;
  final double? progressFraction;
  final String? speedLabel;
  final String? etaLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final speedText = speedLabel;
    final etaText = etaLabel;
    final extras = <String>[];
    if (speedText != null) {
      extras.add(speedText);
    }
    if (etaText != null) {
      extras.add(etaText);
    }

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

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<SendTransferMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final metric in metrics)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 132),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.label,
                    style: driftSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: kMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    metric.value,
                    style: driftSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
          const Divider(height: 1, thickness: 1),
          for (int index = 0; index < files.length; index++) ...[
            _FileRow(file: files[index]),
            if (index < files.length - 1)
              const Divider(height: 1, thickness: 1),
          ],
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
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
      ),
    );
  }
}
