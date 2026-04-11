import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_nearby_coordinator.dart';
import 'package:drift_app/state/nearby_discovery_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runScanOnce marks scanning and stores sorted destinations', () async {
    final host = FakeNearbyScanHost(
      state: FakeNearbyScanState(
        items: const [
          TransferItemViewData(
            name: 'sample.txt',
            path: 'sample.txt',
            size: '18 KB',
            kind: TransferItemKind.file,
          ),
        ],
        deviceType: 'phone',
      ),
    );
    final source = FakeNearbyDiscoverySource(
      result: const [
        SendDestinationViewData(
          name: 'Zulu Laptop',
          kind: SendDestinationKind.laptop,
          lanTicket: 'ticket-z',
          lanFullname: 'zulu._drift._udp.local.',
        ),
        SendDestinationViewData(
          name: 'Alpha Laptop',
          kind: SendDestinationKind.laptop,
          lanTicket: 'ticket-a',
          lanFullname: 'alpha._drift._udp.local.',
        ),
      ],
    );
    final coordinator = SendNearbyCoordinator(
      nearbyDiscoverySource: source,
    );

    await coordinator.runScanOnce(host);

    expect(host.nearbyScanInFlightCalls, 2);
    expect(host.lastNearbyScanInFlightValue, isFalse);
    expect(host.nearbyScanCompletedOnceCalls, 1);
    expect(source.timeouts, [const Duration(seconds: 4)]);
    expect(host.nearbyDestinations.map((item) => item.name), [
      'Alpha Laptop',
      'Zulu Laptop',
    ]);
  });
}

class FakeNearbyScanState {
  const FakeNearbyScanState({
    required this.items,
    required this.deviceType,
    this.isInspecting = false,
    this.nearbyScanInFlight = false,
    this.nearbyScanCompletedOnce = false,
  });

  final List<TransferItemViewData> items;
  final String deviceType;
  final bool isInspecting;
  final bool nearbyScanInFlight;
  final bool nearbyScanCompletedOnce;
}

class FakeNearbyScanHost implements SendNearbyScanHost {
  FakeNearbyScanHost({required FakeNearbyScanState state}) : _state = state;

  FakeNearbyScanState _state;
  int nearbyScanInFlightCalls = 0;
  int nearbyScanCompletedOnceCalls = 0;
  Duration? lastTimeout;
  List<SendDestinationViewData> nearbyDestinations = const [];
  bool? lastNearbyScanInFlightValue;

  @override
  List<TransferItemViewData> get currentSendItems => _state.items;

  @override
  String get currentDeviceType => _state.deviceType;

  @override
  bool get isInspectingSendItems => _state.isInspecting;

  @override
  bool get nearbyScanInFlight => _state.nearbyScanInFlight;

  @override
  void setNearbyScanInFlight(bool value) {
    nearbyScanInFlightCalls += 1;
    lastNearbyScanInFlightValue = value;
    _state = FakeNearbyScanState(
      items: _state.items,
      deviceType: _state.deviceType,
      isInspecting: _state.isInspecting,
      nearbyScanInFlight: value,
      nearbyScanCompletedOnce: _state.nearbyScanCompletedOnce,
    );
  }

  @override
  void setNearbyScanCompletedOnce(bool value) {
    nearbyScanCompletedOnceCalls += 1;
    _state = FakeNearbyScanState(
      items: _state.items,
      deviceType: _state.deviceType,
      isInspecting: _state.isInspecting,
      nearbyScanInFlight: _state.nearbyScanInFlight,
      nearbyScanCompletedOnce: value,
    );
  }

  @override
  void setNearbyDestinations(List<SendDestinationViewData> destinations) {
    nearbyDestinations = destinations;
  }

  @override
  void setSendSetupError(String message) {}

  @override
  void clearNearbyScanTimer() {}

  @override
  void logNearbyScanFailure(Object error, StackTrace stackTrace) {}
}

class FakeNearbyDiscoverySource implements NearbyDiscoverySource {
  FakeNearbyDiscoverySource({required this.result});

  final List<SendDestinationViewData> result;
  final List<Duration> timeouts = [];

  @override
  Future<List<SendDestinationViewData>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    timeouts.add(timeout);
    return result;
  }
}
