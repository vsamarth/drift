use std::sync::Arc;

use drift_core::protocol::{Identity, TransferRole};
use drift_core::transfer::{
    SendRequest, Sender, SenderEvent as CoreSenderEvent, TransferOutcome as CoreTransferOutcome,
    TransferPlan,
};
use iroh::{Endpoint, RelayMode, endpoint::presets};
use rand::random;
use tokio::sync::{Mutex, mpsc, oneshot, watch};
use tokio_stream::StreamExt;
use tokio_stream::wrappers::UnboundedReceiverStream;

use crate::error::{AppError, AppResult, UserFacingError, UserFacingErrorKind};
use crate::types::{SendEvent, SendPhase};

use super::destination::SendDestination;
use super::destination::{
    display_destination_label, is_receiver_decline_cancel, parse_device_type,
};
use super::draft::SendDraft;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendSessionOutcome {
    Accepted {
        receiver_device_name: String,
        receiver_endpoint_id: iroh::EndpointId,
    },
    Declined {
        reason: String,
    },
}

#[derive(Debug)]
pub struct SendRun {
    pub events: SendEventStream,
    cancel_tx: Arc<Mutex<Option<watch::Sender<bool>>>>,
    outcome_rx: oneshot::Receiver<AppResult<SendSessionOutcome>>,
}

#[derive(Debug, Clone)]
pub struct SendCancelHandle {
    cancel_tx: Arc<Mutex<Option<watch::Sender<bool>>>>,
}

pub type SendEventStream = UnboundedReceiverStream<SendEvent>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendSession {
    draft: SendDraft,
    destination: SendDestination,
}

impl SendSession {
    pub fn new(draft: SendDraft, destination: SendDestination) -> Self {
        Self { draft, destination }
    }

    pub fn draft(&self) -> &SendDraft {
        &self.draft
    }

    pub fn destination(&self) -> &SendDestination {
        &self.destination
    }

    pub fn start(self) -> SendRun {
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        let (outcome_tx, outcome_rx) = oneshot::channel();
        let cancel_tx = Arc::new(Mutex::new(None));
        let cancel_tx_for_task = Arc::clone(&cancel_tx);

        tokio::spawn(async move {
            let outcome = self.drive(event_tx, cancel_tx_for_task).await;
            let _ = outcome_tx.send(outcome);
        });

        SendRun {
            events: UnboundedReceiverStream::new(event_rx),
            cancel_tx,
            outcome_rx,
        }
    }

    async fn drive(
        self,
        event_tx: mpsc::UnboundedSender<SendEvent>,
        cancel_tx_slot: Arc<Mutex<Option<watch::Sender<bool>>>>,
    ) -> AppResult<SendSessionOutcome> {
        let preview = self.draft.inspect()?;
        let mut destination_label = self.destination.display_label();

        emit_send_event(
            &event_tx,
            SendEvent {
                phase: SendPhase::Connecting,
                destination_label: destination_label.clone(),
                status_message: "Request sent".to_owned(),
                item_count: preview.file_count,
                total_size: preview.total_size,
                bytes_sent: 0,
                plan: None,
                snapshot: None,
                remote_device_type: None,
                connection_path: None,
                error: None,
            },
        );

        let resolved = match self.destination.resolve().await {
            Ok(resolved) => resolved,
            Err(error) => {
                emit_send_event(
                    &event_tx,
                    failed_event_from_error(&destination_label, error.clone().into()),
                );
                return Err(error);
            }
        };
        destination_label = resolved.destination_label;

        let device_type = parse_device_type(&self.draft.config().device_type)?;
        let endpoint = Endpoint::builder(presets::N0)
            .alpns(vec![
                drift_core::protocol::ALPN.to_vec(),
                iroh_blobs::ALPN.to_vec(),
            ])
            .relay_mode(RelayMode::Default)
            .secret_key(iroh::SecretKey::from_bytes(&random::<[u8; 32]>()))
            .bind()
            .await
            .map_err(|e| AppError::BindingFailed {
                context: format!("sender endpoint: {e}"),
            })?;
        let identity = Identity {
            role: TransferRole::Sender,
            endpoint_id: endpoint.addr().id,
            device_name: self.draft.config().device_name.clone(),
            device_type,
        };
        let sender = Sender::new(
            endpoint,
            identity,
            SendRequest {
                peer_endpoint_addr: resolved.peer_endpoint_addr.clone(),
                peer_endpoint_id: resolved.peer_endpoint_id,
                files: self.draft.paths().to_vec(),
            },
        );

        let sender_run = sender.run_with_events();
        let (mut core_events, cancel_tx, outcome_rx) = sender_run.into_parts();
        {
            let mut slot = cancel_tx_slot.lock().await;
            *slot = Some(cancel_tx);
        }
        let mut current_label = destination_label.clone();
        let mut current_plan: Option<TransferPlan> = None;

        while let Some(core_event) = core_events.next().await {
            let mapped =
                map_sender_event(&mut current_label, &preview, &mut current_plan, core_event);
            emit_send_event(&event_tx, mapped);
        }

        let core_outcome = outcome_rx.await.map_err(|e| AppError::Internal {
            message: e.to_string(),
        })?;

        match core_outcome {
            Ok(CoreTransferOutcome::Completed) => Ok(SendSessionOutcome::Accepted {
                receiver_device_name: String::new(),
                receiver_endpoint_id: resolved.peer_endpoint_id,
            }),
            Ok(CoreTransferOutcome::Declined { reason }) => {
                Ok(SendSessionOutcome::Declined { reason })
            }
            Ok(CoreTransferOutcome::Cancelled(cancellation)) => {
                if is_receiver_decline_cancel(&cancellation) {
                    Ok(SendSessionOutcome::Declined {
                        reason: cancellation.reason,
                    })
                } else {
                    Err(AppError::Cancelled {
                        reason: cancellation.reason,
                    })
                }
            }
            Err(error) => {
                emit_send_event(
                    &event_tx,
                    failed_event_from_error(&current_label, error.into()),
                );
                Err(AppError::Internal {
                    message: "transfer failed".to_owned(),
                })
            }
        }
    }
}

