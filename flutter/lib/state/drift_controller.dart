import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import 'drift_sample_data.dart';

class DriftController extends ChangeNotifier {
  DriftController({
    String? deviceName,
    String idleReceiveCode = 'F9P2Q1',
    String idleReceiveStatus = 'Ready',
    List<SendDestinationViewData>? nearbySendDestinations,
    List<TransferItemViewData>? droppedSendItems,
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
         nearbySendDestinations ?? sampleSendDestinations,
       );

  static const int compactPreviewLimit = 3;

  final String _deviceName;
  final String _idleReceiveCode;
  final String _idleReceiveStatus;
  final List<TransferItemViewData> _defaultDroppedSendItems;
  final List<SendDestinationViewData> _defaultSendDestinations;
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

  String get deviceName => _deviceName;
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
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.collecting;
    _sendDropActive = true;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
    _nearbySendDestinations = _defaultSendDestinations;
    _sendItems = _defaultDroppedSendItems;
    notifyListeners();
  }

  void clearSendFlow() {
    _mode = TransferDirection.send;
    _sendStage = TransferStage.idle;
    _sendDropActive = false;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
    _nearbySendDestinations = const [];
    _sendItems = const [];
    _sendSummary = null;
    notifyListeners();
  }

  void selectNearbyDestination(SendDestinationViewData destination) {
    _sendDestinationCode = '';
    _beginSend(destination.name, statusMessage: 'Connecting');
    notifyListeners();
  }

  void updateSendDestinationCode(String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (normalized == _sendDestinationCode) {
      return;
    }
    _sendDestinationCode = normalized;
    notifyListeners();
    if (_sendDestinationCode.length == 6) {
      _beginSend(_formatCodeAsDestination(_sendDestinationCode));
      notifyListeners();
    }
  }

  void generateOffer() {
    _beginSend(_sendDestinationLabel ?? sampleSendSummary.destinationLabel);
    notifyListeners();
  }

  void markSendWaiting() {
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.waiting;
    _sendSummary = (_sendSummary ?? sampleSendSummary).copyWith(
      destinationLabel:
          _sendDestinationLabel ?? sampleSendSummary.destinationLabel,
      statusMessage: 'Waiting for the other device',
    );
    notifyListeners();
  }

  void completeSendDemo() {
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.completed;
    _sendSummary = sampleSendSummary.copyWith(
      statusMessage: 'Your files were sent',
      destinationLabel:
          _sendDestinationLabel ?? sampleSendSummary.destinationLabel,
    );
    notifyListeners();
  }

  void failSendDemo() {
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.error;
    _sendSummary = sampleSendSummary.copyWith(
      statusMessage: 'This transfer did not finish. Try again.',
      destinationLabel:
          _sendDestinationLabel ?? sampleSendSummary.destinationLabel,
    );
    notifyListeners();
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

  void resetShell() {
    _mode = TransferDirection.send;
    _sendStage = TransferStage.idle;
    _sendDropActive = false;
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

  void _beginSend(
    String destinationLabel, {
    String statusMessage = 'Connecting',
  }) {
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.ready;
    _sendDropActive = false;
    _sendDestinationLabel = destinationLabel;
    _nearbySendDestinations = _defaultSendDestinations;
    _sendItems = List<TransferItemViewData>.unmodifiable(
      _sendItems.isEmpty ? sampleSendItems : _sendItems,
    );
    _sendSummary = sampleSendSummary.copyWith(
      itemCount: _sendItems.length,
      destinationLabel: destinationLabel,
      statusMessage: statusMessage,
    );
  }

  void _returnToSendSelection() {
    _mode = TransferDirection.send;
    _sendStage = TransferStage.collecting;
    _sendDropActive = true;
    _sendDestinationCode = '';
    _sendDestinationLabel = null;
    _nearbySendDestinations = _defaultSendDestinations;
    _sendSummary = null;
    _resetReceiveFlow();
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
