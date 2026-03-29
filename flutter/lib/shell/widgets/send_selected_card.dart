import 'package:flutter/material.dart';

import '../../state/drift_controller.dart';
import 'preview_list.dart';
import 'shell_surface_card.dart';

class SendSelectedCard extends StatelessWidget {
  const SendSelectedCard({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final count = controller.sendItems.length;

    return ShellSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 1 ? '1 item ready' : '$count items ready',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Create a code to send them',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          PreviewList(
            items: controller.visibleSendItems,
            hiddenItemCount: controller.hiddenSendItemCount,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: controller.generateOffer,
                  child: const Text('Create code'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: controller.clearSendFlow,
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
