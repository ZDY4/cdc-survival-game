use std::path::PathBuf;

use bevy::asset::AssetPlugin;
use bevy::log::LogPlugin;
use bevy::prelude::*;
use bevy::window::WindowPlugin;
use bevy_egui::EguiPlugin;
use game_bevy::{init_runtime_logging, RuntimeLogSettings};

use crate::{
    build_persisted_primary_window, WindowSizePersistenceConfig, WindowSizePersistencePlugin,
};

#[derive(Debug, Clone)]
pub struct EditorAppShellConfig {
    pub app_id: String,
    pub title: String,
    pub asset_dir: PathBuf,
    pub window: WindowSizePersistenceConfig,
}

impl EditorAppShellConfig {
    pub fn new(
        app_id: impl Into<String>,
        title: impl Into<String>,
        asset_dir: PathBuf,
        window: WindowSizePersistenceConfig,
    ) -> Self {
        Self {
            app_id: app_id.into(),
            title: title.into(),
            asset_dir,
            window,
        }
    }
}

pub fn configure_editor_app_shell(app: &mut App, config: &EditorAppShellConfig) {
    let log_settings = RuntimeLogSettings::new(&config.app_id).with_single_run_file();
    if let Err(error) = init_runtime_logging(&log_settings) {
        eprintln!("failed to initialize {} logging: {error}", config.app_id);
    } else {
        info!("{} logger initialized", config.app_id);
    }

    app.add_plugins(
        DefaultPlugins
            .build()
            .disable::<LogPlugin>()
            .set(WindowPlugin {
                primary_window: Some(build_persisted_primary_window(
                    config.window.clone(),
                    config.title.clone(),
                )),
                ..default()
            })
            .set(AssetPlugin {
                file_path: config.asset_dir.display().to_string(),
                ..default()
            }),
    )
    .add_plugins(EguiPlugin::default())
    .add_plugins(WindowSizePersistencePlugin::new(config.window.clone()));
}
