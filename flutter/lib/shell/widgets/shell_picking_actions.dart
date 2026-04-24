import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../features/send/application/model.dart';
import '../../features/send/application/send_selection_picker.dart';

mixin ShellPickingActions {
  Future<void> openSelectedFiles(
    BuildContext context,
    List<SendPickedFile> files,
  ) async {
    context.goSendDraft(files: files);
  }

  Future<void> pickSelection(
    BuildContext context,
    WidgetRef ref,
    Future<List<SendPickedFile>> Function(SendSelectionPicker picker) pick,
  ) async {
    final pickerService = ref.read(sendSelectionPickerProvider);
    final files = await pick(pickerService);
    if (files.isEmpty) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    await openSelectedFiles(context, files);
  }

  Future<void> pickFiles(BuildContext context, WidgetRef ref) {
    return pickSelection(context, ref, (picker) => picker.pickFiles());
  }

  Future<void> pickFolder(BuildContext context, WidgetRef ref) {
    return pickSelection(context, ref, (picker) => picker.pickFolder());
  }
}
