import 'package:flutter/foundation.dart';

enum TransferRole { sender, receiver }

enum DeviceType { phone, laptop }

@immutable
class TransferIdentity {
  const TransferIdentity({
    required this.role,
    required this.endpointId,
    required this.deviceName,
    required this.deviceType,
  });

  final TransferRole role;
  final String endpointId;
  final String deviceName;
  final DeviceType deviceType;

  String get displayName {
    final value = deviceName.trim();
    return value.isEmpty ? 'Unknown device' : value;
  }
}
