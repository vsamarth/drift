import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/presentation/widgets/send_draft_file_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('file row itself is not tappable like a button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SendDraftFileList(
            files: [
              SendPickedFile(
                path: '/tmp/report.pdf',
                name: 'report.pdf',
                sizeBytes: BigInt.from(1024),
              ),
            ],
            maxHeight: 200,
            onRemove: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(InkWell), findsOneWidget);
    expect(find.byTooltip('Remove'), findsOneWidget);
  });
}
