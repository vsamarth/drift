use std::collections::VecDeque;
use std::time::{Duration, Instant};

use super::types::{
    TransferFileId, TransferPhase, TransferPlan, TransferPlanFile, TransferSnapshot,
};

const DEFAULT_SPEED_WINDOW: Duration = Duration::from_secs(3);
const MIN_SPEED_SPAN: Duration = Duration::from_millis(750);

#[derive(Debug, Clone)]
pub struct SpeedCalculator {
    window: Duration,
    samples: VecDeque<(Instant, u64)>,
}

impl SpeedCalculator {
    pub fn new() -> Self {
        Self::with_window(DEFAULT_SPEED_WINDOW)
    }

    pub fn with_window(window: Duration) -> Self {
        Self {
            window,
            samples: VecDeque::new(),
        }
    }

    pub fn reset(&mut self) {
        self.samples.clear();
    }

    pub fn record(&mut self, now: Instant, bytes_transferred: u64) {
        self.samples.push_back((now, bytes_transferred));
        self.prune(now);
    }

    pub fn bytes_per_sec(&mut self, now: Instant) -> Option<u64> {
        self.prune(now);
        let (start_at, start_bytes) = *self.samples.front()?;
        let (end_at, end_bytes) = *self.samples.back()?;
        let elapsed = end_at.checked_duration_since(start_at)?;
        if elapsed < MIN_SPEED_SPAN {
            return None;
        }

        let delta_bytes = end_bytes.saturating_sub(start_bytes);
        if delta_bytes == 0 {
            return None;
        }

        Some((delta_bytes as f64 / elapsed.as_secs_f64()).round().max(1.0) as u64)
    }

    fn prune(&mut self, now: Instant) {
        while let Some((first_at, _)) = self.samples.front() {
            if now.duration_since(*first_at) <= self.window {
                break;
            }
            self.samples.pop_front();
        }
    }
}

#[derive(Debug, Clone)]
pub struct ProgressTracker {
    plan: TransferPlan,
    phase: TransferPhase,
    bytes_transferred: u64,
    speed: SpeedCalculator,
}

impl ProgressTracker {
    pub fn new(plan: TransferPlan) -> Self {
        Self {
            plan,
            phase: TransferPhase::Connecting,
            bytes_transferred: 0,
            speed: SpeedCalculator::new(),
        }
    }

    pub fn plan(&self) -> &TransferPlan {
        &self.plan
    }

    pub fn phase(&self) -> TransferPhase {
        self.phase
    }

    pub fn bytes_transferred(&self) -> u64 {
        self.bytes_transferred
    }

    pub fn set_phase(&mut self, phase: TransferPhase, now: Instant) {
        self.phase = phase;
        if !matches!(self.phase, TransferPhase::Transferring) {
            self.speed.reset();
        } else {
            self.speed.record(now, self.bytes_transferred);
        }
    }

    pub fn set_bytes_transferred(&mut self, bytes_transferred: u64, now: Instant) {
        self.bytes_transferred = bytes_transferred.min(self.plan.total_bytes);
        if matches!(self.phase, TransferPhase::Transferring) {
            self.speed.record(now, self.bytes_transferred);
        }
    }

    pub fn mark_finalizing(&mut self, now: Instant) {
        self.set_phase(TransferPhase::Finalizing, now);
    }

    pub fn mark_completed(&mut self, _now: Instant) {
        self.bytes_transferred = self.plan.total_bytes;
        self.phase = TransferPhase::Completed;
        self.speed.reset();
    }

    pub fn mark_cancelled(&mut self) {
        self.phase = TransferPhase::Cancelled;
        self.speed.reset();
    }

    pub fn mark_failed(&mut self) {
        self.phase = TransferPhase::Failed;
        self.speed.reset();
    }

    pub fn snapshot(&mut self, now: Instant) -> TransferSnapshot {
        let (completed_files, active_file_id, active_file_bytes) =
            self.derive_file_position(self.bytes_transferred);
        let bytes_per_sec = if matches!(self.phase, TransferPhase::Transferring) {
            self.speed.bytes_per_sec(now)
        } else {
            None
        };
        let eta_seconds = if matches!(self.phase, TransferPhase::Transferring) {
            bytes_per_sec.and_then(|rate| {
                let remaining = self.plan.total_bytes.saturating_sub(self.bytes_transferred);
                if rate == 0 || remaining == 0 {
                    None
                } else {
                    Some(((remaining as f64) / rate as f64).ceil() as u64)
                }
            })
        } else {
            None
        };

        TransferSnapshot {
            session_id: self.plan.session_id.clone(),
            phase: self.phase,
            total_files: self.plan.total_files,
            completed_files,
            total_bytes: self.plan.total_bytes,
            bytes_transferred: self.bytes_transferred,
            active_file_id,
            active_file_bytes,
            bytes_per_sec,
            eta_seconds,
        }
    }

