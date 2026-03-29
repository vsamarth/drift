import '../core/models/transfer_models.dart';

const List<TransferItemViewData> sampleSendItems = [
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
  TransferItemViewData(
    name: 'notes.md',
    path: 'notes.md',
    size: '22 KB',
    kind: TransferItemKind.file,
  ),
];

const TransferSummaryViewData sampleSendSummary = TransferSummaryViewData(
  itemCount: 4,
  totalSize: '14.7 MB',
  code: 'AB2CD3',
  expiresAt: 'Ready to transfer',
  destinationLabel: 'Maya’s iPhone',
  statusMessage: 'Connecting',
);

const List<TransferItemViewData> sampleReceiveItems = [
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
  TransferItemViewData(
    name: 'boarding-pass.pdf',
    path: 'docs/boarding-pass.pdf',
    size: '340 KB',
    kind: TransferItemKind.file,
  ),
];

const TransferSummaryViewData sampleReceiveSummary = TransferSummaryViewData(
  itemCount: 4,
  totalSize: '14.9 MB',
  code: 'AB2CD3',
  expiresAt: 'Code confirmed',
  destinationLabel: 'Downloads',
  statusMessage: 'Save these files to Downloads',
);
