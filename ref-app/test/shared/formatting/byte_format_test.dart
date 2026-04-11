import 'package:drift_app/shared/formatting/byte_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats bytes with the expected unit scale', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
