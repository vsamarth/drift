import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/receive/application/controller.dart';
import '../features/receive/presentation/widgets/idle_card.dart';
import '../features/send/application/model.dart';
import '../features/send/presentation/dropped_files_page.dart';
import '../features/send/send_drop_zone.dart';
import '../features/settings/feature.dart';
import '../theme/drift_theme.dart';

class DriftShell extends ConsumerWidget {
  const DriftShell({super.key});

  Future<void> _openSelectedFiles(
    NavigatorState navigator,
    List<SendPickedFile> files,
  ) async {
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => DroppedFilesPage(files: files),
      ),
    );
  }

  Future<void> _pickFiles(NavigatorState navigator) async {
    final pickedFiles = await openFiles();
    if (pickedFiles.isEmpty) {
      return;
    }

    final files = pickedFiles
        .map((file) => SendPickedFile.fromPath(file.path.isNotEmpty
            ? file.path
            : file.name))
        .toList(growable: false);
    await _openSelectedFiles(navigator, files);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiverState = ref.watch(receiverIdleViewStateProvider);
    final navigator = Navigator.of(context);

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ReceiveIdleCard(
                state: receiverState,
                onOpenSettings: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsFeature(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SendDropZone(
                  onChooseFiles: () => _pickFiles(navigator),
                  onDropPaths: (paths) {
                    if (paths.isEmpty) {
                      return;
                    }
                    final files = paths
                        .map(SendPickedFile.fromPath)
                        .toList(growable: false);
                    unawaited(_openSelectedFiles(navigator, files));
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
