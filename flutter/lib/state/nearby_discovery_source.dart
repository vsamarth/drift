import 'package:flutter/foundation.dart';

import '../core/models/transfer_models.dart';
import '../src/rust/api/lan.dart' as rust_lan;

abstract class NearbyDiscoverySource {
  Future<List<SendDestinationViewData>> scan({
    Duration timeout = const Duration(seconds: 12),
  });
}

class LocalNearbyDiscoverySource implements NearbyDiscoverySource {
  const LocalNearbyDiscoverySource();

  @override
  Future<List<SendDestinationViewData>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    debugPrint('[NearbyDiscoverySource] starting scan (timeout: ${timeout.inSeconds}s)');
    try {
      final raw = await rust_lan.scanNearbyReceivers(
        timeoutSecs: BigInt.from(timeout.inSeconds),
      );
      debugPrint('[NearbyDiscoverySource] found ${raw.length} raw receivers');
      
      final byFullname = <String, rust_lan.NearbyReceiverInfo>{};
      for (final receiver in raw) {
        debugPrint('[NearbyDiscoverySource]   - raw receiver: ${receiver.fullname} (label: ${receiver.label})');
        byFullname[receiver.fullname] = receiver;
      }
      final items = byFullname.values.map(_mapNearbyReceiver).toList();
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      debugPrint('[NearbyDiscoverySource] returning ${items.length} mapped destinations');
      return List<SendDestinationViewData>.unmodifiable(items);
    } catch (e, stack) {
      debugPrint('[NearbyDiscoverySource] scan failed: $e');
      debugPrintStack(stackTrace: stack);
      rethrow;
    }
  }
}

SendDestinationViewData _mapNearbyReceiver(
  rust_lan.NearbyReceiverInfo receiver,
) {
  final name = receiver.label.trim().isEmpty ? 'Nearby device' : receiver.label;
  return SendDestinationViewData(
    name: name,
    kind: SendDestinationKind.laptop,
    lanTicket: receiver.ticket,
    lanFullname: receiver.fullname,
  );
}
