import 'dart:collection';

import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';
import '../../application/manifest.dart';
import 'transfer_presentation_helpers.dart';

class ManifestTree extends StatelessWidget {
  const ManifestTree({
    super.key,
    required this.items,
  });

  final List<TransferManifestItem> items;

  @override
  Widget build(BuildContext context) {
    final tree = _buildTree(items);
    if (tree.children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No files', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in _orderedChildren(tree)) ...[
          _ManifestTreeNodeView(
            node: child,
            depth: 0,
            ancestorHasFollowingSiblings: const [],
          ),
        ],
      ],
    );
  }
}

class _ManifestTreeNodeView extends StatelessWidget {
  const _ManifestTreeNodeView({
    required this.node,
    required this.depth,
    required this.ancestorHasFollowingSiblings,
  });

  final _ManifestTreeNode node;
  final int depth;
  final List<bool> ancestorHasFollowingSiblings;

  @override
  Widget build(BuildContext context) {
    final compressed = _compressNode(node);
    final renderedNode = compressed.node;
    final isFolder = renderedNode is _ManifestTreeFolderNode;
    final labelStyle = driftSans(
      fontSize: isFolder ? 13.5 : 13,
      fontWeight: isFolder ? FontWeight.w600 : FontWeight.w500,
      color: isFolder ? kInk : kInk,
    );
    final sizeLabel = formatBytes(renderedNode.totalSizeBytes);
    final rowHeight = isFolder ? 28.0 : 26.0;
    final gutterWidth = depth == 0 ? 14.0 : depth * 12.0 + 14.0;
    final children = renderedNode is _ManifestTreeFolderNode
        ? _orderedChildren(renderedNode)
        : const <_ManifestTreeNode>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: isFolder ? 2 : 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: gutterWidth,
                height: rowHeight,
                child: CustomPaint(
                  painter: ManifestTreeConnectorPainter(
                    depth: depth,
                    ancestorHasFollowingSiblings: ancestorHasFollowingSiblings,
                    color: kBorder.withValues(alpha: 0.95),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Icon(
                  isFolder
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 18,
                  color: isFolder ? const Color(0xFF6C8590) : kMuted,
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: compressed.fullPath,
                  child: Text(
                    compressed.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 116,
                child: Text(
                  sizeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: driftSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: kMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < children.length; i++)
          _ManifestTreeNodeView(
            node: children[i],
            depth: depth + 1,
            ancestorHasFollowingSiblings: [
              ...ancestorHasFollowingSiblings,
              i != children.length - 1,
            ],
          ),
      ],
    );
  }
}

class _CompressedNode {
  const _CompressedNode({
    required this.node,
    required this.label,
    required this.fullPath,
  });

  final _ManifestTreeNode node;
  final String label;
  final String fullPath;
}

sealed class _ManifestTreeNode {
  _ManifestTreeNode({
    required this.name,
    required this.fullPath,
  });

  final String name;
  final String fullPath;

  BigInt get totalSizeBytes;
}

class _ManifestTreeFolderNode extends _ManifestTreeNode {
  _ManifestTreeFolderNode({
    required super.name,
    required super.fullPath,
  });

  final LinkedHashMap<String, _ManifestTreeNode> children = LinkedHashMap();
  BigInt _totalSizeBytes = BigInt.zero;

  @override
  BigInt get totalSizeBytes => _totalSizeBytes;

  void addSize(BigInt sizeBytes) {
    _totalSizeBytes += sizeBytes;
  }
}

class _ManifestTreeFileNode extends _ManifestTreeNode {
  _ManifestTreeFileNode({
    required super.name,
    required super.fullPath,
    required this.sizeBytes,
  });

  final BigInt sizeBytes;

  @override
  BigInt get totalSizeBytes => sizeBytes;
}

_ManifestTreeFolderNode _buildTree(List<TransferManifestItem> items) {
  final root = _ManifestTreeFolderNode(name: '', fullPath: '');

  for (final item in items) {
    final segments = item.path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      continue;
    }

    var folder = root;
    var currentPath = <String>[];
    final visitedFolders = <_ManifestTreeFolderNode>[root];

    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      currentPath = [...currentPath, segment];
      final isLeaf = index == segments.length - 1;
      if (isLeaf) {
        final file = _ManifestTreeFileNode(
          name: segment,
          fullPath: currentPath.join('/'),
          sizeBytes: item.sizeBytes,
        );
        folder.children[segment] = file;
      } else {
        final nextFolder = folder.children.putIfAbsent(
          segment,
          () => _ManifestTreeFolderNode(
            name: segment,
            fullPath: currentPath.join('/'),
          ),
        );
        folder = nextFolder as _ManifestTreeFolderNode;
        visitedFolders.add(folder);
      }
    }

    for (final ancestor in visitedFolders) {
      ancestor.addSize(item.sizeBytes);
    }
  }

  return root;
}

List<_ManifestTreeNode> _orderedChildren(_ManifestTreeFolderNode node) {
  final folders = <_ManifestTreeNode>[];
  final files = <_ManifestTreeNode>[];

  for (final child in node.children.values) {
    if (child is _ManifestTreeFolderNode) {
      folders.add(child);
    } else {
      files.add(child);
    }
  }

  folders.sort((left, right) => left.name.compareTo(right.name));
  files.sort((left, right) => left.name.compareTo(right.name));
  return [...folders, ...files];
}

class ManifestTreeConnectorPainter extends CustomPainter {
  ManifestTreeConnectorPainter({
    required this.depth,
    required this.ancestorHasFollowingSiblings,
    required this.color,
  });

  final int depth;
  final List<bool> ancestorHasFollowingSiblings;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final centerY = size.height / 2;

    for (var i = 0; i < ancestorHasFollowingSiblings.length; i++) {
      if (!ancestorHasFollowingSiblings[i]) {
        continue;
      }
      final x = i * 12.0 + 6.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    if (depth > 0) {
      final branchX = (depth - 1) * 12.0 + 6.0;
      canvas.drawLine(Offset(branchX, centerY), Offset(size.width, centerY), paint);
      canvas.drawCircle(Offset(branchX, centerY), 1.4, paint..style = PaintingStyle.fill);
    } else {
      canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paint);
      canvas.drawCircle(Offset(0, centerY), 1.4, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant ManifestTreeConnectorPainter oldDelegate) {
    return oldDelegate.depth != depth ||
        oldDelegate.ancestorHasFollowingSiblings != ancestorHasFollowingSiblings ||
        oldDelegate.color != color;
  }
}

_CompressedNode _compressNode(_ManifestTreeNode node) {
  if (node is! _ManifestTreeFolderNode || node.name.isEmpty) {
    return _CompressedNode(
      node: node,
      label: node.name,
      fullPath: node.fullPath,
    );
  }

  final labels = <String>[node.name];
  var current = node;

  while (true) {
    final children = _orderedChildren(current);
    if (children.length != 1) {
      break;
    }

    final onlyChild = children.single;
    if (onlyChild is! _ManifestTreeFolderNode) {
      break;
    }

    labels.add(onlyChild.name);
    current = onlyChild;
  }

  return _CompressedNode(
    node: current,
    label: labels.join(' / '),
    fullPath: labels.join('/'),
  );
}
