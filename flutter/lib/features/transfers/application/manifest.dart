import 'package:flutter/foundation.dart';

@immutable
class TransferManifestItem {
  const TransferManifestItem({
    required this.path,
    required this.sizeBytes,
  });

  final String path;
  final BigInt sizeBytes;
}

@immutable
class TransferManifest {
  const TransferManifest({
    required this.items,
  });

  final List<TransferManifestItem> items;

  int get itemCount => items.length;

  BigInt get totalSizeBytes => items.fold(
        BigInt.zero,
        (sum, item) => sum + item.sizeBytes,
      );
}
