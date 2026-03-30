import 'dart:async';
import 'dart:ui';

import 'package:drift_app/app/drift_app.dart';
import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/platform/receive_registration_source.dart';
import 'package:drift_app/platform/send_item_source.dart';
import 'package:drift_app/platform/send_transfer_source.dart';
import 'package:drift_app/state/drift_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpUtilityApp(
  WidgetTester tester, {
  Size size = const Size(440, 560),
  DriftController? controller,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(DriftApp(controller: controller));
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

DriftController buildTestController({
  List<SendDestinationViewData>? nearbySendDestinations,
  NearbySendScan? nearbySendScan,
  List<TransferItemViewData>? droppedSendItems,
  SendItemSource? sendItemSource,
  SendTransferSource? sendTransferSource,
}) => DriftController(
  deviceName: 'Samarth MacBook Pro',
  idleReceiveCode: 'F9P2Q1',
  enableIdleReceiverRefresh: false,
  animateSendingConnection: false,
  nearbySendDestinations: nearbySendDestinations,
  nearbySendScan: nearbySendScan ?? (() async => <SendDestinationViewData>[]),
  droppedSendItems: droppedSendItems,
  sendItemSource:
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
              ),
              TransferItemViewData(
                name: 'photos',
                path: 'photos/',
                size: '12 items',
                kind: TransferItemKind.folder,
              ),
            ],
      ),
  sendTransferSource: sendTransferSource ?? FakeSendTransferSource(),
  receiveRegistrationSource: const FakeReceiveRegistrationSource(),
  enableIdleIncomingListener: false,
);

class FakeSendItemSource implements SendItemSource {
  FakeSendItemSource({required this.pickedItems});

  final List<TransferItemViewData> pickedItems;

  @override
  Future<List<TransferItemViewData>> pickFiles() async =>
      List<TransferItemViewData>.unmodifiable(pickedItems);

  @override
  Future<List<TransferItemViewData>> loadPaths(List<String> paths) async =>
      List<TransferItemViewData>.unmodifiable(pickedItems);
}

class FakeReceiveRegistrationSource implements ReceiveRegistrationSource {
  const FakeReceiveRegistrationSource();

  @override
  Future<ReceiveRegistrationData> ensureReceiverRegistration({
    required String deviceName,
  }) async =>
      const ReceiveRegistrationData(code: 'F9P2Q1', expiresAt: 'unused');
}

