import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../src/rust/api/device.dart' as rust_device;

class DriftAppIdentity {
  const DriftAppIdentity({
    required this.deviceName,
    required this.deviceType,
    required this.downloadRoot,
    this.discoverableByDefault = true,
    this.serverUrl,
  });

  final String deviceName;
  final String deviceType;
  final String downloadRoot;
  final bool discoverableByDefault;
  final String? serverUrl;

  DriftAppIdentity copyWith({
    String? deviceName,
    String? deviceType,
    String? downloadRoot,
    bool? discoverableByDefault,
    String? serverUrl,
  }) {
    return DriftAppIdentity(
      deviceName: deviceName ?? this.deviceName,
      deviceType: deviceType ?? this.deviceType,
      downloadRoot: downloadRoot ?? this.downloadRoot,
      discoverableByDefault:
          discoverableByDefault ?? this.discoverableByDefault,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriftAppIdentity &&
          runtimeType == other.runtimeType &&
          deviceName == other.deviceName &&
          deviceType == other.deviceType &&
          downloadRoot == other.downloadRoot &&
          discoverableByDefault == other.discoverableByDefault &&
          serverUrl == other.serverUrl;

  @override
  int get hashCode => Object.hash(
    deviceName,
    deviceType,
    downloadRoot,
    discoverableByDefault,
    serverUrl,
  );
}

DriftAppIdentity buildDefaultDriftAppIdentity({
  String? deviceName,
  String? deviceType,
  String? downloadRoot,
  String? serverUrl,
  bool? discoverable,
}) {
  return DriftAppIdentity(
    deviceName: normalizeDeviceName(
      deviceName ?? rust_device.randomDeviceName(),
    ),
    deviceType: deviceType ?? inferDeviceType(),
    downloadRoot: downloadRoot ?? defaultReceiveDownloadRoot(),
    discoverableByDefault: discoverable ?? true,
    serverUrl: normalizeServerUrl(serverUrl),
  );
}

String inferDeviceType() {
  if (Platform.isAndroid || Platform.isIOS) {
    return 'phone';
  }
  return 'laptop';
}

String defaultReceiveDownloadRoot() {
  final home = _userHomeDirectory();
  if (home == null || home.isEmpty) {
    return '${Directory.systemTemp.path}${Platform.pathSeparator}Downloads${Platform.pathSeparator}Drift';
  }
  return '$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}Drift';
}

Future<String> resolvePreferredReceiveDownloadRoot() async {
  if (Platform.isAndroid) {
    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir != null) {
      return '${downloadsDir.path}${Platform.pathSeparator}Drift';
    }
    final externalDirs = await getExternalStorageDirectories(
      type: StorageDirectory.downloads,
    );
    final externalDir = externalDirs?.firstOrNull;
    if (externalDir != null) {
      return '${externalDir.path}${Platform.pathSeparator}Drift';
    }
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}${Platform.pathSeparator}Drift';
  }
  if (Platform.isIOS) {
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}${Platform.pathSeparator}Drift';
  }
  return defaultReceiveDownloadRoot();
}

bool shouldMigrateLegacyDefaultReceiveRoot(String path) {
  if (!(Platform.isAndroid || Platform.isIOS)) {
    return false;
  }

  final normalized = path.trim();
  if (normalized.isEmpty) {
    return true;
  }

  return _legacyDefaultReceiveRoots().contains(normalized);
}

Set<String> _legacyDefaultReceiveRoots() {
  final roots = <String>{
    '${Directory.systemTemp.path}${Platform.pathSeparator}Downloads${Platform.pathSeparator}Drift',
  };
  final home = _userHomeDirectory();
  if (home != null && home.isNotEmpty) {
    roots.add(
      '$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}Drift',
    );
  }
  return roots;
}

String? _userHomeDirectory() {
  if (Platform.isWindows) {
    return Platform.environment['USERPROFILE'];
  }
  return Platform.environment['HOME'];
}

String normalizeDeviceName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return rust_device.randomDeviceName();
  }

  final firstSegment = trimmed.split('.').first.trim();
  return firstSegment.isEmpty ? rust_device.randomDeviceName() : firstSegment;
}

String? normalizeServerUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
