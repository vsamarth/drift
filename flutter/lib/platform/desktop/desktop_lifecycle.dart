import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/receive/application/service.dart';

class DesktopLifecycle extends ConsumerStatefulWidget {
  const DesktopLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopLifecycle> createState() => _DesktopLifecycleState();
}

class _DesktopLifecycleState extends ConsumerState<DesktopLifecycle>
    with WindowListener, TrayListener {
  static const _showWindowKey = 'show_window';
  static const _quitKey = 'quit';

  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    if (!_isDesktop) {
      return;
    }
    windowManager.addListener(this);
    trayManager.addListener(this);
    unawaited(_initializeDesktopLifecycle());
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _initializeDesktopLifecycle() async {
    await windowManager.setPreventClose(true);
    await trayManager.setIcon(_trayIconPath);
    await trayManager.setToolTip('Drift is listening for file transfers');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _showWindowKey, label: 'Open Drift'),
          MenuItem.separator(),
          MenuItem(key: _quitKey, label: 'Quit Drift'),
        ],
      ),
    );
  }

  @override
  void onWindowClose() {
    unawaited(_hideInsteadOfClosing());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showDriftWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _showWindowKey:
        unawaited(showDriftWindow());
        break;
      case _quitKey:
        unawaited(_quitApp());
        break;
    }
  }

  Future<void> _hideInsteadOfClosing() async {
    if (_quitting) {
      return;
    }
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  Future<void> _quitApp() async {
    _quitting = true;
    await ref.read(receiverServiceSourceProvider).shutdown();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showDriftWindow() async {
  if (!_isDesktop) {
    return;
  }
  await windowManager.show();
  await windowManager.restore();
  await windowManager.focus();
}

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

String get _trayIconPath {
  if (Platform.isWindows) {
    return 'windows/runner/resources/app_icon.ico';
  }
  return 'assets/logo.png';
}
