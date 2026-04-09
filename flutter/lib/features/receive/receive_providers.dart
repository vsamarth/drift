import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/drift_dependencies.dart';
import '../../state/receiver_service_source.dart';

final receiveServiceSourceProvider = Provider<ReceiverServiceSource>((ref) {
  return ref.watch(receiverServiceSourceProvider);
});
