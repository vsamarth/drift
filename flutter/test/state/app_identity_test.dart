import 'package:drift_app/state/app_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default download root ends with Downloads/Drift', () {
    expect(defaultReceiveDownloadRoot(), endsWith('Downloads/Drift'));
  });
}
