import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_app_notifier.dart';
import 'package:drift_app/state/drift_app_state.dart';
import 'package:drift_app/state/receiver_service_source.dart';

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

  @override
  void updateSendDestinationCode(String value) {
    updateSendDestinationCodeCalls += 1;
  }

  @override
  void clearSendDestinationCode() {
    clearSendDestinationCodeCalls += 1;
  }

  @override
  void startSend() {
    startSendCalls += 1;
  }

  @override
  void cancelSendInProgress() {
    cancelSendInProgressCalls += 1;
  }

  @override
  void handleTransferResultPrimaryAction() {
    handleTransferResultPrimaryActionCalls += 1;
  }

  @override
  void selectNearbyDestination(SendDestinationViewData destination) {
    selectNearbyDestinationCalls += 1;
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
