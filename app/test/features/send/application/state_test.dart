import 'package:app/features/send/application/state.dart';
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
}

