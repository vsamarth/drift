import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import '../platform/app_focus.dart';
import '../platform/receive_registration_source.dart';
import '../platform/send_item_source.dart';
import '../platform/send_transfer_source.dart';
import '../src/rust/api/device.dart' as rust_device;
import '../src/rust/api/lan.dart' as rust_lan;
import '../src/rust/api/receiver.dart' as rust_receiver;
import 'drift_sample_data.dart';

/// Resolves nearby receivers for the send screen (mDNS). Tests inject a stub; production uses Rust.
typedef NearbySendScan = Future<List<SendDestinationViewData>> Function();

Future<List<SendDestinationViewData>> _rustNearbySendScan() async {
  final raw = await rust_lan.scanNearbyReceivers(timeoutSecs: BigInt.from(12));
  final byFullname = <String, rust_lan.NearbyReceiverInfo>{};
  for (final r in raw) {
    byFullname[r.fullname] = r;
  }
  final list = byFullname.values.map(_sendDestinationFromNearbyInfo).toList();
  list.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return list;
}

SendDestinationViewData _sendDestinationFromNearbyInfo(
  rust_lan.NearbyReceiverInfo r,
) {
  final name = r.label.trim().isEmpty ? 'Nearby device' : r.label;
  return SendDestinationViewData(
    name: name,
    kind: SendDestinationKind.laptop,
    lanTicket: r.ticket,
    lanFullname: r.fullname,
  );
}

class DriftController extends ChangeNotifier {
  DriftController({
    String? deviceName,
    String? deviceType,
    String idleReceiveCode = '......',
    String idleReceiveStatus = 'Registering',
    bool enableIdleReceiverRefresh = true,
    List<SendDestinationViewData>? nearbySendDestinations,
    NearbySendScan? nearbySendScan,
    List<TransferItemViewData>? droppedSendItems,
    SendItemSource? sendItemSource,
    SendTransferSource? sendTransferSource,
    ReceiveRegistrationSource? receiveRegistrationSource,
    bool animateSendingConnection = true,
    bool enableIdleIncomingListener = true,
  }) : _deviceName = _normalizeDeviceName(deviceName ?? _defaultDeviceName()),
       _deviceType = deviceType ?? _inferDeviceType(),
       _idleReceiveCode = idleReceiveCode.trim().toUpperCase(),
       _idleReceiveStatus = idleReceiveStatus,
       _defaultDroppedSendItems = List<TransferItemViewData>.unmodifiable(
         droppedSendItems ??
             const [
               TransferItemViewData(
                 name: 'sample.txt',
                 path: 'sample.txt',
                 size: '18 KB',
                 kind: TransferItemKind.file,
               ),
               TransferItemViewData(
                 name: 'photos',
                 path: 'photos/',
                 size: '12 items',
                 kind: TransferItemKind.folder,
               ),
             ],
       ),
       _defaultSendDestinations = List<SendDestinationViewData>.unmodifiable(
         nearbySendDestinations ?? const [],
       ),
       _sendItemSource = sendItemSource ?? const LocalSendItemSource(),
       _sendTransferSource =
           sendTransferSource ?? const LocalSendTransferSource(),
       _receiveRegistrationSource =
           receiveRegistrationSource ?? const LocalReceiveRegistrationSource(),
       _nearbySendScan = nearbySendScan ?? _rustNearbySendScan,
       _animateSendingConnection = animateSendingConnection,
       _enableIdleIncomingListener = enableIdleIncomingListener {
    unawaited(_ensureIdleReceiver());
    if (enableIdleReceiverRefresh) {
      _idleReceiverRefreshTimer = Timer.periodic(const Duration(minutes: 1), (
        _,
      ) {
        unawaited(_ensureIdleReceiver());
      });
    }
    _startIdleIncomingListener();
  }

  final String _deviceName;
  final String _deviceType;
  String _idleReceiveCode;
  String _idleReceiveStatus;
  final List<TransferItemViewData> _defaultDroppedSendItems;
  final List<SendDestinationViewData> _defaultSendDestinations;
  final SendItemSource _sendItemSource;
  final SendTransferSource _sendTransferSource;
  final ReceiveRegistrationSource _receiveRegistrationSource;
  final NearbySendScan _nearbySendScan;
  final bool _enableIdleIncomingListener;
  Timer? _idleReceiverRefreshTimer;
  Timer? _nearbyScanTimer;
  bool _nearbyScanInFlight = false;
  /// True after a browse attempt finishes while [canBrowseNearbyReceivers] was satisfied.
  bool _nearbyScanCompletedOnce = false;
  StreamSubscription<SendTransferUpdate>? _sendTransferSubscription;
  StreamSubscription<rust_receiver.IdleIncomingEvent>? _idleIncomingSubscription;
  bool _idleIncomingDecisionPending = false;
  int _sendTransferGeneration = 0;
  TransferDirection _mode = TransferDirection.send;
  TransferStage _sendStage = TransferStage.idle;
  TransferStage _receiveStage = TransferStage.idle;
  bool _sendDropActive = false;
  bool _receiveEntryExpanded = false;
  String _sendDestinationCode = '';
  String? _sendDestinationLabel;
  String? _sendRemoteDeviceType;
  String _receiveCode = '';
  String? _receiveErrorText;
  List<TransferItemViewData> _sendItems = const [];
  List<TransferItemViewData> _receiveItems = const [];
  List<SendDestinationViewData> _nearbySendDestinations = const [];
  TransferSummaryViewData? _sendSummary;
  TransferSummaryViewData? _receiveSummary;
  bool _isInspectingSendItems = false;
  final bool _animateSendingConnection;

