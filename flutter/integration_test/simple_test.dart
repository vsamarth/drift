import 'package:flutter_test/flutter_test.dart';
import 'package:drift_app/app/drift_app.dart';
import 'package:drift_app/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('launches the Drift shell', (WidgetTester tester) async {
    await tester.pumpWidget(const DriftApp());
    await tester.pumpAndSettle();

    expect(find.text('Drop files to send'), findsOneWidget);
  });
}
