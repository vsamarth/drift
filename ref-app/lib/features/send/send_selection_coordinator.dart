import '../../core/models/transfer_models.dart';
import '../../platform/send_item_source.dart';
import 'send_selection_builder.dart';

abstract interface class SendSelectionHost {
  List<TransferItemViewData> get currentSendItems;

  void clearSendFlow();

  void beginSendInspection({required bool clearExistingItems});

  void applyPendingSendItems(List<TransferItemViewData> items);

  void applySelectedSendItems(List<TransferItemViewData> items);

  void finishSendInspection();

  void clearSendSetupError();

  void reportSendSelectionError(
    String userMessage,
    Object error,
    StackTrace stackTrace,
  );
}

class SendSelectionCoordinator {
  const SendSelectionCoordinator({
    required SendItemSource itemSource,
    required SendSelectionBuilder selectionBuilder,
  }) : _itemSource = itemSource,
       _selectionBuilder = selectionBuilder;

  final SendItemSource _itemSource;
  final SendSelectionBuilder _selectionBuilder;

  Future<void> pickSendItems(SendSelectionHost host) async {
    try {
      final items = await _itemSource.pickFiles();
      if (items.isEmpty) {
        return;
      }
      host.clearSendSetupError();
      host.beginSendInspection(clearExistingItems: true);
      host.applySelectedSendItems(items);
    } catch (error, stackTrace) {
      host.clearSendFlow();
      host.reportSendSelectionError(
        'Drift couldn\'t prepare the selected files.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> appendSendItemsFromPicker(SendSelectionHost host) async {
    final paths = await _itemSource.pickAdditionalPaths();
    if (paths.isEmpty) {
      return;
    }
    await appendDroppedSendItems(host, paths);
  }

  Future<void> acceptDroppedSendItems(
    SendSelectionHost host,
    List<String> paths,
  ) async {
    if (paths.isEmpty) {
      return;
    }
    host.beginSendInspection(clearExistingItems: true);
    try {
      final items = await _itemSource.loadPaths(paths);
      if (items.isEmpty) {
        host.clearSendFlow();
        return;
      }
      host.clearSendSetupError();
      host.applySelectedSendItems(items);
    } catch (error, stackTrace) {
      host.clearSendFlow();
      host.reportSendSelectionError(
        'Drift couldn\'t prepare the dropped files.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> appendDroppedSendItems(
    SendSelectionHost host,
    List<String> paths,
  ) async {
    if (paths.isEmpty) {
      return;
    }
    host.beginSendInspection(clearExistingItems: false);
    host.applyPendingSendItems(
      _selectionBuilder.appendPendingItems(
        existingItems: host.currentSendItems,
        incomingPaths: paths,
      ),
    );
    try {
      final items = await _itemSource.appendPaths(
        existingPaths: host.currentSendItems.map((item) => item.path).toList(
          growable: false,
        ),
        incomingPaths: paths,
      );
      if (items.isEmpty) {
        host.finishSendInspection();
        return;
      }
      host.clearSendSetupError();
      host.applySelectedSendItems(items);
    } catch (error, stackTrace) {
      host.finishSendInspection();
      host.reportSendSelectionError(
        'Drift couldn\'t add those files right now.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> removeSendItem(SendSelectionHost host, String path) async {
    if (path.trim().isEmpty || host.currentSendItems.isEmpty) {
      return;
    }
    host.beginSendInspection(clearExistingItems: false);
    try {
      final items = await _itemSource.removePath(
        existingPaths: host.currentSendItems.map((item) => item.path).toList(
          growable: false,
        ),
        removedPath: path,
      );
      if (items.isEmpty) {
        host.clearSendFlow();
        return;
      }
      host.clearSendSetupError();
      host.applySelectedSendItems(items);
    } catch (error, stackTrace) {
      host.finishSendInspection();
      host.reportSendSelectionError(
        'Drift couldn\'t update the selected files.',
        error,
        stackTrace,
      );
    }
  }
}
