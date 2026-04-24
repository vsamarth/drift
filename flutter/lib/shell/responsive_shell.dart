import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/receive/application/controller.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

class ResponsiveShell extends ConsumerWidget {
  const ResponsiveShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We watch this here as requested by the plan, although the child shells 
    // also watch it for their own internal needs.
    ref.watch(receiverIdleViewStateProvider);

    final isMobile = Platform.isAndroid || Platform.isIOS;

    if (isMobile) {
      return const MobileShell();
    }

    return const DesktopShell();
  }
}
