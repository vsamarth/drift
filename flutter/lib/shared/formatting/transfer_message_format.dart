bool isHumanReadableTransferMessage(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) {
    return false;
  }

  if (trimmed.contains('\n')) {
    return false;
  }
  if (trimmed.length > 140) {
    return false;
  }

  const noisyFragments = <String>[
    'Exception',
    'StackTrace',
    'socketexception',
    'typeerror',
  ];
  final lower = trimmed.toLowerCase();
  return !noisyFragments.any(
    (fragment) => lower.contains(fragment.toLowerCase()),
  );
}

String sendFailureMessage(String rawMessage) {
  if (isHumanReadableTransferMessage(rawMessage)) {
    return rawMessage;
  }
  return 'Drift couldn\'t finish sending the files. Try again.';
}

String receiveFailureMessage(String rawMessage) {
  if (isHumanReadableTransferMessage(rawMessage)) {
    return rawMessage;
  }
  return 'Drift couldn\'t save all incoming files successfully.';
}
