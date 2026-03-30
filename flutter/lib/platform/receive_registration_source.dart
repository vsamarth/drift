import '../src/rust/api/receiver.dart' as rust_receiver;

class ReceiveRegistrationData {
  const ReceiveRegistrationData({required this.code, required this.expiresAt});

  final String code;
  final String expiresAt;
}

abstract class ReceiveRegistrationSource {
  /// [deviceName] must match the UI / wire identity (used for mDNS `label`).
  Future<ReceiveRegistrationData> ensureReceiverRegistration({
    required String deviceName,
  });
}

class LocalReceiveRegistrationSource implements ReceiveRegistrationSource {
  const LocalReceiveRegistrationSource();

  @override
  Future<ReceiveRegistrationData> ensureReceiverRegistration({
    required String deviceName,
  }) async {
    final registration = await rust_receiver.ensureReceiverRegistration(
      deviceName: deviceName,
    );
    return ReceiveRegistrationData(
      code: registration.code,
      expiresAt: registration.expiresAt,
    );
  }
}
