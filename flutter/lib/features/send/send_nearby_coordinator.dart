import '../../core/models/transfer_models.dart';
import '../../state/nearby_discovery_source.dart';

abstract interface class SendNearbyScanHost {
  List<TransferItemViewData> get currentSendItems;

  String get currentDeviceType;

  bool get isInspectingSendItems;

  bool get nearbyScanInFlight;

  void setNearbyScanInFlight(bool value);

  void setNearbyScanCompletedOnce(bool value);

  void setNearbyDestinations(List<SendDestinationViewData> destinations);

  void setSendSetupError(String message);

  void clearNearbyScanTimer();

  void logNearbyScanFailure(Object error, StackTrace stackTrace);
}

class SendNearbyCoordinator {
  const SendNearbyCoordinator({
    required NearbyDiscoverySource nearbyDiscoverySource,
  }) : _nearbyDiscoverySource = nearbyDiscoverySource;

  final NearbyDiscoverySource _nearbyDiscoverySource;

  Duration scanTimeoutForDeviceType(String deviceType) => deviceType == 'phone'
      ? const Duration(seconds: 4)
      : const Duration(seconds: 8);

  Duration refreshIntervalForDeviceType(String deviceType) => deviceType == 'phone'
      ? const Duration(seconds: 8)
      : const Duration(seconds: 12);

  Future<void> runScanOnce(SendNearbyScanHost host) async {
    final current = host.currentSendItems;
    if (current.isEmpty || host.isInspectingSendItems || host.nearbyScanInFlight) {
      return;
    }

    host.setNearbyScanInFlight(true);
    try {
      final next = await _nearbyDiscoverySource.scan(
        timeout: scanTimeoutForDeviceType(host.currentDeviceType),
      );
      if (host.isInspectingSendItems) {
        return;
      }
      final sorted = List<SendDestinationViewData>.of(next)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      host.setNearbyDestinations(
        List<SendDestinationViewData>.unmodifiable(sorted),
      );
      host.setNearbyScanInFlight(false);
      host.setNearbyScanCompletedOnce(true);
    } catch (error, stackTrace) {
      host.logNearbyScanFailure(error, stackTrace);
      host.setSendSetupError(
        'Drift couldn\'t scan for nearby devices right now.',
      );
      host.setNearbyScanInFlight(false);
      host.setNearbyScanCompletedOnce(true);
    }
  }

  void startPeriodicScan(SendNearbyScanHost host) {
    host.clearNearbyScanTimer();
  }
}
