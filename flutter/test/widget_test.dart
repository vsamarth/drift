import 'dart:async';
import 'dart:ui';

import 'package:drift_app/app/drift_app.dart';
import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/platform/send_item_source.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:drift_app/state/nearby_discovery_source.dart';
import 'package:drift_app/state/receiver_service_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift_app/src/rust/api/receiver.dart' as rust_receiver;

Future<void> pumpUtilityApp(
  WidgetTester tester, {
  Size size = const Size(440, 560),
  ProviderContainer? container,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final resolvedContainer = container ?? buildTestContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: resolvedContainer,
      child: const DriftApp(),
    ),
  );
  await tester.pumpAndSettle();
  expectNoFlutterError(tester);
}

void expectNoFlutterError(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

/// [WidgetTester.pumpAndSettle] never finishes while a [TextField] caret is
/// blinking; use this after receive/send code interactions instead.
Future<void> pumpUiSettled(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder receiveCodeFieldFinder() =>
    find.byKey(const ValueKey<String>('receive-code-field'));

Finder receiveCodeFieldPrimary() => receiveCodeFieldFinder().at(0);

Finder receiveButton() =>
    find.byKey(const ValueKey<String>('receive-submit')).last;
Finder chooseFilesButton() => find.text('Select files');
Finder saveToDownloadsButton() => find.text('Save to Downloads');
Finder idleDropSurface() =>
    find.byKey(const ValueKey<String>('send-drop-surface'));
Finder idleIdentityZone() =>
    find.byKey(const ValueKey<String>('idle-identity-zone'));
Finder idleReceiveCodePill() =>
    find.byKey(const ValueKey<String>('idle-receive-code'));
Finder sendCodeField() => find.byKey(const ValueKey<String>('send-code-field'));
Finder shellBackButton() =>
    find.byKey(const ValueKey<String>('shell-back-button'));

typedef NearbySendScan = Future<List<SendDestinationViewData>> Function();

ProviderContainer buildTestContainer({
  List<SendDestinationViewData>? nearbySendDestinations,
  NearbySendScan? nearbySendScan,
  List<TransferItemViewData>? droppedSendItems,
  SendItemSource? sendItemSource,
  SendTransferSource? sendTransferSource,
  NearbyDiscoverySource? nearbyDiscoverySource,
  ReceiverServiceSource? receiverServiceSource,
  bool enableIdleIncomingListener = false,
}) {
  final resolvedSendItemSource =
      sendItemSource ??
      FakeSendItemSource(
        pickedItems:
            droppedSendItems ??
            const [
              TransferItemViewData(
                name: 'sample.txt',
                path: 'sample.txt',
                size: '18 KB',
                kind: TransferItemKind.file,
                sizeBytes: 18 * 1024,
              ),
              TransferItemViewData(
                name: 'photos',
                path: 'photos/',
                size: '12 files • 240 KB',
                kind: TransferItemKind.folder,
                sizeBytes: 240 * 1024,
              ),
            ],
      );
  final resolvedSendTransferSource =
      sendTransferSource ?? FakeSendTransferSource();
  final resolvedNearbyDiscoverySource =
      nearbyDiscoverySource ??
      FakeNearbyDiscoverySource(
        destinations: nearbySendDestinations ?? const [],
        scanHandler: nearbySendScan,
      );
  final resolvedReceiverServiceSource =
      receiverServiceSource ?? FakeReceiverServiceSource();

  final container = ProviderContainer(
    overrides: [
      driftAppIdentityProvider.overrideWith(
        (ref) => const DriftAppIdentity(
          deviceName: 'Samarth MacBook Pro',
          deviceType: 'laptop',
          downloadRoot: '/tmp/Downloads',
        ),
      ),
      sendItemSourceProvider.overrideWith((ref) => resolvedSendItemSource),
      sendTransferSourceProvider.overrideWith(
        (ref) => resolvedSendTransferSource,
      ),
      nearbyDiscoverySourceProvider.overrideWith(
        (ref) => resolvedNearbyDiscoverySource,
      ),
      receiverServiceSourceProvider.overrideWith(
        (ref) => resolvedReceiverServiceSource,
      ),
      animateSendingConnectionProvider.overrideWith((ref) => false),
      enableIdleIncomingListenerProvider.overrideWith(
        (ref) => enableIdleIncomingListener,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class FakeSendItemSource implements SendItemSource {
  FakeSendItemSource({
    required List<TransferItemViewData> pickedItems,
    List<List<String>>? pickResponses,
    Map<String, TransferItemViewData>? itemCatalog,
  }) : _pickResponses =
           pickResponses ??
           [pickedItems.map((item) => item.path).toList(growable: false)],
       _itemCatalog = {
         for (final item in pickedItems) item.path: item,
         ...?itemCatalog,
       };

  final List<List<String>> _pickResponses;
  final Map<String, TransferItemViewData> _itemCatalog;
  int _pickIndex = 0;

  @override
  Future<List<TransferItemViewData>> pickFiles() async =>
      _mapPaths(_nextPickResponse());

  @override
  Future<List<String>> pickAdditionalPaths() async => _nextPickResponse();

  @override
  Future<List<TransferItemViewData>> pickAdditionalFiles({
    required List<String> existingPaths,
  }) async {
    return appendPaths(
      existingPaths: existingPaths,
      incomingPaths: _nextPickResponse(),
    );
  }

  @override
  Future<List<TransferItemViewData>> loadPaths(List<String> paths) async =>
      _mapPaths(paths);

  @override
  Future<List<TransferItemViewData>> appendPaths({
    required List<String> existingPaths,
    required List<String> incomingPaths,
  }) async {
    final merged = <String>[];
    final seen = <String>{};
    for (final path in [...existingPaths, ...incomingPaths]) {
      if (seen.add(path)) {
        merged.add(path);
      }
    }
    return _mapPaths(merged);
  }

  @override
  Future<List<TransferItemViewData>> removePath({
    required List<String> existingPaths,
    required String removedPath,
  }) async {
    return _mapPaths(
      existingPaths
          .where((path) => path != removedPath)
          .toList(growable: false),
    );
  }

  List<String> _nextPickResponse() {
    final index = _pickIndex < _pickResponses.length
        ? _pickIndex
        : _pickResponses.length - 1;
    _pickIndex += 1;
    return _pickResponses[index];
  }

  List<TransferItemViewData> _mapPaths(List<String> paths) {
    final seen = <String>{};
    return List<TransferItemViewData>.unmodifiable(
      paths.where(seen.add).map((path) => _itemCatalog[path]!).toList(),
    );
  }
}

class FakeNearbyDiscoverySource implements NearbyDiscoverySource {
  FakeNearbyDiscoverySource({this.destinations = const [], this.scanHandler});

  final List<SendDestinationViewData> destinations;
  final NearbySendScan? scanHandler;

  @override
  Future<List<SendDestinationViewData>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final next = await (scanHandler?.call() ?? Future.value(destinations));
    return List<SendDestinationViewData>.unmodifiable(next);
  }
}

class FakeSendTransferSource implements SendTransferSource {
  SendTransferRequestData? lastRequest;
  StreamController<SendTransferUpdate>? _controller;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    lastRequest = request;
    unawaited(_controller?.close());
    _controller = StreamController<SendTransferUpdate>.broadcast();
    return _controller!.stream;
  }

  void emit(SendTransferUpdate update) {
    _controller?.add(update);
  }

  Future<void> finish() async {
    await _controller?.close();
  }
}

class FakeReceiverServiceSource implements ReceiverServiceSource {
  FakeReceiverServiceSource({
    this.initialBadge = const ReceiverBadgeState(
      code: 'F9P2Q1',
      status: 'Ready',
    ),
  });

  final ReceiverBadgeState initialBadge;
  final StreamController<ReceiverBadgeState> _badgeController =
      StreamController<ReceiverBadgeState>.broadcast();
  final StreamController<rust_receiver.ReceiverTransferEvent>
  _incomingController =
      StreamController<rust_receiver.ReceiverTransferEvent>.broadcast();
  final List<bool> discoverableCalls = <bool>[];
  final List<bool> respondToOfferCalls = <bool>[];

  void emitBadge(ReceiverBadgeState badge) {
    _badgeController.add(badge);
  }

  void emitIncoming(rust_receiver.ReceiverTransferEvent event) {
    _incomingController.add(event);
  }

  Future<void> dispose() async {
    await _badgeController.close();
    await _incomingController.close();
  }

  @override
  Future<void> respondToOffer({required bool accept}) async {
    respondToOfferCalls.add(accept);
  }

  @override
  Future<void> setDiscoverable({required bool enabled}) async {
    discoverableCalls.add(enabled);
  }

  @override
  Stream<ReceiverBadgeState> watchBadge(DriftAppIdentity identity) async* {
    yield initialBadge;
    yield* _badgeController.stream;
  }

  @override
  Stream<rust_receiver.ReceiverTransferEvent> watchIncomingTransfers(
    DriftAppIdentity identity,
  ) {
    return _incomingController.stream;
  }
}

SendTransferUpdate sendTransferUpdate({
  required SendTransferUpdatePhase phase,
  required String destinationLabel,
  required String statusMessage,
  String? errorMessage,
  int itemCount = 2,
  String totalSize = '18 KB',
  int bytesSent = 0,
  int totalBytes = 0,
}) {
  return SendTransferUpdate(
    phase: phase,
    destinationLabel: destinationLabel,
    statusMessage: statusMessage,
    itemCount: itemCount,
    totalSize: totalSize,
    bytesSent: bytesSent,
    totalBytes: totalBytes,
    errorMessage: errorMessage,
  );
}

Future<String?> recordClipboardWrites(Future<void> Function() action) async {
  String? clipboardText;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboardText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return clipboardText == null
                ? null
                : <String, Object?>{'text': clipboardText};
        }
        return null;
      });

  try {
    await action();
    return clipboardText;
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

void main() {
  testWidgets('app launches with a calm single-surface idle state', (
    tester,
  ) async {
    await pumpUtilityApp(tester);

    expect(find.byKey(const ValueKey<String>('utility-shell')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('idle-identity-zone')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('idle-device-icon')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.laptop_mac_rounded), findsOneWidget);
    expect(find.text('Samarth MacBook Pro'), findsOneWidget);
    expect(find.text('F9P 2Q1'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Receive code'), findsOneWidget);
    expect(find.text('Drop files to send'), findsOneWidget);
    expect(find.text('Send instantly using a code'), findsNothing);
    expect(find.text('Receive files'), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('Receive'), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets('empty file pick stays on idle send state', (tester) async {
    await pumpUtilityApp(
      tester,
      container: buildTestContainer(
        sendItemSource: FakeSendItemSource(pickedItems: const []),
      ),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expect(find.text('Send with code'), findsNothing);
    expect(shellBackButton(), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets('receive code pill copies the idle code to the clipboard', (
    tester,
  ) async {
    await pumpUtilityApp(tester);

    final copiedText = await recordClipboardWrites(() async {
      await tester.tap(idleReceiveCodePill());
      await tester.pump();
    });

    expect(copiedText, 'F9P2Q1');
    expect(find.text('Copied'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('receive flow previews files and completes', (tester) async {
    final container = buildTestContainer();
    container.read(driftAppNotifierProvider.notifier).openReceiveEntry();
    await pumpUtilityApp(tester, container: container);

    await tester.enterText(receiveCodeFieldPrimary(), 'ab2cd3');
    await tester.pump();
    await tester.ensureVisible(receiveButton());
    await tester.tap(receiveButton());
    await pumpUiSettled(tester);

    expect(find.text('Wants to send you 4 files (14.9 MB).'), findsOneWidget);
    expect(find.text('Save to Downloads'), findsOneWidget);
    expect(find.text('sample.txt'), findsOneWidget);
    expect(find.text('vacation.jpg'), findsOneWidget);
    expect(find.text('beach.mov'), findsOneWidget);
    expect(find.text('boarding-pass.pdf'), findsOneWidget);
    expect(find.text('+1 more item'), findsNothing);
    expect(find.text('4 files · 14.9 MB'), findsOneWidget);

    await tester.ensureVisible(saveToDownloadsButton());
    await tester.tap(saveToDownloadsButton());
    await pumpUiSettled(tester);

    expect(find.text('Files saved'), findsOneWidget);
    expect(find.text('Saved to Downloads'), findsOneWidget);
    expect(shellBackButton(), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets('receive flow validates short codes inline', (tester) async {
    final container = buildTestContainer();
    container.read(driftAppNotifierProvider.notifier).openReceiveEntry();
    await pumpUtilityApp(tester, container: container);

    await tester.enterText(receiveCodeFieldPrimary(), 'abc');
    await tester.pump();
    await tester.ensureVisible(receiveButton());
    await tester.tap(receiveButton());
    await pumpUiSettled(tester);

    expect(
      find.text('Enter the 6-character code from the sender.'),
      findsOneWidget,
    );
    expectNoFlutterError(tester);
  });

  testWidgets('after drop state routes straight to manual code entry', (
    tester,
  ) async {
    final sendTransferSource = FakeSendTransferSource();
    final container = buildTestContainer(
      sendTransferSource: sendTransferSource,
    );
    await pumpUtilityApp(tester, container: container);

    await tester.ensureVisible(chooseFilesButton());
    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('2 files, 258 KB'), findsOneWidget);
    expect(find.text('Send with code'), findsOneWidget);
    expect(find.text('sample.txt'), findsWidgets);
    expect(find.text('Create code'), findsNothing);

    await tester.enterText(sendCodeField(), 'ab2cd3');
    await tester.pump();

    sendTransferSource.emit(
      sendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Code AB2 CD3',
        statusMessage: 'Request sent',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sending'), findsWidgets);
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.text('Code AB2 CD3'), findsNWidgets(2));

    sendTransferSource.emit(
      sendTransferUpdate(
        phase: SendTransferUpdatePhase.waitingForDecision,
        destinationLabel: 'Maya’s iPhone',
        statusMessage: 'Waiting for confirmation.',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sending'), findsOneWidget);
    expect(find.text('Waiting for confirmation.'), findsOneWidget);
    expect(find.text('2 files · 18 KB'), findsOneWidget);

    sendTransferSource.emit(
      sendTransferUpdate(
        phase: SendTransferUpdatePhase.sending,
        destinationLabel: 'Maya’s iPhone',
        statusMessage: 'Sending to Maya’s iPhone.',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sending to Maya’s iPhone.'), findsOneWidget);

    sendTransferSource.emit(
      sendTransferUpdate(
        phase: SendTransferUpdatePhase.completed,
        destinationLabel: 'Maya’s iPhone',
        statusMessage: 'Files sent successfully',
      ),
    );
    await sendTransferSource.finish();
    await tester.pumpAndSettle();

    expect(find.text('Transfer complete'), findsOneWidget);
    expect(find.text('Files sent successfully'), findsOneWidget);
    expect(find.text('Sent to'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('18 KB'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('valid send code starts automatically without a submit button', (
    tester,
  ) async {
    final sendTransferSource = FakeSendTransferSource();
    await pumpUtilityApp(
      tester,
      container: buildTestContainer(sendTransferSource: sendTransferSource),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    await tester.enterText(sendCodeField(), 'ab2cd3');
    await tester.pump();

    expect(sendTransferSource.lastRequest, isNotNull);
    expect(sendTransferSource.lastRequest?.code, 'AB2CD3');
    expect(sendTransferSource.lastRequest?.deviceName, 'Samarth MacBook Pro');
    expect(sendTransferSource.lastRequest?.paths, ['sample.txt', 'photos/']);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Finish transfer'), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets('back arrow returns send flow to the previous screen', (
    tester,
  ) async {
    final sendTransferSource = FakeSendTransferSource();
    await pumpUtilityApp(
      tester,
      container: buildTestContainer(sendTransferSource: sendTransferSource),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(shellBackButton(), findsOneWidget);
    expect(find.text('Send with code'), findsOneWidget);

    await tester.enterText(sendCodeField(), 'ab2cd3');
    await tester.pump();

    sendTransferSource.emit(
      sendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Code AB2 CD3',
        statusMessage: 'Request sent',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sending'), findsOneWidget);

    await tester.tap(shellBackButton());
    await tester.pumpAndSettle();

    expect(find.text('Send with code'), findsOneWidget);
    expect(find.text('sample.txt'), findsWidgets);

    await tester.tap(shellBackButton());
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('cancel during send returns to file selection', (tester) async {
    final sendTransferSource = FakeSendTransferSource();
    final container = buildTestContainer(
      sendTransferSource: sendTransferSource,
    );
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();
    await tester.enterText(sendCodeField(), 'ab2cd3');
    await tester.pump();

    sendTransferSource.emit(
      sendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Code AB2 CD3',
        statusMessage: 'Request sent',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Send with code'), findsOneWidget);
    expect(find.text('sample.txt'), findsWidgets);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
    expectNoFlutterError(tester);
  });

  testWidgets('nearby device row starts send with LAN ticket', (tester) async {
    final sendTransferSource = FakeSendTransferSource();
    Future<List<SendDestinationViewData>> fakeScan() async => [
      const SendDestinationViewData(
        name: 'Lab Mac',
        kind: SendDestinationKind.laptop,
        lanTicket: 'ticket-abc',
        lanFullname: 'recv-abc123xyz0._drift._udp.local.',
      ),
    ];

    await pumpUtilityApp(
      tester,
      container: buildTestContainer(
        sendTransferSource: sendTransferSource,
        nearbySendScan: fakeScan,
      ),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('Lab Mac'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(
        const ValueKey<String>(
          'nearby-tile-recv-abc123xyz0._drift._udp.local.',
        ),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'nearby-tile-recv-abc123xyz0._drift._udp.local.',
        ),
      ),
    );
    await tester.pump();

    expect(sendTransferSource.lastRequest, isNotNull);
    expect(sendTransferSource.lastRequest?.ticket, 'ticket-abc');
    expect(sendTransferSource.lastRequest?.lanDestinationLabel, 'Lab Mac');
    expect(sendTransferSource.lastRequest?.code, '');
    expect(sendTransferSource.lastRequest?.paths, ['sample.txt', 'photos/']);
    expectNoFlutterError(tester);
  });

  testWidgets('partial send code does not begin the transfer', (tester) async {
    final sendTransferSource = FakeSendTransferSource();
    final container = buildTestContainer(
      sendTransferSource: sendTransferSource,
    );
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('No nearby devices found.'), findsOneWidget);

    await tester.enterText(sendCodeField(), 'ab2');
    await tester.pump();

    expect(sendTransferSource.lastRequest, isNull);
    expect(find.text('Connecting'), findsNothing);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
    expectNoFlutterError(tester);
  });

  testWidgets(
    'send failure shows the rust error and back returns to selection',
    (tester) async {
      final sendTransferSource = FakeSendTransferSource();
      final container = buildTestContainer(
        sendTransferSource: sendTransferSource,
      );
      await pumpUtilityApp(tester, container: container);

      await tester.tap(chooseFilesButton());
      await tester.pumpAndSettle();
      await tester.enterText(sendCodeField(), 'ab2cd3');
      await tester.pump();

      sendTransferSource.emit(
        sendTransferUpdate(
          phase: SendTransferUpdatePhase.connecting,
          destinationLabel: 'Code AB2 CD3',
          statusMessage: 'Request sent',
        ),
      );
      await tester.pumpAndSettle();

      sendTransferSource.emit(
        sendTransferUpdate(
          phase: SendTransferUpdatePhase.failed,
          destinationLabel: 'Code AB2 CD3',
          statusMessage: 'Request sent',
          errorMessage:
              'receiver declined the offer: receiver declined the offer',
        ),
      );
      await sendTransferSource.finish();
      await tester.pumpAndSettle();

      expect(find.text('Transfer failed'), findsOneWidget);
      expect(
        find.text('receiver declined the offer: receiver declined the offer'),
        findsOneWidget,
      );

      await tester.tap(shellBackButton());
      await tester.pumpAndSettle();

      expect(find.text('Send with code'), findsOneWidget);
      expect(find.text('sample.txt'), findsWidgets);
      container.read(driftAppNotifierProvider.notifier).resetShell();
      await tester.pumpAndSettle();
      expectNoFlutterError(tester);
    },
  );

  testWidgets('recipient fallback avoids raw unknown device labels', (
    tester,
  ) async {
    final sendTransferSource = FakeSendTransferSource();
    await pumpUtilityApp(
      tester,
      container: buildTestContainer(sendTransferSource: sendTransferSource),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();
    await tester.enterText(sendCodeField(), 'ab2cd3');
    await tester.pump();

    sendTransferSource.emit(
      sendTransferUpdate(
        phase: SendTransferUpdatePhase.waitingForDecision,
        destinationLabel: 'unknown-device',
        statusMessage: 'Waiting for confirmation.',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recipient device'), findsNWidgets(2));
    expect(find.text('unknown-device'), findsNothing);
    expect(find.text('Waiting for confirmation.'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('send selection shows nearby section and manual code entry', (
    tester,
  ) async {
    final container = buildTestContainer();
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Send with code'), findsOneWidget);
    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('No nearby devices found.'), findsOneWidget);
    expect(sendCodeField(), findsOneWidget);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
    expectNoFlutterError(tester);
  });

  testWidgets('single dropped item renders a compact summary row', (
    tester,
  ) async {
    final container = buildTestContainer(
      droppedSendItems: const [
        TransferItemViewData(
          name: 'proposal.pdf',
          path: 'proposal.pdf',
          size: '2.4 MB',
          kind: TransferItemKind.file,
          sizeBytes: 2516582,
        ),
      ],
    );
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('1 file, 2.4 MB'), findsOneWidget);
    expect(find.text('proposal.pdf'), findsOneWidget);
    expect(find.text('+1 more item'), findsNothing);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
    expectNoFlutterError(tester);
  });

  testWidgets('tapping Add more appends to the current selection', (
    tester,
  ) async {
    const extraItem = TransferItemViewData(
      name: 'notes.pdf',
      path: 'notes.pdf',
      size: '42 KB',
      kind: TransferItemKind.file,
    );
    final container = buildTestContainer(
      sendItemSource: FakeSendItemSource(
        pickedItems: const [
          TransferItemViewData(
            name: 'sample.txt',
            path: 'sample.txt',
            size: '18 KB',
            kind: TransferItemKind.file,
          ),
        ],
        pickResponses: const [
          ['sample.txt'],
          ['notes.pdf'],
        ],
        itemCatalog: const {'notes.pdf': extraItem},
      ),
    );
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await pumpUiSettled(tester);
    await tester.tap(find.text('Add more'));
    await pumpUiSettled(tester);

    expect(find.text('sample.txt'), findsOneWidget);
    expect(find.text('notes.pdf'), findsOneWidget);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
  });

  testWidgets('tapping remove on a row removes only that row', (tester) async {
    final container = buildTestContainer(
      droppedSendItems: const [
        TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
        ),
        TransferItemViewData(
          name: 'photos',
          path: 'photos/',
          size: '12 items',
          kind: TransferItemKind.folder,
        ),
      ],
    );
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await pumpUiSettled(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('remove-send-item-sample.txt')),
    );
    await pumpUiSettled(tester);

    expect(find.text('sample.txt'), findsNothing);
    expect(find.text('photos'), findsOneWidget);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
  });

  testWidgets('receive error can recover back into a valid receive flow', (
    tester,
  ) async {
    final container = buildTestContainer();
    container.read(driftAppNotifierProvider.notifier).openReceiveEntry();
    await pumpUtilityApp(tester, container: container);

    await tester.enterText(receiveCodeFieldPrimary(), 'abc');
    await tester.pump();
    await tester.ensureVisible(receiveButton());
    await tester.tap(receiveButton());
    await pumpUiSettled(tester);

    await tester.enterText(receiveCodeFieldPrimary(), 'ab2cd3');
    await tester.pump();
    await tester.ensureVisible(receiveButton());
    await tester.tap(receiveButton());
    await pumpUiSettled(tester);

    expect(find.text('Wants to send you 4 files (14.9 MB).'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('back arrow returns receive review to code entry', (
    tester,
  ) async {
    final container = buildTestContainer();
    container.read(driftAppNotifierProvider.notifier).openReceiveEntry();
    await pumpUtilityApp(tester, container: container);

    await tester.enterText(receiveCodeFieldPrimary(), 'ab2cd3');
    await tester.pump();
    await tester.ensureVisible(receiveButton());
    await tester.tap(receiveButton());
    await pumpUiSettled(tester);

    expect(find.text('Wants to send you 4 files (14.9 MB).'), findsOneWidget);
    expect(shellBackButton(), findsOneWidget);

    await tester.tap(shellBackButton());
    await pumpUiSettled(tester);

    expect(find.text('Receive files'), findsOneWidget);
    expect(receiveCodeFieldFinder(), findsOneWidget);
    expect(find.text('Wants to send you 4 files (14.9 MB).'), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets('idle drop surface reacts to hover without shifting layout', (
    tester,
  ) async {
    await pumpUtilityApp(tester);

    final beforeSize = tester.getSize(idleDropSurface());
    final beforeWidget = tester.widget<AnimatedContainer>(idleDropSurface());
    final beforeDecoration = beforeWidget.decoration! as BoxDecoration;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(idleDropSurface()));
    await tester.pump(const Duration(milliseconds: 220));

    final afterWidget = tester.widget<AnimatedContainer>(idleDropSurface());
    final afterDecoration = afterWidget.decoration! as BoxDecoration;

    expect(tester.getSize(idleDropSurface()), beforeSize);
    expect(afterDecoration.color, isNot(equals(beforeDecoration.color)));
    expect(find.text('Drop files to send'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('hovering the idle window does not affect the drop surface', (
    tester,
  ) async {
    await pumpUtilityApp(tester);

    final beforeWidget = tester.widget<AnimatedContainer>(idleDropSurface());
    final beforeDecoration = beforeWidget.decoration! as BoxDecoration;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(idleIdentityZone()));
    await tester.pump(const Duration(milliseconds: 220));

    final afterWidget = tester.widget<AnimatedContainer>(idleDropSurface());
    final afterDecoration = afterWidget.decoration! as BoxDecoration;

    expect(afterDecoration.color, equals(beforeDecoration.color));
    expect(afterDecoration.border, equals(beforeDecoration.border));
    expect(find.text('Drop files to send'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('larger windows keep the same compact shell', (tester) async {
    await pumpUtilityApp(tester, size: const Size(840, 760));

    expect(find.byKey(const ValueKey<String>('utility-shell')), findsOneWidget);
    expect(find.text('Drop files to send'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('utility-shell'))).width,
      lessThanOrEqualTo(540),
    );
    expectNoFlutterError(tester);
  });
}
