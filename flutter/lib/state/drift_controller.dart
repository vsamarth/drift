import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import 'drift_sample_data.dart';

class DriftController extends ChangeNotifier {
  DriftController();

  static const int compactPreviewLimit = 3;

  TransferDirection _mode = TransferDirection.send;
  TransferStage _sendStage = TransferStage.idle;
  TransferStage _receiveStage = TransferStage.idle;
  bool _sendDropActive = false;
  bool _receiveEntryExpanded = false;
  String _receiveCode = '';
  String? _receiveErrorText;
  List<TransferItemViewData> _sendItems = const [];
  List<TransferItemViewData> _receiveItems = const [];
  TransferSummaryViewData? _sendSummary;
  TransferSummaryViewData? _receiveSummary;

  TransferDirection get mode => _mode;
  TransferStage get sendStage => _sendStage;
  TransferStage get receiveStage => _receiveStage;
  bool get sendDropActive => _sendDropActive;
  bool get receiveEntryExpanded => _receiveEntryExpanded;
  String get receiveCode => _receiveCode;
  String? get receiveErrorText => _receiveErrorText;
  List<TransferItemViewData> get sendItems => _sendItems;
  List<TransferItemViewData> get receiveItems => _receiveItems;
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
    _sendItems = const [
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
    ];
    notifyListeners();
  }

  void clearSendFlow() {
    _mode = TransferDirection.send;
    _sendStage = TransferStage.idle;
    _sendDropActive = false;
    _sendItems = const [];
    _sendSummary = null;
    notifyListeners();
  }

  void generateOffer() {
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.ready;
    _sendDropActive = false;
    _sendItems = List<TransferItemViewData>.unmodifiable(sampleSendItems);
    _sendSummary = sampleSendSummary;
    notifyListeners();
  }

  void markSendWaiting() {
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.waiting;
    _sendSummary = (_sendSummary ?? sampleSendSummary).copyWith(
      statusMessage: 'Waiting for the other device',
    );
    _sendItems = List<TransferItemViewData>.unmodifiable(sampleSendItems);
    notifyListeners();
  }

  void completeSendDemo() {
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.completed;
    _sendSummary = sampleSendSummary.copyWith(
      statusMessage: 'Your files were sent',
    );
    _sendItems = List<TransferItemViewData>.unmodifiable(sampleSendItems);
    notifyListeners();
  }

  void failSendDemo() {
    _resetReceiveFlow();
    _mode = TransferDirection.send;
    _sendStage = TransferStage.error;
    _sendSummary = sampleSendSummary.copyWith(
      statusMessage: 'This transfer did not finish. Try again.',
    );
    _sendItems = List<TransferItemViewData>.unmodifiable(sampleSendItems);
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
    _receiveItems = List<TransferItemViewData>.unmodifiable(
      sampleReceiveItems,
    );
    notifyListeners();
  }

  void acceptReceiveOffer() {
    _mode = TransferDirection.receive;
    _receiveEntryExpanded = true;
    _receiveStage = TransferStage.completed;
    _receiveSummary = sampleReceiveSummary.copyWith(
      statusMessage: 'Saved to Downloads',
    );
    _receiveItems = List<TransferItemViewData>.unmodifiable(
      sampleReceiveItems,
    );
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
    _sendItems = const [];
    _sendSummary = null;
    _resetReceiveFlow();
    notifyListeners();
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
}
