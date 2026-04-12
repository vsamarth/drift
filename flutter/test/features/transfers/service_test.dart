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
    expect(state.offer, isNull);
  });

  test('transfers service tracks an incoming offer', () async {
    final source = FakeReceiverServiceSource();
    final container = ProviderContainer(
      overrides: [transfersServiceSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    expect(container.read(transfersServiceProvider).offer, isNull);

    source.emitIncomingOffer(senderName: 'Maya');
    await Future<void>.delayed(Duration.zero);

    final updated = container.read(transfersServiceProvider);
    expect(updated.phase, TransferSessionPhase.offerPending);
    expect(updated.offer?.displaySenderName, 'Maya');
    expect(updated.offer?.manifest.itemCount, 2);
    expect(updated.offer?.manifest.totalSizeBytes, BigInt.from(3072));
  });

  test('transfers service forwards offer decisions to the source', () async {
    final source = FakeReceiverServiceSource();
    final container = ProviderContainer(
      overrides: [transfersServiceSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(transfersServiceProvider).phase,
      TransferSessionPhase.idle,
    );
    source.emitIncomingOffer(senderName: 'Maya');
    await Future<void>.delayed(Duration.zero);

    await container.read(transfersServiceProvider.notifier).acceptOffer();
    expect(source.lastRespondToOfferAccept, isTrue);
    expect(
      container.read(transfersServiceProvider).phase,
      TransferSessionPhase.receiving,
    );
    expect(container.read(transfersServiceProvider).progress?.totalFiles, 2);

    await container.read(transfersServiceProvider.notifier).declineOffer();
    expect(source.lastRespondToOfferAccept, isFalse);
    expect(
      container.read(transfersServiceProvider).phase,
      TransferSessionPhase.idle,
    );
  });

  test(
    'acceptOffer rolls back to pending offer when backend respond fails',
    () async {
      final source = _FailingOfferResponseSource(throwOnAccept: true);
      final container = ProviderContainer(
        overrides: [transfersServiceSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      source.emitIncomingOffer(senderName: 'Maya');
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        container.read(transfersServiceProvider.notifier).acceptOffer(),
        throwsException,
      );

      final state = container.read(transfersServiceProvider);
      expect(state.phase, TransferSessionPhase.offerPending);
      expect(state.offer?.displaySenderName, 'Maya');
    },
  );

  test(
    'declineOffer restores pending offer when backend respond fails',
    () async {
      final source = _FailingOfferResponseSource(throwOnDecline: true);
      final container = ProviderContainer(
        overrides: [transfersServiceSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      source.emitIncomingOffer(senderName: 'Maya');
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        container.read(transfersServiceProvider.notifier).declineOffer(),
        throwsException,
      );

      final state = container.read(transfersServiceProvider);
      expect(state.phase, TransferSessionPhase.offerPending);
      expect(state.offer?.displaySenderName, 'Maya');
    },
  );
}

class _FailingOfferResponseSource extends FakeReceiverServiceSource {
  _FailingOfferResponseSource({
    this.throwOnAccept = false,
    this.throwOnDecline = false,
  });

  final bool throwOnAccept;
  final bool throwOnDecline;

  @override
  Future<void> respondToOffer({required bool accept}) async {
    await super.respondToOffer(accept: accept);
    if ((accept && throwOnAccept) || (!accept && throwOnDecline)) {
      throw Exception('respond failed');
    }
  }
}
