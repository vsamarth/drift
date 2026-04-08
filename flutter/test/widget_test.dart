import 'dart:async';
import 'dart:ui';

import 'package:drift_app/app/drift_app.dart';
import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/core/theme/drift_theme.dart';
import 'package:drift_app/platform/send_item_source.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/shell/mobile_shell.dart';
import 'package:drift_app/state/app_identity.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:drift_app/state/nearby_discovery_source.dart';
import 'package:drift_app/state/receiver_service_source.dart';
import 'package:drift_app/state/settings_store.dart';
import 'package:drift_app/src/rust/api/error.dart' as rust_error;
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

Future<void> pumpMobileShell(
  WidgetTester tester, {
  Size size = const Size(700, 844),
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
      child: MaterialApp(theme: buildDriftTheme(), home: const MobileShell()),
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

Finder chooseFilesButton() => find.text('Select files');
Finder saveToDownloadsButton() => find.text('Save to Downloads');
Finder idleDropSurface() =>
    find.byKey(const ValueKey<String>('send-drop-surface'));
Finder idleIdentityZone() =>
    find.byKey(const ValueKey<String>('idle-identity-zone'));
Finder idleReceiveCodePill() =>
    find.byKey(const ValueKey<String>('idle-receive-code'));
Finder receiveTab() => find.byKey(const ValueKey<String>('receive-tab'));
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
      driftSettingsStoreProvider.overrideWith(
        (ref) => DriftSettingsStore.inMemory(),
      ),
      initialDriftAppIdentityProvider.overrideWith(
        (ref) => const DriftAppIdentity(
          deviceName: 'Drift Device',
          deviceType: 'laptop',
          downloadRoot: '/tmp/Downloads',
        ),
      ),
      driftAppIdentityProvider.overrideWith(
        (ref) => const DriftAppIdentity(
          deviceName: 'Drift Device',
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
    this.pickFilesError,
  }) : _pickResponses =
           pickResponses ??
           [pickedItems.map((item) => item.path).toList(growable: false)],
       _itemCatalog = {
         for (final item in pickedItems) item.path: item,
         ...?itemCatalog,
       };

  final List<List<String>> _pickResponses;
  final Map<String, TransferItemViewData> _itemCatalog;
  final Object? pickFilesError;
  int _pickIndex = 0;

  @override
  Future<List<TransferItemViewData>> pickFiles() async => pickFilesError == null
      ? _mapPaths(_nextPickResponse())
      : Future<List<TransferItemViewData>>.error(pickFilesError!);

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

class ControlledSendItemSource extends FakeSendItemSource {
  ControlledSendItemSource({required super.pickedItems});

  final Completer<List<TransferItemViewData>> _pickCompleter =
      Completer<List<TransferItemViewData>>();

  @override
  Future<List<TransferItemViewData>> pickFiles() => _pickCompleter.future;

  void completePick(List<TransferItemViewData> items) {
    if (!_pickCompleter.isCompleted) {
      _pickCompleter.complete(List<TransferItemViewData>.unmodifiable(items));
    }
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
  FakeSendTransferSource({this.cancelError});

  SendTransferRequestData? lastRequest;
  StreamController<SendTransferUpdate>? _controller;
  final Object? cancelError;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    lastRequest = request;
    unawaited(_controller?.close());
    _controller = StreamController<SendTransferUpdate>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> cancelTransfer() async {
    if (cancelError != null) {
      throw cancelError!;
    }
    _controller?.add(
      sendTransferUpdate(
        phase: SendTransferUpdatePhase.cancelled,
        destinationLabel: lastRequest?.code.isNotEmpty == true
            ? 'Code AB2 CD3'
            : (lastRequest?.lanDestinationLabel ?? 'Nearby receiver'),
        statusMessage: 'Transfer cancelled.',
      ),
    );
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
      phase: ReceiverBadgePhase.ready,
    ),
    this.respondError,
    this.cancelError,
  });

  final ReceiverBadgeState initialBadge;
  final Object? respondError;
  final Object? cancelError;
  final StreamController<ReceiverBadgeState> _badgeController =
      StreamController<ReceiverBadgeState>.broadcast();
  final StreamController<rust_receiver.ReceiverTransferEvent>
  _incomingController =
      StreamController<rust_receiver.ReceiverTransferEvent>.broadcast();
  final List<bool> discoverableCalls = <bool>[];
  final List<bool> respondToOfferCalls = <bool>[];

  @override
  Future<void> cancelTransfer() async {
    if (cancelError != null) {
      throw cancelError!;
    }
  }

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
    if (respondError != null) {
      throw respondError!;
    }
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

rust_receiver.ReceiverTransferEvent _incomingOfferEvent() {
  return rust_receiver.ReceiverTransferEvent(
    phase: rust_receiver.ReceiverTransferPhase.offerReady,
    senderName: 'Maya',
    senderDeviceType: 'phone',
    destinationLabel: 'Downloads',
    saveRootLabel: 'Downloads',
    statusMessage: 'Maya wants to send you a file.',
    itemCount: BigInt.one,
    totalSizeBytes: BigInt.from(18 * 1024),
    bytesReceived: BigInt.zero,
    totalSizeLabel: '18 KB',
    files: [
      rust_receiver.ReceiverTransferFile(
        path: 'sample.txt',
        size: BigInt.from(18 * 1024),
      ),
    ],
  );
}

rust_receiver.ReceiverTransferEvent _incomingFailedEvent({
  required BigInt receivedBytes,
}) {
  return rust_receiver.ReceiverTransferEvent(
    phase: rust_receiver.ReceiverTransferPhase.failed,
    senderName: 'Maya',
    senderDeviceType: 'phone',
    destinationLabel: 'Downloads',
    saveRootLabel: 'Downloads',
    statusMessage: 'Transfer failed.',
    itemCount: BigInt.one,
    totalSizeBytes: BigInt.from(18 * 1024),
    bytesReceived: receivedBytes,
    totalSizeLabel: '18 KB',
    files: const [],
    error: const rust_error.UserFacingErrorData(
      kind: rust_error.UserFacingErrorKindData.connectionLost,
      title: 'Connection lost',
      message: 'Drift lost the connection while receiving files.',
      recovery: 'Try again when both devices are connected.',
      retryable: true,
    ),
  );
}

rust_receiver.ReceiverTransferEvent _incomingDeclinedEvent() {
  return rust_receiver.ReceiverTransferEvent(
    phase: rust_receiver.ReceiverTransferPhase.declined,
    senderName: 'Maya',
    senderDeviceType: 'phone',
    destinationLabel: 'Downloads',
    saveRootLabel: 'Downloads',
    statusMessage: 'Transfer declined.',
    itemCount: BigInt.one,
    totalSizeBytes: BigInt.from(18 * 1024),
    bytesReceived: BigInt.zero,
    totalSizeLabel: '18 KB',
    files: const [],
  );
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
    expect(find.text('Drift Device'), findsOneWidget);
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

  testWidgets('send selection failure is shown on the idle picker', (
    tester,
  ) async {
    await pumpUtilityApp(
      tester,
      container: buildTestContainer(
        sendItemSource: FakeSendItemSource(
          pickedItems: const [],
          pickFilesError: Exception('permission denied'),
        ),
      ),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expect(
      find.text('Drift couldn\'t prepare the selected files.'),
      findsOneWidget,
    );
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

  testWidgets('mobile selecting files opens the shared send shell', (
    tester,
  ) async {
    final sendItemSource = ControlledSendItemSource(
      pickedItems: const [
        TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
          sizeBytes: 18 * 1024,
        ),
      ],
    );
    final container = buildTestContainer(sendItemSource: sendItemSource);
    await pumpMobileShell(tester, container: container);

    expect(find.text('Tap to choose files to send.'), findsOneWidget);
    expect(find.text('Selected files'), findsNothing);

    await tester.tap(chooseFilesButton());
    await tester.pump();

    expect(find.text('Selected files'), findsNothing);

    sendItemSource.completePick(const [
      TransferItemViewData(
        name: 'sample.txt',
        path: 'sample.txt',
        size: '18 KB',
        kind: TransferItemKind.file,
        sizeBytes: 18 * 1024,
      ),
    ]);
    await pumpUiSettled(tester);

    expect(find.text('Selected files'), findsWidgets);
    expect(find.text('Nearby devices'), findsOneWidget);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await pumpUiSettled(tester);
    expectNoFlutterError(tester);
  });

  testWidgets('mobile incoming offer uses the shared receive review screen', (
    tester,
  ) async {
    final receiverService = FakeReceiverServiceSource();
    final container = buildTestContainer(
      receiverServiceSource: receiverService,
      enableIdleIncomingListener: true,
    );
    await pumpMobileShell(tester, container: container);

    receiverService.emitIncoming(_incomingOfferEvent());
    await pumpUiSettled(tester);

    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('Maya'), findsWidgets);
    expect(
      find.text('Review the files and accept only if you trust the sender.'),
      findsOneWidget,
    );
    expect(saveToDownloadsButton(), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Decline'));
    await pumpUiSettled(tester);

    receiverService.emitIncoming(_incomingDeclinedEvent());
    await pumpUiSettled(tester);

    expect(find.text('Transfer declined'), findsOneWidget);
    expect(
      find.text('The transfer was declined before any files were received.'),
      findsOneWidget,
    );
    expectNoFlutterError(tester);
  });

  testWidgets('mobile receive completion uses the shared result view', (
    tester,
  ) async {
    final receiverService = FakeReceiverServiceSource();
    final container = buildTestContainer(
      receiverServiceSource: receiverService,
      enableIdleIncomingListener: true,
    );
    await pumpMobileShell(tester, container: container);

    receiverService.emitIncoming(
      rust_receiver.ReceiverTransferEvent(
        phase: rust_receiver.ReceiverTransferPhase.completed,
        senderName: 'Maya',
        senderDeviceType: 'phone',
        destinationLabel: 'Downloads',
        saveRootLabel: 'Downloads',
        statusMessage: 'Files saved',
        itemCount: BigInt.one,
        totalSizeBytes: BigInt.from(18 * 1024),
        bytesReceived: BigInt.from(18 * 1024),
        totalSizeLabel: '18 KB',
        files: [
          rust_receiver.ReceiverTransferFile(
            path: 'sample.txt',
            size: BigInt.from(18 * 1024),
          ),
        ],
      ),
    );
    await pumpUiSettled(tester);

    expect(find.text('Files saved'), findsWidgets);
    expect(find.text('Saved to'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await pumpUiSettled(tester);

    expect(find.text('Tap to choose files to send.'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('mobile receive failure stays on a transfer error state', (
    tester,
  ) async {
    final receiverService = FakeReceiverServiceSource();
    final container = buildTestContainer(
      receiverServiceSource: receiverService,
      enableIdleIncomingListener: true,
    );
    await pumpMobileShell(tester, container: container);

    receiverService.emitIncoming(_incomingOfferEvent());
    await pumpUiSettled(tester);
    await tester.tap(saveToDownloadsButton());
    await pumpUiSettled(tester);

    receiverService.emitIncoming(
      _incomingFailedEvent(receivedBytes: BigInt.from(9 * 1024)),
    );
    await pumpUiSettled(tester);

    expect(find.text('Couldn\'t finish receiving files'), findsOneWidget);
    expect(
      find.text('Drift lost the connection while receiving files.'),
      findsOneWidget,
    );
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await pumpUiSettled(tester);

    expect(find.text('Tap to choose files to send.'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('mobile receive declined stays on a terminal declined state', (
    tester,
  ) async {
    final receiverService = FakeReceiverServiceSource();
    final container = buildTestContainer(
      receiverServiceSource: receiverService,
      enableIdleIncomingListener: true,
    );
    await pumpMobileShell(tester, container: container);

    receiverService.emitIncoming(_incomingOfferEvent());
    await pumpUiSettled(tester);
    receiverService.emitIncoming(_incomingDeclinedEvent());
    await pumpUiSettled(tester);

    expect(find.text('Transfer declined'), findsOneWidget);
    expect(
      find.text('The transfer was declined before any files were received.'),
      findsOneWidget,
    );
    expect(find.text('Done'), findsOneWidget);
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

    expect(find.text('Send'), findsOneWidget);
    expect(sendTransferSource.lastRequest, isNull);

    await tester.tap(find.text('Send'));
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

  testWidgets('valid send code starts only after tapping Send', (tester) async {
    final sendTransferSource = FakeSendTransferSource();
    await pumpUtilityApp(
      tester,
      container: buildTestContainer(sendTransferSource: sendTransferSource),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    await tester.enterText(sendCodeField(), 'ab2cd3');
    await tester.pump();

    expect(sendTransferSource.lastRequest, isNull);

    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sendTransferSource.lastRequest, isNotNull);
    expect(sendTransferSource.lastRequest?.code, 'AB2CD3');
    expect(sendTransferSource.lastRequest?.deviceName, 'Drift Device');
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

    await tester.tap(find.text('Send'));
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

  testWidgets('cancel during send shows a cancelled result', (tester) async {
    final sendTransferSource = FakeSendTransferSource();
    final container = buildTestContainer(
      sendTransferSource: sendTransferSource,
    );
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();
    await tester.enterText(sendCodeField(), 'ab2cd3');
    await tester.pump();

    await tester.tap(find.text('Send'));
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
    await tester.tap(find.text('Yes, cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Transfer cancelled'), findsOneWidget);
    expect(
      find.text('The transfer was stopped before all files were sent.'),
      findsOneWidget,
    );
    expect(find.text('Send again'), findsOneWidget);

    await tester.tap(find.text('Send again'));
    await tester.pumpAndSettle();

    expect(find.text('Send with code'), findsOneWidget);
    expect(find.text('sample.txt'), findsWidgets);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
    expectNoFlutterError(tester);
  });

  testWidgets('cancel failure during send shows a terminal error', (
    tester,
  ) async {
    final sendTransferSource = FakeSendTransferSource(
      cancelError: Exception('cancel failed'),
    );
    final container = buildTestContainer(
      sendTransferSource: sendTransferSource,
    );
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();
    await tester.enterText(sendCodeField(), 'ab2cd3');
    await tester.pump();

    await tester.tap(find.text('Send'));
    await tester.pump();

    sendTransferSource.emit(
      sendTransferUpdate(
        phase: SendTransferUpdatePhase.connecting,
        destinationLabel: 'Code AB2 CD3',
        statusMessage: 'Request sent',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Transfer failed'), findsOneWidget);
    expect(find.text('Drift couldn\'t cancel the transfer.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
    expectNoFlutterError(tester);
  });

  testWidgets(
    'nearby device selection starts send with LAN ticket after Send',
    (tester) async {
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

      await tester.ensureVisible(find.text('Lab Mac'));
      await tester.tap(find.text('Lab Mac'));
      await tester.pump();

      expect(sendTransferSource.lastRequest, isNull);

      await tester.tap(find.text('Send'));
      await tester.pump();

      expect(sendTransferSource.lastRequest, isNotNull);
      expect(sendTransferSource.lastRequest?.ticket, 'ticket-abc');
      expect(sendTransferSource.lastRequest?.lanDestinationLabel, 'Lab Mac');
      expect(sendTransferSource.lastRequest?.code, '');
      expect(sendTransferSource.lastRequest?.paths, ['sample.txt', 'photos/']);
      expectNoFlutterError(tester);
    },
  );

  testWidgets('partial send code does not begin the transfer', (tester) async {
    final sendTransferSource = FakeSendTransferSource();
    final container = buildTestContainer(
      sendTransferSource: sendTransferSource,
    );
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('No nearby devices found'), findsOneWidget);

    await tester.enterText(sendCodeField(), 'ab2');
    await tester.pump();

    expect(sendTransferSource.lastRequest, isNull);
    expect(find.text('Connecting'), findsNothing);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
    expectNoFlutterError(tester);
  });

  testWidgets('send failure shows retry action and preserves selection', (
    tester,
  ) async {
    final sendTransferSource = FakeSendTransferSource();
    final container = buildTestContainer(
      sendTransferSource: sendTransferSource,
    );
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();
    await tester.enterText(sendCodeField(), 'ab2cd3');
    await tester.pump();

    await tester.tap(find.text('Send'));
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
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Send with code'), findsOneWidget);
    expect(find.text('sample.txt'), findsWidgets);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
    expectNoFlutterError(tester);
  });

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

    await tester.tap(find.text('Send'));
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
    expect(find.text('No nearby devices found'), findsOneWidget);
    expect(sendCodeField(), findsOneWidget);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
    expectNoFlutterError(tester);
  });

  testWidgets('nearby scan failure is shown in the send draft', (tester) async {
    Future<List<SendDestinationViewData>> failingScan() async {
      throw Exception('mdns unavailable');
    }

    final container = buildTestContainer(nearbySendScan: failingScan);
    await pumpUtilityApp(tester, container: container);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Send with code'), findsOneWidget);
    expect(
      find.text('Drift couldn\'t scan for nearby devices right now.'),
      findsOneWidget,
    );
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

  testWidgets('tapping Add files appends to the current selection', (
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
    await tester.tap(find.text('Add files'));
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
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await pumpUiSettled(tester);

    expect(find.text('sample.txt'), findsNothing);
    expect(find.text('photos'), findsOneWidget);
    container.read(driftAppNotifierProvider.notifier).resetShell();
    await tester.pumpAndSettle();
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
