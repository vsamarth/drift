import 'package:flutter/material.dart';

import '../../core/models/transfer_models.dart';
import '../../core/theme/drift_theme.dart';
import '../../state/drift_controller.dart';

class ModeTabs extends StatelessWidget {
  const ModeTabs({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ModeTabButton(
              buttonKey: const ValueKey<String>('send-tab'),
              label: 'Send',
              selected: controller.mode == TransferDirection.send,
              onPressed: () => controller.setMode(TransferDirection.send),
            ),
          ),
          Expanded(
            child: ModeTabButton(
              buttonKey: const ValueKey<String>('receive-tab'),
              label: 'Receive',
              selected: controller.mode == TransferDirection.receive,
              onPressed: () => controller.setMode(TransferDirection.receive),
            ),
          ),
        ],
      ),
    );
  }
}

class ModeTabButton extends StatelessWidget {
  const ModeTabButton({
    super.key,
    this.buttonKey,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final Key? buttonKey;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? kSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: buttonKey,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              label,
              style: driftSans(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? kInk : kMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
