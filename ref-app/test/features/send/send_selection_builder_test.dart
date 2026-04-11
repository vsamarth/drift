import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_selection_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a pending folder item from a trailing slash path', () {
    const builder = SendSelectionBuilder();

    final item = builder.pendingItemForPath('photos/');

    expect(item.name, 'photos');
    expect(item.path, 'photos/');
    expect(item.size, 'Adding...');
    expect(item.kind, TransferItemKind.folder);
  });
}
