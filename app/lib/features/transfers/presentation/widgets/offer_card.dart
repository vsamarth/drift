import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.senderName,
    required this.onAccept,
    required this.onDecline,
  });

  final String senderName;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kFill,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Center(
        child: Container(
          width: 176,
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0E000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF49B36C).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.file_download_outlined,
                  size: 14,
                  color: Color(0xFF49B36C),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Incoming offer',
                style: driftSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                senderName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: driftSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ready to review',
                style: driftSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: kMuted,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDecline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF5F6368),
                        side: const BorderSide(color: Color(0xFFD7D7D7)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onAccept,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF49B36C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
