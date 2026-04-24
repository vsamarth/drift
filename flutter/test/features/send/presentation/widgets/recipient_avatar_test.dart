import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/send/presentation/widgets/recipient_avatar.dart';
import 'package:app/features/transfers/presentation/widgets/sending_connection_strip.dart';
import 'package:app/theme/drift_theme.dart';

void main() {
  testWidgets('RecipientAvatar shows progress and triggers success animation', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipientAvatar(
            deviceName: 'Test Device',
            deviceType: 'phone',
            mode: SendingStripMode.transferring,
            progress: 0.5,
          ),
        ),
      ),
    );

    // Verify progress indicator exists
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    
    // Check initial color (kAccentCyan)
    var progressIndicator = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect((progressIndicator.valueColor as AlwaysStoppedAnimation).value, kAccentCyan);

    // Update progress to 1.0
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipientAvatar(
            deviceName: 'Test Device',
            deviceType: 'phone',
            mode: SendingStripMode.transferring,
            progress: 1.0,
          ),
        ),
      ),
    );

    // After updating to 1.0, the animation (scale) should start, but color should stay cyan.
    await tester.pump(const Duration(milliseconds: 300));
    
    progressIndicator = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    final color = (progressIndicator.valueColor as AlwaysStoppedAnimation).value;
    
    expect(color, kAccentCyan, reason: 'Color should stay kAccentCyan even when progress reaches 1.0');
  });
}
