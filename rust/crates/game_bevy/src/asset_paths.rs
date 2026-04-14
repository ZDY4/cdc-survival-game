use std::path::{Path, PathBuf};

pub fn rust_asset_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets")
}

pub fn rust_asset_path(relative: impl AsRef<Path>) -> PathBuf {
    rust_asset_dir().join(relative)
}
