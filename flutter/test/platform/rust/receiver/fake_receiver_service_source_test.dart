import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/feature.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import 'package:app/src/rust/api/receiver.dart' as rust_receiver;

void main() {
  test('fake receiver source exposes its current state first', () async {
    final source = FakeReceiverServiceSource();
    final iterator = StreamIterator(source.watchState());
    addTearDown(iterator.cancel);

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.pairingCode.code, 'ABC123');
    expect(iterator.current.snapshot.lifecycle, ReceiverLifecycle.ready);
  });

  test('fake receiver source emits updates', () async {
    final source = FakeReceiverServiceSource(
      initialState: const ReceiverServiceState.registering(),
    );
    final iterator = StreamIterator(source.watchState());
    addTearDown(iterator.cancel);

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.snapshot.lifecycle, ReceiverLifecycle.starting);

    source.emit(const ReceiverServiceState.unavailable());

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.pairingCode.isAvailable, isFalse);
  });

  test('fake receiver source emits incoming offers', () async {
    final source = FakeReceiverServiceSource();
    final iterator = StreamIterator(source.watchIncomingTransfers());
    addTearDown(iterator.cancel);

    await Future<void>.delayed(Duration.zero);
    final next = iterator.moveNext();
    source.emitIncomingOffer(senderName: 'Maya');

    expect(await next, isTrue);
    expect(
      iterator.current.phase,
      rust_receiver.ReceiverTransferPhase.offerReady,
    );
    expect(iterator.current.senderName, 'Maya');
    expect(iterator.current.files, hasLength(2));
  });
}
