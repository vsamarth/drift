use std::sync::Arc;

use futures_lite::StreamExt;
use iroh::Endpoint;
use iroh_blobs::{
    ALPN as BLOBS_ALPN, api::remote::GetProgressItem, store::fs::FsStore, ticket::BlobTicket,
};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::trace;

use super::error::{BlobError, BlobTextError, Result};
use super::util::ScratchDir;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BlobDownloadUpdate {
    Progress { bytes_received: u64 },
    Done,
    Failed { message: String },
}

pub type BlobDownloadUpdateStream = UnboundedReceiverStream<BlobDownloadUpdate>;

#[derive(Debug)]
pub struct BlobDownloadSession {
    events: BlobDownloadUpdateStream,
    store: Arc<FsStore>,
    root: ScratchDir,
    task: JoinHandle<Result<()>>,
}

impl BlobDownloadSession {
    pub(crate) fn events_mut(&mut self) -> &mut BlobDownloadUpdateStream {
        &mut self.events
    }

    pub(crate) fn store(&self) -> &FsStore {
        self.store.as_ref()
    }

    pub(crate) fn abort(&self) {
        self.task.abort();
    }

    pub async fn shutdown(self) -> Result<()> {
        let BlobDownloadSession {
            events: _,
            store,
            root,
            task,
        } = self;
        let task_result = match task.await {
            Ok(v) => v,
            Err(error) if error.is_cancelled() => Ok(()),
            Err(error) => Err(BlobError::join_download_task(error)),
        };
        let store = Arc::try_unwrap(store).map_err(|_| BlobError::store_still_shared())?;
        store
            .shutdown()
            .await
            .map_err(|source| BlobError::store_shutdown("blob download session", source))?;
        drop(root);
        task_result?;
        Ok(())
    }
}

pub trait BlobDownloadStrategy: Send + Sync + 'static {
    fn spawn(
        &self,
        endpoint: Endpoint,
        store: Arc<FsStore>,
        ticket: BlobTicket,
        update_tx: mpsc::UnboundedSender<BlobDownloadUpdate>,
    ) -> JoinHandle<Result<()>>;
}

#[derive(Debug, Default, Clone, Copy)]
pub struct SequentialBlobDownload;

impl BlobDownloadStrategy for SequentialBlobDownload {
    fn spawn(
        &self,
        endpoint: Endpoint,
        store: Arc<FsStore>,
        ticket: BlobTicket,
        update_tx: mpsc::UnboundedSender<BlobDownloadUpdate>,
    ) -> JoinHandle<Result<()>> {
        tokio::spawn(async move {
            let ticket_context = format!("ticket {ticket:?}");
            let connection = endpoint
                .connect(ticket.addr().clone(), BLOBS_ALPN)
                .await
                .map_err(|source| BlobError::connect(format!("ticket {ticket:?}"), source))?;

            let mut stream = store.remote().fetch(connection, ticket).stream();

            loop {
                match stream.next().await {
                    Some(GetProgressItem::Progress(offset)) => {
                        let _ = update_tx.send(BlobDownloadUpdate::Progress {
                            bytes_received: offset,
                        });
                    }
                    Some(GetProgressItem::Done(_)) | None => {
                        let _ = update_tx.send(BlobDownloadUpdate::Done);
                        break Ok(());
                    }
                    Some(GetProgressItem::Error(err)) => {
                        let message = format!("blob fetch error: {err}");
                        let _ = update_tx.send(BlobDownloadUpdate::Failed {
                            message: message.clone(),
                        });
                        break Err(BlobError::fetch(
                            ticket_context,
                            BlobTextError::new(message),
                        ));
                    }
                }
            }
        })
    }
}

#[derive(Debug)]
pub struct BlobReceiver<S = SequentialBlobDownload> {
    endpoint: Endpoint,
    strategy: S,
}

impl BlobReceiver<SequentialBlobDownload> {
    pub fn new(endpoint: Endpoint) -> Self {
        Self {
            endpoint,
            strategy: SequentialBlobDownload,
        }
    }
}

impl<S> BlobReceiver<S>
where
    S: BlobDownloadStrategy,
{
    pub fn with_strategy(endpoint: Endpoint, strategy: S) -> Self {
        Self { endpoint, strategy }
    }

    pub async fn start(&self, session_id: &str, ticket: BlobTicket) -> Result<BlobDownloadSession> {
        let root = ScratchDir::new("drift-blob", session_id).await?;
        let store = Arc::new(
            FsStore::load(&root.path)
                .await
                .map_err(|source| BlobError::store_load(root.path.clone(), source))?,
        );
        let (update_tx, update_rx) = mpsc::unbounded_channel();
        let task = self
            .strategy
            .spawn(self.endpoint.clone(), store.clone(), ticket, update_tx);

        trace!(session_id = %session_id, "started blob download session");

        Ok(BlobDownloadSession {
            events: UnboundedReceiverStream::new(update_rx),
            store,
            root,
            task,
        })
    }
}
