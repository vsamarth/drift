import 'dart:ui';

import 'package:drift_app/app/drift_app.dart';
import 'package:drift_app/state/drift_controller.dart';
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

Finder receiveButton() =>
    find.byKey(const ValueKey<String>('receive-submit')).last;
Finder chooseFilesButton() => find.text('Select files');
Finder saveToDownloadsButton() => find.text('Save to Downloads');
Finder copyCodeButton() => find.text('Copy code');
Finder idleDropSurface() =>
    find.byKey(const ValueKey<String>('send-drop-surface'));
Finder idleIdentityZone() =>
    find.byKey(const ValueKey<String>('idle-identity-zone'));
Finder idleReceiveCodePill() =>
    find.byKey(const ValueKey<String>('idle-receive-code'));

DriftController buildTestController() => DriftController(
  deviceName: 'Samarth MacBook Pro',
  idleReceiveCode: 'F9P2Q1',
);

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

    await tester.enterText(
      find.byKey(const ValueKey<String>('receive-code-field')),
      'ab2cd3',
    );
    await tester.pump();
    await tester.ensureVisible(receiveButton());
    await tester.tap(receiveButton());
    await tester.pumpAndSettle();

    expect(find.text('Save these files?'), findsOneWidget);
    expect(find.text('Save to Downloads'), findsOneWidget);
    expect(find.text('vacation.jpg'), findsOneWidget);
    expect(find.text('+1 more item'), findsOneWidget);

    await tester.ensureVisible(saveToDownloadsButton());
    await tester.tap(saveToDownloadsButton());
    await tester.pumpAndSettle();

    expect(find.text('Files saved'), findsOneWidget);
    expect(find.text('Saved to Downloads'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('receive flow validates short codes inline', (tester) async {
    final controller = buildTestController()..openReceiveEntry();
    await pumpUtilityApp(tester, controller: controller);

    await tester.enterText(
      find.byKey(const ValueKey<String>('receive-code-field')),
      'abc',
    );
    await tester.pump();
    await tester.ensureVisible(receiveButton());
    await tester.tap(receiveButton());
    await tester.pumpAndSettle();

    expect(
      find.text('Enter the 6-character code from the sender.'),
      findsOneWidget,
    );
    expectNoFlutterError(tester);
  });

  testWidgets('send flow covers selection, code sharing, and completion', (
    tester,
  ) async {
    await pumpUtilityApp(tester, controller: buildTestController());

    await tester.ensureVisible(chooseFilesButton());
    await tester.tap(chooseFilesButton());
    await tester.pumpAndSettle();

    expect(find.text('2 items ready'), findsOneWidget);
    expect(find.text('sample.txt'), findsWidgets);

    await tester.tap(find.text('Create code'));
    await tester.pumpAndSettle();

    expect(find.text('Ready to send'), findsOneWidget);
    expect(find.text('AB2 CD3'), findsOneWidget);
    expect(find.text('+1 more item'), findsOneWidget);

    await tester.ensureVisible(copyCodeButton());
    await tester.tap(copyCodeButton());
    await tester.pumpAndSettle();

    expect(find.text('Waiting for receiver…'), findsOneWidget);

    await tester.tap(find.text('Mark as done'));
    await tester.pumpAndSettle();

    expect(find.text('Transfer complete'), findsOneWidget);

    await tester.tap(find.text('Send more files'));
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('receive error can recover back into a valid receive flow', (
    tester,
  ) async {
    final controller = buildTestController()..openReceiveEntry();
    await pumpUtilityApp(tester, controller: controller);

    await tester.enterText(
      find.byKey(const ValueKey<String>('receive-code-field')),
      'abc',
    );
    await tester.pump();
    await tester.ensureVisible(receiveButton());
    await tester.tap(receiveButton());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('receive-code-field')),
      'ab2cd3',
    );
    await tester.pump();
    await tester.ensureVisible(receiveButton());
    await tester.tap(receiveButton());
    await tester.pumpAndSettle();

    expect(find.text('Save these files?'), findsOneWidget);
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
