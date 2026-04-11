import 'package:app/features/send/presentation/send_selection_source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chooser sheet dismisses before invoking file callback', (
    WidgetTester tester,
  ) async {
    final observer = _TestNavigatorObserver();
    var popCountAtInvocation = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  showSendSelectionSourceSheet(
                    context,
                    onChooseFiles: () {
                      popCountAtInvocation = observer.popCount;
                    },
                    onChooseFolder: () {},
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Folder'), findsOneWidget);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(popCountAtInvocation, 1);
    expect(observer.popCount, 1);
    expect(find.text('Folder'), findsNothing);
  });
}

class _TestNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount += 1;
    super.didPop(route, previousRoute);
  }
}