impl SendRun {
    pub fn cancel_handle(&self) -> SendCancelHandle {
        SendCancelHandle {
            cancel_tx: Arc::clone(&self.cancel_tx),
        }
    }

    pub fn into_parts(
        self,
    ) -> (
        SendEventStream,
        oneshot::Receiver<AppResult<SendSessionOutcome>>,
    ) {
        (self.events, self.outcome_rx)
    }

    pub async fn cancel_transfer(&self) -> AppResult<()> {
        self.cancel_handle().cancel_transfer().await
    }

    pub async fn outcome(self) -> AppResult<SendSessionOutcome> {
        self.outcome_rx.await.map_err(|_| AppError::Internal {
            message: "waiting for send outcome".to_owned(),
        })?
    }
}

impl SendCancelHandle {
    pub async fn cancel_transfer(&self) -> AppResult<()> {
        let guard = self.cancel_tx.lock().await;
        match guard.as_ref() {
            Some(cancel_tx) => {
                let _ = cancel_tx.send(true);
                Ok(())
            }
            None => Err(AppError::NoActiveTransfer),
        }
    }
}

pub(crate) fn emit_send_event(event_tx: &mpsc::UnboundedSender<SendEvent>, event: SendEvent) {
    let _ = event_tx.send(event);
}

pub(crate) fn failed_event_from_error(
    destination_label: &str,
    error: UserFacingError,
) -> SendEvent {
    SendEvent {
        phase: SendPhase::Failed,
        destination_label: destination_label.to_owned(),
        status_message: format!("Starting transfer to {destination_label}."),
        item_count: 0,
        total_size: 0,
        bytes_sent: 0,
        plan: None,
        snapshot: None,
        remote_device_type: None,
        connection_path: None,
        error: Some(error),
    }
}

