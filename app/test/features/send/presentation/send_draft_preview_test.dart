import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/app/app_router.dart';
import 'package:app/features/send/application/controller.dart';
import 'package:app/features/send/application/directory_size.dart';
import 'package:app/features/receive/application/service.dart';
import 'package:app/features/receive/application/state.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/send_selection_picker.dart';
import 'package:app/features/send/application/state.dart';
import 'package:app/features/settings/settings_providers.dart';
import 'package:app/features/send/presentation/send_draft_preview.dart';
import 'package:app/features/send/presentation/send_transfer_route.dart';
import 'package:app/platform/send_transfer_source.dart';
import 'package:app/platform/rust/receiver/fake_source.dart';
import 'package:app/theme/drift_theme.dart';
import '../../../support/fake_send_selection_picker.dart';
import '../../../support/settings_test_overrides.dart';

class FakeSendTransferSource implements SendTransferSource {
  final StreamController<SendTransferUpdate> _updates =
      StreamController<SendTransferUpdate>.broadcast(sync: true);

  bool cancelCalled = false;

  @override
  Stream<SendTransferUpdate> startTransfer(SendTransferRequestData request) {
    return _updates.stream;
  }

  @override
  Future<void> cancelTransfer() async {
    cancelCalled = true;
  }

  Future<void> close() async {
    await _updates.close();
  }
}

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

ProviderContainer _buildContainer({
  required DirectorySizeCalculator directorySizeCalculator,
  required SendSelectionPicker picker,
  required FakeReceiverServiceSource receiverSource,
  List overrides = const [],
}) {
  return ProviderContainer(
    overrides: [
      initialAppSettingsProvider.overrideWithValue(testAppSettings),
      directorySizeCalculatorProvider.overrideWithValue(
        directorySizeCalculator,
      ),
      receiverServiceSourceProvider.overrideWithValue(receiverSource),
      sendSelectionPickerProvider.overrideWithValue(picker),
      ...overrides,
    ],
  );
}

