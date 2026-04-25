import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:app/features/receive/application/state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'model.dart';
import 'item_size.dart';
import 'directory_size.dart';
import '../../../platform/send_transfer_source.dart';
import '../../transfers/application/format_utils.dart';
import '../../settings/application/controller.dart';
import 'state.dart';
import 'transfer_state.dart';

part 'controller.g.dart';

@Riverpod(keepAlive: true)
class SendController extends _$SendController {
  StreamSubscription<SendTransferUpdate>? _transferSubscription;
  final Set<String> _pendingDirectorySizes = <String>{};
  DateTime? _transferStartTime;
  int _activeTransferToken = 0;

  @override
  SendState build() {
    ref.onDispose(_dispose);
    return const SendStateIdle();
  }

  void beginDraft(List<SendPickedFile> files) {
    unawaited(_cancelActiveTransfer());
    state = SendStateDrafting(
      items: files.map(SendDraftItem.fromPickedFile).toList(growable: false),
    );
    _hydrateDirectorySizes();
  }

  void appendDraftItems(List<SendPickedFile> files) {
    final currentState = state;
    if (currentState is! SendStateDrafting) {
      beginDraft(files);
      return;
    }

    state = currentState.copyWith(
      items: [
        ...currentState.items,
        ...files.map(SendDraftItem.fromPickedFile),
      ],
    );
    _hydrateDirectorySizes();
  }

  void removeDraftItem(String path) {
    final currentState = state;
    if (currentState is! SendStateDrafting) {
      return;
    }

    final nextItems = currentState.items
        .where((item) => item.path != path)
        .toList(growable: false);
    if (nextItems.isEmpty) {
      clearDraft();
      return;
    }

    state = currentState.copyWith(items: nextItems);
  }

  void updateDestinationCode(String value) {
    final currentState = state;
    if (currentState is! SendStateDrafting) {
      return;
    }

    final normalized = _normalizedCode(value);
    state = currentState.copyWith(
      destination: normalized.isEmpty
          ? const SendDestinationState.none()
          : SendDestinationState.code(normalized),
    );
  }

  void clearDestinationCode() {
    final currentState = state;
    if (currentState is! SendStateDrafting) {
      return;
    }

    state = currentState.copyWith(
      destination: const SendDestinationState.none(),
    );
  }

  void selectNearbyReceiver(NearbyReceiver receiver) {
    final currentState = state;
    if (currentState is! SendStateDrafting) {
      return;
    }

    state = currentState.copyWith(
      destination: SendDestinationState.nearby(
        ticket: receiver.ticket,
        lanDestinationLabel: receiver.label,
      ),
    );
  }

  void clearDraft() {
    unawaited(_cancelActiveTransfer());
    state = const SendStateIdle();
    _pendingDirectorySizes.clear();
  }

