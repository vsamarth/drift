import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/drift_theme.dart';

class HeroCode extends StatefulWidget {
  const HeroCode({super.key, required this.code, required this.clipboardCode});
  final String code;
  final String clipboardCode;

  @override
  State<HeroCode> createState() => _HeroCodeState();
}

class _HeroCodeState extends State<HeroCode> {
  bool _copied = false;
  Timer? _timer;

  void _onCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.clipboardCode));
    await HapticFeedback.mediumImpact();
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final codeStr = widget.code;
    final displayCode = codeStr.length == 6 
        ? '${codeStr.substring(0, 3)}  ${codeStr.substring(3)}' 
        : codeStr;

    return GestureDetector(
      onTap: _onCopy,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _copied ? 'Copied to clipboard' : 'Tap to copy',
              key: ValueKey(_copied),
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _copied ? const Color(0xFF5E9B70) : kMuted.withValues(alpha: 0.5),
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              displayCode,
              style: driftMono(
                fontSize: 72,
                fontWeight: FontWeight.w800,
                color: kInk,
                letterSpacing: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
