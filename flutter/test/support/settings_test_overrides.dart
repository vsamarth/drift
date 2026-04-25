import 'package:app/features/settings/feature.dart';
import 'package:app/platform/rust/rendezvous_defaults.dart';

const AppSettings testAppSettings = AppSettings(
  deviceName: 'Drift',
  downloadRoot: '/tmp/Drift',
  discoverableByDefault: true,
  discoveryServerUrl: null,
);
