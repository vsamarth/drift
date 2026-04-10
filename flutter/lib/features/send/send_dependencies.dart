import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../platform/send_item_source.dart';
import '../../platform/send_transfer_source.dart';
import '../../state/drift_dependencies.dart' as deps;
import '../../state/nearby_discovery_source.dart';

part 'send_dependencies.g.dart';

@Riverpod(keepAlive: true)
SendItemSource sendItemSource(SendItemSourceRef ref) {
  return ref.watch(deps.sendItemSourceProvider);
}

@Riverpod(keepAlive: true)
SendTransferSource sendTransferSource(SendTransferSourceRef ref) {
  return ref.watch(deps.sendTransferSourceProvider);
}

@Riverpod(keepAlive: true)
NearbyDiscoverySource nearbyDiscoverySource(NearbyDiscoverySourceRef ref) {
  return ref.watch(deps.nearbyDiscoverySourceProvider);
}
