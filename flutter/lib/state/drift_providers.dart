import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/shell_routing.dart';
import 'drift_app_notifier.dart';
import 'drift_app_state.dart';
import 'receiver_service_source.dart';

export 'drift_dependencies.dart';

final driftAppNotifierProvider =
    NotifierProvider<DriftAppNotifier, DriftAppState>(DriftAppNotifier.new);

final shellViewProvider = Provider<ShellView>(
  (ref) =>
      ref.watch(driftAppNotifierProvider.select((state) => state.shellView)),
);

final showShellBackButtonProvider = Provider<bool>(
  (ref) => ref.watch(
    driftAppNotifierProvider.select((state) => state.showShellBackButton),
  ),
);

final canGoBackProvider = Provider<bool>(
  (ref) =>
      ref.watch(driftAppNotifierProvider.select((state) => state.canGoBack)),
);

final idleBadgeProvider = Provider<ReceiverBadgeState>(
  (ref) => ref.watch(
    driftAppNotifierProvider.select((state) => state.receiverBadge),
  ),
);

final sendDraftSessionProvider = Provider<SendDraftSession?>((ref) {
  final session = ref.watch(
    driftAppNotifierProvider.select((state) => state.session),
  );
  return session is SendDraftSession ? session : null;
});

final sendTransferSessionProvider = Provider<SendTransferSession?>((ref) {
  final session = ref.watch(
    driftAppNotifierProvider.select((state) => state.session),
  );
  return session is SendTransferSession ? session : null;
});

final sendResultSessionProvider = Provider<SendResultSession?>((ref) {
  final session = ref.watch(
    driftAppNotifierProvider.select((state) => state.session),
  );
  return session is SendResultSession ? session : null;
});

final receiveEntrySessionProvider = Provider<ReceiveEntrySession?>((ref) {
  final session = ref.watch(
    driftAppNotifierProvider.select((state) => state.session),
  );
  return session is ReceiveEntrySession ? session : null;
});

final receiveOfferSessionProvider = Provider<ReceiveOfferSession?>((ref) {
  final session = ref.watch(
    driftAppNotifierProvider.select((state) => state.session),
  );
  return session is ReceiveOfferSession ? session : null;
});

final receiveTransferSessionProvider = Provider<ReceiveTransferSession?>((ref) {
  final session = ref.watch(
    driftAppNotifierProvider.select((state) => state.session),
  );
  return session is ReceiveTransferSession ? session : null;
});

final receiveResultSessionProvider = Provider<ReceiveResultSession?>((ref) {
  final session = ref.watch(
    driftAppNotifierProvider.select((state) => state.session),
  );
  return session is ReceiveResultSession ? session : null;
});
