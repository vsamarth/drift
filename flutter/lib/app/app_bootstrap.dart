import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/settings/application/repository.dart';
import '../features/settings/application/state.dart';
import '../platform/rust/receiver/rust_source.dart';
import '../src/rust/api/device.dart' as rust_device;

class AppBootstrap {
  const AppBootstrap({
    required this.settingsRepository,
    required this.initialSettings,
    required this.receiverSource,
  });

  final SettingsRepository settingsRepository;
  final AppSettings initialSettings;
  final RustReceiverServiceSource receiverSource;
}

Future<AppBootstrap> loadAppBootstrap({
  String Function()? randomDeviceName,
  String? defaultDownloadRoot,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final repository = SettingsRepository(
    prefs: prefs,
    randomDeviceName: randomDeviceName ?? rust_device.randomDeviceName,
    defaultDownloadRoot:
        defaultDownloadRoot ?? await resolvePreferredReceiveDownloadRoot(),
  );
  final initialSettings = await repository.loadOrCreate();
  return AppBootstrap(
    settingsRepository: repository,
    initialSettings: initialSettings,
    receiverSource: RustReceiverServiceSource(
      deviceName: initialSettings.deviceName,
      downloadRoot: initialSettings.downloadRoot,
      serverUrl: initialSettings.discoveryServerUrl,
    ),
  );
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
    final externalDir = externalDirs != null && externalDirs.isNotEmpty
        ? externalDirs.first
        : null;
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

  final downloadsDir = await getDownloadsDirectory();
  if (downloadsDir != null) {
    return '${downloadsDir.path}${Platform.pathSeparator}Drift';
  }

  final home = _userHomeDirectory();
  if (home != null && home.isNotEmpty) {
    return '$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}Drift';
  }

  return '${Directory.systemTemp.path}${Platform.pathSeparator}Drift';
}

String? _userHomeDirectory() {
  if (Platform.isWindows) {
    return Platform.environment['USERPROFILE'];
  }
  return Platform.environment['HOME'];
}
