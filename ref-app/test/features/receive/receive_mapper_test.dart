import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/receive/receive_mapper.dart';
import 'package:drift_app/shared/formatting/byte_format.dart';
import 'package:drift_app/src/rust/api/receiver.dart' as rust_receiver;
import 'package:drift_app/src/rust/api/transfer.dart' as rust_transfer;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('incomingFileToViewData derives the file name and formatted size', () {
    final file = rust_receiver.ReceiverTransferFile(
      path: '/Users/sam/Downloads/report.pdf',
      size: BigInt.from(2048),
    );

    final viewData = incomingFileToViewData(file);

    expect(viewData.name, 'report.pdf');
    expect(viewData.path, '/Users/sam/Downloads/report.pdf');
    expect(viewData.size, formatBytes(2048));
    expect(viewData.sizeBytes, 2048);
    expect(viewData.kind, TransferItemKind.file);
  });

  test('progressFromSnapshot maps bytes and transfer labels', () {
    final snapshot = rust_transfer.TransferSnapshotData(
      sessionId: 'session-1',
      phase: rust_transfer.TransferPhaseData.transferring,
      totalFiles: 2,
      completedFiles: 1,
      totalBytes: BigInt.from(4096),
      bytesTransferred: BigInt.from(2048),
      bytesPerSec: BigInt.from(2048),
      etaSeconds: BigInt.from(45),
    );

    final progress = progressFromSnapshot(snapshot);

    expect(progress.bytesTransferred, 2048);
    expect(progress.totalBytes, 4096);
    expect(progress.speedLabel, '2.0 KB/s');
    expect(progress.etaLabel, '45 s');
  });

  test('buildReceiveCompletionMetrics keeps the summary rows in order', () {
    final summary = TransferSummaryViewData(
      itemCount: 3,
      totalSize: '12 MB',
      code: 'ABC123',
      expiresAt: '',
      destinationLabel: 'Downloads/Drift',
      statusMessage: 'Saved',
      senderName: 'Sam',
    );

    final rows = buildReceiveCompletionMetrics(
      summary: summary,
      bytesReceived: 12 * 1024 * 1024,
      startedAt: null,
    );

    expect(rows?.map((row) => row.label).toList(), [
      'From',
      'Saved to',
      'Files',
      'Size',
    ]);
    expect(rows?[0].value, 'Sam');
    expect(rows?[1].value, 'Downloads/Drift');
    expect(rows?[2].value, '3');
    expect(rows?[3].value, '12 MB');
  });
}
