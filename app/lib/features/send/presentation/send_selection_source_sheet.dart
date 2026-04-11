import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/drift_theme.dart';

Future<void> showSendSelectionSourceSheet(
  BuildContext context, {
  required FutureOr<void> Function() onChooseFiles,
  required FutureOr<void> Function() onChooseFolder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return SendSelectionSourceSheet(
        onChooseFiles: onChooseFiles,
        onChooseFolder: onChooseFolder,
      );
    },
  );
}

class SendSelectionSourceSheet extends StatelessWidget {
  const SendSelectionSourceSheet({
    super.key,
    required this.onChooseFiles,
    required this.onChooseFolder,
  });

  final FutureOr<void> Function() onChooseFiles;
  final FutureOr<void> Function() onChooseFolder;

  void _handleSelection(
    BuildContext context,
    FutureOr<void> Function() callback,
  ) {
    Navigator.of(context).pop();
    unawaited(Future<void>.sync(callback));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    'Select from',
                    style: driftSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kMuted,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                _SelectionActionTile(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'Files',
                  onTap: () => _handleSelection(context, onChooseFiles),
                ),
                _SelectionActionTile(
                  icon: Icons.folder_outlined,
                  label: 'Folder',
                  onTap: () => _handleSelection(context, onChooseFolder),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionActionTile extends StatelessWidget {
  const _SelectionActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(icon, color: kInk),
      title: Text(
        label,
        style: driftSans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: kInk,
        ),
      ),
      onTap: onTap,
    );
  }
}
