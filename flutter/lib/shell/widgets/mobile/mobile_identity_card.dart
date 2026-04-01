import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../../../core/theme/drift_theme.dart';

class MobileIdentityCard extends StatefulWidget {
  const MobileIdentityCard({
    super.key,
    required this.deviceName,
    required this.receiveCode,
    required this.status,
  });

  final String deviceName;
  final String receiveCode;
  final String status;

  @override
  State<MobileIdentityCard> createState() => _MobileIdentityCardState();
}

class _MobileIdentityCardState extends State<MobileIdentityCard> {
  bool _copied = false;
  Timer? _timer;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.receiveCode));
    _timer?.cancel();
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.deviceName,
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
                            decoration: const BoxDecoration(
                              color: Color(0xFF49B36C),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.status,
                            style: driftSans(
                              fontSize: 14,
                              color: kMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 1,
                            height: 12,
                            color: kBorder,
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.wifi_tethering_rounded,
                            size: 14,
                            color: kAccentCyanStrong,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Broadcasting',
                            style: driftSans(
                              fontSize: 14,
                              color: kAccentCyanStrong,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
              child: Row(
                children: [
                  Text(
                    _formatCode(widget.receiveCode),
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
                        ? const Icon(Icons.check_circle_outline_rounded,
                            color: Color(0xFF49B36C), key: ValueKey('done'))
                        : Icon(Icons.copy_rounded,
                            color: kMuted.withValues(alpha: 0.5),
                            key: const ValueKey('copy')),
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
