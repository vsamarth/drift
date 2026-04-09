import 'package:drift_app/shared/formatting/transfer_message_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps human readable transfer messages intact', () {
    expect(
      isHumanReadableTransferMessage('Drift could not finish sending files.'),
      isTrue,
    );
    expect(
      sendFailureMessage('Transfer timed out after 10 seconds.'),
      'Transfer timed out after 10 seconds.',
    );
    expect(
      receiveFailureMessage('Everything saved successfully.'),
      'Everything saved successfully.',
    );
  });

  test('falls back for technical error messages', () {
    const rawMessage = 'SocketException: Connection reset by peer';

    expect(isHumanReadableTransferMessage(rawMessage), isFalse);
    expect(
      sendFailureMessage(rawMessage),
      'Drift couldn\'t finish sending the files. Try again.',
    );
    expect(
      receiveFailureMessage(rawMessage),
      'Drift couldn\'t save all incoming files successfully.',
    );
  });
}
