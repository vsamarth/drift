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
        /// Rendezvous short code from the receiver (required unless `--nearby`).
        #[arg(short = 'c', long = "code")]
        code: Option<String>,
        /// Discover receivers on the local network via mDNS instead of using a short code.
        #[arg(long)]
        nearby: bool,
        /// How long to scan for LAN receivers when using `--nearby`.
        #[arg(long, default_value_t = 15)]
        nearby_timeout_secs: u64,
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
            nearby,
            nearby_timeout_secs,
            files,
            server,
        } => match (nearby, code.as_ref()) {
            (true, None) => drift::send_nearby(files, nearby_timeout_secs, server).await,
                (false, Some(c)) => send(c.clone(), files, server).await,
            (true, Some(_)) => {
                anyhow::bail!("pass either CODE or --nearby, not both");
            }
            (false, None) => {
                anyhow::bail!("pass a short CODE or use --nearby to discover receivers on the LAN");
            }
        },
        Command::Receive { out, server } => receive(out, server).await,
    }
}
