import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'state.dart';

part 'controller.g.dart';

@riverpod
SendState sendController(Ref ref) {
  return const SendState.idle();
}