  int? _sendPayloadBytesSent;
  int? _sendPayloadTotalBytes;
  String? _sendTransferSpeedLabel;
  String? _sendTransferEtaLabel;
  DateTime? _lastSendProgressSampleAt;
  int? _lastSendProgressBytes;
  double? _sendSmoothedBps;
  DateTime? _sendPayloadStartedAt;
  List<TransferMetricRow>? _sendCompletionMetrics;

  // Receiving payload progress (overall bytes).
  int? _receivePayloadBytesReceived;
  int? _receivePayloadTotalBytes;
  DateTime? _receivePayloadStartedAt;

  String get deviceName => _deviceName;
  String get deviceType => _deviceType;
  bool get animateSendingConnection => _animateSendingConnection;
  String get idleReceiveCode => _idleReceiveCode;
  String get idleReceiveStatus => _idleReceiveStatus;
  TransferDirection get mode => _mode;
  TransferStage get sendStage => _sendStage;
  TransferStage get receiveStage => _receiveStage;
  bool get sendDropActive => _sendDropActive;
  bool get receiveEntryExpanded => _receiveEntryExpanded;
  String get sendDestinationCode => _sendDestinationCode;
  String? get sendDestinationLabel => _sendDestinationLabel;
  String? get sendRemoteDeviceType => _sendRemoteDeviceType;
  String get receiveCode => _receiveCode;
  String? get receiveErrorText => _receiveErrorText;
  List<TransferItemViewData> get sendItems => _sendItems;
  bool get isInspectingSendItems => _isInspectingSendItems;
  List<TransferItemViewData> get receiveItems => _receiveItems;
  List<SendDestinationViewData> get nearbySendDestinations =>
      List<SendDestinationViewData>.unmodifiable(_nearbySendDestinations);

  /// Whether LAN browse is active (files chosen and not in the inspection overlay).
  bool get canBrowseNearbyReceivers => _shouldScanNearby;

  bool get nearbyScanInProgress => _nearbyScanInFlight;

  /// After the first browse in this send-selection session (see empty vs loading UI).
  bool get nearbyScanHasCompletedOnce => _nearbyScanCompletedOnce;
  TransferSummaryViewData? get sendSummary => _sendSummary;
  TransferSummaryViewData? get receiveSummary => _receiveSummary;

  int? get sendPayloadBytesSent => _sendPayloadBytesSent;
  int? get sendPayloadTotalBytes => _sendPayloadTotalBytes;
  String? get sendTransferSpeedLabel => _sendTransferSpeedLabel;
  String? get sendTransferEtaLabel => _sendTransferEtaLabel;
  bool get hasSendPayloadProgress =>
      _sendPayloadBytesSent != null &&
      _sendPayloadTotalBytes != null &&
      _sendPayloadTotalBytes! > 0;

  List<TransferMetricRow>? get sendCompletionMetrics => _sendCompletionMetrics;

  int? get receivePayloadBytesReceived => _receivePayloadBytesReceived;
  int? get receivePayloadTotalBytes => _receivePayloadTotalBytes;
  bool get hasReceivePayloadProgress =>
      _receivePayloadBytesReceived != null &&
      _receivePayloadTotalBytes != null &&
      _receivePayloadTotalBytes! > 0;

  List<TransferMetricRow>? get receiveCompletionMetrics {
    if (_receiveStage != TransferStage.completed || _receiveSummary == null) {
      return null;
    }
    final s = _receiveSummary!;
    final startedAt = _receivePayloadStartedAt;
    final now = DateTime.now();
    final bytesReceived = _receivePayloadBytesReceived ?? 0;
    final payloadSec = startedAt == null
        ? null
        : now.difference(startedAt).inMilliseconds / 1000.0;
    return [
      if (s.senderName.isNotEmpty)
        TransferMetricRow(label: 'From', value: s.senderName),
      TransferMetricRow(
        label: 'Saved to',
        value: s.destinationLabel,
      ),
      TransferMetricRow(
        label: 'Files',
        value: '${s.itemCount}',
      ),
      TransferMetricRow(label: 'Size', value: s.totalSize),
      if (startedAt != null) ...[
        if (now.difference(startedAt).inMilliseconds >= 200)
          TransferMetricRow(
            label: 'Transfer time',
            value: _formatElapsedDuration(now.difference(startedAt)),
          ),
        if (payloadSec != null && payloadSec >= 0.25 && bytesReceived > 0)
          TransferMetricRow(
            label: 'Average speed',
            value: _formatBytesPerSecond(bytesReceived / payloadSec),
          ),
      ],
    ];
  }

