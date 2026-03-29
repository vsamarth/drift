import 'package:flutter/material.dart';

enum TransferDirection { send, receive }

enum TransferStage {
  idle,
  collecting,
  ready,
  waiting,
  review,
  completed,
  error,
}

enum TransferItemKind { file, folder }

enum SendDestinationKind { laptop, phone, tablet }

@immutable
class TransferItemViewData {
  const TransferItemViewData({
    required this.name,
    required this.path,
    required this.size,
    required this.kind,
  });

  final String name;
  final String path;
  final String size;
  final TransferItemKind kind;
}

@immutable
class SendDestinationViewData {
  const SendDestinationViewData({
    required this.name,
    required this.kind,
    this.hint,
  });

  final String name;
  final SendDestinationKind kind;
  final String? hint;
}

@immutable
class TransferMetricRow {
  const TransferMetricRow({required this.label, required this.value});

  final String label;
  final String value;
}

@immutable
class TransferSummaryViewData {
  const TransferSummaryViewData({
    required this.itemCount,
    required this.totalSize,
    required this.code,
    required this.expiresAt,
    required this.destinationLabel,
    required this.statusMessage,
  });

  final int itemCount;
  final String totalSize;
  final String code;
  final String expiresAt;
  final String destinationLabel;
  final String statusMessage;

  TransferSummaryViewData copyWith({
    int? itemCount,
    String? totalSize,
    String? code,
    String? expiresAt,
    String? destinationLabel,
    String? statusMessage,
  }) {
    return TransferSummaryViewData(
      itemCount: itemCount ?? this.itemCount,
      totalSize: totalSize ?? this.totalSize,
      code: code ?? this.code,
      expiresAt: expiresAt ?? this.expiresAt,
      destinationLabel: destinationLabel ?? this.destinationLabel,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
