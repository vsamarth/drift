import 'dart:convert';

import 'package:animated_tree_view/animated_tree_view.dart';
import 'package:flutter/material.dart';

import '../../../../theme/drift_theme.dart';
import '../../application/manifest.dart';
import 'transfer_presentation_helpers.dart';

class ManifestTree extends StatelessWidget {
  const ManifestTree({super.key, required this.items});

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

    return TreeView.simpleTyped<_ManifestNodeData, TreeNode<_ManifestNodeData>>(
      tree: tree,
      showRootNode: false,
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      focusToNewNode: false,
      expansionBehavior: ExpansionBehavior.none,
      expansionIndicatorBuilder: noExpansionIndicatorBuilder,
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      indentation: Indentation(
        width: 10,
        style: IndentStyle.squareJoint,
        thickness: 1,
        color: kBorder.withValues(alpha: 0.75),
      ),
      onTreeReady: (controller) {
        // Only expand the top-level items by default.
        controller.expandAllChildren(controller.tree, recursive: false);
      },
      builder: (context, node) {
        final data = node.data!;
        final isTopLevel = node.level == 1;

        return InkWell(
          onTap: data.isFolder
              ? () => node.expansionNotifier.value = !node.isExpanded
              : null,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: isTopLevel ? 4 : 2.5,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Icon(
                    data.isFolder
                        ? (isTopLevel
                              ? Icons.folder_rounded
                              : Icons.folder_outlined)
                        : Icons.insert_drive_file_outlined,
                    size: 18,
                    color: data.isFolder
                        ? (isTopLevel
                              ? const Color(0xFF4A5D65)
                              : const Color(0xFF6C8590))
                        : kMuted,
                  ),
                ),
                Expanded(
                  child: Tooltip(
                    message: data.fullPath,
                    child: Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: driftSans(
                        fontSize: isTopLevel && data.isFolder
                            ? 14
                            : (data.isFolder ? 13.5 : 13),
                        fontWeight: isTopLevel && data.isFolder
                            ? FontWeight.w700
                            : (data.isFolder
                                  ? FontWeight.w600
                                  : FontWeight.w500),
                        color: kInk,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 108,
                  child: Text(
                    formatBytes(data.sizeBytes),
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
        );
      },
    );
  }
}

class _ManifestNodeData {
  _ManifestNodeData.folder({
    required this.label,
    required this.fullPath,
    required this.sizeBytes,
  }) : isFolder = true;

  _ManifestNodeData.file({
    required this.label,
    required this.fullPath,
    required this.sizeBytes,
  }) : isFolder = false;

  final String label;
  final String fullPath;
  final bool isFolder;
  BigInt sizeBytes;
}

class _PathEntry {
  const _PathEntry({
    required this.segments,
    required this.sizeBytes,
    required this.fullPath,
  });

  final List<String> segments;
  final BigInt sizeBytes;
  final String fullPath;
}

TreeNode<_ManifestNodeData> _buildTree(List<TransferManifestItem> items) {
  final root = TreeNode<_ManifestNodeData>.root(
    data: _ManifestNodeData.folder(
      label: '',
      fullPath: '',
      sizeBytes: BigInt.zero,
    ),
  );

  final entries = items
      .map(
        (item) => _PathEntry(
          segments: item.path
              .split('/')
              .where((segment) => segment.isNotEmpty)
              .toList(growable: false),
          sizeBytes: item.sizeBytes,
          fullPath: item.path,
        ),
      )
      .where((entry) => entry.segments.isNotEmpty)
      .toList(growable: false);

  root.addAll(_buildChildren(entries, prefix: const []));
  final rootChildren = root.children.values.cast<TreeNode<_ManifestNodeData>>();
  root.data!.sizeBytes = rootChildren.fold<BigInt>(
    BigInt.zero,
    (sum, node) => sum + node.data!.sizeBytes,
  );
  return root;
}

List<TreeNode<_ManifestNodeData>> _buildChildren(
  List<_PathEntry> entries, {
  required List<String> prefix,
}) {
  final folderGroups = <String, List<_PathEntry>>{};
  final fileEntries = <_PathEntry>[];

  for (final entry in entries) {
    final remaining = entry.segments
        .skip(prefix.length)
        .toList(growable: false);
    if (remaining.isEmpty) {
      continue;
    }

    if (remaining.length == 1) {
      fileEntries.add(entry);
    } else {
      folderGroups.putIfAbsent(remaining.first, () => []).add(entry);
    }
  }

  final children = <TreeNode<_ManifestNodeData>>[];

  final folderNames = folderGroups.keys.toList()..sort();
  for (final folderName in folderNames) {
    final childPrefix = [...prefix, folderName];
    final childEntries = folderGroups[folderName]!;
    final childNode = TreeNode<_ManifestNodeData>(
      key: _safeKey(childPrefix.join('/')),
      data: _ManifestNodeData.folder(
        label: folderName,
        fullPath: childPrefix.join('/'),
        sizeBytes: BigInt.zero,
      ),
    );
    final grandChildren = _buildChildren(childEntries, prefix: childPrefix);
    childNode.addAll(grandChildren);
    childNode.data!.sizeBytes = grandChildren.fold<BigInt>(
      BigInt.zero,
      (sum, node) => sum + node.data!.sizeBytes,
    );
    children.add(childNode);
  }

  fileEntries.sort((left, right) => left.fullPath.compareTo(right.fullPath));
  for (final entry in fileEntries) {
    final label = entry.segments.last;
    children.add(
      TreeNode<_ManifestNodeData>(
        key: _safeKey(entry.fullPath),
        data: _ManifestNodeData.file(
          label: label,
          fullPath: entry.fullPath,
          sizeBytes: entry.sizeBytes,
        ),
      ),
    );
  }

  return children;
}

String _safeKey(String value) => base64Url.encode(utf8.encode(value));
