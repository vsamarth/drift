import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/receive/application/state.dart';
import 'package:app/features/send/application/controller.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/state.dart';
import 'package:app/features/settings/settings_providers.dart';
import '../../../support/settings_test_overrides.dart';

void main() {
  test('send controller starts idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(sendControllerProvider);

    expect(state.phase, SendSessionPhase.idle);
    expect(state.destination.mode, SendDestinationMode.none);
    expect(state.request, isNull);
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
    expect(drafting.destination.mode, SendDestinationMode.none);

    controller.clearDraft();

    final idle = container.read(sendControllerProvider);
    expect(idle.phase, SendSessionPhase.idle);
    expect(idle.items, isEmpty);
    expect(idle.destination.mode, SendDestinationMode.none);
  });

  test('send controller buildSendRequest returns null when destination is missing', () {
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);

    expect(controller.buildSendRequest(), isNull);
    expect(controller.canStartSend, isFalse);
  });

  test('send controller builds a code request for a valid 6-character code', () {
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    controller.updateDestinationCode('ABC123');

    final request = controller.buildSendRequest();
    expect(request, isNotNull);
    expect(controller.canStartSend, isTrue);
    expect(request?.destinationMode, SendDestinationMode.code);
    expect(request?.code, 'ABC123');
    expect(request?.ticket, isNull);
    expect(request?.lanDestinationLabel, isNull);
    expect(request?.paths, ['/tmp/report.pdf']);
    expect(request?.deviceName, 'Drift');
    expect(request?.serverUrl, isNull);
  });

  test('send controller buildSendRequest returns null for an invalid code', () {
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    controller.updateDestinationCode('ABC');

    expect(controller.buildSendRequest(), isNull);
    expect(controller.canStartSend, isFalse);
  });

  test('send controller builds a nearby request from the selected receiver', () {
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    controller.selectNearbyReceiver(
      const NearbyReceiver(
        fullname: 'samarth-laptop',
        label: 'Laptop',
        code: 'ABC123',
        ticket: 'ticket-1',
      ),
    );

    final state = container.read(sendControllerProvider);
    expect(state.destination.mode, SendDestinationMode.nearby);
    expect(state.destination.code, isNull);

    final request = controller.buildSendRequest();
    expect(request, isNotNull);
    expect(controller.canStartSend, isTrue);
    expect(request?.destinationMode, SendDestinationMode.nearby);
    expect(request?.ticket, 'ticket-1');
    expect(request?.lanDestinationLabel, 'Laptop');
    expect(request?.code, isNull);
    expect(request?.paths, ['/tmp/report.pdf']);
  });
}
