import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_providers.dart';

class ShellHeader extends ConsumerWidget {
  const ShellHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showBackButton = ref.watch(showShellBackButtonProvider);
    final canGoBack = ref.watch(canGoBackProvider);
    if (!showBackButton) {
      return const SizedBox(height: 24);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        key: const ValueKey<String>('shell-back-button'),
        onPressed: canGoBack
            ? ref.read(driftAppNotifierProvider.notifier).goBack
            : null,
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kMuted),
      ),
    );
  }
}
