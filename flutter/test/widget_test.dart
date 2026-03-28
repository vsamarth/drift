import 'package:drift_app/app/drift_app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpDesktopApp(WidgetTester tester) async {
  await pumpSizedApp(tester, const Size(1440, 1000));
}

Future<void> pumpSizedApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(const DriftApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('app launches in send mode', (tester) async {
    await pumpDesktopApp(tester);

    expect(find.text('drift'), findsOneWidget);
    expect(find.text('Send'), findsWidgets);
    expect(find.text('Drag files or folders here.'), findsOneWidget);
  });

  testWidgets('mode switching updates workspace without replacing shell', (
    tester,
  ) async {
    await pumpDesktopApp(tester);

    await tester.tap(find.byKey(const ValueKey<String>('mode-Receive')));
    await tester.pumpAndSettle();

    expect(find.text('Receive'), findsWidgets);
    expect(find.text('Manifest Preview'), findsOneWidget);
  });

  testWidgets('send flow covers collecting and ready states', (tester) async {
    await pumpDesktopApp(tester);

    await tester.tap(find.text('Simulate Drop'));
    await tester.pumpAndSettle();

    expect(find.text('Drop zone is live and ready.'), findsOneWidget);
    expect(find.text('sample.txt'), findsWidgets);

    await tester.tap(find.text('Load Sample Files'));
    await tester.pumpAndSettle();

    expect(find.text('AB2CD3'), findsWidgets);
    expect(
      find.text('Offer ready. Share the short code with your receiver.'),
      findsWidgets,
    );
  });

  testWidgets('receive flow covers review, completed, and error states', (
    tester,
  ) async {
    await pumpDesktopApp(tester);

    await tester.tap(find.byKey(const ValueKey<String>('mode-Receive')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('receive-code-field')),
      'ab2cd3',
    );
    await tester.pump();
    await tester.tap(find.text('Preview Offer'));
    await tester.pumpAndSettle();

    expect(find.text('Accept Transfer'), findsOneWidget);
    expect(find.text('vacation.jpg'), findsOneWidget);

    await tester.tap(find.text('Accept Transfer'));
    await tester.pumpAndSettle();

    expect(
      find.text('Accepted. Files will be saved to ~/Downloads/Drift.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Expired Example'));
    await tester.pumpAndSettle();

    expect(
      find.text('That code has expired. Ask the sender to create a new one.'),
      findsWidgets,
    );
  });

  testWidgets('send workspace stays usable in a compact window', (
    tester,
  ) async {
    await pumpSizedApp(tester, const Size(980, 720));

    expect(find.text('Drag files or folders here.'), findsOneWidget);

    await tester.tap(find.text('Simulate Drop'));
    await tester.pumpAndSettle();

    expect(find.text('Drop zone is live and ready.'), findsOneWidget);
    expect(find.text('Selection'), findsOneWidget);
    expect(find.text('Offer Status'), findsOneWidget);
  });
}
