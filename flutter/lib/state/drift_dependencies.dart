import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/send_item_source.dart';
import '../platform/send_transfer_source.dart';
import 'app_identity.dart';
import 'nearby_discovery_source.dart';
import 'receiver_service_source.dart';
import 'settings_store.dart';

final driftSettingsStoreProvider = Provider<DriftSettingsStore>(
  (ref) => DriftSettingsStore.inMemory(),
);

final initialDriftAppIdentityProvider = Provider<DriftAppIdentity>(
  (ref) => buildDefaultDriftAppIdentity(),
);

final driftAppIdentityProvider = Provider<DriftAppIdentity>(
  (ref) => ref.watch(initialDriftAppIdentityProvider),
);

final sendItemSourceProvider = Provider<SendItemSource>(
  (ref) => const LocalSendItemSource(),
);

final sendTransferSourceProvider = Provider<SendTransferSource>(
  (ref) => const LocalSendTransferSource(),
);

final nearbyDiscoverySourceProvider = Provider<NearbyDiscoverySource>(
  (ref) => const LocalNearbyDiscoverySource(),
);

final receiverServiceSourceProvider = Provider<ReceiverServiceSource>(
  (ref) => const LocalReceiverServiceSource(),
);

final animateSendingConnectionProvider = Provider<bool>((ref) => true);

final enableIdleIncomingListenerProvider = Provider<bool>((ref) => true);
