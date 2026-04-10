import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/feature.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';

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
}