void main() {
  testWidgets('shows the send draft preview', (WidgetTester tester) async {
    final container = _buildContainer(
      directorySizeCalculator: FakeDirectorySizeCalculator({
        '/tmp/photos': BigInt.from(1024),
      }),
      receiverSource: FakeReceiverServiceSource(),
      picker: FakeSendSelectionPicker(),
    );
    addTearDown(container.dispose);
    container.read(sendControllerProvider.notifier).beginDraft([
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
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SendDraftPreview()),
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

  testWidgets('uses a stronger active Send button color', (
    WidgetTester tester,
  ) async {
    final container = _buildContainer(
      directorySizeCalculator: FakeDirectorySizeCalculator({}),
      receiverSource: FakeReceiverServiceSource(),
      picker: FakeSendSelectionPicker(),
      overrides: [
        sendTransferSourceProvider.overrideWithValue(FakeSendTransferSource()),
      ],
    );
    addTearDown(container.dispose);
    final fakeSource = container.read(sendTransferSourceProvider) as FakeSendTransferSource;
    addTearDown(fakeSource.close);
    container.read(sendControllerProvider.notifier).beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SendDraftPreview()),
      ),
    );
    await _pumpPreview(tester);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final background = button.style?.backgroundColor?.resolve(const {});

    expect(background, kAccentCyanStrong);
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

    final container = _buildContainer(
      directorySizeCalculator: FakeDirectorySizeCalculator({}),
      receiverSource: FakeReceiverServiceSource(),
      picker: picker,
    );
    addTearDown(container.dispose);
    container.read(sendControllerProvider.notifier).beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SendDraftPreview()),
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

    final container = _buildContainer(
      directorySizeCalculator: FakeDirectorySizeCalculator({
        '/tmp/photos': BigInt.from(2048),
      }),
      receiverSource: FakeReceiverServiceSource(),
      picker: picker,
    );
    addTearDown(container.dispose);
    container.read(sendControllerProvider.notifier).beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SendDraftPreview()),
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

  testWidgets('shows nearby devices without prefilled code when selected', (
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

    final container = _buildContainer(
      directorySizeCalculator: FakeDirectorySizeCalculator({}),
      receiverSource: receiverSource,
      picker: FakeSendSelectionPicker(),
    );
    addTearDown(container.dispose);
    container.read(sendControllerProvider.notifier).beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SendDraftPreview()),
      ),
    );
    await _pumpPreview(tester);

    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Send with code'), findsOneWidget);
    expect(
      find.text('Use the 6 characters shown on the receiver.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Laptop'));
    await _pumpPreview(tester);

    expect(find.text('ABC123'), findsNothing);
    expect(
      container.read(sendControllerProvider).destination.mode,
      SendDestinationMode.nearby,
    );
    expect(
      container.read(sendControllerProvider).destination.ticket,
      'ticket-1',
    );
    expect(container.read(sendControllerProvider).destination.code, isNull);
  });

  testWidgets('tapping Send shows the transfer page', (
    WidgetTester tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutePaths.sendDraft,
      routes: [
        GoRoute(
          path: AppRoutePaths.home,
          builder: (context, state) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: AppRoutePaths.sendDraftSegment,
              builder: (context, state) => const SendDraftPreview(),
            ),
            GoRoute(
              path: AppRoutePaths.sendTransferSegment,
              builder: (context, state) =>
                  SendTransferRoutePage(request: state.extra as SendRequestData),
            ),
          ],
        ),
      ],
    );

    final container = _buildContainer(
      directorySizeCalculator: FakeDirectorySizeCalculator({}),
      receiverSource: FakeReceiverServiceSource(),
      picker: FakeSendSelectionPicker(),
      overrides: [
        sendTransferSourceProvider.overrideWithValue(FakeSendTransferSource()),
      ],
    );
    addTearDown(container.dispose);
    final fakeSource =
        container.read(sendTransferSourceProvider) as FakeSendTransferSource;
    addTearDown(fakeSource.close);
    container.read(sendControllerProvider.notifier).beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    container
        .read(sendControllerProvider.notifier)
        .updateDestinationCode('ABC123');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpPreview(tester);

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(
      container.read(sendControllerProvider).phase,
      SendSessionPhase.transferring,
    );
    expect(find.text('Transferring'), findsOneWidget);
    expect(find.text('/tmp/report.pdf'), findsOneWidget);
  });

  testWidgets('tapping back pops the router and returns home', (
    WidgetTester tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutePaths.sendDraft,
      routes: [
        GoRoute(
          path: AppRoutePaths.home,
          builder: (context, state) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: AppRoutePaths.sendDraftSegment,
              builder: (context, state) => const SendDraftPreview(),
            ),
          ],
        ),
      ],
    );

    final container = _buildContainer(
      directorySizeCalculator: FakeDirectorySizeCalculator({}),
      receiverSource: FakeReceiverServiceSource(),
      picker: FakeSendSelectionPicker(),
    );
    addTearDown(container.dispose);
    container.read(sendControllerProvider.notifier).beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpPreview(tester);

    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.sendDraft,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

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
      routes: [
        GoRoute(
          path: AppRoutePaths.home,
          builder: (context, state) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: AppRoutePaths.sendDraftSegment,
              builder: (context, state) => const SendDraftPreview(),
            ),
          ],
        ),
      ],
    );

    final container = _buildContainer(
      directorySizeCalculator: FakeDirectorySizeCalculator({}),
      receiverSource: FakeReceiverServiceSource(),
      picker: FakeSendSelectionPicker(),
    );
    addTearDown(container.dispose);
    container.read(sendControllerProvider.notifier).beginDraft([
      SendPickedFile(
        path: '/tmp/report.pdf',
        name: 'report.pdf',
        sizeBytes: BigInt.from(1024),
      ),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
