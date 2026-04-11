import 'package:flutter_test/flutter_test.dart';

import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/api/error_bridge.dart';

void main() {
  test('user facing error kinds include other', () {
    expect(UserFacingErrorKindData.values, contains(UserFacingErrorKindData.other));
  });

  test('bridge errors preserve the other kind', () {
    final error = tryParseUserFacingBridgeError(
      '{"kind":"Other","title":"Transfer failed","message":"Something happened","retryable":false}',
    );

    expect(error, isNotNull);
    expect(error!.error.kind, UserFacingErrorKindData.other);
  });
}
