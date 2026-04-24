import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';

class SettingsSectionField extends StatelessWidget {
  const SettingsSectionField({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: driftSans(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: kInk,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}
