import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';

class ReceiveCodeField extends StatefulWidget {
  const ReceiveCodeField({
    super.key,
    required this.code,
    required this.onChanged,
    this.onSubmitted,
    this.hasError = false,
    this.fieldKey,
    this.hintText = 'Enter code',
    this.compact = false,
    this.understated = false,
  });

  final String code;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool hasError;
  final Key? fieldKey;
  final String hintText;
  final bool compact;
  final bool understated;

  @override
  State<ReceiveCodeField> createState() => _ReceiveCodeFieldState();
}

class _ReceiveCodeFieldState extends State<ReceiveCodeField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.code);
  }

  @override
  void didUpdateWidget(covariant ReceiveCodeField old) {
    super.didUpdateWidget(old);
    if (widget.code != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: widget.code,
        selection: TextSelection.collapsed(offset: widget.code.length),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const errorColor = Color(0xFFCC3333);
    final isSmall = widget.compact || widget.understated;

    return TextField(
      key: widget.fieldKey,
      controller: _ctrl,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textCapitalization: TextCapitalization.characters,
      style: driftMono(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.5,
        color: kInk,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        fillColor: widget.understated
            ? kSurface.withValues(alpha: 0.70)
            : (widget.compact ? kSurface2 : kSurface),
        contentPadding: isSmall
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
            : null,
        hintStyle: driftSans(
          color: kSubtle,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: widget.hasError
                ? errorColor
                : (isSmall ? kBorder.withValues(alpha: 0.62) : kBorder),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: widget.hasError ? errorColor : kAccentCyanStrong,
            width: isSmall ? 1.2 : 1.5,
          ),
        ),
      ),
    );
  }
}
