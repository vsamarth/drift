import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/transfers/application/identity.dart';
import 'package:app/features/transfers/application/manifest.dart';
import 'package:app/features/transfers/application/result_view_data.dart';
import 'package:app/features/transfers/application/state.dart';

void main() {
  TransferIncomingOffer makeOffer({
    String senderName = 'Maya',
    String destinationLabel = 'Downloads',
    String saveRootLabel = 'Downloads',
    String statusMessage = 'Transfer complete',
  }) {
    return TransferIncomingOffer(
      sender: TransferIdentity(
        role: TransferRole.sender,
        endpointId: 'endpoint-1',
        deviceName: senderName,
        deviceType: DeviceType.laptop,
      ),
      manifest: TransferManifest(
        items: [
          TransferManifestItem(
            path: 'report.pdf',
            sizeBytes: BigInt.from(1024),
          ),
          TransferManifestItem(path: 'photo.jpg', sizeBytes: BigInt.from(2048)),
        ],
      ),
      destinationLabel: destinationLabel,
      saveRootLabel: saveRootLabel,
      statusMessage: statusMessage,
      bytesReceived: BigInt.zero,
    );
  }

  test('builds completed transfer result data', () {
    final state = TransferSessionState.completed(
      offer: makeOffer(statusMessage: 'Files saved successfully.'),
      result: TransferTransferResult(
        bytesTransferred: BigInt.from(3072),
        totalBytes: BigInt.from(3072),
        completedFiles: 2,
        totalFiles: 2,
      ),
    );

    final viewData = buildTransferResultViewData(state);

    expect(viewData.outcome, TransferResultOutcome.success);
    expect(viewData.title, 'Files saved');
    expect(viewData.message, 'Saved to Downloads');
    expect(viewData.primaryLabel, 'Done');
    expect(viewData.metrics, isNotNull);
    expect(viewData.metrics, hasLength(4));
    expect(viewData.metrics!.first.label, 'From');
    expect(viewData.metrics![2].value, '2');
  });

  test('builds cancelled transfer result data', () {
    final state = TransferSessionState.cancelled(
      offer: makeOffer(),
      errorMessage: 'Cancelled by sender.',
    );

    final viewData = buildTransferResultViewData(state);

    expect(viewData.outcome, TransferResultOutcome.cancelled);
    expect(viewData.title, 'Receive cancelled');
    expect(viewData.message, 'Cancelled by sender.');
    expect(viewData.metrics, isNull);
    expect(viewData.primaryLabel, 'Done');
  });

  test('builds failed transfer result data', () {
    final state = TransferSessionState.failed(
      offer: makeOffer(),
      errorMessage: 'Network lost.',
    );

    final viewData = buildTransferResultViewData(state);

    expect(viewData.outcome, TransferResultOutcome.failed);
    expect(viewData.title, 'Couldn\'t finish receiving files');
    expect(viewData.message, 'Network lost.');
    expect(viewData.metrics, isNull);
    expect(viewData.primaryLabel, 'Done');
  });
}
