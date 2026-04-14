use std::path::PathBuf;
use std::sync::OnceLock;

use bevy_log::tracing_subscriber::fmt::writer::MakeWriterExt;
use bevy_log::tracing_subscriber::prelude::*;
use bevy_log::{Level, DEFAULT_FILTER};
use thiserror::Error;
use time::macros::format_description;
use time::OffsetDateTime;
use tracing_appender::rolling::{never, RollingFileAppender, Rotation};
use tracing_log::LogTracer;

static LOGGING_INITIALIZED: OnceLock<()> = OnceLock::new();

#[derive(Debug, Clone)]
pub struct RuntimeLogSettings {
    pub app_name: String,
    pub log_root: PathBuf,
    pub max_log_files: usize,
    pub file_name: Option<String>,
}

impl RuntimeLogSettings {
    pub fn new(app_name: impl Into<String>) -> Self {
        Self {
            app_name: app_name.into(),
            log_root: workspace_log_root(),
            max_log_files: 14,
            file_name: None,
        }
    }

    fn log_dir(&self) -> PathBuf {
        self.log_root.join(&self.app_name)
    }

    pub fn with_file_name(mut self, file_name: impl Into<String>) -> Self {
        self.file_name = Some(file_name.into());
        self
    }

    pub fn with_single_run_file(mut self) -> Self {
        self.file_name = Some(single_run_log_file_name());
        self
    }
}

#[derive(Debug, Error)]
pub enum RuntimeLogInitError {
    #[error("failed to initialize log file under {path}: {source}")]
    FileAppender {
        path: PathBuf,
        #[source]
        source: tracing_appender::rolling::InitError,
    },
    #[error("failed to initialize global log tracer: {0}")]
    LogTracer(#[from] tracing_log::log_tracer::SetLoggerError),
    #[error("failed to install global tracing subscriber: {0}")]
    Subscriber(#[from] tracing::subscriber::SetGlobalDefaultError),
}

pub fn init_runtime_logging(settings: &RuntimeLogSettings) -> Result<(), RuntimeLogInitError> {
    if LOGGING_INITIALIZED.get().is_some() {
        return Ok(());
    }

    let file_appender =
        build_file_appender(settings).map_err(|source| RuntimeLogInitError::FileAppender {
            path: settings.log_dir(),
            source,
        })?;
    let filter_expression = std::env::var("CDC_BEVY_LOG")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| format!("{},{}", Level::INFO, DEFAULT_FILTER));
    let filter_layer =
        bevy_log::tracing_subscriber::EnvFilter::builder().parse_lossy(filter_expression);
    let fmt_layer = bevy_log::tracing_subscriber::fmt::layer()
        .with_target(true)
        .with_file(true)
        .with_line_number(true)
        .with_writer(std::io::stderr.and(file_appender));
    let subscriber = bevy_log::tracing_subscriber::registry()
        .with(filter_layer)
        .with(fmt_layer);

    LogTracer::init()?;
    tracing::subscriber::set_global_default(subscriber)?;
    let _ = LOGGING_INITIALIZED.set(());
    Ok(())
}

fn workspace_log_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../logs")
}

fn build_file_appender(
    settings: &RuntimeLogSettings,
) -> Result<RollingFileAppender, tracing_appender::rolling::InitError> {
    if let Some(file_name) = settings.file_name.as_deref() {
        return Ok(never(settings.log_dir(), file_name));
    }

    RollingFileAppender::builder()
        .rotation(Rotation::DAILY)
        .filename_prefix("runtime")
        .filename_suffix("log")
        .max_log_files(settings.max_log_files)
        .build(settings.log_dir())
}

fn single_run_log_file_name() -> String {
    let timestamp =
        local_log_timestamp().unwrap_or_else(|| format!("unix-{}", unix_timestamp_millis()));
    format!("runtime.{timestamp}.log")
}

fn local_log_timestamp() -> Option<String> {
    let now = OffsetDateTime::now_local().ok()?;
    let format =
        format_description!("[year]-[month]-[day]_[hour]-[minute]-[second].[subsecond digits:3]");
    now.format(&format).ok()
}

fn unix_timestamp_millis() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|value| value.as_millis())
        .unwrap_or_default()
}
