import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:animated_tree_view/animated_tree_view.dart';

import 'package:app/features/receive/feature.dart';
import 'package:app/features/settings/feature.dart';
import 'package:app/features/transfers/feature.dart';
import 'package:app/theme/drift_theme.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import 'package:app/src/rust/api/receiver.dart' as rust_receiver;
import '../../support/settings_test_overrides.dart';

void main() {
  testWidgets('shows an empty transfer state without the old card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    expect(find.text('No offers yet'), findsNothing);
  });

  testWidgets('shows an incoming transfer offer', (WidgetTester tester) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('Maya'), findsAtLeastNWidgets(1));
    expect(
      find.text('Review the files and accept only if you trust the sender.'),
      findsOneWidget,
    );
    expect(find.text('No offers yet'), findsNothing);
  });

  testWidgets('shows offer details and manifest items', (
    WidgetTester tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('wants to send you 2 files (3.0 KB).'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('Save to Downloads'), findsOneWidget);
  });

  testWidgets('renders nested manifest paths as a tree', (
    WidgetTester tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(
      senderName: 'Maya',
      files: [
        rust_receiver.ReceiverTransferFile(
          path: 'crates/Cargo.toml',
          size: BigInt.from(376),
        ),
        rust_receiver.ReceiverTransferFile(
          path: 'crates/core/src/actor.rs',
          size: BigInt.from(12 * 1024),
        ),
        rust_receiver.ReceiverTransferFile(
          path: 'crates/core/src/nearby.rs',
          size: BigInt.from(922),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('crates'), findsOneWidget);
    expect(find.text('core'), findsOneWidget);
    expect(find.text('src'), findsOneWidget);
    expect(find.text('Cargo.toml'), findsOneWidget);
    expect(find.text('actor.rs'), findsOneWidget);
    expect(find.text('nearby.rs'), findsOneWidget);
  });

  testWidgets('uses a package tree with connector lines', (
    WidgetTester tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(
      senderName: 'Maya',
      files: [
        rust_receiver.ReceiverTransferFile(
          path: 'crates/core/src/actor.rs',
          size: BigInt.from(12 * 1024),
        ),
        rust_receiver.ReceiverTransferFile(
          path: 'crates/core/src/nearby.rs',
          size: BigInt.from(922),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TreeView &&
            widget.indentation.style == IndentStyle.squareJoint,
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps manifest tree rows tightly stacked', (
    WidgetTester tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(
      senderName: 'Maya',
      files: [
        rust_receiver.ReceiverTransferFile(
          path: 'crates/core/src/actor.rs',
          size: BigInt.from(12 * 1024),
        ),
        rust_receiver.ReceiverTransferFile(
          path: 'crates/core/src/nearby.rs',
          size: BigInt.from(922),
        ),
      ],
    );
    await tester.pumpAndSettle();

    final actorTop = tester.getTopLeft(find.text('actor.rs')).dy;
    final nearbyTop = tester.getTopLeft(find.text('nearby.rs')).dy;

    expect(nearbyTop - actorTop, lessThan(34));
  });

  testWidgets('decline button calls the source and returns to idle', (
    tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(source.lastRespondToOfferAccept, isFalse);
    expect(find.text('Incoming'), findsNothing);
    expect(find.text('No offers yet'), findsNothing);
  });

  testWidgets('accepting an offer shows the receiving state', (tester) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to Downloads'));
    await tester.pumpAndSettle();

    expect(find.text('Receiving'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Incoming'), findsNothing);
    expect(find.text('wants to send you 2 files (3.0 KB).'), findsNothing);
  });

  testWidgets('cancelling a receiving transfer shows the cancelled result', (
    tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to Downloads'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Receive cancelled'), findsOneWidget);
    expect(
      find.text('Drift stopped receiving before all files were saved.'),
      findsOneWidget,
    );
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Receiving'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('No offers yet'), findsNothing);
    expect(find.text('Receive cancelled'), findsNothing);
  });

  testWidgets('completing a receiving transfer shows the completed state', (
    tester,
  ) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to Downloads'));
    await tester.pumpAndSettle();

    source.emitCompletedTransfer(
      senderName: 'Maya',
      destinationLabel: 'Pictures',
      saveRootLabel: 'Downloads',
    );
    await tester.pumpAndSettle();

    expect(find.text('Success'), findsOneWidget);
    expect(find.text('Files saved'), findsOneWidget);
    expect(find.text('Pictures'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Receiving'), findsNothing);

    final doneButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(doneButton.style?.backgroundColor?.resolve(<WidgetState>{}), kPrimary);
  });

  testWidgets('done on a completed transfer returns to idle', (tester) async {
    final source = FakeReceiverServiceSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferReviewAnimationProvider.overrideWithValue(false),
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          receiverServiceSourceProvider.overrideWithValue(source),
          transfersServiceSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 440, height: 560, child: ReceiveFeature()),
          ),
        ),
      ),
    );

    source.emitIncomingOffer(senderName: 'Maya');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to Downloads'));
    await tester.pumpAndSettle();

    source.emitCompletedTransfer(
      senderName: 'Maya',
      destinationLabel: 'Pictures',
      saveRootLabel: 'Downloads',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('No offers yet'), findsNothing);
    expect(find.text('Complete'), findsNothing);
  });
}
