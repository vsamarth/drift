import '../../core/models/transfer_models.dart';

class SendSelectionBuilder {
  const SendSelectionBuilder();

  List<TransferItemViewData> appendPendingItems({
    required List<TransferItemViewData> existingItems,
    required List<String> incomingPaths,
  }) {
    if (incomingPaths.isEmpty) {
      return List<TransferItemViewData>.unmodifiable(existingItems);
    }

    final seen = existingItems.map((item) => item.path.trim()).toSet();
    final mergedItems = List<TransferItemViewData>.of(existingItems);

    for (final rawPath in incomingPaths) {
      final path = rawPath.trim();
      if (path.isEmpty || !seen.add(path)) {
        continue;
      }
      mergedItems.add(pendingItemForPath(path));
    }

    return List<TransferItemViewData>.unmodifiable(mergedItems);
  }

  TransferItemViewData pendingItemForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final segments = trimmed.split('/')
      ..removeWhere((segment) => segment.isEmpty);
    final name = segments.isEmpty ? trimmed : segments.last;
    final isFolder = normalized.endsWith('/');

    return TransferItemViewData(
      name: name.isEmpty ? path : name,
      path: path,
      size: 'Adding...',
      kind: isFolder ? TransferItemKind.folder : TransferItemKind.file,
    );
  }
}
