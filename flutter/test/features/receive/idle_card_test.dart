import 'package:app/features/receive/application/state.dart';
import 'package:app/features/receive/presentation/widgets/idle_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiverIdleViewState _idleState() {
  return const ReceiverIdleViewState(
    deviceName: 'Rusty Ridge',
    badge: ReceiverBadgeState.ready(),
    status: 'Ready',
    code: 'ABC123',
    clipboardCode: 'ABC123',
    lifecycle: ReceiverLifecycle.ready,
  );
}

void _mockClipboardChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          return null;
        }
        return null;
      });
}

void main() {
  testWidgets('receive code control exposes copy semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReceiveIdleCard(state: _idleState())),
        ),
      );
      await tester.pump();

      final semanticsNode = tester.getSemantics(
        find.byKey(const ValueKey<String>('idle-receive-code')),
      );
      final semanticsData = semanticsNode.getSemanticsData();
      expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);
      expect(semanticsData.label, contains('Copy receive code'));
      expect(semanticsData.hint, contains('Copies the receive code'));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('receive code can be copied again with keyboard activation', (
    tester,
  ) async {
    _mockClipboardChannel();
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReceiveIdleCard(state: _idleState())),
      ),
    );
    await tester.pump();

    final copyCodeControl = find.byKey(
      const ValueKey<String>('idle-receive-code'),
    );

    await tester.tap(copyCodeControl);
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Receive code'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('Copied'), findsOneWidget);
  });
}
