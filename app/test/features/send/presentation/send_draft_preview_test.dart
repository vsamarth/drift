import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/app/app_router.dart';
import 'package:app/features/send/application/directory_size.dart';
import 'package:app/features/receive/application/service.dart';
import 'package:app/features/receive/application/state.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/send_selection_picker.dart';
import 'package:app/features/send/presentation/send_draft_preview.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import '../../../support/fake_send_selection_picker.dart';

class FakeDirectorySizeCalculator implements DirectorySizeCalculator {
  FakeDirectorySizeCalculator(this.sizes);

  final Map<String, BigInt> sizes;

  @override
  Future<BigInt> sizeOfDirectory(String path) async {
    return sizes[path] ?? BigInt.zero;
  }
}

Future<void> _pumpPreview(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  testWidgets('shows the send draft preview', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          directorySizeCalculatorProvider.overrideWithValue(
            FakeDirectorySizeCalculator({'/tmp/photos': BigInt.from(1024)}),
          ),
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
              SendPickedFile(
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
    await _pumpPreview(tester);

    expect(find.text('Selected files'), findsOneWidget);
    expect(find.text('3 items, 4.0 KB'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photos'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('1.0 KB'), findsNWidgets(2));
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(3));
    expect(find.text('Add files'), findsOneWidget);
    expect(find.text('Add folders'), findsOneWidget);
    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('No nearby devices found'), findsOneWidget);
    expect(find.text('Send with code'), findsOneWidget);
    expect(
      find.text('Use the 6 characters shown on the receiver.'),
      findsOneWidget,
    );
    expect(find.text('AB12CD'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('appends files when Add files is tapped', (
    WidgetTester tester,
  ) async {
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
          directorySizeCalculatorProvider.overrideWithValue(
            FakeDirectorySizeCalculator({}),
          ),
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
    await _pumpPreview(tester);

    await tester.tap(find.text('Add files'));
    await _pumpPreview(tester);

    expect(picker.filesPickCount, 1);
    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(find.text('Selected files'), findsOneWidget);
    expect(find.text('2 items, 3.0 KB'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
  });

  testWidgets('appends folders when Add folders is tapped', (
    WidgetTester tester,
  ) async {
    final picker = FakeSendSelectionPicker(
      folderResult: [
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
          directorySizeCalculatorProvider.overrideWithValue(
            FakeDirectorySizeCalculator({'/tmp/photos': BigInt.from(2048)}),
          ),
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
    await _pumpPreview(tester);

    await tester.tap(find.text('Add folders'));
    await _pumpPreview(tester);

    expect(picker.folderPickCount, 1);
    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photos'), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.text('2 items, 3.0 KB'), findsOneWidget);
  });

  testWidgets(
    'shows nearby devices and prefills the code field when selected',
    (WidgetTester tester) async {
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
            directorySizeCalculatorProvider.overrideWithValue(
              FakeDirectorySizeCalculator({}),
            ),
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
      await _pumpPreview(tester);

      expect(find.text('Nearby devices'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('Send with code'), findsOneWidget);
      expect(find.text('AB12CD'), findsOneWidget);
      expect(
        find.text('Use the 6 characters shown on the receiver.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Laptop'));
      await _pumpPreview(tester);

      expect(find.text('ABC123'), findsOneWidget);
    },
  );

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
                final files = state.extra as List<SendPickedFile>? ?? const [];
                return SendDraftPreview(files: files);
              },
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpPreview(tester);

    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.sendDraft,
    );

    await tester.tap(find.byTooltip('Back'));
    await _pumpPreview(tester);

    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.home,
    );
    expect(find.byType(SendDraftPreview), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('removing the last file pops back to the previous page', (
    WidgetTester tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutePaths.sendDraft,
      initialExtra: [
        SendPickedFile(
          path: '/tmp/report.pdf',
          name: 'report.pdf',
          sizeBytes: BigInt.from(1024),
        ),
      ],
      routes: [
        GoRoute(
          path: AppRoutePaths.home,
          builder: (context, state) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: AppRoutePaths.sendDraftSegment,
              builder: (context, state) {
                final files = state.extra as List<SendPickedFile>? ?? const [];
                return SendDraftPreview(files: files);
              },
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          directorySizeCalculatorProvider.overrideWithValue(
            FakeDirectorySizeCalculator({}),
          ),
          receiverServiceSourceProvider.overrideWithValue(
            FakeReceiverServiceSource(),
          ),
          sendSelectionPickerProvider.overrideWithValue(
            FakeSendSelectionPicker(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpPreview(tester);

    expect(find.byType(SendDraftPreview), findsOneWidget);
    await tester.tap(find.byTooltip('Remove'));
    await _pumpPreview(tester);

    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.home,
    );
    expect(find.byType(SendDraftPreview), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });
}
