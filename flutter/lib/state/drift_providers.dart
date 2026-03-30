import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/receive_registration_source.dart';
import '../platform/send_item_source.dart';
import '../platform/send_transfer_source.dart';
import 'app_identity.dart';
import 'drift_controller.dart';
import 'receiver_service_controller.dart';

final driftAppIdentityProvider = Provider<DriftAppIdentity>(
  (ref) => buildDefaultDriftAppIdentity(),
);

final sendItemSourceProvider = Provider<SendItemSource>(
  (ref) => const LocalSendItemSource(),
);

final sendTransferSourceProvider = Provider<SendTransferSource>(
  (ref) => const LocalSendTransferSource(),
);

final receiveRegistrationSourceProvider = Provider<ReceiveRegistrationSource>(
  (ref) => const LocalReceiveRegistrationSource(),
);

final driftControllerProvider =
    ChangeNotifierProvider.autoDispose<DriftController>((ref) {
      final identity = ref.watch(driftAppIdentityProvider);
      final controller = DriftController(
        deviceName: identity.deviceName,
        deviceType: identity.deviceType,
        sendItemSource: ref.watch(sendItemSourceProvider),
        sendTransferSource: ref.watch(sendTransferSourceProvider),
        receiveRegistrationSource: ref.watch(receiveRegistrationSourceProvider),
        enableIdleReceiverRegistrationBootstrap: false,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final receiverServiceControllerProvider =
    ChangeNotifierProvider.autoDispose<ReceiverServiceController>((ref) {
      final identity = ref.watch(driftAppIdentityProvider);
      final controller = ReceiverServiceController(
        deviceName: identity.deviceName,
        deviceType: identity.deviceType,
        downloadRoot: identity.downloadRoot,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
