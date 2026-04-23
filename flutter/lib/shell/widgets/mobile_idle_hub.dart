import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/receive/application/state.dart';
import '../../theme/drift_theme.dart';

class MobileIdleHub extends ConsumerStatefulWidget {
  const MobileIdleHub({super.key, required this.state, this.onOpenSettings});

  final ReceiverIdleViewState state;
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<MobileIdleHub> createState() => _MobileIdleHubState();
}

class _MobileIdleHubState extends ConsumerState<MobileIdleHub> {
  bool _copied = false;
  Timer? _copiedResetTimer;

  String _formatCode(String raw) {
    if (raw.length != 6) return raw;
    return '${raw.substring(0, 3)} ${raw.substring(3)}';
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    _copiedResetTimer?.cancel();
    if (mounted) {
      setState(() => _copied = true);
    }
    _copiedResetTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeColor = widget.state.badge.color;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: kBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.state.deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: driftSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: kInk,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: badgeColor.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.state.badge.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: driftSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey<String>('mobile-idle-settings-button'),
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Settings',
                style: IconButton.styleFrom(
                  backgroundColor: kFill.withValues(alpha: 0.5),
                  foregroundColor: kInk,
                  iconSize: 20,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Tooltip(
            message: 'Tap to copy',
            child: InkWell(
              onTap: () => _copyCode(widget.state.clipboardCode),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                      child: Text(
                        _copied ? 'Copied' : 'Receive Code',
                        key: ValueKey(_copied),
                        style: driftSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _copied
                              ? const Color(0xFF5E9B70)
                              : kMuted.withValues(alpha: 0.62),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _formatCode(widget.state.code),
                      style: driftMono(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: kInk,
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
