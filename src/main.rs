use clap::Parser;
use color_eyre::eyre::Context;
use tracing::{instrument, level_filters::LevelFilter};
use tracing_error::ErrorLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, Layer};

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Args {
    command: String,
    name: String,
}

fn main() -> color_eyre::Result<()> {
    color_eyre::install().expect("installing color eyre format handler");
    let format = tracing_subscriber::fmt::format().compact();
    let filter = tracing_subscriber::EnvFilter::builder()
        .with_default_directive(LevelFilter::INFO.into())
        .from_env()
        .expect("parsing log config from RUST_LOG failed");
    let fmt_layer = tracing_subscriber::fmt::layer()
        .event_format(format)
        .with_filter(filter);
    let error_layer = ErrorLayer::default();
    tracing_subscriber::registry()
        .with(fmt_layer)
        .with(error_layer)
        .init();
    let args = Args::parse();
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .context("building tokio runtime")?
        .block_on(async move {
            tokio::spawn(start(args))
                .await
                .context("failed to merge main task")?
        })
}

#[instrument(level = "info", skip_all)]
async fn start(args: Args) -> color_eyre::Result<()> {
    println!("name: {}, exec: {}", args.name, args.command);
    Ok(())
}
