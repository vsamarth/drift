import 'dart:async';

import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/platform/send_item_source.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_app_notifier.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:drift_app/state/nearby_discovery_source.dart';
import 'package:drift_app/state/receiver_service_source.dart';
import 'package:drift_app/features/send/send_shell_actions.dart'
    as send_shell_actions;

const List<TransferItemViewData> _sampleSendItems = [
  TransferItemViewData(
    name: 'sample.txt',
    path: 'sample.txt',
    size: '18 KB',
    kind: TransferItemKind.file,
  ),
];

const TransferItemViewData _extraSendItem = TransferItemViewData(
  name: 'notes.pdf',
  path: 'notes.pdf',
  size: '12 KB',
  kind: TransferItemKind.file,
);

class FakeSendAppNotifier extends DriftAppNotifier {
  FakeSendAppNotifier(this._state);

  DriftAppState _state;
  int pickSendItemsCalls = 0;
  int appendSendItemsFromPickerCalls = 0;
  int rescanNearbySendDestinationsCalls = 0;
  int acceptDroppedSendItemsCalls = 0;
  int appendDroppedSendItemsCalls = 0;
  int removeSendItemCalls = 0;
  int updateSendDestinationCodeCalls = 0;
  int clearSendDestinationCodeCalls = 0;
  int applySendDraftSessionCalls = 0;
  int clearSendFlowCalls = 0;
  int beginSendInspectionCalls = 0;
  int applyPendingSendItemsCalls = 0;
  int applySelectedSendItemsCalls = 0;
  int finishSendInspectionCalls = 0;
  int clearSendSetupErrorCalls = 0;
  int reportSendSelectionErrorCalls = 0;
  int setNearbyScanInFlightCalls = 0;
  int setNearbyScanCompletedOnceCalls = 0;
  int setNearbyDestinationsCalls = 0;
  int setSendSetupErrorCalls = 0;
  int clearNearbyScanTimerCalls = 0;
  int logNearbyScanFailureCalls = 0;
  int startSendCalls = 0;
  int cancelSendInProgressCalls = 0;
  int handleTransferResultPrimaryActionCalls = 0;
  int selectNearbyDestinationCalls = 0;

  @override
  DriftAppState build() => _state;

  void setState(DriftAppState nextState) {
    _state = nextState;
    state = nextState;
  }

  @override
  void pickSendItems() {
    pickSendItemsCalls += 1;
  }

  @override
  void appendSendItemsFromPicker() {
    appendSendItemsFromPickerCalls += 1;
  }

  @override
  void rescanNearbySendDestinations() {
    rescanNearbySendDestinationsCalls += 1;
  }

  @override
  void acceptDroppedSendItems(List<String> paths) {
    acceptDroppedSendItemsCalls += 1;
  }

  @override
  void appendDroppedSendItems(List<String> paths) {
    appendDroppedSendItemsCalls += 1;
  }

  @override
  void removeSendItem(String path) {
    removeSendItemCalls += 1;
  }

  void updateSendDestinationCode(String value) {
    updateSendDestinationCodeCalls += 1;
  }

  void clearSendDestinationCode() {
    clearSendDestinationCodeCalls += 1;
  }

  @override
  void applySendDraftSession(SendDraftSession session) {
    applySendDraftSessionCalls += 1;
    setState(
      _state.copyWith(session: session, clearSendSetupErrorMessage: true),
    );
  }

  @override
  void clearSendFlow() {
    clearSendFlowCalls += 1;
    setState(
      _state.copyWith(
        session: const IdleSession(),
        clearSendSetupErrorMessage: true,
      ),
    );
  }

  @override
  void beginSendInspection({required bool clearExistingItems}) {
    beginSendInspectionCalls += 1;
    final current = _state.session;
    final items = clearExistingItems && current is SendDraftSession
        ? const <TransferItemViewData>[]
        : _state.sendItems;
    setState(
      _state.copyWith(
        session: SendDraftSession(
          items: List<TransferItemViewData>.unmodifiable(items),
          isInspecting: true,
          nearbyDestinations: const [],
          nearbyScanInFlight: false,
          nearbyScanCompletedOnce: false,
          destinationCode: current is SendDraftSession
              ? current.destinationCode
              : '',
        ),
      ),
    );
  }

  @override
  void applyPendingSendItems(List<TransferItemViewData> items) {
    applyPendingSendItemsCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(
      _state.copyWith(
        session: current.copyWith(
          items: List<TransferItemViewData>.unmodifiable(items),
        ),
      ),
    );
  }

