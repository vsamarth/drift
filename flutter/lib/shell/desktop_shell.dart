import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/receive/application/controller.dart';
import '../features/receive/presentation/widgets/idle_card.dart';
import '../features/receive/presentation/receive_transfer_route_gate.dart';
import '../app/app_router.dart';
import '../features/send/application/model.dart';
import '../features/send/application/send_selection_picker.dart';
import '../features/send/presentation/send_selection_source_sheet.dart';
import '../features/send/send_drop_zone.dart';
import '../theme/drift_theme.dart';

class DesktopShell extends ConsumerWidget {
  const DesktopShell({super.key});

  Future<void> _openSelectedFiles(
    BuildContext context,
    List<SendPickedFile> files,
  ) async {
    context.goSendDraft(files: files);
  }

  Future<void> _pickSelection(
    BuildContext context,
    WidgetRef ref,
    Future<List<SendPickedFile>> Function(SendSelectionPicker picker) pick,
  ) async {
    final pickerService = ref.read(sendSelectionPickerProvider);
    final files = await pick(pickerService);
    if (files.isEmpty) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    await _openSelectedFiles(context, files);
  }

  Future<void> _pickFiles(BuildContext context, WidgetRef ref) {
    return _pickSelection(context, ref, (picker) => picker.pickFiles());
  }

  Future<void> _pickFolder(BuildContext context, WidgetRef ref) {
    return _pickSelection(context, ref, (picker) => picker.pickFolder());
  }

  Future<List<SendPickedFile>> _loadDroppedFiles(List<String> paths) async {
    return paths
        .map((path) {
          final entityType = FileSystemEntity.typeSync(path);
          final picked = entityType == FileSystemEntityType.directory
              ? SendPickedFile.directory(path)
              : SendPickedFile.fromPath(path);
          BigInt? sizeBytes;
          if (picked.kind == SendPickedFileKind.file) {
            try {
              sizeBytes = BigInt.from(File(path).lengthSync());
            } catch (_) {
              sizeBytes = null;
            }
          }
          return SendPickedFile(
            path: picked.path,
            name: picked.name,
            kind: picked.kind,
            sizeBytes: sizeBytes,
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiverState = ref.watch(receiverIdleViewStateProvider);
    return ReceiveTransferRouteGate(
      child: Scaffold(
        backgroundColor: kBg,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ReceiveIdleCard(
                state: receiverState,
                onOpenSettings: () {
                  context.goSettings();
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SendDropZone(
                  onChooseFiles: () {
                    return showSendSelectionSourceSheet(
                      context,
                      onChooseFiles: () => _pickFiles(context, ref),
                      onChooseFolder: () => _pickFolder(context, ref),
                    );
                  },
                  onDropPaths: (paths) {
                    if (paths.isEmpty) {
                      return;
                    }
                    unawaited(
                      _loadDroppedFiles(paths).then((files) async {
                        if (!context.mounted) {
                          return;
                        }
                        await _openSelectedFiles(context, files);
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
