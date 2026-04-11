import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/receive/application/controller.dart';
import '../features/receive/presentation/widgets/idle_card.dart';
import '../features/send/application/model.dart';
import '../features/send/send_drop_zone.dart';
import '../theme/drift_theme.dart';

class DriftShell extends ConsumerWidget {
  const DriftShell({super.key});

  Future<void> _openSelectedFiles(
    BuildContext context,
    List<SendPickedFile> files,
  ) async {
    context.go('/send/draft', extra: files);
  }

  Future<List<SendPickedFile>> _loadPickedFiles() async {
    final pickedFiles = await openFiles();
    if (pickedFiles.isEmpty) {
      return const [];
    }

    return Future.wait(
      pickedFiles.map((file) async {
        final path = file.path.isNotEmpty ? file.path : file.name;
        final name = file.name.trim().isEmpty
            ? Uri.file(path).pathSegments.isNotEmpty
                ? Uri.file(path).pathSegments.last
                : path
            : file.name;
        BigInt? sizeBytes;
        try {
          sizeBytes = BigInt.from(await file.length());
        } catch (_) {
          sizeBytes = null;
        }
        return SendPickedFile(path: path, name: name, sizeBytes: sizeBytes);
      }),
    );
  }

  Future<void> _pickFiles(BuildContext context) async {
    final files = await _loadPickedFiles();
    if (files.isEmpty) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    await _openSelectedFiles(context, files);
  }

  Future<List<SendPickedFile>> _loadDroppedFiles(List<String> paths) async {
    return Future.wait(
      paths.map((path) async {
        final picked = SendPickedFile.fromPath(path);
        BigInt? sizeBytes;
        try {
          sizeBytes = BigInt.from(await XFile(path).length());
        } catch (_) {
          sizeBytes = null;
        }
        return SendPickedFile(
          path: picked.path,
          name: picked.name,
          sizeBytes: sizeBytes,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiverState = ref.watch(receiverIdleViewStateProvider);

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
                  context.go('/settings');
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SendDropZone(
                  onChooseFiles: () => _pickFiles(context),
                  onDropPaths: (paths) {
                    if (paths.isEmpty) {
                      return;
                    }
                    unawaited(
                      _loadDroppedFiles(paths).then(
                        (files) async {
                          if (!context.mounted) {
                            return;
                          }
                          await _openSelectedFiles(context, files);
                        },
                      ),
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
