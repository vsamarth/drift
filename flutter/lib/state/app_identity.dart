import 'dart:io';

import '../src/rust/api/device.dart' as rust_device;

class DriftAppIdentity {
  const DriftAppIdentity({
    required this.deviceName,
    required this.deviceType,
    required this.downloadRoot,
  });

  final String deviceName;
  final String deviceType;
  final String downloadRoot;
}

DriftAppIdentity buildDefaultDriftAppIdentity({
  String? deviceName,
  String? deviceType,
  String? downloadRoot,
}) {
  return DriftAppIdentity(
    deviceName: normalizeDeviceName(
      deviceName ?? rust_device.randomDeviceName(),
    ),
    deviceType: deviceType ?? inferDeviceType(),
    downloadRoot: downloadRoot ?? defaultReceiveDownloadRoot(),
  );
}

String inferDeviceType() {
  if (Platform.isAndroid || Platform.isIOS) {
    return 'phone';
  }
  return 'laptop';
}

String defaultReceiveDownloadRoot() {
  // For now, keep Flutter writes confined to a guaranteed-writable directory.
  // (This avoids macOS App Sandbox issues with `~/Downloads`.)
  return '${Directory.systemTemp.path}${Platform.pathSeparator}Downloads';
}

String normalizeDeviceName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return rust_device.randomDeviceName();
  }

  final firstSegment = trimmed.split('.').first.trim();
  return firstSegment.isEmpty ? rust_device.randomDeviceName() : firstSegment;
}
