import 'package:app/features/send/application/state.dart';
import 'package:app/features/send/application/model.dart';
import 'package:app/features/send/application/transfer_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('send state starts idle with no draft data', () {
    const state = SendState.idle();

    expect(state.phase, SendSessionPhase.idle);
    expect(state.items, isEmpty);
    expect(state.destination.mode, SendDestinationMode.none);
    expect(state.request, isNull);
    expect(state.result, isNull);
    expect(state.errorMessage, isNull);
  });

  test('send state can represent a draft with a destination', () {
    final state = SendState.drafting(
      items: [
        SendDraftItem(
          path: '/tmp/report.pdf',
          name: 'report.pdf',
          kind: SendPickedFileKind.file,
          sizeBytes: BigInt.from(1024),
        ),
      ],
      destination: const SendDestinationState.code('ABC123'),
    );

    expect(state.phase, SendSessionPhase.drafting);
    expect(state.items, hasLength(1));
    expect(state.items.single.path, '/tmp/report.pdf');
    expect(state.destination.mode, SendDestinationMode.code);
    expect(state.destination.code, 'ABC123');
    expect(state.request, isNull);
    expect(state.result, isNull);
    expect(state.errorMessage, isNull);
  });

  test('send state can represent an active transfer with a request snapshot', () {
    final state = SendState.transferring(
      items: const [],
      destination: const SendDestinationState.code('ABC123'),
      request: const SendRequestData(
        destinationMode: SendDestinationMode.code,
        paths: ['/tmp/report.pdf'],
        deviceName: 'MacBook Pro',
        deviceType: 'laptop',
        code: 'ABC123',
      ),
      transfer: SendTransferState(
        phase: SendTransferPhase.connecting,
        destinationLabel: 'Code ABC 123',
        statusMessage: 'Request sent',
        itemCount: BigInt.one,
        totalSize: BigInt.zero,
        bytesSent: BigInt.zero,
        totalBytes: BigInt.zero,
      ),
    );

    expect(state.phase, SendSessionPhase.transferring);
    expect(state.destination.mode, SendDestinationMode.code);
    expect(state.request?.code, 'ABC123');
    expect(state.transfer?.phase, SendTransferPhase.connecting);
  });

  test('send state can represent a final result with the original request snapshot', () {
    final state = SendState.result(
      items: const [],
      destination: const SendDestinationState.nearby(
        ticket: 'ticket-1',
        lanDestinationLabel: 'Laptop',
      ),
      request: const SendRequestData(
        destinationMode: SendDestinationMode.nearby,
        paths: ['/tmp/report.pdf'],
        deviceName: 'MacBook Pro',
        deviceType: 'laptop',
        ticket: 'ticket-1',
        lanDestinationLabel: 'Laptop',
      ),
      transfer: SendTransferState(
        phase: SendTransferPhase.completed,
        destinationLabel: 'Laptop',
        statusMessage: 'Sent successfully',
        itemCount: BigInt.zero,
        totalSize: BigInt.zero,
        bytesSent: BigInt.zero,
        totalBytes: BigInt.zero,
      ),
      result: const SendTransferResult(
        outcome: SendTransferOutcome.success,
        title: 'Sent',
        message: 'Done',
      ),
    );

    expect(state.phase, SendSessionPhase.result);
    expect(state.destination.mode, SendDestinationMode.nearby);
    expect(state.request?.destinationMode, SendDestinationMode.nearby);
    expect(state.request?.ticket, 'ticket-1');
    expect(state.result?.outcome, SendTransferOutcome.success);
    expect(state.transfer?.phase, SendTransferPhase.completed);
  });
}
