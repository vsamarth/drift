use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};
use drift_core::{receive, receive_ticket, send, send_ticket};

#[derive(Parser, Debug)]
#[command(name = "drift", version, about = "Short-code file transfer over iroh")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    Send {
        #[arg(required = true)]
        files: Vec<PathBuf>,
        #[arg(long)]
        server: Option<String>,
    },
    Receive {
        code: String,
        #[arg(short, long, default_value = ".")]
        out: PathBuf,
        #[arg(long)]
        server: Option<String>,
    },
    SendTicket {
        ticket: String,
        #[arg(required = true)]
        files: Vec<PathBuf>,
    },
    ReceiveTicket {
        #[arg(short, long, default_value = ".")]
        out: PathBuf,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Send { files, server } => send(files, server).await,
        Command::Receive { code, out, server } => receive(code, out, server).await,
        Command::SendTicket { ticket, files } => send_ticket(ticket, files).await,
        Command::ReceiveTicket { out } => receive_ticket(out).await,
    }
}
