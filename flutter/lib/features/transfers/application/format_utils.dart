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

String formatEta(BigInt etaSeconds) {
  final seconds = etaSeconds.toInt();
  if (seconds < 60) {
    return '$seconds s left';
  }

  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return remainingSeconds == 0
        ? '$minutes m left'
        : '$minutes m $remainingSeconds s left';
  }

  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return remainingMinutes == 0
      ? '$hours h left'
      : '$hours h $remainingMinutes m left';
}