  @override
  void applySelectedSendItems(List<TransferItemViewData> items) {
    applySelectedSendItemsCalls += 1;
    setState(
      _state.copyWith(
        session: SendDraftSession(
          items: List<TransferItemViewData>.unmodifiable(items),
          isInspecting: false,
          nearbyDestinations: const [],
          nearbyScanInFlight: false,
          nearbyScanCompletedOnce: false,
          destinationCode: '',
        ),
      ),
    );
  }

  @override
  void finishSendInspection() {
    finishSendInspectionCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(_state.copyWith(session: current.copyWith(isInspecting: false)));
  }

  @override
  void clearSendSetupError() {
    clearSendSetupErrorCalls += 1;
    setState(_state.copyWith(clearSendSetupErrorMessage: true));
  }

  @override
  void reportSendSelectionError(
    String userMessage,
    Object error,
    StackTrace stackTrace,
  ) {
    reportSendSelectionErrorCalls += 1;
    setState(_state.copyWith(sendSetupErrorMessage: userMessage));
  }

  void startSend() {
    startSendCalls += 1;
  }

  @override
  void cancelSendInProgress() {
    cancelSendInProgressCalls += 1;
  }

  void handleTransferResultPrimaryAction() {
    handleTransferResultPrimaryActionCalls += 1;
  }

  void selectNearbyDestination(SendDestinationViewData destination) {
    selectNearbyDestinationCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(
      _state.copyWith(
        session: send_shell_actions.selectNearbyDestination(
          current,
          destination,
        ),
      ),
    );
  }

  @override
  List<TransferItemViewData> get currentSendItems => _state.sendItems;

  @override
  String get currentDeviceName => _state.deviceName;

  @override
  String get currentDeviceType => _state.deviceType;

  @override
  String? get currentServerUrl => _state.serverUrl;

  @override
  void clearNearbyScanTimer() {
    clearNearbyScanTimerCalls += 1;
  }

  @override
  void logNearbyScanFailure(Object error, StackTrace stackTrace) {
    logNearbyScanFailureCalls += 1;
  }

  @override
  void setNearbyScanInFlight(bool value) {
    setNearbyScanInFlightCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(
      _state.copyWith(session: current.copyWith(nearbyScanInFlight: value)),
    );
  }

  @override
  void setNearbyScanCompletedOnce(bool value) {
    setNearbyScanCompletedOnceCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(
      _state.copyWith(
        session: current.copyWith(nearbyScanCompletedOnce: value),
      ),
    );
  }

  @override
  void setNearbyDestinations(List<SendDestinationViewData> destinations) {
    setNearbyDestinationsCalls += 1;
    final current = _state.session;
    if (current is! SendDraftSession) {
      return;
    }
    setState(
      _state.copyWith(
        session: current.copyWith(
          nearbyDestinations: List<SendDestinationViewData>.unmodifiable(
            destinations,
          ),
        ),
      ),
    );
  }

  @override
  void setSendSetupError(String message) {
    setSendSetupErrorCalls += 1;
    setState(_state.copyWith(sendSetupErrorMessage: message));
  }

  @override
  void applySendTransferUpdate(SendTransferUpdate update) {
    // Keep tests focused on the call path; state transitions are covered by
    // dedicated reducer tests.
  }
}

class FakeSendItemSource implements SendItemSource {
  FakeSendItemSource({
    List<List<String>>? pickResponses,
    Map<String, TransferItemViewData>? itemCatalog,
    this.pickFilesError,
  }) : _pickResponses =
           pickResponses ??
           const [
             ['sample.txt'],
           ],
       _itemCatalog =
           itemCatalog ??
           {'sample.txt': _sampleSendItems[0], 'notes.pdf': _extraSendItem};

  final List<List<String>> _pickResponses;
  final Map<String, TransferItemViewData> _itemCatalog;
  final Object? pickFilesError;
  int _pickIndex = 0;
  int pickFilesCalls = 0;
  int pickAdditionalPathsCalls = 0;
  int pickAdditionalFilesCalls = 0;
  int loadPathsCalls = 0;
  int appendPathsCalls = 0;
  int removePathCalls = 0;

  @override
  Future<List<TransferItemViewData>> pickFiles() async {
    pickFilesCalls += 1;
    return pickFilesError == null
        ? _mapPaths(_nextPickResponse())
        : Future<List<TransferItemViewData>>.error(pickFilesError!);
  }

  @override
  Future<List<String>> pickAdditionalPaths() async {
    pickAdditionalPathsCalls += 1;
    return _nextPickResponse();
  }

  @override
  Future<List<TransferItemViewData>> pickAdditionalFiles({
    required List<String> existingPaths,
  }) async {
    pickAdditionalFilesCalls += 1;
    return appendPaths(
      existingPaths: existingPaths,
      incomingPaths: _nextPickResponse(),
    );
  }

