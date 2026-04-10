import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/drift_theme.dart';
import '../../application/state.dart';

class ReceiveIdleCard extends StatefulWidget {
  const ReceiveIdleCard({super.key, required this.state, this.onOpenSettings});

  final ReceiverIdleViewState state;
  final VoidCallback? onOpenSettings;

  @override
  State<ReceiveIdleCard> createState() => _ReceiveIdleCardState();
}

class _ReceiveIdleCardState extends State<ReceiveIdleCard> {
  bool _codeHovering = false;
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
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.state.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: driftSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: kInk,
                          letterSpacing: -0.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: badgeColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: badgeColor.withValues(alpha: 0.22),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              widget.state.badge.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: driftSans(
                                fontSize: 11.5,
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
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Text(
                            _copied ? 'Copied' : 'Receive code',
                            key: ValueKey<String>(
                              _copied ? 'copied-label' : 'receive-label',
                            ),
                            style: driftSans(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w500,
                              color: _copied
                                  ? const Color(0xFF5E9B70)
                                  : kMuted.withValues(alpha: 0.62),
                              letterSpacing: 0.18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _codeHovering = true),
                          onExit: (_) => setState(() => _codeHovering = false),
                          child: GestureDetector(
                            onTap: () => _copyCode(widget.state.clipboardCode),
                            child: AnimatedContainer(
                              key: const ValueKey<String>('idle-receive-code'),
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOutCubic,
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: _codeHovering
                                    ? Colors.white
                                    : const Color(0xFFFDFDFD),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _codeHovering
                                      ? const Color(0xFFCFCFCF)
                                      : const Color(0xFFD7D7D7),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: _codeHovering ? 0.028 : 0.018,
                                    ),
                                    blurRadius: _codeHovering ? 10 : 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  _formatCode(widget.state.code),
                                  style: driftMono(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF111111),
                                    letterSpacing: 2.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const ValueKey<String>('idle-settings-button'),
                      onPressed: widget.onOpenSettings ?? () {},
                      tooltip: 'Settings',
                      style: IconButton.styleFrom(
                        fixedSize: const Size(38, 38),
                        minimumSize: const Size(38, 38),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: const Color(0xFFFCFCFC),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFD7D7D7)),
                        ),
                      ),
                      icon: Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: kMuted.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
