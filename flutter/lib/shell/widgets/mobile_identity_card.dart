import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../features/receive/application/state.dart';
import '../../../theme/drift_theme.dart';

class MobileIdentityCard extends StatefulWidget {
  const MobileIdentityCard({super.key, required this.state});

  final ReceiverIdleViewState state;

  @override
  State<MobileIdentityCard> createState() => _MobileIdentityCardState();
}

class _MobileIdentityCardState extends State<MobileIdentityCard> {
  bool _copied = false;
  Timer? _timer;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.state.clipboardCode));
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() => _copied = true);
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatCode(String code) {
    if (code.length != 6) return code;
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: kBorder, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.state.deviceName,
                  style: driftSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: widget.state.badge.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.state.badge.label,
                      style: driftSans(
                        fontSize: 14,
                        color: widget.state.badge.color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'RECEIVE CODE',
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: kMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _copy,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text(
                    _formatCode(widget.state.code),
                    style: driftMono(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: kInk,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _copied
                        ? const Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF49B36C),
                            key: ValueKey('done'),
                          )
                        : Icon(
                            Icons.copy_rounded,
                            color: kMuted.withValues(alpha: 0.5),
                            key: const ValueKey('copy'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