  List<TransferItemViewData> get activeItems =>
      _mode == TransferDirection.receive ? _receiveItems : _sendItems;
  String? get primaryItemLabel =>
      activeItems.isEmpty ? null : activeItems.first.name;
  int get remainingItemCount =>
      activeItems.isEmpty ? 0 : activeItems.length - 1;
  bool get hasActiveTransferCard =>
      _sendStage != TransferStage.idle || _receiveStage != TransferStage.idle;
  bool get hasSendFlow => _sendStage != TransferStage.idle;
  bool get hasReceiveFlow => _receiveStage != TransferStage.idle;
  bool get canGoBack => hasSendFlow || _mode == TransferDirection.receive;

  /// Back control in [ShellHeader]; hidden on send success so users rely on primary actions.
  bool get showShellBackButton =>
      canGoBack &&
      _sendStage != TransferStage.completed &&
      !(_mode == TransferDirection.receive &&
          _receiveStage == TransferStage.waiting);

  void setMode(TransferDirection mode) {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    if (mode == TransferDirection.receive) {
      _receiveErrorText = null;
    }
    notifyListeners();
  }

  void openReceiveEntry() {
    _mode = TransferDirection.receive;
    _receiveStage = TransferStage.idle;
    _receiveErrorText = null;
    _receiveItems = const [];
    _receiveSummary = null;
    _clearReceivePayloadMetrics();
    notifyListeners();
  }

  void closeReceiveEntry() {
    _receiveEntryExpanded = false;
    _mode = TransferDirection.receive;
    _receiveStage = TransferStage.idle;
    _receiveCode = '';
    _receiveErrorText = null;
    _receiveItems = const [];
    _receiveSummary = null;
    _clearReceivePayloadMetrics();
    notifyListeners();
  }

  void activateSendDropTarget() {
    _applySelectedSendItems(_defaultDroppedSendItems);
  }

  void pickSendItems() {
    unawaited(_pickSendItems());
  }

  void acceptDroppedSendItems(List<String> paths) {
    unawaited(_acceptDroppedSendItems(paths));
  }

  void appendDroppedSendItems(List<String> paths) {
    unawaited(_appendDroppedSendItems(paths));
  }

  void clearSendFlow() {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.idle;
    _sendDropActive = false;
    _isInspectingSendItems = false;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
    _sendRemoteDeviceType = null;
    _nearbySendDestinations = const [];
    _sendItems = const [];
    _sendSummary = null;
    _clearSendTransferMetrics();
    _sendPayloadStartedAt = null;
    _sendCompletionMetrics = null;
    notifyListeners();
  }

  void updateSendDestinationCode(String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (normalized == _sendDestinationCode) {
      return;
    }
    _sendDestinationCode = normalized;
    notifyListeners();
    if (_sendDestinationCode.length == 6 &&
        _sendStage == TransferStage.collecting &&
        !_isInspectingSendItems &&
        _sendItems.isNotEmpty) {
      _startSendTransfer(_sendDestinationCode);
    }
  }

  void updateReceiveCode(String value) {
    _receiveCode = value.toUpperCase();
    _receiveErrorText = null;
    if (_receiveStage == TransferStage.error) {
      _receiveStage = TransferStage.idle;
    }
    notifyListeners();
  }

  void previewReceiveOffer() {
    _mode = TransferDirection.receive;
    final trimmed = _receiveCode.trim().toUpperCase();
    _receiveCode = trimmed;
    if (trimmed.length < 6) {
      _receiveStage = TransferStage.error;
      _receiveSummary = null;
      _receiveItems = const [];
      _receiveErrorText = 'Enter the 6-character code from the sender.';
      notifyListeners();
      return;
    }

    _receiveEntryExpanded = true;
    _receiveStage = TransferStage.review;
    _receiveErrorText = null;
    _receiveSummary = sampleReceiveSummary;
    _receiveItems = List<TransferItemViewData>.unmodifiable(sampleReceiveItems);
    notifyListeners();
  }

  void acceptReceiveOffer() {
    if (!_idleIncomingDecisionPending) {
      // Preview flow with sample data (no idle incoming listener).
      if (_receiveStage == TransferStage.review) {
        _receiveStage = TransferStage.completed;
        _receiveSummary = (_receiveSummary ?? sampleReceiveSummary).copyWith(
          statusMessage: 'Saved to Downloads',
        );
        notifyListeners();
      }
      return;
    }

    // Approve the pending offer over the wire; Rust will then emit
    // `IdleIncomingPhase.receiving` and `IdleIncomingPhase.completed`.
    _idleIncomingDecisionPending = false;
    _mode = TransferDirection.receive;
    _receiveEntryExpanded = true;
    _receiveStage = TransferStage.waiting;
    _receiveErrorText = null;

    // Reset per-transfer progress while keeping the known total bytes from the
    // OfferReady phase.
    _receivePayloadBytesReceived = null;
    _receivePayloadStartedAt = null;

    // Keep current summary (sender/files/destination) but switch message until
    // the Rust listener reports the real phase transitions.
    _receiveSummary = (_receiveSummary ?? sampleReceiveSummary).copyWith(
      statusMessage: 'Receiving files…',
    );

    unawaited(_respondIdleIncoming(accept: true));
    notifyListeners();
  }

  void declineReceiveOffer() {
    if (_idleIncomingDecisionPending) {
      _idleIncomingDecisionPending = false;
      unawaited(_respondIdleIncoming(accept: false));
      return;
    }
    closeReceiveEntry();
  }

