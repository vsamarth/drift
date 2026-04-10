import 'package:flutter/material.dart';

import '../features/receive/feature.dart';
import '../features/send/send_feature.dart';

class DriftShell extends StatelessWidget {
  const DriftShell({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFC),
              Color(0xFFF1F5F9),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: const [
                Expanded(
                  flex: 5,
                  child: ReceiveFeature(),
                ),
                SizedBox(height: 14),
                Expanded(
                  flex: 5,
                  child: SendFeaturePlaceholder(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
