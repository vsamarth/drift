import 'package:flutter/foundation.dart';

import 'models.dart';

class DriftController extends ChangeNotifier {
  DriftController();

  TransferDirection _mode = TransferDirection.send;
  TransferStage _sendStage = TransferStage.idle;
  TransferStage _receiveStage = TransferStage.idle;
  bool _sendDropActive = false;
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
  String get receiveCode => _receiveCode;
  String? get receiveErrorText => _receiveErrorText;
  List<TransferItemViewData> get sendItems => _sendItems;
  List<TransferItemViewData> get receiveItems => _receiveItems;
  TransferSummaryViewData? get sendSummary => _sendSummary;
  TransferSummaryViewData? get receiveSummary => _receiveSummary;

  void setMode(TransferDirection mode) {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
  }

  void activateSendDropTarget() {
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
    _sendStage = TransferStage.idle;
    _sendDropActive = false;
    _sendItems = const [];
    _sendSummary = null;
    notifyListeners();
  }

  void generateOffer() {
    _mode = TransferDirection.send;
    _sendStage = TransferStage.ready;
    _sendDropActive = false;
    _sendItems = List<TransferItemViewData>.unmodifiable(_sampleSendItems);
    _sendSummary = _sampleSendSummary;
    notifyListeners();
  }

  void markSendWaiting() {
    _mode = TransferDirection.send;
    _sendStage = TransferStage.waiting;
    _sendSummary ??= _sampleSendSummary;
    _sendItems = List<TransferItemViewData>.unmodifiable(_sampleSendItems);
    notifyListeners();
  }

  void completeSendDemo() {
    _mode = TransferDirection.send;
    _sendStage = TransferStage.completed;
    _sendSummary = _sampleSendSummary.copyWith(
      statusMessage: 'Transfer complete. Files were delivered directly.',
    );
    _sendItems = List<TransferItemViewData>.unmodifiable(_sampleSendItems);
    notifyListeners();
  }

  void failSendDemo() {
    _mode = TransferDirection.send;
    _sendStage = TransferStage.error;
    _sendSummary = _sampleSendSummary.copyWith(
      statusMessage: 'Receiver declined the offer before connecting.',
    );
    _sendItems = List<TransferItemViewData>.unmodifiable(_sampleSendItems);
    notifyListeners();
  }

  void updateReceiveCode(String value) {
    _receiveCode = value.toUpperCase();
    _receiveErrorText = null;
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
      _receiveErrorText = 'Enter a six-character code to preview the offer.';
      notifyListeners();
      return;
    }

    _receiveStage = TransferStage.review;
    _receiveErrorText = null;
    _receiveSummary = _sampleReceiveSummary;
    _receiveItems = List<TransferItemViewData>.unmodifiable(
      _sampleReceiveItems,
    );
    notifyListeners();
  }

  void acceptReceiveOffer() {
    _mode = TransferDirection.receive;
    _receiveStage = TransferStage.completed;
    _receiveSummary = _sampleReceiveSummary.copyWith(
      statusMessage: 'Accepted. Files will be saved to ~/Downloads/Drift.',
    );
    _receiveItems = List<TransferItemViewData>.unmodifiable(
      _sampleReceiveItems,
    );
    notifyListeners();
  }

  void declineReceiveOffer() {
    _mode = TransferDirection.receive;
    _receiveStage = TransferStage.idle;
    _receiveItems = const [];
    _receiveSummary = null;
    _receiveErrorText = null;
    notifyListeners();
  }

  void loadReceiveError() {
    _mode = TransferDirection.receive;
    _receiveCode = 'F9P2Q1';
    _receiveStage = TransferStage.error;
    _receiveSummary = null;
    _receiveItems = const [];
    _receiveErrorText =
        'That code has expired. Ask the sender to create a new one.';
    notifyListeners();
  }
}

const List<TransferItemViewData> _sampleSendItems = [
  TransferItemViewData(
    name: 'sample.txt',
    path: 'sample.txt',
    size: '18 KB',
    kind: TransferItemKind.file,
  ),
  TransferItemViewData(
    name: 'photos',
    path: 'photos/',
    size: '8 items',
    kind: TransferItemKind.folder,
  ),
  TransferItemViewData(
    name: 'pitch-deck.pdf',
    path: 'docs/pitch-deck.pdf',
    size: '2.4 MB',
    kind: TransferItemKind.file,
  ),
];

const TransferSummaryViewData _sampleSendSummary = TransferSummaryViewData(
  itemCount: 3,
  totalSize: '14.6 MB',
  code: 'AB2CD3',
  expiresAt: 'Expires in 14 minutes',
  destinationLabel: 'Direct peer transfer over iroh',
  statusMessage: 'Offer ready. Share the short code with your receiver.',
);

const List<TransferItemViewData> _sampleReceiveItems = [
  TransferItemViewData(
    name: 'sample.txt',
    path: 'sample.txt',
    size: '18 KB',
    kind: TransferItemKind.file,
  ),
  TransferItemViewData(
    name: 'vacation.jpg',
    path: 'photos/vacation.jpg',
    size: '4.3 MB',
    kind: TransferItemKind.file,
  ),
  TransferItemViewData(
    name: 'beach.mov',
    path: 'photos/beach.mov',
    size: '10.2 MB',
    kind: TransferItemKind.file,
  ),
];

const TransferSummaryViewData _sampleReceiveSummary = TransferSummaryViewData(
  itemCount: 3,
  totalSize: '14.6 MB',
  code: 'AB2CD3',
  expiresAt: 'Expires in 14 minutes',
  destinationLabel: '~/Downloads/Drift',
  statusMessage: 'Incoming offer ready to review.',
);
