use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};
use drift::{receive, send};

#[derive(Parser, Debug)]
#[command(
    name = "drift",
    version,
    about = "Minimal AirDrop-style file transfer over iroh"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    Receive {
        #[arg(short, long, default_value = ".")]
        out: PathBuf,
    },
    Send {
        ticket: String,
        #[arg(required = true)]
        files: Vec<PathBuf>,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Receive { out } => receive(out).await,
        Command::Send { ticket, files } => send(ticket, files).await,
    }
}
