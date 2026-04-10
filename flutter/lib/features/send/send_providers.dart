export 'send_controller.dart' show SendController, sendControllerProvider;
export 'send_dependencies.dart'
    show
        nearbyDiscoverySourceProvider,
        sendItemSourceProvider,
        sendTransferSourceProvider;
export 'send_session_controller.dart' show sendSessionControllerProvider;

import 'send_controller.dart';

@Deprecated('Use sendControllerProvider instead.')
final sendStateProvider = sendControllerProvider;
