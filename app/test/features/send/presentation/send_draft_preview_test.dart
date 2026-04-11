import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/presentation/send_draft_preview.dart';

void main() {
  testWidgets('shows the send draft preview', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SendDraftPreview(
          files: [
            SendPickedFile(
              path: '/tmp/report.pdf',
              name: 'report.pdf',
              sizeBytes: BigInt.from(1024),
            ),
            SendPickedFile(
              path: '/tmp/photo.jpg',
              name: 'photo.jpg',
              sizeBytes: BigInt.from(2048),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Selected files'), findsWidgets);
    expect(find.text('Choose how you want to send this selection.'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
  });
}