class FakeSendTransferSource implements SendTransferSource {
  SendTransferRequestData? lastRequest;
  StreamController<SendTransferUpdate>? _controller;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    lastRequest = request;
    _controller?.close();
    _controller = StreamController<SendTransferUpdate>();
    return _controller!.stream;
  }

  void emit(SendTransferUpdate update) {
    _controller?.add(update);
  }

  Future<void> finish() async {
    await _controller?.close();
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
    await pumpUtilityApp(tester, controller: buildTestController());

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
    expect(find.text('Drop to send'), findsNothing);
    expect(find.text('Send instantly using a code'), findsNothing);
    expect(find.text('Receive files'), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('Receive'), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets('empty file pick stays on idle send state', (tester) async {
    await pumpUtilityApp(
      tester,
      controller: buildTestController(
        sendItemSource: FakeSendItemSource(pickedItems: const []),
      ),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expect(find.text('Or enter a code'), findsNothing);
    expect(shellBackButton(), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets('receive code pill copies the idle code to the clipboard', (
    tester,
  ) async {
    await pumpUtilityApp(tester, controller: buildTestController());

    final copiedText = await recordClipboardWrites(() async {
      await tester.tap(idleReceiveCodePill());
      await tester.pump();
    });

    expect(copiedText, 'F9P2Q1');
    expect(find.text('Copied'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('receive flow previews files and completes', (tester) async {
    final controller = buildTestController()..openReceiveEntry();
    await pumpUtilityApp(tester, controller: controller);

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
    expect(find.text('4 · 14.9 MB'), findsOneWidget);

    await tester.ensureVisible(saveToDownloadsButton());
    await tester.tap(saveToDownloadsButton());
    await pumpUiSettled(tester);

    expect(find.text('Files saved'), findsOneWidget);
    expect(find.text('Saved to Downloads'), findsOneWidget);
    expect(find.text('Saved to'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('14.9 MB'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('receive flow validates short codes inline', (tester) async {
    final controller = buildTestController()..openReceiveEntry();
    await pumpUtilityApp(tester, controller: controller);

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
    await pumpUtilityApp(
      tester,
      controller: buildTestController(sendTransferSource: sendTransferSource),
    );

    await tester.ensureVisible(chooseFilesButton());
    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.text('Or enter a code'), findsOneWidget);
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

    await tester.tap(find.text('Send more files'));
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
      controller: buildTestController(sendTransferSource: sendTransferSource),
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
      controller: buildTestController(sendTransferSource: sendTransferSource),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(shellBackButton(), findsOneWidget);
    expect(find.text('Or enter a code'), findsOneWidget);

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

    expect(find.text('Or enter a code'), findsOneWidget);
    expect(find.text('sample.txt'), findsWidgets);

    await tester.tap(shellBackButton());
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('cancel during send returns to file selection', (tester) async {
    final sendTransferSource = FakeSendTransferSource();
    await pumpUtilityApp(
      tester,
      controller: buildTestController(sendTransferSource: sendTransferSource),
    );

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

    expect(find.text('Or enter a code'), findsOneWidget);
    expect(find.text('sample.txt'), findsWidgets);
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
      controller: buildTestController(
        sendTransferSource: sendTransferSource,
        nearbySendScan: fakeScan,
      ),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('Lab Mac'), findsOneWidget);

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
    await pumpUtilityApp(
      tester,
      controller: buildTestController(sendTransferSource: sendTransferSource),
    );

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('No nearby devices found.'), findsOneWidget);

    await tester.enterText(sendCodeField(), 'ab2');
    await tester.pump();

    expect(sendTransferSource.lastRequest, isNull);
    expect(find.text('Connecting'), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets(
    'send failure shows the rust error and back returns to selection',
    (tester) async {
      final sendTransferSource = FakeSendTransferSource();
      await pumpUtilityApp(
        tester,
        controller: buildTestController(sendTransferSource: sendTransferSource),
      );

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

      expect(find.text('Or enter a code'), findsOneWidget);
      expect(find.text('sample.txt'), findsWidgets);
      expectNoFlutterError(tester);
    },
  );

  testWidgets('recipient fallback avoids raw unknown device labels', (
    tester,
  ) async {
    final sendTransferSource = FakeSendTransferSource();
    await pumpUtilityApp(
      tester,
      controller: buildTestController(sendTransferSource: sendTransferSource),
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
    final controller = buildTestController(nearbySendDestinations: const []);
    await pumpUtilityApp(tester, controller: controller);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('Or enter a code'), findsOneWidget);
    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('No nearby devices found.'), findsOneWidget);
    expect(sendCodeField(), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('single dropped item renders a compact summary row', (
    tester,
  ) async {
    final controller = buildTestController(
      droppedSendItems: const [
        TransferItemViewData(
          name: 'proposal.pdf',
          path: 'proposal.pdf',
          size: '2.4 MB',
          kind: TransferItemKind.file,
        ),
      ],
    );
    await pumpUtilityApp(tester, controller: controller);

    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('proposal.pdf'), findsOneWidget);
    expect(find.text('+1 more item'), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets('receive error can recover back into a valid receive flow', (
    tester,
  ) async {
    final controller = buildTestController()..openReceiveEntry();
    await pumpUtilityApp(tester, controller: controller);

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
    final controller = buildTestController()..openReceiveEntry();
    await pumpUtilityApp(tester, controller: controller);

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
    await pumpUtilityApp(tester, controller: buildTestController());

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
    expect(find.text('Drop to send'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('hovering the idle window reinforces the drop surface', (
    tester,
  ) async {
    await pumpUtilityApp(tester, controller: buildTestController());

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
    final beforeBorder = beforeDecoration.border! as Border;
    final afterBorder = afterDecoration.border! as Border;

    expect(afterBorder.top.color, isNot(equals(beforeBorder.top.color)));
    expect(afterDecoration.color, isNot(equals(beforeDecoration.color)));
    expect(find.text('Drop to send'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('larger windows keep the same compact shell', (tester) async {
    await pumpUtilityApp(
      tester,
      size: const Size(840, 760),
      controller: buildTestController(),
    );

    expect(find.byKey(const ValueKey<String>('utility-shell')), findsOneWidget);
    expect(find.text('Drop files to send'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('utility-shell'))).width,
      lessThanOrEqualTo(540),
    );
    expectNoFlutterError(tester);
  });
}