  @override
  Future<List<TransferItemViewData>> loadPaths(List<String> paths) async {
    loadPathsCalls += 1;
    return _mapPaths(paths);
  }

  @override
  Future<List<TransferItemViewData>> appendPaths({
    required List<String> existingPaths,
    required List<String> incomingPaths,
  }) async {
    appendPathsCalls += 1;
    final merged = <String>[];
    final seen = <String>{};
    for (final path in [...existingPaths, ...incomingPaths]) {
      if (seen.add(path)) {
        merged.add(path);
      }
    }
    return _mapPaths(merged);
  }

  @override
  Future<List<TransferItemViewData>> removePath({
    required List<String> existingPaths,
    required String removedPath,
  }) async {
    removePathCalls += 1;
    return _mapPaths(
      existingPaths
          .where((path) => path != removedPath)
          .toList(growable: false),
    );
  }

  List<String> _nextPickResponse() {
    final index = _pickIndex < _pickResponses.length
        ? _pickIndex
        : _pickResponses.length - 1;
    _pickIndex += 1;
    return _pickResponses[index];
  }

  List<TransferItemViewData> _mapPaths(List<String> paths) {
    final seen = <String>{};
    return List<TransferItemViewData>.unmodifiable(
      paths.where(seen.add).map((path) => _itemCatalog[path]!).toList(),
    );
  }
}

class FakeSendTransferSource implements SendTransferSource {
  FakeSendTransferSource({this.cancelError});

  SendTransferRequestData? lastRequest;
  int startTransferCalls = 0;
  int cancelTransferCalls = 0;
  final StreamController<SendTransferUpdate> controller =
      StreamController<SendTransferUpdate>.broadcast();
  final Object? cancelError;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    startTransferCalls += 1;
    lastRequest = request;
    return controller.stream;
  }

  @override
  Future<void> cancelTransfer() async {
    cancelTransferCalls += 1;
    if (cancelError != null) {
      throw cancelError!;
    }
  }

  Future<void> dispose() async {
    await controller.close();
  }
}

class FakeNearbyDiscoverySource implements NearbyDiscoverySource {
  FakeNearbyDiscoverySource({this.scanHandler, this.destinations = const []});

  int scanCount = 0;
  final List<SendDestinationViewData> destinations;
  Future<List<SendDestinationViewData>> Function()? scanHandler;

  @override
  Future<List<SendDestinationViewData>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    scanCount += 1;
    if (scanHandler != null) {
      return await scanHandler!();
    }
    return destinations;
  }
}

DriftAppState buildSendDraftState({
  String deviceName = 'Drift Device',
  String deviceType = 'laptop',
  String downloadRoot = '/tmp/Downloads',
}) {
  return DriftAppState(
    identity: DriftAppIdentity(
      deviceName: deviceName,
      deviceType: deviceType,
      downloadRoot: downloadRoot,
    ),
    receiverBadge: const ReceiverBadgeState(
      code: 'F9P2Q1',
      status: 'Ready',
      phase: ReceiverBadgePhase.ready,
    ),
    session: const SendDraftSession(
      items: [
        TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
        ),
      ],
      isInspecting: false,
      nearbyDestinations: [
        SendDestinationViewData(
          name: 'Lab Mac',
          kind: SendDestinationKind.laptop,
          lanTicket: 'ticket-123',
          lanFullname: 'lab-mac._drift._udp.local.',
        ),
      ],
      nearbyScanInFlight: false,
      nearbyScanCompletedOnce: true,
      destinationCode: '',
    ),
    animateSendingConnection: false,
  );
}

DriftAppState buildSendTransferState() {
  return DriftAppState(
    identity: const DriftAppIdentity(
      deviceName: 'Drift Device',
      deviceType: 'laptop',
      downloadRoot: '/tmp/Downloads',
    ),
    receiverBadge: const ReceiverBadgeState(
      code: 'F9P2Q1',
      status: 'Ready',
      phase: ReceiverBadgePhase.ready,
    ),
    session: const SendTransferSession(
      phase: SendTransferSessionPhase.sending,
      items: [
        TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
        ),
      ],
      summary: TransferSummaryViewData(
        itemCount: 1,
        totalSize: '18 KB',
        code: 'AB2CD3',
        expiresAt: '',
        destinationLabel: 'Maya’s iPhone',
        statusMessage: 'Sending files...',
      ),
      payloadBytesSent: 9 * 1024,
      payloadTotalBytes: 18 * 1024,
      payloadSpeedLabel: '1 MB/s',
      payloadEtaLabel: '1 min',
      remoteDeviceType: 'phone',
    ),
    animateSendingConnection: false,
  );
}