  SendRequestData? buildSendRequest() {
    final currentState = state;
    final (items, destination) = switch (currentState) {
      SendStateDrafting(:final items, :final destination) => (
        items,
        destination,
      ),
      SendStateTransferring(:final items, :final destination) => (
        items,
        destination,
      ),
      SendStateResult(:final items, :final destination) => (items, destination),
      SendStateIdle() => (null, null),
    };

    if (items == null || items.isEmpty || destination == null) {
      return null;
    }

    final settings = ref.read(settingsControllerProvider).settings;
    final paths = items.map((item) => item.path).toList(growable: false);

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

  bool canStartSend() => buildSendRequest() != null;

  void startTransfer(SendRequestData request) {
    final currentState = state;
    if (currentState is! SendStateDrafting) {
      return;
    }

    final validatedRequest = buildSendRequest();
    if (validatedRequest == null ||
        !_sameSendRequest(request, validatedRequest)) {
      return;
    }

    final transferSource = ref.read(sendTransferSourceProvider);
    final transferToken = ++_activeTransferToken;
    _transferStartTime = DateTime.now();
    state = SendStateTransferring(
      items: currentState.items,
      destination: currentState.destination,
      request: validatedRequest,
      transfer: _buildInitialTransferState(
        validatedRequest,
        currentState.items,
        currentState.resolvedDirectorySizes,
      ),
      resolvedDirectorySizes: currentState.resolvedDirectorySizes,
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
        .listen(
          (update) => _handleTransferUpdate(update, transferToken),
          onError: (Object error, StackTrace stackTrace) =>
              _handleTransferError(error, stackTrace, transferToken),
        );
  }

  void cancelTransfer() {
    unawaited(_cancelActiveTransfer());
    final currentState = state;
    if (currentState is SendStateTransferring) {
      state = SendStateDrafting(
        items: currentState.items,
        destination: currentState.destination,
        resolvedDirectorySizes: currentState.resolvedDirectorySizes,
      );
    }
  }

  void _hydrateDirectorySizes() {
    final currentState = state;
    final (items, resolvedSizes) = switch (currentState) {
      SendStateDrafting(:final items, :final resolvedDirectorySizes) => (
        items,
        resolvedDirectorySizes,
      ),
      SendStateTransferring(:final items, :final resolvedDirectorySizes) => (
        items,
        resolvedDirectorySizes,
      ),
      SendStateResult(:final items, :final resolvedDirectorySizes) => (
        items,
        resolvedDirectorySizes,
      ),
      SendStateIdle() => (null, null),
    };

    if (items == null || resolvedSizes == null) return;

    for (final item in items) {
      if (item.kind != SendPickedFileKind.directory) {
        continue;
      }
      if (resolvedSizes.containsKey(item.path) ||
          _pendingDirectorySizes.contains(item.path)) {
        continue;
      }
      _pendingDirectorySizes.add(item.path);
      unawaited(_resolveDirectorySize(item.path));
    }
  }

  Future<void> _resolveDirectorySize(String path) async {
    try {
      final sizeBytes = await ref
          .read(directorySizeCalculatorProvider)
          .sizeOfDirectory(path);

      final currentState = state;
      final (items, resolvedSizes) = switch (currentState) {
        SendStateDrafting(:final items, :final resolvedDirectorySizes) => (
          items,
          resolvedDirectorySizes,
        ),
        SendStateTransferring(:final items, :final resolvedDirectorySizes) => (
          items,
          resolvedDirectorySizes,
        ),
        SendStateResult(:final items, :final resolvedDirectorySizes) => (
          items,
          resolvedDirectorySizes,
        ),
        SendStateIdle() => (null, null),
      };

      if (items == null || resolvedSizes == null) return;

      final exists = items.any(
        (item) =>
            item.path == path && item.kind == SendPickedFileKind.directory,
      );
      if (!exists) {
        return;
      }

      final nextSizes = Map<String, BigInt>.from(resolvedSizes);
      nextSizes[path] = sizeBytes;
      final totalSize = totalDraftItemSize(items, nextSizes);

      if (currentState is SendStateDrafting) {
        state = currentState.copyWith(resolvedDirectorySizes: nextSizes);
      } else if (currentState is SendStateTransferring) {
        state = currentState.copyWith(
          resolvedDirectorySizes: nextSizes,
          transfer: currentState.transfer.copyWith(totalSize: totalSize),
        );
      } else if (currentState is SendStateResult) {
        state = currentState.copyWith(
          resolvedDirectorySizes: nextSizes,
          transfer: currentState.transfer.copyWith(totalSize: totalSize),
        );
      }
    } finally {
      _pendingDirectorySizes.remove(path);
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

  void _handleTransferUpdate(SendTransferUpdate update, int transferToken) {
    if (transferToken != _activeTransferToken) {
      return;
    }
    final currentState = state;
    if (currentState is! SendStateTransferring) {
      return;
    }

    final nextTransfer = currentState.transfer.copyWith(
      phase: switch (update.phase) {
        SendTransferUpdatePhase.connecting => SendTransferPhase.connecting,
        SendTransferUpdatePhase.waitingForDecision =>
          SendTransferPhase.waitingForDecision,
        SendTransferUpdatePhase.accepted => SendTransferPhase.accepted,
        SendTransferUpdatePhase.sending => SendTransferPhase.sending,
        SendTransferUpdatePhase.completed => SendTransferPhase.completed,
        SendTransferUpdatePhase.cancelled => SendTransferPhase.cancelled,
        SendTransferUpdatePhase.declined => SendTransferPhase.declined,
        SendTransferUpdatePhase.failed => SendTransferPhase.failed,
      },
      destinationLabel: update.destinationLabel,
      statusMessage: update.statusMessage,
      itemCount: update.itemCount,
      totalSize: update.totalSize,
      bytesSent: update.bytesSent,
      totalBytes: update.totalBytes,
      plan: update.plan ?? currentState.transfer.plan,
      snapshot: update.snapshot ?? currentState.transfer.snapshot,
      remoteDeviceType:
          update.remoteDeviceType ?? currentState.transfer.remoteDeviceType,
      error: update.error ?? currentState.transfer.error,
    );

    Duration? duration;
    String? avgSpeedLabel;
    if (update.phase == SendTransferUpdatePhase.completed ||
        update.phase == SendTransferUpdatePhase.failed ||
        update.phase == SendTransferUpdatePhase.cancelled ||
        update.phase == SendTransferUpdatePhase.declined) {
      if (_transferStartTime != null) {
        duration = DateTime.now().difference(_transferStartTime!);
        if (duration.inMilliseconds > 0) {
          final avgSpeed =
              (update.bytesSent.toDouble() / (duration.inMilliseconds / 1000.0))
                  .round();
          avgSpeedLabel = '${formatBytes(BigInt.from(avgSpeed))}/s';
        }
        _transferStartTime = null;
      }
    }

    switch (update.phase) {
      case SendTransferUpdatePhase.completed:
        _completeTransfer(
          SendTransferResult(
            outcome: SendTransferOutcome.success,
            title: 'Sent',
            message: update.statusMessage,
            duration: duration,
            averageSpeedLabel: avgSpeedLabel,
          ),
          transfer: nextTransfer,
        );
      case SendTransferUpdatePhase.cancelled:
        _completeTransfer(
          SendTransferResult(
            outcome: SendTransferOutcome.cancelled,
            title: 'Cancelled',
            message: update.statusMessage,
            duration: duration,
            averageSpeedLabel: avgSpeedLabel,
          ),
          transfer: nextTransfer,
        );
      case SendTransferUpdatePhase.declined:
        _completeTransfer(
          SendTransferResult(
            outcome: SendTransferOutcome.declined,
            title: 'Declined',
            message: update.statusMessage,
            duration: duration,
            averageSpeedLabel: avgSpeedLabel,
          ),
          transfer: nextTransfer,
        );
      case SendTransferUpdatePhase.failed:
        _completeTransfer(
          SendTransferResult(
            outcome: SendTransferOutcome.failed,
            title: update.error?.title ?? 'Send failed',
            message: update.error?.message ?? update.statusMessage,
            duration: duration,
            averageSpeedLabel: avgSpeedLabel,
          ),
          transfer: nextTransfer,
          errorMessage: update.error?.message ?? update.statusMessage,
        );
      case SendTransferUpdatePhase.connecting:
      case SendTransferUpdatePhase.waitingForDecision:
      case SendTransferUpdatePhase.accepted:
      case SendTransferUpdatePhase.sending:
        state = currentState.copyWith(transfer: nextTransfer);
    }
  }

  void _handleTransferError(
    Object error,
    StackTrace stackTrace,
    int transferToken,
  ) {
    if (transferToken != _activeTransferToken) {
      return;
    }
    final currentState = state;
    if (currentState is! SendStateTransferring) {
      return;
    }
    _completeTransfer(
      SendTransferResult(
        outcome: SendTransferOutcome.failed,
        title: 'Send failed',
        message: error.toString(),
      ),
      transfer: currentState.transfer.copyWith(
        phase: SendTransferPhase.failed,
        statusMessage: 'Send failed',
        error: null,
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

  bool _sameSendRequest(SendRequestData left, SendRequestData right) {
    return left.destinationMode == right.destinationMode &&
        listEquals(left.paths, right.paths) &&
        left.deviceName == right.deviceName &&
        left.deviceType == right.deviceType &&
        left.code == right.code &&
        left.ticket == right.ticket &&
        left.lanDestinationLabel == right.lanDestinationLabel &&
        left.serverUrl == right.serverUrl;
  }

  Future<void> _completeTransfer(
    SendTransferResult result, {
    required SendTransferState transfer,
    String? errorMessage,
  }) async {
    final currentState = state;
    if (currentState is! SendStateTransferring) {
      return;
    }

    if (result.outcome == SendTransferOutcome.success) {
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    state = SendStateResult(
      items: currentState.items,
      destination: currentState.destination,
      request: currentState.request,
      transfer: transfer,
      result: result,
      errorMessage: errorMessage,
      resolvedDirectorySizes: currentState.resolvedDirectorySizes,
    );
    final subscription = _transferSubscription;
    _transferSubscription = null;
    unawaited(subscription?.cancel());
  }

  SendTransferState _buildInitialTransferState(
    SendRequestData request,
    List<SendDraftItem> items,
    Map<String, BigInt> resolvedDirectorySizes,
  ) {
    final totalSize = totalDraftItemSize(items, resolvedDirectorySizes);
    return SendTransferState.connecting(
      destinationLabel:
          request.lanDestinationLabel ?? request.code ?? 'Recipient device',
      itemCount: BigInt.from(items.length),
      totalSize: totalSize,
    );
  }
}
