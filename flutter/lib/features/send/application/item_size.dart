import 'model.dart';

BigInt effectiveDraftItemSize(
  SendDraftItem item,
  Map<String, BigInt> resolvedDirectorySizes,
) {
  if (item.kind == SendPickedFileKind.directory) {
    return resolvedDirectorySizes[item.path] ?? item.sizeBytes;
  }

  return item.sizeBytes;
}

BigInt totalDraftItemSize(
  Iterable<SendDraftItem> items,
  Map<String, BigInt> resolvedDirectorySizes,
) {
  return items.fold<BigInt>(
    BigInt.zero,
    (sum, item) => sum + effectiveDraftItemSize(item, resolvedDirectorySizes),
  );
}