  void loadReceiveError() {
    _mode = TransferDirection.receive;
    _receiveEntryExpanded = true;
    _receiveCode = 'F9P2Q1';
    _receiveStage = TransferStage.error;
    _receiveSummary = null;
    _receiveItems = const [];
    _receiveErrorText = 'That code expired. Ask the sender for a new code.';
    notifyListeners();
  }

  /// Stops an in-flight send (waiting for recipient / connecting) and returns
  /// to the file + code screen. No-op if not in [ready] or [waiting].
  void cancelSendInProgress() {
    if (_sendStage != TransferStage.ready && _sendStage != TransferStage.waiting) {
      return;
    }
    _returnToSendSelection();
    notifyListeners();
  }

  void resetShell() {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.idle;
    _sendDropActive = false;
    _isInspectingSendItems = false;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
    _nearbySendDestinations = const [];
    _sendItems = const [];
    _sendSummary = null;
    _clearSendTransferMetrics();
    _sendPayloadStartedAt = null;
    _sendCompletionMetrics = null;
    _resetReceiveFlow();
    notifyListeners();
  }

  void goBack() {
    if (_mode == TransferDirection.receive) {
      switch (_receiveStage) {
        case TransferStage.review:
          if (_idleIncomingDecisionPending) {
            unawaited(_respondIdleIncoming(accept: false));
          }
          _receiveStage = TransferStage.idle;
          _receiveEntryExpanded = false;
          _receiveErrorText = null;
          _receiveItems = const [];
          _receiveSummary = null;
          _idleIncomingDecisionPending = false;
          notifyListeners();
          return;
        case TransferStage.error:
        case TransferStage.completed:
          _receiveStage = TransferStage.idle;
          _receiveEntryExpanded = false;
          _receiveErrorText = null;
          _receiveItems = const [];
          _receiveSummary = null;
          notifyListeners();
          return;
        case TransferStage.idle:
        case TransferStage.collecting:
        case TransferStage.ready:
        case TransferStage.waiting:
          resetShell();
          return;
      }
    }

    switch (_sendStage) {
      case TransferStage.collecting:
        clearSendFlow();
        return;
      case TransferStage.ready:
      case TransferStage.waiting:
      case TransferStage.completed:
      case TransferStage.error:
        _returnToSendSelection();
        notifyListeners();
        return;
      case TransferStage.idle:
      case TransferStage.review:
        resetShell();
        return;
    }
  }

  void _resetReceiveFlow() {
    _receiveEntryExpanded = false;
    _receiveStage = TransferStage.idle;
    _receiveErrorText = null;
    _receiveItems = const [];
    _receiveSummary = null;
    _idleIncomingDecisionPending = false;
    _clearReceivePayloadMetrics();
  }

  void _beginSend(SendTransferUpdate update) {
    _cancelNearbyScanTimer();
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = switch (update.phase) {
      SendTransferUpdatePhase.connecting => TransferStage.ready,
      SendTransferUpdatePhase.waitingForDecision => TransferStage.waiting,
      SendTransferUpdatePhase.sending => TransferStage.waiting,
      SendTransferUpdatePhase.completed => TransferStage.completed,
      SendTransferUpdatePhase.failed => TransferStage.error,
    };
    _applySendTransferMetrics(update);
    _sendDropActive = false;
    _sendDestinationLabel = update.destinationLabel;
    _sendRemoteDeviceType = update.remoteDeviceType;
    _nearbySendDestinations = _defaultSendDestinations;
    _sendItems = List<TransferItemViewData>.unmodifiable(
      _sendItems.isEmpty ? sampleSendItems : _sendItems,
    );
    _sendSummary = (_sendSummary ?? sampleSendSummary).copyWith(
      itemCount: update.itemCount,
      totalSize: update.totalSize,
      code: _sendDestinationCode,
      destinationLabel: update.destinationLabel,
      statusMessage: update.errorMessage ?? update.statusMessage,
    );
    if (update.phase == SendTransferUpdatePhase.completed) {
      _sendCompletionMetrics = _buildSendCompletionMetrics(update);
    } else {
      _sendCompletionMetrics = null;
    }
    if (update.phase == SendTransferUpdatePhase.completed ||
        update.phase == SendTransferUpdatePhase.failed) {
      unawaited(_resumeIdleLanAdvertisementAfterSend());
    }
  }

  Future<void> _pickSendItems() async {
    _beginSendInspection(clearExistingItems: true);
    try {
      final items = await _sendItemSource.pickFiles();
      if (items.isEmpty) {
        clearSendFlow();
        return;
      }
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      clearSendFlow();
      _reportSendSelectionError(error, stackTrace);
    }
  }

  Future<void> _acceptDroppedSendItems(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    _beginSendInspection(clearExistingItems: true);
    try {
      final items = await _sendItemSource.loadPaths(paths);
      if (items.isEmpty) {
        clearSendFlow();
        return;
      }
      _applySelectedSendItems(items);
    } catch (error, stackTrace) {
      clearSendFlow();
      _reportSendSelectionError(error, stackTrace);
    }
  }

