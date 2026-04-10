import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'receive_feature.g.dart';

@riverpod
ReceiveFeatureVisuals receiveFeatureVisuals(Ref ref) {
  return const ReceiveFeatureVisuals(
    title: 'Receiver',
    accent: Color(0xFF2563EB),
    primaryTone: Color(0xFFEAF2FF),
    secondaryTone: Color(0xFFD9E8FF),
  );
}

@immutable
class ReceiveFeatureVisuals {
  const ReceiveFeatureVisuals({
    required this.title,
    required this.accent,
    required this.primaryTone,
    required this.secondaryTone,
  });

  final String title;
  final Color accent;
  final Color primaryTone;
  final Color secondaryTone;
}

class ReceiveFeaturePlaceholder extends ConsumerWidget {
  const ReceiveFeaturePlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visuals = ref.watch(receiveFeatureVisualsProvider);
    return _FeatureCard(
      title: visuals.title,
      accent: visuals.accent,
      primaryTone: visuals.primaryTone,
      secondaryTone: visuals.secondaryTone,
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.accent,
    required this.primaryTone,
    required this.secondaryTone,
  });

  final String title;
  final Color accent;
  final Color primaryTone;
  final Color secondaryTone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: primaryTone,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SkeletonLine(
                                  widthFactor: 0.58,
                                  height: 14,
                                  color: accent.withValues(alpha: 0.26),
                                ),
                                const SizedBox(height: 8),
                                _SkeletonLine(
                                  widthFactor: 0.92,
                                  height: 10,
                                  color: accent.withValues(alpha: 0.14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: secondaryTone,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const SizedBox(height: 78),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.widthFactor,
    required this.height,
    required this.color,
  });

  final double widthFactor;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}
