import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/drift_theme.dart';

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
      onChanged: (val) {
        final upper = val.toUpperCase();
        if (upper != val) {
          _ctrl.value = TextEditingValue(
            text: upper,
            selection: TextSelection.collapsed(offset: upper.length),
          );
        }
        widget.onChanged(upper);
      },
      onSubmitted: widget.onSubmitted,
      textAlign: TextAlign.center,
      textCapitalization: TextCapitalization.characters,
      maxLength: 6,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
      ],
      style: driftMono(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 4.0,
        color: kInk,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        counterText: '',
        fillColor: widget.understated
            ? kSurface.withValues(alpha: 0.6)
            : (widget.compact ? kSurface2 : kSurface),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: driftSans(
          color: kSubtle,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: widget.hasError
                ? errorColor
                : (isSmall ? kBorder.withValues(alpha: 0.6) : kBorder),
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: widget.hasError ? errorColor : kAccentCyanStrong,
            width: 1.8,
          ),
        ),
      ),
    );
  }
}
