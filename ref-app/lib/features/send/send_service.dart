import '../../platform/send_item_source.dart';
import '../../platform/send_transfer_source.dart';
import '../../state/nearby_discovery_source.dart';

class SendService {
  const SendService({
    required SendItemSource itemSource,
    required SendTransferSource transferSource,
    required NearbyDiscoverySource nearbyDiscoverySource,
  }) : _itemSource = itemSource,
       _transferSource = transferSource,
       _nearbyDiscoverySource = nearbyDiscoverySource;

  final SendItemSource _itemSource;
  final SendTransferSource _transferSource;
  final NearbyDiscoverySource _nearbyDiscoverySource;

  SendItemSource get itemSource => _itemSource;
  SendTransferSource get transferSource => _transferSource;
  NearbyDiscoverySource get nearbyDiscoverySource => _nearbyDiscoverySource;
}
