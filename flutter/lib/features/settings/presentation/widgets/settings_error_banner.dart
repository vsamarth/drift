import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';

class SettingsErrorBanner extends StatelessWidget {
  const SettingsErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFCC3333).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFCC3333).withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: Color(0xFFCC3333),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: driftSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: kInk,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
