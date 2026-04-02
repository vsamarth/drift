import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/transfer_models.dart';
import '../../../core/theme/drift_theme.dart';
import '../../../state/drift_providers.dart';
import '../receive_code_field.dart';
import 'nearby_devices_section.dart';
import 'selected_files_preview.dart';

class MobileSendDraftView extends ConsumerWidget {
  const MobileSendDraftView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(driftAppNotifierProvider);
    final notifier = ref.read(driftAppNotifierProvider.notifier);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                'Selected files',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to send this selection.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              SelectedFilesPreview(
                items: state.sendItems,
                onAddMore: notifier.appendSendItemsFromPicker,
                isPicking: state.isInspectingSendItems,
              ),
              const SizedBox(height: 16),
              _FirstFileBytesPanel(items: state.sendItems),
              const SizedBox(height: 16),
              NearbyDevicesSection(
                devices: state.nearbySendDestinations,
                selectedDevice: null,
                isScanning: state.nearbyScanInProgress,
                onSelect: notifier.selectNearbyDestination,
                onScan: notifier.rescanNearbySendDestinations,
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Enter the six-character receiver code to start the transfer.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      ReceiveCodeField(
                        code: state.sendDestinationCode,
                        onChanged: notifier.updateSendDestinationCode,
                        hintText: 'Receiver code',
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _FirstFileBytesPanel extends StatelessWidget {
  const _FirstFileBytesPanel({required this.items});

  final List<TransferItemViewData> items;

  TransferItemViewData? get _firstReadableFile {
    for (final item in items) {
      if (item.kind == TransferItemKind.file) {
        return item;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final file = _firstReadableFile;
    final theme = Theme.of(context);

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File read diagnostic',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: kInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              file == null
                  ? 'No regular file is selected yet.'
                  : 'First file: ${file.name}',
              style: theme.textTheme.bodyMedium,
            ),
            if (file != null) ...[
              const SizedBox(height: 12),
              _DiagnosticScrollText(
                file.path,
                style: driftSans(fontSize: 12, color: kMuted),
              ),
              const SizedBox(height: 12),
              FutureBuilder<_FirstBytesProbe>(
                future: _readFirstBytes(file.path),
                builder: (context, snapshot) {
                  final probe = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator(minHeight: 4);
                  }
                  if (probe == null) {
                    return Text(
                      'No diagnostic data available.',
                      style: theme.textTheme.bodyMedium,
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        probe.errorMessage == null
                            ? 'First 10 bytes'
                            : 'Read error',
                        style: driftSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kMuted,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _DiagnosticScrollText(
                        probe.errorMessage ?? probe.hexBytes,
                        style: driftSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kInk,
                        ),
                      ),
                      if (probe.errorMessage == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Byte count read: ${probe.byteCount}',
                          style: driftSans(fontSize: 12, color: kMuted),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<_FirstBytesProbe> _readFirstBytes(String path) async {
    try {
      final file = File(path);
      final bytes = await file
          .openRead(0, 10)
          .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
      return _FirstBytesProbe(
        byteCount: bytes.length,
        hexBytes: bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' '),
      );
    } catch (error) {
      return _FirstBytesProbe(
        byteCount: 0,
        hexBytes: '',
        errorMessage: error.toString(),
      );
    }
  }
}

class _FirstBytesProbe {
  const _FirstBytesProbe({
    required this.byteCount,
    required this.hexBytes,
    this.errorMessage,
  });

  final int byteCount;
  final String hexBytes;
  final String? errorMessage;
}

class _DiagnosticScrollText extends StatelessWidget {
  const _DiagnosticScrollText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: SelectableText(text, style: style),
      ),
    );
  }
}
