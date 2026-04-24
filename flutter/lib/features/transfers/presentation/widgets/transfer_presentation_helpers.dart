import 'package:flutter/material.dart';
import '../../../../theme/drift_theme.dart';
import '../../application/identity.dart';

export '../../application/format_utils.dart';

String displaySender(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Unknown sender' : trimmed;
}

String incomingSubtitle(int itemCount, String totalSize) {
  final fileWord = itemCount == 1 ? 'file' : 'files';
  return 'wants to send you $itemCount $fileWord ($totalSize)';
}

String fileCountLabel(int itemCount) {
  return itemCount == 1 ? '1 file' : '$itemCount files';
}

String deviceTypeLabel(DeviceType type) {
  return switch (type) {
    DeviceType.phone => 'phone',
    DeviceType.laptop => 'laptop',
  };
}

Widget buildSubtitleText(String text) {
  return Text(
    text,
    textAlign: TextAlign.center,
    style: driftSans(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: kMuted,
      height: 1.4,
    ),
  );
}

Widget buildSpeedLine({
  required String speedLabel,
  required String? etaLabel,
}) {
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: speedLabel,
          style: driftSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: kInk,
          ),
        ),
        if (etaLabel != null) ...[
          TextSpan(
            text: '  ·  ',
            style: driftSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: kSubtle,
            ),
          ),
          TextSpan(
            text: etaLabel,
            style: driftSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: kMuted,
            ),
          ),
        ],
      ],
    ),
    textAlign: TextAlign.center,
  );
}