  Future<void> _appendDroppedSendItems(List<String> paths) async {
    if (paths.isEmpty) {
      return;
    }
    _beginSendInspection(clearExistingItems: false);
    try {
      final items = await _sendItemSource.loadPaths(paths);
      if (items.isEmpty) {
        _finishSendInspection();
        return;
      }
      _applySelectedSendItems(_mergeSendItems(_sendItems, items));
    } catch (error, stackTrace) {
      _finishSendInspection();
      _reportSendSelectionError(error, stackTrace);
    }
  }

  void _applySelectedSendItems(List<TransferItemViewData> items) {
    _cancelActiveSendTransfer();
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.collecting;
    _sendDropActive = true;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
    _sendRemoteDeviceType = null;
    _nearbySendDestinations = _defaultSendDestinations;
    _sendItems = List<TransferItemViewData>.unmodifiable(items);
    _isInspectingSendItems = false;
    notifyListeners();
    _scheduleNearbyScanning();
  }

  void _beginSendInspection({required bool clearExistingItems}) {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.collecting;
    _sendDropActive = true;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
    _sendRemoteDeviceType = null;
    _nearbySendDestinations = _defaultSendDestinations;
    _isInspectingSendItems = true;
    if (clearExistingItems) {
      _sendItems = const [];
    }
    notifyListeners();
  }

  void _finishSendInspection() {
    _isInspectingSendItems = false;
    notifyListeners();
    if (_sendItems.isNotEmpty) {
      _scheduleNearbyScanning();
    }
  }

  List<TransferItemViewData> _mergeSendItems(
    List<TransferItemViewData> existing,
    List<TransferItemViewData> incoming,
  ) {
    final merged = <TransferItemViewData>[];
    final seenPaths = <String>{};

    for (final item in [...existing, ...incoming]) {
      if (seenPaths.add(item.path)) {
        merged.add(item);
      }
    }

    return merged;
  }

  void _reportSendSelectionError(Object error, StackTrace stackTrace) {
    debugPrint('Failed to inspect selected send items: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  void dispose() {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _idleReceiverRefreshTimer?.cancel();
    unawaited(_idleIncomingSubscription?.cancel());
    _idleIncomingSubscription = null;
    super.dispose();
  }

  void _startIdleIncomingListener() {
    if (!_enableIdleIncomingListener) {
      return;
    }
    unawaited(_idleIncomingSubscription?.cancel());
    _idleIncomingSubscription = rust_receiver
        .startIdleIncomingListener(
          downloadRoot: _defaultReceiveDownloadRoot(),
          deviceName: _deviceName,
          deviceType: _deviceType,
        )
        .listen(
          _onIdleIncomingEvent,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Idle incoming listener error: $error');
            debugPrintStack(stackTrace: stackTrace);
            resetShell();
          },
        );
  }

  void _onIdleIncomingEvent(rust_receiver.IdleIncomingEvent event) {
    switch (event.phase) {
      case rust_receiver.IdleIncomingPhase.connecting:
        return;
      case rust_receiver.IdleIncomingPhase.offerReady:
        _applyIdleOfferReady(event);
        return;
      case rust_receiver.IdleIncomingPhase.receiving:
        _idleIncomingDecisionPending = false;
        _mode = TransferDirection.receive;
        _receiveEntryExpanded = true;
        _receiveStage = TransferStage.waiting;
        _receivePayloadBytesReceived = _bigIntToInt(event.totalSizeBytes);
        if (_receivePayloadStartedAt == null &&
            (_receivePayloadBytesReceived ?? 0) > 0) {
          _receivePayloadStartedAt = DateTime.now();
        }
        _receiveSummary = (_receiveSummary ??
                TransferSummaryViewData(
                  itemCount: _bigIntToInt(event.itemCount),
                  totalSize: event.totalSizeLabel,
                  code: _idleReceiveCode,
                  expiresAt: '',
                  destinationLabel: event.destinationLabel,
                  statusMessage: event.statusMessage,
                  senderName: event.senderName,
                ))
            .copyWith(statusMessage: event.statusMessage);
        notifyListeners();
        return;
      case rust_receiver.IdleIncomingPhase.completed:
        _idleIncomingDecisionPending = false;
        _mode = TransferDirection.receive;
        _receiveEntryExpanded = true;
        _receiveStage = TransferStage.completed;
        _receivePayloadBytesReceived = _bigIntToInt(event.totalSizeBytes);
        _receivePayloadTotalBytes ??= _receivePayloadBytesReceived;
        _receiveSummary = (_receiveSummary ??
                TransferSummaryViewData(
                  itemCount: _bigIntToInt(event.itemCount),
                  totalSize: event.totalSizeLabel,
                  code: _idleReceiveCode,
                  expiresAt: '',
                  destinationLabel: event.saveRootLabel,
                  statusMessage: event.statusMessage,
                  senderName: event.senderName,
                ))
            .copyWith(
              itemCount: _bigIntToInt(event.itemCount),
              totalSize: event.totalSizeLabel,
              destinationLabel: event.saveRootLabel,
              statusMessage: event.statusMessage,
            );
        _receiveErrorText = null;
        notifyListeners();
        unawaited(_ensureIdleReceiver());
        return;
      case rust_receiver.IdleIncomingPhase.failed:
        _idleIncomingDecisionPending = false;
        debugPrint(
          '[drift/controller] incoming receive failed: '
          '${event.errorMessage ?? event.statusMessage}',
        );
        resetShell();
        unawaited(_ensureIdleReceiver());
        return;
      case rust_receiver.IdleIncomingPhase.declined:
        _idleIncomingDecisionPending = false;
        _resetReceiveFlow();
        _mode = TransferDirection.receive;
        notifyListeners();
        unawaited(_ensureIdleReceiver());
        return;
    }
  }