    fn derive_file_position(
        &self,
        bytes_transferred: u64,
    ) -> (u32, Option<TransferFileId>, Option<u64>) {
        if self.plan.files.is_empty() {
            return (0, None, None);
        }

        let mut offset = 0_u64;
        let mut completed_files = 0_u32;
        for file in &self.plan.files {
            let end = offset.saturating_add(file.size);
            if file.size == 0 {
                if bytes_transferred >= offset {
                    completed_files = completed_files.saturating_add(1);
                    offset = end;
                    continue;
                }
                return (completed_files, Some(file.id), Some(0));
            }

            if bytes_transferred >= end {
                completed_files = completed_files.saturating_add(1);
                offset = end;
                continue;
            }

            if bytes_transferred >= offset {
                return (
                    completed_files,
                    Some(file.id),
                    Some(bytes_transferred.saturating_sub(offset)),
                );
            }

            return (completed_files, Some(file.id), Some(0));
        }

        (self.plan.total_files, None, None)
    }
}

pub(crate) fn transfer_plan_from_files(
    session_id: impl Into<String>,
    files: impl IntoIterator<Item = TransferPlanFile>,
) -> anyhow::Result<TransferPlan> {
    TransferPlan::try_new(session_id, files.into_iter().collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plan() -> TransferPlan {
        TransferPlan::try_new(
            "session-1",
            vec![
                TransferPlanFile {
                    id: 0,
                    path: "a.txt".to_owned(),
                    size: 10,
                },
                TransferPlanFile {
                    id: 1,
                    path: "empty.txt".to_owned(),
                    size: 0,
                },
                TransferPlanFile {
                    id: 2,
                    path: "b.txt".to_owned(),
                    size: 20,
                },
            ],
        )
        .unwrap()
    }

    #[test]
    fn speed_calculator_uses_sliding_window() {
        let mut speed = SpeedCalculator::with_window(Duration::from_secs(3));
        let start = Instant::now();
        speed.record(start, 0);
        assert_eq!(speed.bytes_per_sec(start), None);

        let later = start + Duration::from_secs(1);
        speed.record(later, 3_000);
        assert_eq!(speed.bytes_per_sec(later), Some(3_000));

        let much_later = later + Duration::from_secs(3);
        speed.record(much_later, 7_000);
        assert_eq!(speed.bytes_per_sec(much_later), Some(1_333));

        let newest = much_later + Duration::from_secs(1);
        speed.record(newest, 8_000);
        assert_eq!(speed.bytes_per_sec(newest), Some(1_000));
    }

    #[test]
    fn tracker_derives_active_file_from_aggregate_bytes() {
        let mut tracker = ProgressTracker::new(plan());
        let now = Instant::now();
        tracker.set_phase(TransferPhase::Transferring, now);
        tracker.set_bytes_transferred(12, now + Duration::from_secs(1));

        let snapshot = tracker.snapshot(now + Duration::from_secs(2));

        assert_eq!(snapshot.completed_files, 2);
        assert_eq!(snapshot.active_file_id, Some(2));
        assert_eq!(snapshot.active_file_bytes, Some(2));
        assert_eq!(snapshot.phase, TransferPhase::Transferring);
    }

    #[test]
    fn tracker_finalizing_clears_speed_and_eta() {
        let mut tracker = ProgressTracker::new(plan());
        let now = Instant::now();
        tracker.set_phase(TransferPhase::Transferring, now);
        tracker.set_bytes_transferred(10, now + Duration::from_secs(1));
        tracker.mark_finalizing(now + Duration::from_secs(2));

        let snapshot = tracker.snapshot(now + Duration::from_secs(3));

        assert_eq!(snapshot.phase, TransferPhase::Finalizing);
        assert_eq!(snapshot.bytes_transferred, 10);
        assert_eq!(snapshot.bytes_per_sec, None);
        assert_eq!(snapshot.eta_seconds, None);
    }

    #[test]
    fn tracker_finalization_preserves_transfer_totals() {
        let mut tracker = ProgressTracker::new(plan());
        let now = Instant::now();
        tracker.set_phase(TransferPhase::Transferring, now);
        tracker.set_bytes_transferred(30, now + Duration::from_secs(1));
        tracker.mark_finalizing(now + Duration::from_secs(2));

        let snapshot = tracker.snapshot(now + Duration::from_secs(3));

        assert_eq!(snapshot.phase, TransferPhase::Finalizing);
        assert_eq!(snapshot.bytes_transferred, 30);
        assert_eq!(snapshot.completed_files, 3);
        assert_eq!(snapshot.active_file_id, None);
        assert_eq!(snapshot.eta_seconds, None);
    }

    #[test]
    fn tracker_marks_completion_after_finalizing() {
        let mut tracker = ProgressTracker::new(plan());
        let now = Instant::now();
        tracker.set_phase(TransferPhase::Transferring, now);
        tracker.set_bytes_transferred(30, now + Duration::from_secs(1));
        tracker.mark_finalizing(now + Duration::from_secs(2));
        tracker.mark_completed(now + Duration::from_secs(3));

        let snapshot = tracker.snapshot(now + Duration::from_secs(4));

        assert_eq!(snapshot.phase, TransferPhase::Completed);
        assert_eq!(snapshot.completed_files, 3);
        assert_eq!(snapshot.bytes_transferred, 30);
        assert!(snapshot.is_terminal());
    }
}
