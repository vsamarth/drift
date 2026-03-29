import 'package:flutter/material.dart';

import '../../state/drift_controller.dart';
import 'preview_list.dart';

class ReceiveReviewCard extends StatelessWidget {
  const ReceiveReviewCard({super.key, required this.controller});

  final DriftController controller;

  @override
  Widget build(BuildContext context) {
    final summary = controller.receiveSummary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Save these files?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '${summary?.itemCount ?? 0} items · ${summary?.totalSize ?? ''}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: PreviewList(
                items: controller.visibleReceiveItems,
                hiddenItemCount: controller.hiddenReceiveItemCount,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: controller.acceptReceiveOffer,
                  child: const Text('Save to Downloads'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: controller.declineReceiveOffer,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
