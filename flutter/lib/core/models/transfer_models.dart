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
    this.sizeBytes,
  });

  final String name;
  final String path;
  final String size;
  final TransferItemKind kind;
  final int? sizeBytes;
}

@immutable
class SendDestinationViewData {
  const SendDestinationViewData({
    required this.name,
    required this.kind,
    this.hint,
    this.lanTicket,
    this.lanFullname,
  });

  final String name;
  final SendDestinationKind kind;
  final String? hint;

  /// LAN send ticket from mDNS (`drift_core::lan`); when set, tap uses ticket send.
  final String? lanTicket;

  /// mDNS fullname for deduplication while scanning.
  final String? lanFullname;
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
    this.senderName = '',
  });

  final int itemCount;
  final String totalSize;
  final String code;
  final String expiresAt;
  final String destinationLabel;
  final String statusMessage;
  final String senderName;

  TransferSummaryViewData copyWith({
    int? itemCount,
    String? totalSize,
    String? code,
    String? expiresAt,
    String? destinationLabel,
    String? statusMessage,
    String? senderName,
  }) {
    return TransferSummaryViewData(
      itemCount: itemCount ?? this.itemCount,
      totalSize: totalSize ?? this.totalSize,
      code: code ?? this.code,
      expiresAt: expiresAt ?? this.expiresAt,
      destinationLabel: destinationLabel ?? this.destinationLabel,
      statusMessage: statusMessage ?? this.statusMessage,
      senderName: senderName ?? this.senderName,
    );
  }
}
