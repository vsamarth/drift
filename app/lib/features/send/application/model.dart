import 'package:flutter/foundation.dart';

enum SendDestinationMode { none, code, nearby }

enum SendTransferOutcome { success, cancelled, declined, failed }

enum SendPickedFileKind { file, directory }

@immutable
class SendRequestData {
  const SendRequestData({
    required this.destinationMode,
    required this.paths,
    required this.deviceName,
    required this.deviceType,
    this.code,
    this.ticket,
    this.lanDestinationLabel,
    this.serverUrl,
  })  : assert(
          destinationMode != SendDestinationMode.code || code != null,
          'Code requests must include a code.',
        ),
        assert(
          destinationMode != SendDestinationMode.code || ticket == null,
          'Code requests must not include a ticket.',
        ),
        assert(
          destinationMode != SendDestinationMode.code ||
              lanDestinationLabel == null,
          'Code requests must not include a nearby destination label.',
        ),
        assert(
          destinationMode != SendDestinationMode.nearby || code == null,
          'Nearby requests must not include a code.',
        ),
        assert(
          destinationMode != SendDestinationMode.nearby || ticket != null,
          'Nearby requests must include a ticket.',
        ),
        assert(
          destinationMode != SendDestinationMode.nearby ||
              lanDestinationLabel != null,
          'Nearby requests must include a destination label.',
        );

  final SendDestinationMode destinationMode;
  final List<String> paths;
  final String deviceName;
  final String deviceType;
  final String? code;
  final String? ticket;
  final String? lanDestinationLabel;
  final String? serverUrl;
}

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
    required this.kind,
    required this.sizeBytes,
  });

  factory SendDraftItem.fromPickedFile(SendPickedFile file) {
    return SendDraftItem(
      path: file.path,
      name: file.name,
      kind: file.kind,
      sizeBytes: file.sizeBytes ?? BigInt.zero,
    );
  }

  final String path;
  final String name;
  final SendPickedFileKind kind;
  final BigInt sizeBytes;
}

@immutable
class SendPickedFile {
  const SendPickedFile({
    required this.path,
    required this.name,
    this.kind = SendPickedFileKind.file,
    this.sizeBytes,
  });

  factory SendPickedFile.fromPath(String path) {
    final uri = Uri.file(path);
    final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : path;
    return SendPickedFile(path: path, name: name.trim().isEmpty ? path : name);
  }

  factory SendPickedFile.directory(String path) {
    final uri = Uri.file(path);
    final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : path;
    return SendPickedFile(
      path: path,
      name: name.trim().isEmpty ? path : name,
      kind: SendPickedFileKind.directory,
    );
  }

  final String path;
  final String name;
  final SendPickedFileKind kind;
  final BigInt? sizeBytes;
}
