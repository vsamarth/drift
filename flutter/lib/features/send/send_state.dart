import '../../core/models/transfer_models.dart';
import '../../state/app_identity.dart';
import '../../state/drift_app_state.dart';
import '../../src/rust/api/transfer.dart' as rust_transfer;

class SendState {
  const SendState(this.appState);

  factory SendState.fromAppState(DriftAppState state) {
    return SendState(state);
  }

  final DriftAppState appState;

  DriftAppIdentity get identity => appState.identity;
  bool get animateSendingConnection => appState.animateSendingConnection;
  String? get sendSetupErrorMessage => appState.sendSetupErrorMessage;
  TransferDirection get mode => appState.mode;
  TransferStage get sendStage => appState.sendStage;
  String get deviceName => appState.deviceName;
  String get deviceType => appState.deviceType;
  String get sendDestinationCode => appState.sendDestinationCode;
  String? get sendDestinationLabel => appState.sendDestinationLabel;
  String? get sendRemoteDeviceType => appState.sendRemoteDeviceType;
  List<TransferItemViewData> get sendItems => appState.sendItems;
  List<TransferDisplayItemViewData> get sendDisplayItems =>
      appState.sendDisplayItems;
  List<SendDestinationViewData> get nearbySendDestinations =>
      appState.nearbySendDestinations;
  SendDestinationViewData? get selectedSendDestination =>
      appState.selectedSendDestination;
  TransferSummaryViewData? get sendSummary => appState.sendSummary;
  int? get sendPayloadBytesSent => appState.sendPayloadBytesSent;
  int? get sendPayloadTotalBytes => appState.sendPayloadTotalBytes;
  String? get sendTransferSpeedLabel => appState.sendTransferSpeedLabel;
  String? get sendTransferEtaLabel => appState.sendTransferEtaLabel;
  bool get hasSendPayloadProgress => appState.hasSendPayloadProgress;
  List<TransferMetricRow>? get sendCompletionMetrics =>
      appState.sendCompletionMetrics;
  rust_transfer.TransferPlanData? get sendTransferPlan =>
      appState.sendTransferPlan;
  rust_transfer.TransferSnapshotData? get sendTransferSnapshot =>
      appState.sendTransferSnapshot;
  bool get canBrowseNearbyReceivers => appState.canBrowseNearbyReceivers;
  bool get nearbyScanInProgress => appState.nearbyScanInProgress;
  bool get nearbyScanHasCompletedOnce => appState.nearbyScanHasCompletedOnce;
  bool get isInspectingSendItems => appState.isInspectingSendItems;
  TransferResultViewData? get transferResult => appState.transferResult;
  bool get discoverableEnabled => appState.discoverableEnabled;
}
