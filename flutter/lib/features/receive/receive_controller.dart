import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/drift_providers.dart';
import 'receive_providers.dart';
import 'receive_state.dart';

class ReceiveController extends Notifier<ReceiveState> {
  @override
  ReceiveState build() {
    final appState = ref.watch(driftAppNotifierProvider);
    ref.watch(receiveServiceProvider);
    return ReceiveState.fromAppState(appState);
  }

  void acceptReceiveOffer() {
    ref.read(driftAppNotifierProvider.notifier).acceptReceiveOffer();
  }

  void declineReceiveOffer() {
    ref.read(driftAppNotifierProvider.notifier).declineReceiveOffer();
  }

  void cancelReceiveInProgress() {
    ref.read(driftAppNotifierProvider.notifier).cancelReceiveInProgress();
  }
}
