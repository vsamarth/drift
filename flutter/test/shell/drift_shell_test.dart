import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app/app_router.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/send_selection_picker.dart';
import 'package:app/features/settings/feature.dart';
import 'package:app/features/send/presentation/send_draft_preview.dart';
import 'package:app/features/send/send_drop_zone.dart';
import '../support/settings_test_overrides.dart';
import '../support/fake_send_selection_picker.dart';

void main() {
  testWidgets('shows the receiver card above the send dropzone', (
    WidgetTester tester,
  ) async {
    final router = buildAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expect(find.text('Drift'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Receive code'), findsOneWidget);
    expect(find.text('Drop files to send'), findsOneWidget);
    expect(find.text('Select files'), findsOneWidget);
  });

  testWidgets('tapping settings navigates to /settings via the router', (
    WidgetTester tester,
  ) async {
    final router = buildAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.home,
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.settings,
    );
    expect(find.byType(SettingsFeature), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('dropping files navigates to /send/draft and shows preview', (
    WidgetTester tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('drift_shell_test');
    final droppedFile = File('${tempDir.path}/report.pdf')
      ..writeAsStringSync('preview');
    final router = buildAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.home,
    );

    final dropZone = tester.widget<SendDropZone>(find.byType(SendDropZone));
    dropZone.onDropPaths([droppedFile.path]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.sendDraft,
    );
    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
  });

  testWidgets('dropping a directory navigates to /send/draft and shows preview', (
    WidgetTester tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('drift_shell_dir');
    final router = buildAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    final dropZone = tester.widget<SendDropZone>(find.byType(SendDropZone));
    dropZone.onDropPaths([directory.path]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.sendDraft,
    );
    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(find.text(directory.path.split(Platform.pathSeparator).last), findsOneWidget);
    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
  });

  testWidgets('choosing Files routes to send draft preview', (
    WidgetTester tester,
  ) async {
    final picker = FakeSendSelectionPicker(
      filesResult: [
        SendPickedFile(
          path: '/tmp/report.pdf',
          name: 'report.pdf',
          sizeBytes: BigInt.from(1024),
        ),
      ],
    );
    final router = buildAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          sendSelectionPickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('Select files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(picker.filesPickCount, 1);
    expect(picker.folderPickCount, 0);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.sendDraft,
    );
    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
  });

  testWidgets('choosing Folder routes to send draft preview', (
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
    final router = buildAppRouter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(testAppSettings),
          sendSelectionPickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('Select files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Folder'));
    await tester.pumpAndSettle();

    expect(picker.filesPickCount, 0);
    expect(picker.folderPickCount, 1);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      AppRoutePaths.sendDraft,
    );
    expect(find.byType(SendDraftPreview), findsOneWidget);
    expect(find.text('photos'), findsOneWidget);
  });
}
