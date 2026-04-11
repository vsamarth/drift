import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/send/application/controller.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/state.dart';

void main() {
  test('send controller starts idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(sendControllerProvider);

    expect(state.phase, SendSessionPhase.idle);
  });

  test('send controller can begin and clear a draft', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);

    final drafting = container.read(sendControllerProvider);
    expect(drafting.phase, SendSessionPhase.drafting);
    expect(drafting.items, hasLength(1));

    controller.clearDraft();

    final idle = container.read(sendControllerProvider);
    expect(idle.phase, SendSessionPhase.idle);
    expect(idle.items, isEmpty);
  });
}
