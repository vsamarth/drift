import 'package:file_selector/file_selector.dart';

import '../core/models/transfer_models.dart';
import '../src/rust/api/preview.dart' as rust_preview;

abstract class SendItemSource {
  Future<List<TransferItemViewData>> pickFiles();

  Future<List<TransferItemViewData>> loadPaths(List<String> paths);
}

class LocalSendItemSource implements SendItemSource {
  const LocalSendItemSource();

  @override
  Future<List<TransferItemViewData>> pickFiles() async {
    final files = await openFiles();
    final paths = files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    return loadPaths(paths);
  }

  @override
  Future<List<TransferItemViewData>> loadPaths(List<String> paths) async {
    final seen = <String>{};
    final normalizedPaths = <String>[];

    for (final rawPath in paths) {
      final normalizedPath = rawPath.trim();
      if (normalizedPath.isEmpty || !seen.add(normalizedPath)) {
        continue;
      }
      normalizedPaths.add(normalizedPath);
    }

    if (normalizedPaths.isEmpty) {
      return const [];
    }

    final preview = await rust_preview.inspectPaths(paths: normalizedPaths);
    return List<TransferItemViewData>.unmodifiable(
      preview.items.map(_mapPreviewItem),
    );
  }

  static TransferItemViewData _mapPreviewItem(rust_preview.SelectionItem item) {
    final fileCount = item.fileCount.toInt();
    final totalSize = item.totalSize.toInt();

    return TransferItemViewData(
      name: item.name,
      path: item.path,
      size: item.isDirectory
          ? _formatDirectorySummary(fileCount, totalSize)
          : _formatBytes(totalSize),
      kind: item.isDirectory ? TransferItemKind.folder : TransferItemKind.file,
    );
  }

  static String _formatDirectorySummary(int fileCount, int totalSize) {
    final fileLabel = '$fileCount ${fileCount == 1 ? 'file' : 'files'}';
    if (fileCount == 0) {
      return 'Empty folder';
    }
    return '$fileLabel • ${_formatBytes(totalSize)}';
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;

    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }

    final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
    final formatted = value.toStringAsFixed(decimals);
    return '$formatted ${units[unitIndex]}';
  }
}
