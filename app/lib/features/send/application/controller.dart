import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:app/features/receive/application/state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'model.dart';
import '../../../platform/send_transfer_source.dart';
import '../../settings/application/controller.dart';
import 'state.dart';

part 'controller.g.dart';

@Riverpod(keepAlive: true)
class SendController extends _$SendController {
  StreamSubscription<SendTransferUpdate>? _transferSubscription;

  @override
  SendState build() {
    ref.onDispose(_dispose);
    return const SendState.idle();
  }

  void beginDraft(List<SendPickedFile> files) {
    unawaited(_cancelActiveTransfer());
    state = SendState.drafting(
      items: files.map(SendDraftItem.fromPickedFile).toList(growable: false),
    );
  }

  void appendDraftItems(List<SendPickedFile> files) {
    if (state.phase != SendSessionPhase.drafting) {
      beginDraft(files);
      return;
    }

    state = SendState.drafting(
      items: [...state.items, ...files.map(SendDraftItem.fromPickedFile)],
      destination: state.destination,
    );
  }

  void removeDraftItem(String path) {
    if (state.phase != SendSessionPhase.drafting) {
      return;
    }

    final nextItems = state.items
        .where((item) => item.path != path)
        .toList(growable: false);
    if (nextItems.isEmpty) {
      clearDraft();
      return;
    }

    state = SendState.drafting(
      items: nextItems,
      destination: state.destination,
    );
  }

  void updateDestinationCode(String value) {
    if (state.phase != SendSessionPhase.drafting) {
      return;
    }

    final normalized = _normalizedCode(value);
    state = SendState.drafting(
      items: state.items,
      destination: normalized.isEmpty
          ? const SendDestinationState.none()
          : SendDestinationState.code(normalized),
    );
  }

  void clearDestinationCode() {
    if (state.phase != SendSessionPhase.drafting) {
      return;
    }

    state = SendState.drafting(
      items: state.items,
      destination: const SendDestinationState.none(),
    );
  }

  void selectNearbyReceiver(NearbyReceiver receiver) {
    if (state.phase != SendSessionPhase.drafting) {
      return;
    }

    state = SendState.drafting(
      items: state.items,
      destination: SendDestinationState.nearby(
        ticket: receiver.ticket,
        lanDestinationLabel: receiver.label,
      ),
    );
  }

  void clearDraft() {
    unawaited(_cancelActiveTransfer());
    state = const SendState.idle();
  }

  SendRequestData? buildSendRequest() {
    if (state.phase != SendSessionPhase.drafting || state.items.isEmpty) {
      return null;
    }

    final settings = ref.read(settingsControllerProvider).settings;
    final paths = state.items.map((item) => item.path).toList(growable: false);
    final destination = state.destination;

    switch (destination.mode) {
      case SendDestinationMode.none:
        return null;
      case SendDestinationMode.code:
        final code = _normalizedCode(destination.code ?? '');
        if (code.length != 6) {
          return null;
        }
        return SendRequestData(
          destinationMode: SendDestinationMode.code,
          paths: paths,
          deviceName: settings.deviceName,
          deviceType: _localDeviceTypeLabel(),
          code: code,
          serverUrl: settings.discoveryServerUrl,
        );
      case SendDestinationMode.nearby:
        return SendRequestData(
          destinationMode: SendDestinationMode.nearby,
          paths: paths,
          deviceName: settings.deviceName,
          deviceType: _localDeviceTypeLabel(),
          ticket: destination.ticket,
          lanDestinationLabel: destination.lanDestinationLabel,
          serverUrl: settings.discoveryServerUrl,
        );
    }
  }

  bool get canStartSend => buildSendRequest() != null;

