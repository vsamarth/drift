import 'package:flutter/foundation.dart';

enum SendTransferOutcome { success, cancelled, declined, failed }

@immutable
class SendTransferResult {
  const SendTransferResult({
    required this.outcome,
    required this.title,
    required this.message,
  });

  final SendTransferOutcome outcome;
  final String title;
  final String message;
}

@immutable
class SendDraftItem {
  const SendDraftItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final BigInt sizeBytes;
}

@immutable
class SendPickedFile {
  const SendPickedFile({
    required this.path,
    required this.name,
  });

  factory SendPickedFile.fromPath(String path) {
    final uri = Uri.file(path);
    final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : path;
    return SendPickedFile(
      path: path,
      name: name.trim().isEmpty ? path : name,
    );
  }

  final String path;
  final String name;
}
