import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/app/app_router.dart';
import 'package:app/features/receive/application/service.dart';
import 'package:app/features/receive/application/state.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/send_selection_picker.dart';
import 'package:app/features/send/presentation/send_draft_preview.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import '../../../support/fake_send_selection_picker.dart';

void main() {
  testWidgets('shows the send draft preview', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receiverServiceSourceProvider.overrideWithValue(
            FakeReceiverServiceSource(),
          ),
          sendSelectionPickerProvider.overrideWithValue(
            FakeSendSelectionPicker(),
          ),
        ],
        child: MaterialApp(
          home: SendDraftPreview(
            files: [
              SendPickedFile(
                path: '/tmp/report.pdf',
                name: 'report.pdf',
                sizeBytes: BigInt.from(1024),
              ),
              const SendPickedFile(
                path: '/tmp/photos',
                name: 'photos',
                kind: SendPickedFileKind.directory,
              ),
              SendPickedFile(
                path: '/tmp/photo.jpg',
                name: 'photo.jpg',
                sizeBytes: BigInt.from(2048),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected files'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photos'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('3 items, 3.0 KB'), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));
    expect(find.text('—'), findsNothing);
    expect(find.text('Add files'), findsOneWidget);
    expect(find.text('Add folders'), findsOneWidget);
    expect(find.text('NEARBY DEVICES'), findsOneWidget);
    expect(find.text('Send with code'), findsOneWidget);
    expect(
      find.text('Enter the six-character receiver code to start the transfer.'),
      findsOneWidget,
    );
  });

  testWidgets('appends files when Add files is tapped', (WidgetTester tester) async {
    final picker = FakeSendSelectionPicker(
      filesResult: [
        SendPickedFile(
          path: '/tmp/photo.jpg',
          name: 'photo.jpg',
          sizeBytes: BigInt.from(2048),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receiverServiceSourceProvider.overrideWithValue(
            FakeReceiverServiceSource(),
          ),
          sendSelectionPickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(
          home: SendDraftPreview(
            files: [
              SendPickedFile(
                path: '/tmp/report.pdf',
                name: 'report.pdf',
                sizeBytes: BigInt.from(1024),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add files'));
    await tester.pumpAndSettle();

    expect(picker.filesPickCount, 1);
    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('2 items, 3.0 KB'), findsOneWidget);
  });

  testWidgets('appends folders when Add folders is tapped', (
    WidgetTester tester,
  ) async {
    final picker = FakeSendSelectionPicker(
      folderResult: const [
        SendPickedFile(
          path: '/tmp/photos',
          name: 'photos',
          kind: SendPickedFileKind.directory,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receiverServiceSourceProvider.overrideWithValue(
            FakeReceiverServiceSource(),
          ),
          sendSelectionPickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(
          home: SendDraftPreview(
            files: [
              SendPickedFile(
                path: '/tmp/report.pdf',
                name: 'report.pdf',
                sizeBytes: BigInt.from(1024),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add folders'));
    await tester.pumpAndSettle();

    expect(picker.folderPickCount, 1);
    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photos'), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.text('2 items, 1.0 KB'), findsOneWidget);
  });

  testWidgets('shows nearby devices and prefills the code field when selected', (
    WidgetTester tester,
  ) async {
    final receiverSource = FakeReceiverServiceSource(
      nearbyResults: const [
        NearbyReceiver(
          fullname: 'samarth-laptop',
          label: 'Laptop',
          code: 'ABC123',
          ticket: 'ticket-1',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
      overrides: [
        receiverServiceSourceProvider.overrideWithValue(receiverSource),
        sendSelectionPickerProvider.overrideWithValue(
          FakeSendSelectionPicker(),
        ),
      ],
      child: MaterialApp(
        home: SendDraftPreview(
          files: [
            SendPickedFile(
              path: '/tmp/report.pdf',
              name: 'report.pdf',
                sizeBytes: BigInt.from(1024),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEARBY DEVICES'), findsOneWidget);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Send with code'), findsOneWidget);
    expect(find.text('Receiver code'), findsOneWidget);

    await tester.tap(find.text('Laptop'));
    await tester.pumpAndSettle();

    expect(find.text('ABC123'), findsOneWidget);
  });

  testWidgets('tapping back pops the router and returns home', (
    WidgetTester tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutePaths.sendDraft,
      initialExtra: const <SendPickedFile>[],
      routes: [
        GoRoute(
          path: AppRoutePaths.home,
          builder: (context, state) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: AppRoutePaths.sendDraftSegment,
              builder: (context, state) {
                final files =
                    state.extra as List<SendPickedFile>? ?? const [];
                return SendDraftPreview(files: files);
              },
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.sendDraft,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.home,
    );
    expect(find.byType(SendDraftPreview), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });
}
