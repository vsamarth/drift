String formatSettingsDownloadRootForDisplay(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }

  const containersMarker = '/Library/Containers/';
  const dataMarker = '/Data/';

  final containersIndex = trimmed.indexOf(containersMarker);
  if (containersIndex <= 0) {
    return trimmed;
  }

  final dataIndex = trimmed.indexOf(dataMarker, containersIndex);
  if (dataIndex <= containersIndex) {
    return trimmed;
  }

  final userPrefix = trimmed.substring(0, containersIndex);
  final afterData = trimmed.substring(dataIndex + dataMarker.length);
  if (afterData.isEmpty) {
    return userPrefix;
  }

  return '$userPrefix/$afterData';
}