  void _applyIdleOfferReady(rust_receiver.IdleIncomingEvent event) {
    final items = event.files.map(_incomingFileToViewData).toList();
    _idleIncomingDecisionPending = true;
    _cancelActiveSendTransfer();
    _mode = TransferDirection.receive;
    _receiveEntryExpanded = true;
    _receiveStage = TransferStage.review;
    _receiveErrorText = null;
    _receiveItems = List<TransferItemViewData>.unmodifiable(items);

    // Save the total size for the receiving progress bar.
    _receivePayloadTotalBytes = _bigIntToInt(event.totalSizeBytes);
    _receivePayloadBytesReceived = null;
    _receivePayloadStartedAt = null;

    _receiveSummary = TransferSummaryViewData(
      itemCount: _bigIntToInt(event.itemCount),
      totalSize: event.totalSizeLabel,
      code: _idleReceiveCode,
      expiresAt: '',
      destinationLabel: event.saveRootLabel.isNotEmpty
          ? event.saveRootLabel
          : 'Downloads',
      statusMessage: event.statusMessage,
      senderName: event.senderName,
    );
    unawaited(focusAppForIncomingTransfer());
    notifyListeners();
  }

  TransferItemViewData _incomingFileToViewData(rust_receiver.IdleIncomingFileRow f) {
    final path = f.path;
    final segments = path.split('/')..removeWhere((s) => s.isEmpty);
    final name = segments.isEmpty ? path : segments.last;
    final bytes = _bigIntToInt(f.size);
    return TransferItemViewData(
      name: name,
      path: path,
      size: _formatByteSize(bytes),
      kind: TransferItemKind.file,
    );
  }

  static int _bigIntToInt(BigInt v) {
    if (v.bitLength > 63) {
      return 0x7fffffff;
    }
    return v.toInt();
  }

