import 'package:drift_app/state/receiver_service_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receiver badge states are color coded', () {
    expect(
      const ReceiverBadgeState.unavailable().statusColor,
      const Color(0xFF8A8A8A),
    );
    expect(
      const ReceiverBadgeState.registering().statusColor,
      const Color(0xFFD4A824),
    );
    expect(
      const ReceiverBadgeState(
        code: 'ABC123',
        status: 'Ready',
        phase: ReceiverBadgePhase.ready,
      ).statusColor,
      const Color(0xFF49B36C),
    );
  });
}
