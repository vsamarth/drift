import 'package:app/features/send/application/state.dart';
import 'package:app/features/send/application/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('send state starts idle with no draft data', () {
    const state = SendState.idle();

    expect(state.phase, SendSessionPhase.idle);
    expect(state.items, isEmpty);
    expect(state.destination, isNull);
    expect(state.result, isNull);
    expect(state.errorMessage, isNull);
  });

  test('send state can represent a draft', () {
    final state = SendState.drafting(
      items: [
        SendDraftItem(
          path: '/tmp/report.pdf',
          name: 'report.pdf',
          kind: SendPickedFileKind.file,
          sizeBytes: BigInt.from(1024),
        ),
      ],
    );

    expect(state.phase, SendSessionPhase.drafting);
    expect(state.items, hasLength(1));
    expect(state.items.single.path, '/tmp/report.pdf');
    expect(state.destination, isNull);
    expect(state.result, isNull);
    expect(state.errorMessage, isNull);
  });
}
