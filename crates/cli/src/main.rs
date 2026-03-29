use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};
use drift::{LoggingOpts, init_tracing, receive, send};

#[derive(Parser, Debug)]
#[command(name = "drift", version, about = "Short-code file transfer over iroh")]
struct Cli {
    #[command(flatten)]
    logging: LoggingOpts,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    Send {
        code: String,
        #[arg(required = true)]
        files: Vec<PathBuf>,
        #[arg(long)]
        server: Option<String>,
    },
    Receive {
        #[arg(short, long, default_value = ".")]
        out: PathBuf,
        #[arg(long)]
        server: Option<String>,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    init_tracing(cli.logging.log_format, cli.logging.verbose);

    match cli.command {
        Command::Send {
            code,
            files,
            server,
        } => send(code, files, server).await,
        Command::Receive { out, server } => receive(out, server).await,
    }
}
