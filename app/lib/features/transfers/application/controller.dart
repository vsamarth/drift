import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'service.dart';
import 'state.dart';

final transfersViewStateProvider = Provider<TransfersViewState>((ref) {
  final service = ref.watch(transfersServiceProvider);
  return TransfersViewState(
    phase: service.phase,
    incomingOffer: service.incomingOffer,
  );
});