  void startTransfer(SendRequestData request) {
    final validatedRequest = buildSendRequest();
    if (validatedRequest == null || !_sameSendRequest(request, validatedRequest)) {
      return;
    }

    final transferSource = ref.read(sendTransferSourceProvider);
    state = SendState.transferring(
      items: state.items,
      destination: state.destination,
      request: validatedRequest,
    );
    unawaited(_transferSubscription?.cancel());
    _transferSubscription = transferSource
        .startTransfer(
          SendTransferRequestData(
            code: validatedRequest.code ?? '',
            paths: validatedRequest.paths,
            deviceName: validatedRequest.deviceName,
            deviceType: validatedRequest.deviceType,
            serverUrl: validatedRequest.serverUrl,
            ticket: validatedRequest.ticket,
            lanDestinationLabel: validatedRequest.lanDestinationLabel,
          ),
        )
        .listen(_handleTransferUpdate, onError: _handleTransferError);
  }

  void cancelTransfer() {
    unawaited(_cancelActiveTransfer());
    if (state.phase == SendSessionPhase.transferring) {
      state = SendState.drafting(
        items: state.items,
        destination: state.destination,
      );
    }
  }

  Future<void> _cancelActiveTransfer() async {
    final subscription = _transferSubscription;
    _transferSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
      try {
        await ref.read(sendTransferSourceProvider).cancelTransfer();
      } catch (_) {
        // Best effort: the native transfer may already be gone.
      }
    }
  }

  void _dispose() {
    unawaited(_cancelActiveTransfer());
  }

  void _handleTransferUpdate(SendTransferUpdate update) {
    if (state.phase != SendSessionPhase.transferring || state.request == null) {
      return;
    }

    switch (update.phase) {
      case SendTransferUpdatePhase.completed:
        _completeTransfer(
          SendTransferResult(
            outcome: SendTransferOutcome.success,
            title: 'Sent',
            message: update.statusMessage,
          ),
        );
      case SendTransferUpdatePhase.cancelled:
        _completeTransfer(
          SendTransferResult(
            outcome: SendTransferOutcome.cancelled,
            title: 'Cancelled',
            message: update.statusMessage,
          ),
        );
      case SendTransferUpdatePhase.declined:
        _completeTransfer(
          SendTransferResult(
            outcome: SendTransferOutcome.declined,
            title: 'Declined',
            message: update.statusMessage,
          ),
        );
      case SendTransferUpdatePhase.failed:
        _completeTransfer(
          SendTransferResult(
            outcome: SendTransferOutcome.failed,
            title: update.error?.title ?? 'Send failed',
            message: update.error?.message ?? update.statusMessage,
          ),
          errorMessage: update.error?.message ?? update.statusMessage,
        );
      case SendTransferUpdatePhase.connecting:
      case SendTransferUpdatePhase.waitingForDecision:
      case SendTransferUpdatePhase.accepted:
      case SendTransferUpdatePhase.sending:
        break;
    }
  }

  void _handleTransferError(Object error, StackTrace stackTrace) {
    if (state.phase != SendSessionPhase.transferring || state.request == null) {
      return;
    }
    _completeTransfer(
      SendTransferResult(
        outcome: SendTransferOutcome.failed,
        title: 'Send failed',
        message: error.toString(),
      ),
      errorMessage: error.toString(),
    );
  }

  String _normalizedCode(String value) {
    return value.replaceAll(' ', '').trim().toUpperCase();
  }

  String _localDeviceTypeLabel() {
    if (kIsWeb) {
      return 'laptop';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 'phone';
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return 'laptop';
    }
  }

  bool _sameSendRequest(
    SendRequestData left,
    SendRequestData right,
  ) {
    return left.destinationMode == right.destinationMode &&
        listEquals(left.paths, right.paths) &&
        left.deviceName == right.deviceName &&
        left.deviceType == right.deviceType &&
        left.code == right.code &&
        left.ticket == right.ticket &&
        left.lanDestinationLabel == right.lanDestinationLabel &&
        left.serverUrl == right.serverUrl;
  }

  void _completeTransfer(
    SendTransferResult result, {
    String? errorMessage,
  }) {
    final request = state.request;
    if (request == null) {
      return;
    }

    state = SendState.result(
      items: state.items,
      destination: state.destination,
      request: request,
      result: result,
      errorMessage: errorMessage,
    );
    final subscription = _transferSubscription;
    _transferSubscription = null;
    unawaited(subscription?.cancel());
  }
}
