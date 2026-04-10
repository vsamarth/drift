import 'dart:async';

import 'package:drift_app/core/models/transfer_models.dart';
import 'package:drift_app/features/send/send_selection_coordinator.dart';
import 'package:drift_app/features/send/send_selection_builder.dart';
import 'package:drift_app/platform/send_item_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pickSendItems clears the setup error and applies picked items', () async {
    final host = FakeSendSelectionHost(
      items: [
        const TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
        ),
      ],
    );
    final source = FakeSendItemSource(
      pickFilesResult: const [
        TransferItemViewData(
          name: 'picked.txt',
          path: 'picked.txt',
          size: '24 KB',
          kind: TransferItemKind.file,
        ),
      ],
    );
    final coordinator = SendSelectionCoordinator(
      itemSource: source,
      selectionBuilder: const SendSelectionBuilder(),
    );

    await coordinator.pickSendItems(host);

    expect(host.clearSendSetupErrorCalls, 1);
    expect(host.beginSendInspectionCalls, 1);
    expect(host.beginSendInspectionClearExistingItems, isTrue);
    expect(host.appliedSelectedItems.single.path, 'picked.txt');
    expect(host.isInspecting, isFalse);
  });

  test('appendDroppedSendItems shows pending items before preview resolves', () async {
    final completer = Completer<List<TransferItemViewData>>();
    final host = FakeSendSelectionHost(
      items: [
        const TransferItemViewData(
          name: 'sample.txt',
          path: 'sample.txt',
          size: '18 KB',
          kind: TransferItemKind.file,
        ),
      ],
    );
    final source = FakeSendItemSource(appendPathsResult: completer.future);
    final coordinator = SendSelectionCoordinator(
      itemSource: source,
      selectionBuilder: const SendSelectionBuilder(),
    );

    final future = coordinator.appendDroppedSendItems(host, ['photos/']);
    expect(host.beginSendInspectionCalls, 1);
    expect(host.items.map((item) => item.path), ['sample.txt', 'photos/']);
    expect(host.isInspecting, isTrue);

    completer.complete([
      const TransferItemViewData(
        name: 'sample.txt',
        path: 'sample.txt',
        size: '18 KB',
        kind: TransferItemKind.file,
      ),
      const TransferItemViewData(
        name: 'photos',
        path: 'photos/',
        size: '12 items',
        kind: TransferItemKind.folder,
      ),
    ]);

    await future;

    expect(host.clearSendSetupErrorCalls, 1);
    expect(host.appliedSelectedItems.map((item) => item.path), [
      'sample.txt',
      'photos/',
    ]);
    expect(host.isInspecting, isFalse);
  });
}

class FakeSendSelectionHost implements SendSelectionHost {
  FakeSendSelectionHost({required List<TransferItemViewData> items})
    : items = List<TransferItemViewData>.of(items);

  List<TransferItemViewData> items;
  bool isInspecting = false;
  int clearSendFlowCalls = 0;
  int beginSendInspectionCalls = 0;
  bool? beginSendInspectionClearExistingItems;
  int finishSendInspectionCalls = 0;
  int applyPendingItemsCalls = 0;
  int clearSendSetupErrorCalls = 0;
  int reportSendSelectionErrorCalls = 0;
  final List<TransferItemViewData> appliedSelectedItems = [];
  final List<TransferItemViewData> appliedPendingItems = [];

  @override
  List<TransferItemViewData> get currentSendItems => items;

  @override
  void applyPendingSendItems(List<TransferItemViewData> items) {
    applyPendingItemsCalls += 1;
    appliedPendingItems
      ..clear()
      ..addAll(items);
    this.items = List<TransferItemViewData>.of(items);
  }

  @override
  void applySelectedSendItems(List<TransferItemViewData> items) {
    appliedSelectedItems
      ..clear()
      ..addAll(items);
    this.items = List<TransferItemViewData>.of(items);
    isInspecting = false;
  }

  @override
  void beginSendInspection({required bool clearExistingItems}) {
    beginSendInspectionCalls += 1;
    beginSendInspectionClearExistingItems = clearExistingItems;
    isInspecting = true;
    if (clearExistingItems) {
      items = <TransferItemViewData>[];
    }
  }

  @override
  void clearSendFlow() {
    clearSendFlowCalls += 1;
    items = <TransferItemViewData>[];
    isInspecting = false;
  }

  @override
  void clearSendSetupError() {
    clearSendSetupErrorCalls += 1;
  }

  @override
  void finishSendInspection() {
    finishSendInspectionCalls += 1;
    isInspecting = false;
  }

  @override
  void reportSendSelectionError(
    String userMessage,
    Object error,
    StackTrace stackTrace,
  ) {
    reportSendSelectionErrorCalls += 1;
  }
}

class FakeSendItemSource implements SendItemSource {
  FakeSendItemSource({
    this.pickFilesResult = const [],
    Future<List<TransferItemViewData>>? appendPathsResult,
  }) : _appendPathsResult = appendPathsResult ??
           Future<List<TransferItemViewData>>.value(const []);

  final List<TransferItemViewData> pickFilesResult;
  final Future<List<TransferItemViewData>> _appendPathsResult;

  @override
  Future<List<TransferItemViewData>> appendPaths({
    required List<String> existingPaths,
    required List<String> incomingPaths,
  }) {
    return _appendPathsResult;
  }

  @override
  Future<List<TransferItemViewData>> loadPaths(List<String> paths) async {
    return const [];
  }

  @override
  Future<List<TransferItemViewData>> pickAdditionalFiles({
    required List<String> existingPaths,
  }) async {
    return const [];
  }

  @override
  Future<List<String>> pickAdditionalPaths() async {
    return const [];
  }

  @override
  Future<List<TransferItemViewData>> pickFiles() async {
    return pickFilesResult;
  }

  @override
  Future<List<TransferItemViewData>> removePath({
    required List<String> existingPaths,
    required String removedPath,
  }) async {
    return const [];
  }
}
