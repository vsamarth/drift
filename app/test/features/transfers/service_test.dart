import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/transfers/feature.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';

void main() {
  test('transfers service starts idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(transfersServiceProvider);

    expect(state.phase, TransferSessionPhase.idle);
    expect(state.incomingOffer, isNull);
  });

  test('transfers service tracks an incoming offer', () async {
    final source = FakeReceiverServiceSource();
    final container = ProviderContainer(
      overrides: [
        transfersServiceSourceProvider.overrideWithValue(source),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(transfersServiceProvider).incomingOffer, isNull);

    source.emitIncomingOffer(senderName: 'Maya');
    await Future<void>.delayed(Duration.zero);

    final updated = container.read(transfersServiceProvider);
    expect(updated.phase, TransferSessionPhase.offerPending);
    expect(updated.incomingOffer?.displaySenderName, 'Maya');
  });

  test('transfers service forwards offer decisions to the source', () async {
    final source = FakeReceiverServiceSource();
    final container = ProviderContainer(
      overrides: [
        transfersServiceSourceProvider.overrideWithValue(source),
      ],
    );
    addTearDown(container.dispose);

    await container.read(transfersServiceProvider.notifier).acceptOffer();
    expect(source.lastRespondToOfferAccept, isTrue);
    expect(container.read(transfersServiceProvider).phase, TransferSessionPhase.receiving);

    await container.read(transfersServiceProvider.notifier).declineOffer();
    expect(source.lastRespondToOfferAccept, isFalse);
    expect(container.read(transfersServiceProvider).phase, TransferSessionPhase.idle);
  });
}
