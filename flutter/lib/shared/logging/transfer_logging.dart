import 'package:flutter/foundation.dart';

void logTransferError({
  required String scope,
  required String action,
  required Object error,
  StackTrace? stackTrace,
}) {
  debugPrint('[drift/$scope] $action failed: $error');
  if (stackTrace != null) {
    debugPrintStack(stackTrace: stackTrace);
  }
}

void logTransferTerminalOutcome({
  required String scope,
  required String phase,
  String? senderName,
  String? destinationLabel,
  String? statusMessage,
  String? errorMessage,
}) {
  final buffer = StringBuffer('[drift/$scope] transfer $phase');
  final normalizedSender = senderName?.trim();
  if (normalizedSender?.isNotEmpty == true) {
    buffer.write(' sender="$normalizedSender"');
  }
  final normalizedDestination = destinationLabel?.trim();
  if (normalizedDestination?.isNotEmpty == true) {
    buffer.write(' destination="$normalizedDestination"');
  }
  final normalizedStatus = statusMessage?.trim();
  if (normalizedStatus?.isNotEmpty == true) {
    buffer.write(' status="$normalizedStatus"');
  }
  final normalizedError = errorMessage?.trim();
  if (normalizedError?.isNotEmpty == true) {
    buffer.write(' error="$normalizedError"');
  }
  debugPrint(buffer.toString());
}
