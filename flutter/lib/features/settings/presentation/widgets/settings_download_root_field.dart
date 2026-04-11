import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';

class SettingsDownloadRootField extends StatelessWidget {
  const SettingsDownloadRootField({
    super.key,
    required this.controller,
    required this.onChoose,
  });

  final TextEditingController controller;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey<String>('settings-download-root-field'),
      controller: controller,
      readOnly: true,
      showCursor: false,
      onTap: onChoose,
      decoration: InputDecoration(
        hintText: '/Users/you/Downloads',
        suffixIconConstraints: const BoxConstraints(
          minWidth: 94,
          minHeight: 44,
        ),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: onChoose,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: kInk,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: kBorder),
              ),
            ),
            child: Text(
              'Choose',
              style: driftSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
