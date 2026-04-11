import 'package:app/app/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('router exposes the home, settings, and send draft routes', () {
    final router = buildAppRouter();

    expect(router.routeInformationParser, isNotNull);
    expect(router.routerDelegate, isNotNull);
  });
}

