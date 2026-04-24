import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'service.dart';
import 'state.dart';

final transferReviewAnimationProvider = Provider<bool>((ref) => true);

final transfersViewStateProvider = Provider<TransferSessionState>((ref) {
  final service = ref.watch(transfersServiceProvider);
  return service;
});
