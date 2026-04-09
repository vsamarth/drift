import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../core/theme/drift_theme.dart';

class SendDropPanel extends StatefulWidget {
  const SendDropPanel({
    super.key,
    required this.onChooseFiles,
    required this.onDropPaths,
    required this.height,
    this.errorMessage,
  });

  final VoidCallback onChooseFiles;
  final ValueChanged<List<String>> onDropPaths;
  final double height;
  final String? errorMessage;

  @override
  State<SendDropPanel> createState() => _SendDropPanelState();
}

class _SendDropPanelState extends State<SendDropPanel> {
  bool _hovering = false;
  bool _dropHovering = false;

  @override
  Widget build(BuildContext context) {
    final isInteractive = _hovering || _dropHovering;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dropHovering = true),
      onDragExited: (_) => setState(() => _dropHovering = false),
      onDragDone: (details) {
        setState(() => _dropHovering = false);
        final paths = details.files
            .map((file) => file.path)
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
        widget.onDropPaths(paths);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onChooseFiles,
          child: AnimatedContainer(
            key: const ValueKey<String>('send-drop-surface'),
            duration: const Duration(milliseconds: 180),
            height: widget.height,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: isInteractive ? const Color(0xFFECEDED) : kBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isInteractive ? const Color(0xFFCED3D4) : kBorder,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 42),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.errorMessage?.trim().isNotEmpty == true) ...[
                    _SendSetupErrorBanner(message: widget.errorMessage!),
                    const SizedBox(height: 18),
                  ],
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isInteractive
                            ? const Color(0xFFF4F4F4)
                            : const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isInteractive
                              ? const Color(0xFFE2E2E2)
                              : const Color(0xFFE9E9E9),
                        ),
                      ),
                      child: Icon(
                        Icons.drive_folder_upload_outlined,
                        size: 18,
                        color: isInteractive
                            ? const Color(0xFF666666)
                            : kMuted.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Drop files to send',
                    style: driftSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: kInk,
                      letterSpacing: -0.7,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: OutlinedButton(
                      onPressed: widget.onChooseFiles,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.35),
                        foregroundColor: const Color(0xFF444444),
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 7,
                        ),
                        side: const BorderSide(
                          color: Color(0xFFE7E7E7),
                          width: 0.9,
                        ),
                        textStyle: driftSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Select files'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendSetupErrorBanner extends StatelessWidget {
  const _SendSetupErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFCC3333).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFCC3333).withValues(alpha: 0.2),
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
