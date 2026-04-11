import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/send/application/controller.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/state.dart';
import 'package:app/features/send/presentation/send_transfer_route.dart';
import 'package:app/features/settings/settings_providers.dart';
import 'package:app/platform/send_transfer_source.dart';
import '../../../support/settings_test_overrides.dart';

class FakeSendTransferSource implements SendTransferSource {
  final StreamController<SendTransferUpdate> _updates =
      StreamController<SendTransferUpdate>.broadcast(sync: true);

  SendTransferRequestData? lastRequest;
  bool cancelCalled = false;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    lastRequest = request;
    return _updates.stream;
  }

  @override
  Future<void> cancelTransfer() async {
    cancelCalled = true;
  }

  Future<void> close() async {
    await _updates.close();
  }
}

Future<void> _pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

void main() {
  testWidgets('send transfer route renders request and enters transferring immediately', (
    WidgetTester tester,
  ) async {
    final fakeSource = FakeSendTransferSource();
    final container = ProviderContainer(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(testAppSettings),
        sendTransferSourceProvider.overrideWithValue(fakeSource),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(fakeSource.close);

    final controller = container.read(sendControllerProvider.notifier);
    controller.beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    controller.updateDestinationCode('ABC123');
    final request = controller.buildSendRequest()!;

    final router = GoRouter(
      initialLocation: '/send/transfer',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: 'send/transfer',
              builder: (context, state) =>
                  SendTransferRoutePage(request: request),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpRoute(tester);

    expect(container.read(sendControllerProvider).phase, SendSessionPhase.transferring);
    expect(fakeSource.lastRequest?.code, 'ABC123');

    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('/tmp/report.pdf'), findsOneWidget);
  });
}
