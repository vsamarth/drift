import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/receive/receive_providers.dart';
import '../features/send/send_providers.dart';
import 'app_shell_state.dart';
import 'shell_routing.dart';

final appShellStateProvider = Provider<AppShellState>((ref) {
  return buildAppShellState(
    sendState: ref.watch(sendStateProvider),
    receiveState: ref.watch(receiveStateProvider),
  );
});

final shellViewProvider = Provider<ShellView>((ref) {
  return ref.watch(appShellStateProvider.select((state) => state.view));
});

final showShellBackButtonProvider = Provider<bool>((ref) {
  return ref.watch(
    appShellStateProvider.select((state) => state.showBackButton),
  );
});

final canGoBackProvider = Provider<bool>((ref) {
  return ref.watch(appShellStateProvider.select((state) => state.canGoBack));
});
