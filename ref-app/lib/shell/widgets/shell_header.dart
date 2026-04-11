import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/drift_theme.dart';
import '../../features/send/send_providers.dart';
import '../app_shell_providers.dart';

class ShellHeader extends ConsumerWidget {
  const ShellHeader({
    super.key,
    this.title,
    this.forceShowBackButton = false,
    this.onBackPressed,
  });

  final String? title;
  final bool forceShowBackButton;
  final VoidCallback? onBackPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showBackButton = ref.watch(showShellBackButtonProvider);
    final canGoBack = ref.watch(canGoBackProvider);
    if (!showBackButton && !forceShowBackButton) {
      return const SizedBox(height: 24);
    }

    final backAction =
        onBackPressed ??
        (canGoBack ? ref.read(sendControllerProvider.notifier).goBack : null);

    return Row(
      children: [
        IconButton(
          key: const ValueKey<String>('shell-back-button'),
          onPressed: backAction,
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 32),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kMuted),
        ),
        if (title != null) ...[
          const SizedBox(width: 6),
          Text(
            title!,
            style: driftSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: kInk,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ],
    );
  }
}
