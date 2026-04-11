import '../../core/models/transfer_models.dart';
import 'send_flow_state.dart';
import 'send_state.dart';

String normalizeSendDestinationCode(String value) {
  return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

SendDraftSession? updateSendDestinationCode(
  SendDraftSession? draft,
  String value,
) {
  if (draft == null) {
    return null;
  }
  final normalized = normalizeSendDestinationCode(value);
  if (normalized == draft.destinationCode) {
    return draft;
  }
  return draft.copyWith(
    destinationCode: normalized,
    clearSelectedDestination: true,
  );
}

SendDraftSession? clearSendDestinationCode(SendDraftSession? draft) {
  if (draft == null) {
    return null;
  }
  return draft.copyWith(destinationCode: '');
}

SendDraftSession? selectNearbyDestination(
  SendDraftSession? draft,
  SendDestinationViewData destination,
) {
  if (draft == null) {
    return null;
  }
  if (draft.selectedDestination == destination) {
    return draft.copyWith(clearSelectedDestination: true);
  }
  return draft.copyWith(
    selectedDestination: destination,
    destinationCode: '',
  );
}

SendDraftSession restoreSendDraft(
  SendState state, {
  String destinationCode = '',
}) {
  return SendDraftSession(
    items: state.sendItems,
    isInspecting: false,
    nearbyDestinations: const [],
    nearbyScanInFlight: false,
    nearbyScanCompletedOnce: false,
    destinationCode: destinationCode,
  );
}
