import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import 'send_drop_zone_surface.dart';

class SendDropZone extends StatefulWidget {
  const SendDropZone({
    super.key,
    required this.onChooseFiles,
    required this.onDropPaths,
  });

  final Future<void> Function() onChooseFiles;
  final ValueChanged<List<String>> onDropPaths;

  @override
  State<SendDropZone> createState() => _SendDropZoneState();
}

class _SendDropZoneState extends State<SendDropZone> {
  bool _hovering = false;
  bool _dropHovering = false;

  @override
  Widget build(BuildContext context) {
    final isInteractive = _hovering || _dropHovering;

    return SizedBox.expand(
      child: DropTarget(
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
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await widget.onChooseFiles();
            },
            child: SendDropZoneSurface(
              isInteractive: isInteractive,
              onChooseFiles: widget.onChooseFiles,
            ),
          ),
        ),
      ),
    );
  }
}
