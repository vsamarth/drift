import '../src/rust/api/receiver.dart' as rust_receiver;

class ReceiveRegistrationData {
  const ReceiveRegistrationData({required this.code, required this.expiresAt});

  final String code;
  final String expiresAt;
}

abstract class ReceiveRegistrationSource {
  Future<ReceiveRegistrationData> ensureIdleReceiver();
}

class LocalReceiveRegistrationSource implements ReceiveRegistrationSource {
  const LocalReceiveRegistrationSource();

  @override
  Future<ReceiveRegistrationData> ensureIdleReceiver() async {
    final registration = await rust_receiver.ensureIdleReceiver();
    return ReceiveRegistrationData(
      code: registration.code,
      expiresAt: registration.expiresAt,
    );
  }
}
