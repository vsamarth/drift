import 'dart:convert';

import 'error.dart';

class UserFacingBridgeError implements Exception {
  const UserFacingBridgeError(this.error);

  final UserFacingErrorData error;

  @override
  String toString() =>
      'UserFacingBridgeError(${error.kind.name}: ${error.message})';
}

UserFacingBridgeError? tryParseUserFacingBridgeError(Object error) {
  final raw = error.toString();
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }

  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final kindValue = decoded['kind'];
    if (kindValue is! String) {
      return null;
    }

    return UserFacingBridgeError(
      UserFacingErrorData(
        kind: _decodeKind(kindValue),
        title: decoded['title'] as String? ?? 'Something went wrong',
        message: decoded['message'] as String? ?? raw,
        recovery: decoded['recovery'] as String?,
        retryable: decoded['retryable'] as bool? ?? false,
      ),
    );
  } catch (_) {
    return null;
  }
}

UserFacingErrorKindData _decodeKind(String value) {
  return switch (value) {
    'InvalidInput' => UserFacingErrorKindData.invalidInput,
    'PairingUnavailable' => UserFacingErrorKindData.pairingUnavailable,
    'PeerDeclined' => UserFacingErrorKindData.peerDeclined,
    'NetworkUnavailable' => UserFacingErrorKindData.networkUnavailable,
    'ConnectionLost' => UserFacingErrorKindData.connectionLost,
    'PermissionDenied' => UserFacingErrorKindData.permissionDenied,
    'FileConflict' => UserFacingErrorKindData.fileConflict,
    'ProtocolIncompatible' => UserFacingErrorKindData.protocolIncompatible,
    'Cancelled' => UserFacingErrorKindData.cancelled,
    _ => UserFacingErrorKindData.internal,
  };
}
