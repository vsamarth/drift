import 'package:drift_app/app/drift_app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpUtilityApp(
  WidgetTester tester, {
  Size size = const Size(440, 560),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(const DriftApp());
  await tester.pumpAndSettle();
  expectNoFlutterError(tester);
}

void expectNoFlutterError(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

Finder receiveButton() =>
    find.byKey(const ValueKey<String>('receive-submit')).last;
Finder sendTab() => find.byKey(const ValueKey<String>('send-tab'));
Finder receiveTab() => find.byKey(const ValueKey<String>('receive-tab'));
Finder chooseFilesButton() => find.text('Choose files');
Finder saveToDownloadsButton() => find.text('Save to Downloads');
Finder copyCodeButton() => find.text('Copy code');

void main() {
  testWidgets('app launches in compact send mode', (tester) async {
    await pumpUtilityApp(tester);

    expect(find.byKey(const ValueKey<String>('utility-shell')), findsOneWidget);
    expect(sendTab(), findsOneWidget);
    expect(receiveTab(), findsOneWidget);
    expect(find.text('Drop files here'), findsOneWidget);
    expect(
      find.text('Any file or folder — received instantly on the other device'),
      findsOneWidget,
    );
    expect(find.text('Receive files'), findsNothing);
    expectNoFlutterError(tester);
  });

  testWidgets('receive flow previews files and completes', (tester) async {
    await pumpUtilityApp(tester);

    await tester.tap(receiveTab());
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
    await pumpUtilityApp(tester);

    await tester.tap(receiveTab());
    await tester.pumpAndSettle();

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
    await pumpUtilityApp(tester);

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

    expect(find.text('Drop files here'), findsOneWidget);
    expectNoFlutterError(tester);
  });

  testWidgets('receive error can recover back into a valid receive flow', (
    tester,
  ) async {
    await pumpUtilityApp(tester);

    await tester.tap(receiveTab());
    await tester.pumpAndSettle();

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

  testWidgets('larger windows keep the same compact shell', (tester) async {
    await pumpUtilityApp(tester, size: const Size(840, 760));

    expect(find.byKey(const ValueKey<String>('utility-shell')), findsOneWidget);
    expect(find.text('Drop files here'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('utility-shell'))).width,
      lessThanOrEqualTo(496),
    );
    expectNoFlutterError(tester);
  });
}
