import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/drift_theme.dart';
import '../application/controller.dart';
import '../application/model.dart';
import '../application/state.dart';

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

    final destinationModeLabel = switch (widget.request.destinationMode) {
      SendDestinationMode.code => 'Code',
      SendDestinationMode.nearby => 'Nearby',
      SendDestinationMode.none => 'Unknown',
    };
    final destinationSummary = switch (widget.request.destinationMode) {
      SendDestinationMode.code => widget.request.code ?? 'No code',
      SendDestinationMode.nearby =>
        widget.request.lanDestinationLabel ??
            widget.request.ticket ??
            'No ticket',
      SendDestinationMode.none => 'No destination',
    };

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          controller.cancelTransfer();
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
            onPressed: () {
              controller.cancelTransfer();
              Navigator.of(context).pop();
            },
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
                  destinationModeLabel,
                  style: driftSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: kMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  destinationSummary,
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
            const SizedBox(height: 18),
            _TransferStatusCard(state: state),
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

class _TransferStatusCard extends StatelessWidget {
  const _TransferStatusCard({required this.state});

  final SendState state;

  @override
  Widget build(BuildContext context) {
    final (title, message, accent, showSpinner) = switch (state.phase) {
      SendSessionPhase.transferring => (
        'Transferring',
        'Starting transfer…',
        kAccentCyanStrong,
        true,
      ),
      SendSessionPhase.result when state.result != null => (
        state.result!.title,
        state.result!.message,
        switch (state.result!.outcome) {
          SendTransferOutcome.success => const Color(0xFF1F7A57),
          SendTransferOutcome.cancelled => const Color(0xFF8B6B20),
          SendTransferOutcome.declined => const Color(0xFF8B4B20),
          SendTransferOutcome.failed => const Color(0xFFB42318),
        },
        false,
      ),
      _ => (
        'Waiting',
        'Preparing transfer…',
        kMuted,
        true,
      ),
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
          Row(
            children: [
              if (showSpinner) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.25,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: driftSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: driftSans(fontSize: 13.5, color: kMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
