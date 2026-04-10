import 'package:drift_app/features/send/send_providers.dart';
import 'package:drift_app/features/send/widgets/send_code_card.dart';
import 'package:drift_app/features/send/widgets/send_selected_card.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'send_test_support.dart';

ProviderScope _buildScope({
  required FakeSendAppNotifier notifier,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [driftAppNotifierProvider.overrideWith(() => notifier)],
    child: child,
  );
}

void main() {
  testWidgets('send selected card renders and delegates add files', (
    tester,
  ) async {
    final notifier = FakeSendAppNotifier(buildSendDraftState());

    await tester.pumpWidget(
      _buildScope(
        notifier: notifier,
        child: const MaterialApp(home: Scaffold(body: SendSelectedCard())),
      ),
    );

    expect(find.text('Selected files'), findsWidgets);
    expect(find.text('Add files'), findsOneWidget);

    await tester.tap(find.text('Add files'));
    await tester.pump();

    expect(notifier.appendSendItemsFromPickerCalls, 1);
  });

  testWidgets('send code card renders transfer state and cancels', (
    tester,
  ) async {
    final notifier = FakeSendAppNotifier(buildSendTransferState());

    await tester.pumpWidget(
      _buildScope(
        notifier: notifier,
        child: const MaterialApp(
          home: Scaffold(
            body: SendCodeCard(
              fillBody: true,
              title: 'Sending',
              status: 'Request sent',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Request sent'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, cancel'));
    await tester.pump();

    expect(notifier.cancelSendInProgressCalls, 1);
  });
}