fn map_sender_event(
    current_label: &mut String,
    preview: &crate::types::SelectionPreview,
    current_plan: &mut Option<TransferPlan>,
    event: CoreSenderEvent,
) -> SendEvent {
    match event {
        CoreSenderEvent::Connecting { prepared_plan, .. } => SendEvent {
            phase: SendPhase::Connecting,
            destination_label: current_label.clone(),
            status_message: "Request sent".to_owned(),
            item_count: preview.file_count,
            total_size: preview.total_size,
            bytes_sent: 0,
            plan: Some(prepared_plan),
            snapshot: None,
            remote_device_type: None,
            connection_path: None,
            error: None,
        },
        CoreSenderEvent::WaitingForDecision {
            receiver_device_name,
            receiver_endpoint_id: _,
            prepared_plan,
            ..
        } => {
            *current_label = display_destination_label(&receiver_device_name);
            SendEvent {
                phase: SendPhase::WaitingForDecision,
                destination_label: current_label.clone(),
                status_message: "Waiting for confirmation.".to_owned(),
                item_count: preview.file_count,
                total_size: preview.total_size,
                bytes_sent: 0,
                plan: Some(prepared_plan),
                snapshot: None,
                remote_device_type: None,
                connection_path: None,
                error: None,
            }
        }
        CoreSenderEvent::Accepted {
            receiver_device_name,
            receiver_endpoint_id: _,
            prepared_plan,
            ..
        } => {
            *current_label = display_destination_label(&receiver_device_name);
            SendEvent {
                phase: SendPhase::Accepted,
                destination_label: current_label.clone(),
                status_message: format!("Receiver {receiver_device_name} confirmed."),
                item_count: preview.file_count,
                total_size: preview.total_size,
                bytes_sent: 0,
                plan: Some(prepared_plan),
                snapshot: None,
                remote_device_type: None,
                connection_path: None,
                error: None,
            }
        }
        CoreSenderEvent::Declined {
            reason,
            prepared_plan,
            ..
        } => SendEvent {
            phase: SendPhase::Declined,
            destination_label: current_label.clone(),
            status_message: "Transfer declined.".to_owned(),
            item_count: preview.file_count,
            total_size: preview.total_size,
            bytes_sent: 0,
            plan: Some(prepared_plan),
            snapshot: None,
            remote_device_type: None,
            connection_path: None,
            error: Some(UserFacingError::new(
                UserFacingErrorKind::PeerDeclined,
                "Transfer declined",
                reason,
            )),
        },
        CoreSenderEvent::Failed {
            error,
            prepared_plan,
            ..
        } => SendEvent {
            phase: SendPhase::Failed,
            destination_label: current_label.clone(),
            status_message: format!("Starting transfer to {current_label}."),
            item_count: preview.file_count,
            total_size: preview.total_size,
            bytes_sent: 0,
            plan: Some(prepared_plan),
            snapshot: None,
            remote_device_type: None,
            connection_path: None,
            error: Some(UserFacingError::from(error)),
        },
        CoreSenderEvent::TransferStarted { plan, .. } => {
            *current_plan = Some(plan.clone());
            SendEvent {
                phase: SendPhase::Sending,
                destination_label: current_label.clone(),
                status_message: format!("Sending to {current_label}."),
                item_count: u64::from(plan.total_files),
                total_size: plan.total_bytes,
                bytes_sent: 0,
                plan: Some(plan.clone()),
                snapshot: None,
                remote_device_type: None,
                connection_path: None,
                error: None,
            }
        }
        CoreSenderEvent::TransferProgress { snapshot, .. } => SendEvent {
            phase: SendPhase::Sending,
            destination_label: current_label.clone(),
            status_message: "Sending to ".to_owned() + &current_label,
            item_count: current_plan
                .as_ref()
                .map(|plan| u64::from(plan.total_files))
                .unwrap_or(u64::from(snapshot.total_files)),
            total_size: current_plan
                .as_ref()
                .map(|plan| plan.total_bytes)
                .unwrap_or(snapshot.total_bytes),
            bytes_sent: snapshot.bytes_transferred,
            plan: current_plan.clone(),
            snapshot: Some(snapshot.clone()),
            remote_device_type: None,
            connection_path: None,
            error: None,
        },
        CoreSenderEvent::TransferCompleted { snapshot, .. } => SendEvent {
            phase: SendPhase::Completed,
            destination_label: current_label.clone(),
            status_message: "Files sent successfully".to_owned(),
            item_count: current_plan
                .as_ref()
                .map(|plan| u64::from(plan.total_files))
                .unwrap_or(u64::from(snapshot.total_files)),
            total_size: current_plan
                .as_ref()
                .map(|plan| plan.total_bytes)
                .unwrap_or(snapshot.total_bytes),
            bytes_sent: snapshot.bytes_transferred,
            plan: current_plan.clone(),
            snapshot: Some(snapshot.clone()),
            remote_device_type: None,
            connection_path: None,
            error: None,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::{SendRun, failed_event_from_error, is_receiver_decline_cancel};
    use crate::error::{AppError, UserFacingErrorKind};
    use drift_core::protocol::{CancelPhase, TransferRole};
    use drift_core::transfer::TransferCancellation;
    use std::sync::Arc;
    use tokio::sync::{Mutex, mpsc, oneshot, watch};
    use tokio_stream::wrappers::UnboundedReceiverStream;

    #[test]
    fn failed_event_uses_structured_error() {
        let error = AppError::Internal {
            message: "boom".to_owned(),
        };
        let event = failed_event_from_error("Remote", error.into());

        let error = event.error.expect("structured error");
        assert_eq!(error.kind(), UserFacingErrorKind::Internal);
        assert_eq!(error.title(), "Something went wrong");
        assert!(error.message().contains("boom"));
    }

    #[test]
    fn receiver_waiting_for_decision_cancel_is_treated_as_decline() {
        let cancellation = TransferCancellation {
            by: TransferRole::Receiver,
            phase: CancelPhase::WaitingForDecision,
            reason: "receiver cancelled before approval".to_owned(),
        };

        assert!(is_receiver_decline_cancel(&cancellation));
        let sender_cancel = TransferCancellation {
            by: TransferRole::Sender,
            phase: CancelPhase::WaitingForDecision,
            reason: "sender cancelled before approval".to_owned(),
        };
        assert!(!is_receiver_decline_cancel(&sender_cancel));
    }

    #[tokio::test]
    async fn send_run_cancel_transfer_signals_watch_channel() {
        let (_event_tx, event_rx) = mpsc::unbounded_channel();
        let (outcome_tx, outcome_rx) = oneshot::channel();
        let (cancel_tx, cancel_rx) = watch::channel(false);
        let run = SendRun {
            events: UnboundedReceiverStream::new(event_rx),
            cancel_tx: Arc::new(Mutex::new(Some(cancel_tx))),
            outcome_rx,
        };

        run.cancel_transfer().await.expect("cancel succeeds");

        assert!(*cancel_rx.borrow());
        drop(outcome_tx);
    }
}
