import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/drift_dependencies.dart';
import '../../state/receiver_service_source.dart';
import 'receive_controller.dart';
import 'receive_service.dart';
import 'receive_state.dart';

final receiveServiceProvider = Provider<ReceiveService>((ref) {
  return ReceiveService(ref.watch(receiverServiceSourceProvider));
});

final receiveStateProvider = NotifierProvider<ReceiveController, ReceiveState>(
  ReceiveController.new,
);

final receiveControllerProvider = receiveStateProvider;
