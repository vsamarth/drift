import 'dart:async';

import '../../core/models/transfer_models.dart';
import '../../platform/send_transfer_source.dart';
import '../../state/drift_sample_data.dart';
import 'send_mapper.dart' as send_mapper;

abstract interface class SendTransferHost {
  List<TransferItemViewData> get currentSendItems;

  String get currentDeviceName;

  String get currentDeviceType;

  String? get currentServerUrl;

  void clearNearbyScanTimer();

  void clearSendMetricState();

  void logSendTransferFailure(Object error, StackTrace stackTrace);
}

class SendTransferCoordinator {
  SendTransferCoordinator({required SendTransferSource transferSource})
    : _transferSource = transferSource;

  final SendTransferSource _transferSource;
  StreamSubscription<SendTransferUpdate>? _subscription;
  int _generation = 0;

  void startSendTransferWithTicket({
    required SendTransferHost host,
    required SendDestinationViewData destination,
    required String ticket,
    required void Function(SendTransferUpdate update) onUpdate,
  }) {
    _cancelActiveTransfer();
    host.clearNearbyScanTimer();
    host.clearSendMetricState();
    final request = SendTransferRequestData(
      code: '',
      ticket: ticket,
      lanDestinationLabel: destination.name,
      paths: host.currentSendItems.map((item) => item.path).toList(
        growable: false,
      ),
      deviceName: host.currentDeviceName,
      deviceType: host.currentDeviceType,
    );
    _listen(
      host: host,
      request: request,
      onUpdate: onUpdate,
      fallbackDestination: destination.name,
    );
  }

  void startSendTransfer({
    required SendTransferHost host,
    required String normalizedCode,
    required void Function(SendTransferUpdate update) onUpdate,
  }) {
    _cancelActiveTransfer();
    host.clearNearbyScanTimer();
    host.clearSendMetricState();
    final request = SendTransferRequestData(
      code: normalizedCode,
      paths: host.currentSendItems.map((item) => item.path).toList(
        growable: false,
      ),
      deviceName: host.currentDeviceName,
      deviceType: host.currentDeviceType,
      serverUrl: host.currentServerUrl,
    );
    _listen(
      host: host,
      request: request,
      onUpdate: onUpdate,
      fallbackDestination: send_mapper.formatCodeAsDestination(normalizedCode),
    );
  }

  void cancelActiveTransfer() {
    _cancelActiveTransfer();
  }

  void _listen({
    required SendTransferHost host,
    required SendTransferRequestData request,
    required void Function(SendTransferUpdate update) onUpdate,
    required String fallbackDestination,
  }) {
    final generation = ++_generation;
    try {
      _subscription = _transferSource.startTransfer(request).listen(
        (update) {
          if (generation != _generation) {
            return;
          }
          onUpdate(update);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (generation != _generation) {
            return;
          }
          host.logSendTransferFailure(error, stackTrace);
          onUpdate(
            SendTransferUpdate(
              phase: SendTransferUpdatePhase.failed,
              destinationLabel: fallbackDestination,
              statusMessage: 'Request sent',
              itemCount: host.currentSendItems.length,
              totalSize: sampleSendSummary.totalSize,
              bytesSent: 0,
              totalBytes: 0,
              errorMessage: error.toString(),
            ),
          );
        },
      );
    } catch (error, stackTrace) {
      host.logSendTransferFailure(error, stackTrace);
      onUpdate(
        SendTransferUpdate(
          phase: SendTransferUpdatePhase.failed,
          destinationLabel: fallbackDestination,
          statusMessage: 'Request sent',
          itemCount: host.currentSendItems.length,
          totalSize: sampleSendSummary.totalSize,
          bytesSent: 0,
          totalBytes: 0,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  void _cancelActiveTransfer() {
    _generation += 1;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
