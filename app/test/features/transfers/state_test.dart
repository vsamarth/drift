import 'package:app/features/transfers/feature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transfer identity trims its display name', () {
    const identity = TransferIdentity(
      role: TransferRole.sender,
      endpointId: 'endpoint-1',
      deviceName: ' Maya ',
      deviceType: DeviceType.laptop,
    );

    expect(identity.displayName, 'Maya');
    expect(identity.endpointId, 'endpoint-1');
    expect(identity.role, TransferRole.sender);
    expect(identity.deviceType, DeviceType.laptop);
  });

  test('transfer manifest counts items and total bytes', () {
    final manifest = TransferManifest(
      items: [
        TransferManifestItem(path: 'report.pdf', sizeBytes: BigInt.from(1024)),
        TransferManifestItem(path: 'photo.jpg', sizeBytes: BigInt.from(2048)),
      ],
    );

    expect(manifest.itemCount, 2);
    expect(manifest.totalSizeBytes, BigInt.from(3072));
  });
}
