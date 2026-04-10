import '../../state/app_identity.dart';

class SettingsState {
  const SettingsState({
    required this.identity,
    this.isSaving = false,
    this.errorMessage,
  });

  final DriftAppIdentity identity;
  final bool isSaving;
  final String? errorMessage;

  SettingsState copyWith({
    DriftAppIdentity? identity,
    bool? isSaving,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return SettingsState(
      identity: identity ?? this.identity,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}
