import '../../application/identity.dart';

String displaySender(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Unknown sender' : trimmed;
}

String incomingSubtitle(int itemCount, String totalSize) {
  final fileWord = itemCount == 1 ? 'file' : 'files';
  return 'wants to send you $itemCount $fileWord ($totalSize)';
}

String fileCountLabel(int itemCount) {
  return itemCount == 1 ? '1 file' : '$itemCount files';
}

String deviceTypeLabel(DeviceType type) {
  return switch (type) {
    DeviceType.phone => 'phone',
    DeviceType.laptop => 'laptop',
  };
}

String formatBytes(BigInt bytes) {
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
