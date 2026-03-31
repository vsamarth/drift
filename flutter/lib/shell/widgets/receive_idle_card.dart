import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/drift_theme.dart';
import '../../state/drift_providers.dart';

class ReceiveIdleCard extends ConsumerWidget {
  const ReceiveIdleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driftAppNotifierProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF4B98AA),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Incoming',
                style: driftSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: kMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Receive files',
            style: driftSans(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: kInk,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Incoming transfers will appear here automatically.',
            style: driftSans(fontSize: 13, color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: kSurface2,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: kBorder.withValues(alpha: 0.9)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_rounded,
                        size: 34,
                        color: kAccentCyanStrong,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Waiting for an incoming transfer',
                        textAlign: TextAlign.center,
                        style: driftSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: kInk,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Keep Drift open while another device sends files to this one.',
                        textAlign: TextAlign.center,
                        style: driftSans(
                          fontSize: 13,
                          color: kMuted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: kFill,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: kBorder),
                        ),
                        child: Text(
                          state.idleReceiveStatus,
                          style: driftSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: kMuted,
                            letterSpacing: 0.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
