use anyhow::Result;
use clap::Parser;
use tracing::{info, Level};
use tracing_subscriber;

mod app;
mod config;
mod otp_client;
mod state;
mod events;
mod ui;
mod message;
mod terminal;
mod chat_ui;
mod rich_text;

use app::App;
use config::Config;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    /// Configuration file path
    #[arg(short, long)]
    config: Option<String>,

    /// OTP server address
    #[arg(short, long, default_value = "127.0.0.1:9487")]
    otp_addr: String,

    /// Enable debug logging
    #[arg(short, long)]
    debug: bool,

    /// Project directory to work with
    #[arg(short, long, default_value = ".")]
    project_dir: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Setup logging
    let log_level = if cli.debug { Level::DEBUG } else { Level::INFO };
    tracing_subscriber::fmt()
        .with_max_level(log_level)
        .init();

    info!("Starting Aiex TUI v{}", env!("CARGO_PKG_VERSION"));

    // Load configuration
    let config = Config::load(cli.config.as_deref())?;

    // Create and run the application
    let mut app = App::new(config, cli.otp_addr, cli.project_dir).await?;
    app.run().await?;

    info!("Aiex TUI shutting down");
    Ok(())
}