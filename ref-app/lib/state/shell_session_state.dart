import '../core/models/transfer_models.dart';
import '../src/rust/api/transfer.dart' as rust_transfer;

abstract class ShellSessionState {
  const ShellSessionState();
}

abstract class TransferResultSession extends ShellSessionState {
  const TransferResultSession({
    required this.items,
    required this.summary,
    this.metrics,
    this.plan,
    this.snapshot,
  });

  final List<TransferItemViewData> items;
  final TransferSummaryViewData summary;
  final List<TransferMetricRow>? metrics;
  final rust_transfer.TransferPlanData? plan;
  final rust_transfer.TransferSnapshotData? snapshot;
}

class IdleSession extends ShellSessionState {
  const IdleSession();
}
