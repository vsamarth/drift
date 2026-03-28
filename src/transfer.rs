use std::path::PathBuf;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use tokio::fs;
use tokio::signal;
use tokio::time::{MissedTickBehavior, interval};

use crate::fs_plan::{build_expected_files, prepare_files};
use crate::rendezvous::{OfferStatus, RendezvousClient};
use crate::session::{bind_endpoint, receive_from_ticket, receive_on_endpoint, send_files_over_connection};
use crate::util::{confirm_accept, human_size};
use crate::wire::{ALPN, decode_ticket, make_ticket};

pub async fn send(files: Vec<PathBuf>, server_url: Option<String>) -> Result<()> {
    let prepared = prepare_files(files).await?;
    let endpoint = bind_endpoint()
        .await
        .context("binding local iroh endpoint")?;
    let ticket = make_ticket(&endpoint).await?;
    let client = RendezvousClient::new(crate::rendezvous::resolve_server_url(server_url.as_deref()));
    let offer = client
        .create_offer(ticket, prepared.manifest.clone())
        .await?;

    println!("Offer ready");
    println!("Code: {}", offer.code);
    println!("Expires: {}", offer.expires_at);
    println!(
        "Files: {} ({})",
        prepared.manifest.file_count,
        human_size(prepared.manifest.total_size)
    );
    println!("Waiting for receiver to accept...");

    let mut accept_future = Box::pin(endpoint.accept());
    let mut poll = interval(Duration::from_secs(2));
    poll.set_missed_tick_behavior(MissedTickBehavior::Delay);
    poll.tick().await;
    let mut ctrl_c = Box::pin(signal::ctrl_c());
    let mut accepted = false;

    loop {
        tokio::select! {
            _ = &mut ctrl_c => {
                endpoint.close().await;
                bail!("transfer interrupted");
            }
            incoming = &mut accept_future => {
                let incoming = incoming.context("sender stopped before a receiver connected")?;
                let connection = incoming.await.context("accepting receiver connection")?;
                println!(
                    "Receiver connected from {}",
                    crate::util::describe_remote(connection.remote_id(), endpoint.remote_info(connection.remote_id()).await.as_ref())
                );
                send_files_over_connection(connection, &prepared.files).await?;
                endpoint.close().await;
                return Ok(());
            }
            _ = poll.tick() => {
                match client.offer_status(&offer.code).await?.status {
                    OfferStatus::Pending => {}
                    OfferStatus::Accepted => {
                        if !accepted {
                            accepted = true;
                            println!("Offer accepted. Waiting for receiver connection...");
                        }
                    }
                    OfferStatus::Declined => {
                        endpoint.close().await;
                        bail!("receiver declined the offer");
                    }
                    OfferStatus::Expired => {
                        endpoint.close().await;
                        bail!("offer expired before the receiver accepted");
                    }
                }
            }
        }
    }
}

pub async fn receive(code: String, out_dir: PathBuf, server_url: Option<String>) -> Result<()> {
    crate::rendezvous::validate_code(&code)?;

    let client = RendezvousClient::new(crate::rendezvous::resolve_server_url(server_url.as_deref()));
    let preview = client.offer_preview(&code).await?;

    fs::create_dir_all(&out_dir)
        .await
        .with_context(|| format!("creating output directory {}", out_dir.display()))?;

    println!("Incoming offer");
    println!("Files: {}", preview.manifest.file_count);
    println!("Total size: {}", human_size(preview.manifest.total_size));
    println!("Expires: {}", preview.expires_at);
    for file in &preview.manifest.files {
        println!("  {} ({})", file.path, human_size(file.size));
    }

    let expected_files = match build_expected_files(&preview.manifest, &out_dir).await {
        Ok(expected_files) => expected_files,
        Err(err) => {
            client
                .decline_offer(&code)
                .await
                .context("declining offer after receive preflight failed")?;
            return Err(err);
        }
    };

    if !confirm_accept()? {
        client.decline_offer(&code).await?;
        println!("Offer declined");
        return Ok(());
    }

    let accepted = client.accept_offer(&code).await?;
    println!("Accepted offer. Connecting to sender...");
    let ticket = decode_ticket(&accepted.ticket)?;
    receive_from_ticket(ticket, out_dir, Some(expected_files)).await
}

pub async fn receive_ticket(out_dir: PathBuf) -> Result<()> {
    fs::create_dir_all(&out_dir)
        .await
        .with_context(|| format!("creating output directory {}", out_dir.display()))?;

    let endpoint = bind_endpoint().await?;
    let ticket = make_ticket(&endpoint).await?;

    println!("Receiver ready");
    println!("Save directory: {}", out_dir.display());
    println!("Ticket:");
    println!("{}", ticket);
    println!("Waiting for a sender...");

    receive_on_endpoint(endpoint, out_dir, None).await
}

pub async fn send_ticket(ticket: String, files: Vec<PathBuf>) -> Result<()> {
    let prepared = prepare_files(files).await?;
    let endpoint = bind_endpoint()
        .await
        .context("binding local iroh endpoint")?;
    let ticket = decode_ticket(&ticket)?;
    let connection = endpoint
        .connect(ticket, ALPN)
        .await
        .context("connecting to receiver")?;

    send_files_over_connection(connection, &prepared.files).await
}
