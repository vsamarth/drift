import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/send_item_source.dart';
import '../../platform/send_transfer_source.dart';
import '../../state/drift_dependencies.dart' as deps;
import '../../state/nearby_discovery_source.dart';
import 'send_controller.dart';
import 'send_service.dart';
import 'send_state.dart';

final sendItemSourceProvider = Provider<SendItemSource>((ref) {
  return ref.watch(deps.sendItemSourceProvider);
});

final sendTransferSourceProvider = Provider<SendTransferSource>((ref) {
  return ref.watch(deps.sendTransferSourceProvider);
});

final nearbyDiscoverySourceProvider = Provider<NearbyDiscoverySource>((ref) {
  return ref.watch(deps.nearbyDiscoverySourceProvider);
});

final sendServiceProvider = Provider<SendService>((ref) {
  return SendService(
    itemSource: ref.watch(sendItemSourceProvider),
    transferSource: ref.watch(sendTransferSourceProvider),
    nearbyDiscoverySource: ref.watch(nearbyDiscoverySourceProvider),
  );
});

final sendStateProvider = NotifierProvider<SendController, SendState>(
  SendController.new,
);

final sendControllerProvider = sendStateProvider;