  static String _formatByteSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }

  static String _defaultReceiveDownloadRoot() {
    // For now, keep Flutter writes confined to a guaranteed-writable directory.
    // (This avoids macOS App Sandbox issues with `~/Downloads`.)
    return '${Directory.systemTemp.path}${Platform.pathSeparator}Downloads';
  }

  Future<void> _respondIdleIncoming({required bool accept}) async {
    try {
      await rust_receiver.respondIdleIncomingOffer(accept: accept);
    } catch (error, stackTrace) {
      debugPrint('respondIdleIncomingOffer failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _idleIncomingDecisionPending = false;
      resetShell();
    }
  }

  Future<void> _ensureIdleReceiver() async {
    // Keep idle-registration refresh strictly on the idle shell so we never
    // disturb an active send/receive session.
    final isIdleShell =
        !hasActiveTransferCard &&
        !_receiveEntryExpanded &&
        !_idleIncomingDecisionPending;
    if (!isIdleShell) {
      return;
    }

    try {
      final registration = await _receiveRegistrationSource.ensureIdleReceiver(
        deviceName: deviceName,
      );
      _idleReceiveCode = registration.code.trim().toUpperCase();
      _idleReceiveStatus = 'Ready';
      notifyListeners();
    } catch (error, stackTrace) {
      if (_idleReceiveCode.trim().length != 6) {
        _idleReceiveStatus = 'Unavailable';
        notifyListeners();
      }
      debugPrint('Failed to ensure idle receiver: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _pauseIdleLanAdvertisementForActiveSend() async {
    try {
      await rust_receiver.pauseIdleLanAdvertisement();
    } catch (error, stackTrace) {
      debugPrint('pauseIdleLanAdvertisement failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _resumeIdleLanAdvertisementAfterSend() async {
    try {
      await rust_receiver.resumeIdleLanAdvertisement();
    } catch (error, stackTrace) {
      debugPrint('resumeIdleLanAdvertisement failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _returnToSendSelection() {
    _cancelActiveSendTransfer();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.collecting;
    _sendDropActive = true;
    _isInspectingSendItems = false;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
    _sendRemoteDeviceType = null;
    _nearbySendDestinations = _defaultSendDestinations;
    _sendSummary = null;
    _clearSendTransferMetrics();
    _sendPayloadStartedAt = null;
    _sendCompletionMetrics = null;
    _resetReceiveFlow();
    _scheduleNearbyScanning();
  }

  bool get _shouldScanNearby =>
      _sendStage == TransferStage.collecting &&
      _sendItems.isNotEmpty &&
      !_isInspectingSendItems;

  void _cancelNearbyScanTimer() {
    _nearbyScanTimer?.cancel();
    _nearbyScanTimer = null;
  }

  void _scheduleNearbyScanning() {
    _cancelNearbyScanTimer();
    _nearbyScanCompletedOnce = false;
    notifyListeners();
    if (!_shouldScanNearby) {
      return;
    }
    unawaited(_runNearbyScanOnce());
    _nearbyScanTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!_shouldScanNearby) {
        _cancelNearbyScanTimer();
        return;
      }
      unawaited(_runNearbyScanOnce());
    });
  }

  Future<void> _runNearbyScanOnce() async {
    if (!_shouldScanNearby || _nearbyScanInFlight) {
      return;
    }
    _nearbyScanInFlight = true;
    notifyListeners();
    try {
      final next = await _nearbySendScan();
      if (!_shouldScanNearby) {
        return;
      }
      _nearbySendDestinations = List<SendDestinationViewData>.unmodifiable(
        next,
      );
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[drift/controller] nearby scan failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _nearbyScanInFlight = false;
      _nearbyScanCompletedOnce = true;
      notifyListeners();
    }
  }

  /// Starts a send using the LAN ticket from mDNS (see [SendDestinationViewData.lanTicket]).
  void selectNearbyDestination(SendDestinationViewData destination) {
    final ticket = destination.lanTicket?.trim();
    if (ticket == null || ticket.isEmpty) {
      return;
    }
    if (!_shouldScanNearby) {
      return;
    }
    _startSendTransferWithTicket(destination, ticket);
  }

  void _startSendTransferWithTicket(
    SendDestinationViewData destination,
    String ticket,
  ) {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _sendPayloadStartedAt = null;
    _sendCompletionMetrics = null;
    final generation = ++_sendTransferGeneration;
    final lanLabel = destination.name;
    _sendDestinationCode = '';
    debugPrint(
      '[drift/controller] starting LAN send transfer '
      'generation=$generation label=$lanLabel items=${_sendItems.length}',
    );
    final request = SendTransferRequestData(
      code: '',
      ticket: ticket,
      lanDestinationLabel: lanLabel,
      paths: _sendItems.map((item) => item.path).toList(growable: false),
      deviceName: _deviceName,
      deviceType: _deviceType,
    );
    _listenToSendTransfer(
      generation: generation,
      request: request,
      errorFallbackDestination:
          _sendDestinationLabel ?? lanLabel,
    );
  }

  void _listenToSendTransfer({
    required int generation,
    required SendTransferRequestData request,
    required String errorFallbackDestination,
  }) {
    unawaited(_pauseIdleLanAdvertisementForActiveSend());
    _sendTransferSubscription = _sendTransferSource
        .startTransfer(request)
        .listen(
          (update) {
            if (generation != _sendTransferGeneration) {
              debugPrint(
                '[drift/controller] ignoring stale send update '
                'generation=$generation current=$_sendTransferGeneration',
              );
              return;
            }
            debugPrint(
              '[drift/controller] applying send update '
              'generation=$generation phase=${update.phase.name} '
              'destination=${update.destinationLabel}',
            );
            _beginSend(update);
            notifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (generation != _sendTransferGeneration) {
              return;
            }
            debugPrint('[drift/controller] failed to send files: $error');
            debugPrintStack(stackTrace: stackTrace);
            _beginSend(
              SendTransferUpdate(
                phase: SendTransferUpdatePhase.failed,
                destinationLabel:
                    _sendDestinationLabel ?? errorFallbackDestination,
                statusMessage: 'Request sent',
                itemCount: _sendItems.length,
                totalSize: sampleSendSummary.totalSize,
                bytesSent: 0,
                totalBytes: 0,
                errorMessage: error.toString(),
              ),
            );
            notifyListeners();
          },
        );
  }

  void _startSendTransfer(String normalizedCode) {
    _cancelNearbyScanTimer();
    _cancelActiveSendTransfer();
    _sendPayloadStartedAt = null;
    _sendCompletionMetrics = null;
    final generation = ++_sendTransferGeneration;
    debugPrint(
      '[drift/controller] starting send transfer '
      'generation=$generation code=$normalizedCode items=${_sendItems.length}',
    );
    final request = SendTransferRequestData(
      code: normalizedCode,
      paths: _sendItems.map((item) => item.path).toList(growable: false),
      deviceName: _deviceName,
      deviceType: _deviceType,
    );
    _listenToSendTransfer(
      generation: generation,
      request: request,
      errorFallbackDestination:
          _sendDestinationLabel ?? _formatCodeAsDestination(normalizedCode),
    );
  }

  void _cancelActiveSendTransfer() {
    if (_sendTransferSubscription != null) {
      debugPrint(
        '[drift/controller] cancelling send transfer '
        'generation=$_sendTransferGeneration',
      );
    }
    _sendTransferGeneration += 1;
    unawaited(_sendTransferSubscription?.cancel());
    _sendTransferSubscription = null;
    unawaited(_resumeIdleLanAdvertisementAfterSend());
  }

  static String _formatCodeAsDestination(String code) {
    final prefix = code.substring(0, 3);
    final suffix = code.substring(3);
    return 'Code $prefix $suffix';
  }

  void _clearSendTransferMetrics() {
    _sendPayloadBytesSent = null;
    _sendPayloadTotalBytes = null;
    _sendTransferSpeedLabel = null;
    _sendTransferEtaLabel = null;
    _lastSendProgressSampleAt = null;
    _lastSendProgressBytes = null;
    _sendSmoothedBps = null;
  }

  void _clearReceivePayloadMetrics() {
    _receivePayloadBytesReceived = null;
    _receivePayloadTotalBytes = null;
    _receivePayloadStartedAt = null;
  }

  void _applySendTransferMetrics(SendTransferUpdate update) {
    switch (update.phase) {
      case SendTransferUpdatePhase.connecting:
      case SendTransferUpdatePhase.waitingForDecision:
        _clearSendTransferMetrics();
        _sendPayloadStartedAt = null;
        return;
      case SendTransferUpdatePhase.sending:
        _sendPayloadBytesSent = update.bytesSent;
        _sendPayloadTotalBytes = update.totalBytes;
        _sendPayloadStartedAt ??= DateTime.now();
        _refreshSendThroughputEstimate();
        return;
      case SendTransferUpdatePhase.completed:
      case SendTransferUpdatePhase.failed:
        _clearSendTransferMetrics();
        return;
    }
  }

  List<TransferMetricRow> _buildSendCompletionMetrics(SendTransferUpdate update) {
    final rows = <TransferMetricRow>[];
    final recipient = update.destinationLabel.trim().isEmpty
        ? 'Recipient device'
        : update.destinationLabel;
    rows.add(TransferMetricRow(label: 'Sent to', value: recipient));
    final n = update.itemCount;
    rows.add(TransferMetricRow(label: 'Files', value: '$n'));
    rows.add(TransferMetricRow(label: 'Size', value: update.totalSize));

    final payloadStart = _sendPayloadStartedAt;
    final now = DateTime.now();
    if (payloadStart != null) {
      final transferElapsed = now.difference(payloadStart);
      if (transferElapsed.inMilliseconds >= 200) {
        rows.add(
          TransferMetricRow(
            label: 'Transfer time',
            value: _formatElapsedDuration(transferElapsed),
          ),
        );
      }
      final payloadSec = transferElapsed.inMilliseconds / 1000.0;
      if (payloadSec >= 0.25 && update.bytesSent > 0) {
        rows.add(
          TransferMetricRow(
            label: 'Average speed',
            value: _formatBytesPerSecond(update.bytesSent / payloadSec),
          ),
        );
      }
    }

    return rows;
  }

  static String _formatElapsedDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 60 * 1000) {
      final sec = (ms / 1000).clamp(0.05, double.infinity);
      if (sec < 10) {
        return '${sec.toStringAsFixed(1)} s';
      }
      return '${sec.round()} s';
    }
    if (ms < 3600 * 1000) {
      final m = d.inMinutes;
      final s = d.inSeconds % 60;
      return s == 0 ? '$m min' : '$m min $s s';
    }
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  void _refreshSendThroughputEstimate() {
    final bytesSent = _sendPayloadBytesSent;
    final totalBytes = _sendPayloadTotalBytes;
    if (bytesSent == null || totalBytes == null || totalBytes <= 0) {
      _sendTransferSpeedLabel = null;
      _sendTransferEtaLabel = null;
      return;
    }

    final now = DateTime.now();
    final prevAt = _lastSendProgressSampleAt;
    final prevBytes = _lastSendProgressBytes;
    if (prevAt != null && prevBytes != null) {
      final dtSec = now.difference(prevAt).inMicroseconds / 1e6;
      final dBytes = bytesSent - prevBytes;
      if (dtSec >= 0.08 && dBytes >= 0) {
        final inst = dBytes / dtSec;
        final prev = _sendSmoothedBps;
        _sendSmoothedBps = prev == null
            ? inst
            : 0.22 * inst + 0.78 * prev;
      }
    }
    _lastSendProgressSampleAt = now;
    _lastSendProgressBytes = bytesSent;

    final bps = _sendSmoothedBps;
    if (bps != null && bps >= 16) {
      _sendTransferSpeedLabel = _formatBytesPerSecond(bps);
      final left = (totalBytes - bytesSent).clamp(0, totalBytes);
      _sendTransferEtaLabel =
          left <= 0 ? null : _formatEtaSeconds(left / bps);
    } else {
      _sendTransferSpeedLabel = null;
      _sendTransferEtaLabel = null;
    }
  }

  static String _formatBytesPerSecond(double bps) {
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    var v = bps;
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i += 1;
    }
    final decimals = v >= 10 || i == 0 ? 0 : 1;
    return '${v.toStringAsFixed(decimals)} ${units[i]}';
  }

  static String _formatEtaSeconds(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) {
      return '';
    }
    if (seconds < 45) {
      return 'About ${seconds.round()} s left';
    }
    if (seconds < 3600) {
      final m = (seconds / 60).ceil();
      return m <= 1 ? 'About 1 min left' : 'About $m min left';
    }
    final h = (seconds / 3600).ceil();
    return h <= 1 ? 'About 1 h left' : 'About $h h left';
  }

  static String _inferDeviceType() {
    // Auto-infer based on where the Flutter app is running.
    if (Platform.isAndroid || Platform.isIOS) {
      return 'phone';
    }
    return 'laptop';
  }

  static String _defaultDeviceName() => rust_device.randomDeviceName();

  static String _normalizeDeviceName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return rust_device.randomDeviceName();
    }

    final firstSegment = trimmed.split('.').first.trim();
    return firstSegment.isEmpty
        ? rust_device.randomDeviceName()
        : firstSegment;
  }
}
