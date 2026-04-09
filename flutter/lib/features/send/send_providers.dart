import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/send_item_source.dart';
import '../../platform/send_transfer_source.dart';
import '../../state/drift_dependencies.dart' as deps;
import '../../state/nearby_discovery_source.dart';

final sendItemSourceProvider = Provider<SendItemSource>((ref) {
  return ref.watch(deps.sendItemSourceProvider);
});

final sendTransferSourceProvider = Provider<SendTransferSource>((ref) {
  return ref.watch(deps.sendTransferSourceProvider);
});

final nearbyDiscoverySourceProvider = Provider<NearbyDiscoverySource>((ref) {
  return ref.watch(deps.nearbyDiscoverySourceProvider);
});
