import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/presentation/dropped_files_page.dart';

void main() {
  testWidgets('shows the dropped files list', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DroppedFilesPage(
          files: [
            SendPickedFile(path: '/tmp/report.pdf', name: 'report.pdf'),
            SendPickedFile(path: '/tmp/photo.jpg', name: 'photo.jpg'),
          ],
        ),
      ),
    );

    expect(find.text('Selected files'), findsWidgets);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('/tmp/report.pdf'), findsOneWidget);
    expect(find.text('/tmp/photo.jpg'), findsOneWidget);
  });
}
