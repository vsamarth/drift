import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/core/theme/drift_theme.dart';
import 'package:drift_app/features/send/widgets/send_code_card.dart';
import 'package:drift_app/features/send/widgets/send_selected_card.dart';
import 'package:drift_app/features/send/send_providers.dart' as send_deps;
import 'package:drift_app/shell/widgets/transfer_result_card.dart';
import 'package:drift_app/state/transfer_result_state.dart';
import 'package:drift_app/state/drift_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'send_test_support.dart';

ProviderScope _buildScope({
  required FakeSendAppNotifier notifier,
  required FakeSendItemSource itemSource,
  required FakeSendTransferSource transferSource,
  required FakeNearbyDiscoverySource nearbySource,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      driftAppNotifierProvider.overrideWith(() => notifier),
      send_deps.sendItemSourceProvider.overrideWithValue(itemSource),
      send_deps.sendTransferSourceProvider.overrideWithValue(transferSource),
      send_deps.nearbyDiscoverySourceProvider.overrideWithValue(nearbySource),
    ],
    child: child,
  );
}

void main() {
  testWidgets('send selected card renders and delegates add files', (
    tester,
  ) async {
    final notifier = FakeSendAppNotifier(buildSendDraftState());
    final itemSource = FakeSendItemSource(
      pickResponses: [
        ['sample.txt', 'notes.pdf'],
      ],
    );
    final transferSource = FakeSendTransferSource();
    final nearbySource = FakeNearbyDiscoverySource();
    addTearDown(() async => await transferSource.dispose());

    await tester.pumpWidget(
      _buildScope(
        notifier: notifier,
        itemSource: itemSource,
        transferSource: transferSource,
        nearbySource: nearbySource,
        child: const MaterialApp(home: Scaffold(body: SendSelectedCard())),
      ),
    );

    expect(find.text('Selected files'), findsWidgets);
    expect(find.text('Add files'), findsOneWidget);

    await tester.tap(find.text('Add files'));
    await tester.pump();

    expect(itemSource.pickAdditionalPathsCalls, 1);
    expect(itemSource.appendPathsCalls, 1);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SendSelectedCard)),
    );
    expect(
      container
          .read(send_deps.sendStateProvider)
          .sendItems
          .map((item) => item.path)
          .toList(),
      ['sample.txt', 'notes.pdf'],
    );
  });

  testWidgets('send code card renders transfer state and cancels', (
    tester,
  ) async {
    final notifier = FakeSendAppNotifier(buildSendTransferState());
    final itemSource = FakeSendItemSource();
    final transferSource = FakeSendTransferSource();
    final nearbySource = FakeNearbyDiscoverySource();
    addTearDown(() async => await transferSource.dispose());

    await tester.pumpWidget(
      _buildScope(
        notifier: notifier,
        itemSource: itemSource,
        transferSource: transferSource,
        nearbySource: nearbySource,
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

    expect(transferSource.cancelTransferCalls, 1);
  });

  testWidgets('transfer result card shows a completion explainer on success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransferResultCard(
            fillBody: true,
            outcome: TransferResultOutcomeData.success,
            title: 'Transfer complete',
            message: 'Files sent successfully',
            metrics: const [
              TransferMetricRow(label: 'Sent to', value: 'Maya’s iPhone'),
              TransferMetricRow(label: 'Files', value: '4'),
              TransferMetricRow(label: 'Size', value: '14.7 MB'),
            ],
            primaryLabel: 'Done',
            onPrimary: () {},
          ),
        ),
      ),
    );

    expect(find.text('Transfer complete'), findsOneWidget);
    expect(find.text('Success'), findsOneWidget);
    expect(find.text('Files sent successfully'), findsOneWidget);
    expect(find.text('4 files finished in 14.7 MB.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      button.style?.backgroundColor?.resolve(<MaterialState>{}),
      kAccentCyanStrong,
    );
  });
}
