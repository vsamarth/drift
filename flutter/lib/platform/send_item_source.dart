import 'package:file_selector/file_selector.dart';

import '../core/models/transfer_models.dart';
import '../src/rust/api/error_bridge.dart';
import '../src/rust/api/preview.dart' as rust_preview;

abstract class SendItemSource {
  Future<List<TransferItemViewData>> pickFiles();

  Future<List<String>> pickAdditionalPaths();

  Future<List<TransferItemViewData>> pickAdditionalFiles({
    required List<String> existingPaths,
  });

  Future<List<TransferItemViewData>> loadPaths(List<String> paths);

  Future<List<TransferItemViewData>> appendPaths({
    required List<String> existingPaths,
    required List<String> incomingPaths,
  });

  Future<List<TransferItemViewData>> removePath({
    required List<String> existingPaths,
    required String removedPath,
  });
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
  Future<List<String>> pickAdditionalPaths() async {
    final files = await openFiles();
    return _normalizePaths(
      files
          .map((file) => file.path)
          .where((path) => path.isNotEmpty)
          .toList(growable: false),
    );
  }

  @override
  Future<List<TransferItemViewData>> pickAdditionalFiles({
    required List<String> existingPaths,
  }) async {
    final paths = await pickAdditionalPaths();
    return appendPaths(existingPaths: existingPaths, incomingPaths: paths);
  }

  @override
  Future<List<TransferItemViewData>> loadPaths(List<String> paths) async {
    final normalizedPaths = _normalizePaths(paths);

    if (normalizedPaths.isEmpty) {
      return const [];
    }

    final preview = await _loadPreview(
      () => rust_preview.inspectPaths(paths: normalizedPaths),
    );
    return List<TransferItemViewData>.unmodifiable(
      preview.items.map(_mapPreviewItem),
    );
  }

  @override
  Future<List<TransferItemViewData>> appendPaths({
    required List<String> existingPaths,
    required List<String> incomingPaths,
  }) async {
    final preview = await _loadPreview(
      () => rust_preview.appendPaths(
        existingPaths: _normalizePaths(existingPaths),
        newPaths: _normalizePaths(incomingPaths),
      ),
    );
    return List<TransferItemViewData>.unmodifiable(
      preview.items.map(_mapPreviewItem),
    );
  }

  @override
  Future<List<TransferItemViewData>> removePath({
    required List<String> existingPaths,
    required String removedPath,
  }) async {
    final preview = await _loadPreview(
      () => rust_preview.removePath(
        existingPaths: _normalizePaths(existingPaths),
        removedPath: removedPath.trim(),
      ),
    );
    return List<TransferItemViewData>.unmodifiable(
      preview.items.map(_mapPreviewItem),
    );
  }

  static Future<rust_preview.SelectionPreview> _loadPreview(
    Future<rust_preview.SelectionPreview> Function() run,
  ) async {
    try {
      return await run();
    } catch (error, stackTrace) {
      final structured = tryParseUserFacingBridgeError(error);
      if (structured != null) {
        Error.throwWithStackTrace(structured, stackTrace);
      }
      rethrow;
    }
  }

  static List<String> _normalizePaths(List<String> paths) {
    final seen = <String>{};
    final normalizedPaths = <String>[];

    for (final rawPath in paths) {
      final normalizedPath = rawPath.trim();
      if (normalizedPath.isEmpty || !seen.add(normalizedPath)) {
        continue;
      }
      normalizedPaths.add(normalizedPath);
    }

    return normalizedPaths;
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
      sizeBytes: totalSize,
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
