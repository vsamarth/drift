import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/send/application/controller.dart';
import 'package:app/features/send/application/state.dart';

void main() {
  test('send controller starts idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(sendControllerProvider);

    expect(state.phase, SendSessionPhase.idle);
  });
}

