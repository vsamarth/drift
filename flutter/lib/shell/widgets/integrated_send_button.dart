import 'package:flutter/material.dart';
import '../../theme/drift_theme.dart';

class IntegratedSendButton extends StatelessWidget {
  const IntegratedSendButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Send Files or Folders'),
        style: FilledButton.styleFrom(
          backgroundColor: kInk,
          foregroundColor: kSurface,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: driftSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}
