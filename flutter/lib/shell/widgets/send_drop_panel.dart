import 'package:flutter/material.dart';

import '../../core/theme/drift_theme.dart';
import 'drop_zone_border_painter.dart';

class SendDropPanel extends StatefulWidget {
  const SendDropPanel({
    super.key,
    required this.onChooseFiles,
    required this.height,
  });

  final VoidCallback onChooseFiles;
  final double height;

  @override
  State<SendDropPanel> createState() => _SendDropPanelState();
}

class _SendDropPanelState extends State<SendDropPanel> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onChooseFiles,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: widget.height,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovering ? const Color(0xFFF8F8F8) : kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovering ? kSubtle : kBorder,
            ),
          ),
          child: CustomPaint(
            painter: DropZoneBorderPainter(
              color: _hovering ? const Color(0xFF8C8C8C) : const Color(0xFFC8C8C8),
              strokeWidth: _hovering ? 1.75 : 1.35,
              dashLength: 7,
              gapLength: 5,
              radius: 12,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _hovering ? kFill : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kBorder),
                      ),
                      child: Icon(
                        Icons.upload_file_outlined,
                        size: 24,
                        color: _hovering ? kInk : kMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Drop files here',
                    style: driftSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: kInk,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Any file or folder — received instantly on the other device',
                    style: driftSans(
                      fontSize: 13,
                      color: kMuted,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: OutlinedButton(
                      onPressed: widget.onChooseFiles,
                      child: const Text('Choose files'),
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
