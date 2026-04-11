import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'state.dart';

part 'controller.g.dart';

@riverpod
class SendController extends _$SendController {
  @override
  SendState build() {
    return const SendState.idle();
  }
}
