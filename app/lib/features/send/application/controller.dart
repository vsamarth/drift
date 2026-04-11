import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'model.dart';
import 'state.dart';

part 'controller.g.dart';

@Riverpod(keepAlive: true)
class SendController extends _$SendController {
  @override
  SendState build() {
    return const SendState.idle();
  }

  void beginDraft(List<SendPickedFile> files) {
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
      items: [
        ...state.items,
        ...files.map(SendDraftItem.fromPickedFile),
      ],
      destination: state.destination,
    );
  }

  void removeDraftItem(String path) {
    if (state.phase != SendSessionPhase.drafting) {
      return;
    }

    final nextItems = state.items.where((item) => item.path != path).toList(
      growable: false,
    );
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

    state = SendState.drafting(
      items: state.items,
      destination: value,
    );
  }

  void clearDestinationCode() {
    if (state.phase != SendSessionPhase.drafting) {
      return;
    }

    state = SendState.drafting(
      items: state.items,
      destination: null,
    );
  }

  void clearDraft() {
    state = const SendState.idle();
  }
}
