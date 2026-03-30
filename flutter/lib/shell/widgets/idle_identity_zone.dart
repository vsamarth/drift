import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';

class IdleIdentityZone extends StatefulWidget {
  const IdleIdentityZone({super.key, required this.controller});

  final DriftController controller;

  @override
  State<IdleIdentityZone> createState() => _IdleIdentityZoneState();
}

class _IdleIdentityZoneState extends State<IdleIdentityZone> {
  bool _codeHovering = false;
  bool _copied = false;
  Timer? _copiedResetTimer;

  IconData get _deviceIcon {
    return widget.controller.deviceType.toLowerCase() == 'phone'
        ? Icons.smartphone_rounded
        : Icons.laptop_mac_rounded;
  }

  String _formatCode(String raw) {
    if (raw.length != 6) return raw;
    return '${raw.substring(0, 3)} ${raw.substring(3)}';
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(
      ClipboardData(text: widget.controller.idleReceiveCode),
    );
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
    return Padding(
      key: const ValueKey<String>('idle-identity-zone'),
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  child: Center(
                    child: Icon(
                      _deviceIcon,
                      key: const ValueKey<String>('idle-device-icon'),
                      size: 18,
                      color: kInk.withValues(alpha: 0.88),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.controller.deviceName,
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
                              color: const Color(0xFF49B36C),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF49B36C,
                                  ).withValues(alpha: 0.22),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              widget.controller.idleReceiveStatus,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: driftSans(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: kMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
              const SizedBox(height: 3),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _codeHovering = true),
                onExit: (_) => setState(() => _codeHovering = false),
                child: GestureDetector(
                  onTap: _copyCode,
                  child: AnimatedContainer(
                    key: const ValueKey<String>('idle-receive-code'),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _codeHovering
                          ? const Color(0xFFFFFFFF)
                          : const Color(0xFFFDFDFD),
                      borderRadius: BorderRadius.circular(14),
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
                    child: Text(
                      _formatCode(widget.controller.idleReceiveCode),
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
            ],
          ),
        ],
      ),
    );
  }
}
