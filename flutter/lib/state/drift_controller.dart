import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import '../platform/receive_registration_source.dart';
import '../platform/send_item_source.dart';
import '../platform/send_transfer_source.dart';
import 'drift_sample_data.dart';

class DriftController extends ChangeNotifier {
  DriftController({
    String? deviceName,
    String idleReceiveCode = '......',
    String idleReceiveStatus = 'Registering',
    bool enableIdleReceiverRefresh = true,
    List<SendDestinationViewData>? nearbySendDestinations,
    List<TransferItemViewData>? droppedSendItems,
    SendItemSource? sendItemSource,
    SendTransferSource? sendTransferSource,
    ReceiveRegistrationSource? receiveRegistrationSource,
    bool animateSendingConnection = true,
  }) : _deviceName = _normalizeDeviceName(deviceName ?? _defaultDeviceName()),
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
       _animateSendingConnection = animateSendingConnection {
    unawaited(_ensureIdleReceiver());
    if (enableIdleReceiverRefresh) {
      _idleReceiverRefreshTimer = Timer.periodic(const Duration(minutes: 1), (
        _,
      ) {
        unawaited(_ensureIdleReceiver());
      });
    }
  }

  static const int compactPreviewLimit = 3;

  final String _deviceName;
  String _idleReceiveCode;
  String _idleReceiveStatus;
  final List<TransferItemViewData> _defaultDroppedSendItems;
  final List<SendDestinationViewData> _defaultSendDestinations;
  final SendItemSource _sendItemSource;
  final SendTransferSource _sendTransferSource;
  final ReceiveRegistrationSource _receiveRegistrationSource;
  Timer? _idleReceiverRefreshTimer;
  StreamSubscription<SendTransferUpdate>? _sendTransferSubscription;
  int _sendTransferGeneration = 0;
  TransferDirection _mode = TransferDirection.send;
  TransferStage _sendStage = TransferStage.idle;
  TransferStage _receiveStage = TransferStage.idle;
  bool _sendDropActive = false;
  bool _receiveEntryExpanded = false;
  String _sendDestinationCode = '';
  String? _sendDestinationLabel;
  String _receiveCode = '';
  String? _receiveErrorText;
  List<TransferItemViewData> _sendItems = const [];
  List<TransferItemViewData> _receiveItems = const [];
  List<SendDestinationViewData> _nearbySendDestinations = const [];
  TransferSummaryViewData? _sendSummary;
  TransferSummaryViewData? _receiveSummary;
  bool _isInspectingSendItems = false;
  final bool _animateSendingConnection;

  String get deviceName => _deviceName;
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
  String get receiveCode => _receiveCode;
  String? get receiveErrorText => _receiveErrorText;
  List<TransferItemViewData> get sendItems => _sendItems;
  bool get isInspectingSendItems => _isInspectingSendItems;
  List<TransferItemViewData> get receiveItems => _receiveItems;
  List<SendDestinationViewData> get nearbySendDestinations =>
      List<SendDestinationViewData>.unmodifiable(_nearbySendDestinations);
  TransferSummaryViewData? get sendSummary => _sendSummary;
  TransferSummaryViewData? get receiveSummary => _receiveSummary;
  List<TransferItemViewData> get visibleSendItems =>
      List<TransferItemViewData>.unmodifiable(
        _sendItems.take(compactPreviewLimit),
      );
  List<TransferItemViewData> get visibleReceiveItems =>
      List<TransferItemViewData>.unmodifiable(
        _receiveItems.take(compactPreviewLimit),
      );
  int get hiddenSendItemCount => _hiddenItemCount(_sendItems);
  int get hiddenReceiveItemCount => _hiddenItemCount(_receiveItems);
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
    _mode = TransferDirection.receive;
    _receiveEntryExpanded = true;
    _receiveStage = TransferStage.completed;
    _receiveSummary = sampleReceiveSummary.copyWith(
      statusMessage: 'Saved to Downloads',
    );
    _receiveItems = List<TransferItemViewData>.unmodifiable(sampleReceiveItems);
    notifyListeners();
  }

  void declineReceiveOffer() {
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
    _resetReceiveFlow();
    notifyListeners();
  }

  void goBack() {
    if (_mode == TransferDirection.receive) {
      switch (_receiveStage) {
        case TransferStage.review:
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

  int _hiddenItemCount(List<TransferItemViewData> items) {
    final hidden = items.length - compactPreviewLimit;
    return hidden > 0 ? hidden : 0;
  }

  void _resetReceiveFlow() {
    _receiveEntryExpanded = false;
    _receiveStage = TransferStage.idle;
    _receiveErrorText = null;
    _receiveItems = const [];
    _receiveSummary = null;
  }

  void _beginSend(SendTransferUpdate update) {
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = switch (update.phase) {
      SendTransferUpdatePhase.connecting => TransferStage.ready,
      SendTransferUpdatePhase.waitingForDecision => TransferStage.waiting,
      SendTransferUpdatePhase.sending => TransferStage.waiting,
      SendTransferUpdatePhase.completed => TransferStage.completed,
      SendTransferUpdatePhase.failed => TransferStage.error,
    };
    _sendDropActive = false;
    _sendDestinationLabel = update.destinationLabel;
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
    _nearbySendDestinations = _defaultSendDestinations;
    _sendItems = List<TransferItemViewData>.unmodifiable(items);
    _isInspectingSendItems = false;
    notifyListeners();
  }

  void _beginSendInspection({required bool clearExistingItems}) {
    _cancelActiveSendTransfer();
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.collecting;
    _sendDropActive = true;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
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
    _cancelActiveSendTransfer();
    _idleReceiverRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _ensureIdleReceiver() async {
    try {
      final registration = await _receiveRegistrationSource
          .ensureIdleReceiver();
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

  void _returnToSendSelection() {
    _cancelActiveSendTransfer();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.collecting;
    _sendDropActive = true;
    _isInspectingSendItems = false;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
    _nearbySendDestinations = _defaultSendDestinations;
    _sendSummary = null;
    _resetReceiveFlow();
  }

  void _startSendTransfer(String normalizedCode) {
    _cancelActiveSendTransfer();
    final generation = ++_sendTransferGeneration;
    debugPrint(
      '[drift/controller] starting send transfer '
      'generation=$generation code=$normalizedCode items=${_sendItems.length}',
    );
    final request = SendTransferRequestData(
      code: normalizedCode,
      paths: _sendItems.map((item) => item.path).toList(growable: false),
      deviceName: _deviceName,
    );

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
                    _sendDestinationLabel ??
                    _formatCodeAsDestination(normalizedCode),
                statusMessage: 'Request sent',
                itemCount: _sendItems.length,
                totalSize: sampleSendSummary.totalSize,
                errorMessage: error.toString(),
              ),
            );
            notifyListeners();
          },
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
  }

  static String _formatCodeAsDestination(String code) {
    final prefix = code.substring(0, 3);
    final suffix = code.substring(3);
    return 'Code $prefix $suffix';
  }

  static String _defaultDeviceName() {
    try {
      final hostname = Platform.localHostname.trim();
      if (hostname.isNotEmpty) {
        return hostname;
      }
    } catch (_) {
      // Fall back to a calm, user-friendly desktop label when hostname is unavailable.
    }
    return 'This Mac';
  }

  static String _normalizeDeviceName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'This Mac';
    }

    final firstSegment = trimmed.split('.').first.trim();
    return firstSegment.isEmpty ? 'This Mac' : firstSegment;
  }
}
