import 'package:flutter/material.dart';
import '../../features/receive/application/state.dart';
import '../../theme/drift_theme.dart';

class IdentityHeader extends StatelessWidget {
  const IdentityHeader({super.key, required this.state, this.onOpenSettings});

  final ReceiverIdleViewState state;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.deviceName,
                style: driftSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: state.badge.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    state.badge.label,
                    style: driftSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: state.badge.color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.tune_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: kMuted,
          ),
        ),
      ],
    );
  }
}
