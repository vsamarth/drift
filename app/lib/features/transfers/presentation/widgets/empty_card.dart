import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';

class EmptyTransfersCard extends StatelessWidget {
  const EmptyTransfersCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kFill,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: kSubtle.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No offers yet',
              style: driftSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kInk,
                letterSpacing: -0.15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Incoming offers will appear here.',
              textAlign: TextAlign.center,
              style: driftSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: kMuted,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
