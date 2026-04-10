import '../../core/models/transfer_models.dart';
import '../../state/app_identity.dart';
import '../../state/drift_app_state.dart';
import '../../state/receiver_service_source.dart';
import '../../src/rust/api/transfer.dart' as rust_transfer;

class ReceiveState {
  const ReceiveState({
    required this.identity,
    required this.receiverBadge,
    required this.session,
    required this.receiveSummary,
    required this.receiveItems,
    required this.receiveDisplayItems,
    required this.receiveTransferSnapshot,
    required this.receiveTransferSpeedLabel,
    required this.receiveTransferEtaLabel,
    required this.receivePayloadBytesReceived,
    required this.receivePayloadTotalBytes,
    required this.receiveSenderDeviceType,
    required this.receiveStage,
    required this.hasReceivePayloadProgress,
  });

  factory ReceiveState.fromAppState(DriftAppState state) {
    return ReceiveState(
      identity: state.identity,
      receiverBadge: state.receiverBadge,
      session: state.session,
      receiveSummary: state.receiveSummary,
      receiveItems: state.receiveItems,
      receiveDisplayItems: state.receiveDisplayItems,
      receiveTransferSnapshot: state.receiveTransferSnapshot,
      receiveTransferSpeedLabel: state.receiveTransferSpeedLabel,
      receiveTransferEtaLabel: state.receiveTransferEtaLabel,
      receivePayloadBytesReceived: state.receivePayloadBytesReceived,
      receivePayloadTotalBytes: state.receivePayloadTotalBytes,
      receiveSenderDeviceType: state.receiveSenderDeviceType,
      receiveStage: state.receiveStage,
      hasReceivePayloadProgress: state.hasReceivePayloadProgress,
    );
  }

  final DriftAppIdentity identity;
  final ReceiverBadgeState receiverBadge;
  final ShellSessionState session;
  final TransferSummaryViewData? receiveSummary;
  final List<TransferItemViewData> receiveItems;
  final List<TransferDisplayItemViewData> receiveDisplayItems;
  final rust_transfer.TransferSnapshotData? receiveTransferSnapshot;
  final String? receiveTransferSpeedLabel;
  final String? receiveTransferEtaLabel;
  final int? receivePayloadBytesReceived;
  final int? receivePayloadTotalBytes;
  final String? receiveSenderDeviceType;
  final TransferStage receiveStage;
  final bool hasReceivePayloadProgress;

  String get deviceName => identity.deviceName;
  String get deviceType => identity.deviceType;
  String get idleReceiveCode => receiverBadge.code;
  String get idleReceiveStatus => receiverBadge.status;
  String? get serverUrl => identity.serverUrl;
  String get downloadRoot => identity.downloadRoot;
}
