use std::fs;
use std::path::PathBuf;

use bevy::prelude::*;
use bevy::window::{PrimaryWindow, Window, WindowMode, WindowResizeConstraints, WindowResized};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone)]
pub struct WindowSizePersistenceConfig {
    pub app_id: String,
    pub default_width: f32,
    pub default_height: f32,
    pub min_width: f32,
    pub min_height: f32,
}

impl WindowSizePersistenceConfig {
    pub fn new(
        app_id: impl Into<String>,
        default_width: f32,
        default_height: f32,
        min_width: f32,
        min_height: f32,
    ) -> Self {
        Self {
            app_id: app_id.into(),
            default_width,
            default_height,
            min_width,
            min_height,
        }
    }

    fn settings_path(&self) -> PathBuf {
        repo_root()
            .join(".local")
            .join(&self.app_id)
            .join("window_settings.json")
    }
}

#[derive(Debug, Clone)]
pub struct WindowSizePersistencePlugin {
    config: WindowSizePersistenceConfig,
}

impl WindowSizePersistencePlugin {
    pub fn new(config: WindowSizePersistenceConfig) -> Self {
        Self { config }
    }
}

impl Plugin for WindowSizePersistencePlugin {
    fn build(&self, app: &mut App) {
        app.insert_resource(WindowSizePersistenceState::new(self.config.clone()))
            .add_systems(Startup, initialize_saved_window_size_state_system)
            .add_systems(Update, persist_window_size_system);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
struct PersistedWindowSize {
    width: f32,
    height: f32,
}

impl PersistedWindowSize {
    fn clamped(self, config: &WindowSizePersistenceConfig) -> Self {
        Self {
            width: clamp_dimension(self.width, config.default_width, config.min_width),
            height: clamp_dimension(self.height, config.default_height, config.min_height),
        }
    }
}

#[derive(Resource, Debug)]
struct WindowSizePersistenceState {
    config: WindowSizePersistenceConfig,
    path: PathBuf,
    last_saved_size: Option<PersistedWindowSize>,
}

impl WindowSizePersistenceState {
    fn new(config: WindowSizePersistenceConfig) -> Self {
        Self {
            path: config.settings_path(),
            config,
            last_saved_size: None,
        }
    }
}

pub fn build_persisted_primary_window(
    config: WindowSizePersistenceConfig,
    title: impl Into<String>,
) -> Window {
    let persisted = load_window_size(&config)
        .unwrap_or(PersistedWindowSize {
            width: config.default_width,
            height: config.default_height,
        })
        .clamped(&config);

    let mut window = Window {
        title: title.into(),
        resize_constraints: WindowResizeConstraints {
            min_width: config.min_width.max(1.0),
            min_height: config.min_height.max(1.0),
            ..default()
        },
        ..default()
    };
    window.resolution.set(persisted.width, persisted.height);
    window
}

fn initialize_saved_window_size_state_system(
    primary_window: Query<&Window, With<PrimaryWindow>>,
    mut state: ResMut<WindowSizePersistenceState>,
) {
    let Ok(window) = primary_window.single() else {
        return;
    };
    state.last_saved_size = Some(current_window_size(window, &state.config));
}

fn persist_window_size_system(
    mut resize_events: MessageReader<WindowResized>,
    primary_window: Query<(Entity, &Window), With<PrimaryWindow>>,
    mut state: ResMut<WindowSizePersistenceState>,
) {
    let Ok((primary_window_entity, window)) = primary_window.single() else {
        return;
    };

    let mut saw_primary_resize = false;
    for event in resize_events.read() {
        if event.window == primary_window_entity {
            saw_primary_resize = true;
        }
    }
    if !saw_primary_resize || window.mode != WindowMode::Windowed {
        return;
    }

    let current_size = current_window_size(window, &state.config);
    if state.last_saved_size == Some(current_size) {
        return;
    }

    if let Some(parent) = state.path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(raw) = serde_json::to_string_pretty(&current_size) {
        if fs::write(&state.path, raw).is_ok() {
            state.last_saved_size = Some(current_size);
        }
    }
}

fn load_window_size(config: &WindowSizePersistenceConfig) -> Option<PersistedWindowSize> {
    let raw = fs::read_to_string(config.settings_path()).ok()?;
    serde_json::from_str::<PersistedWindowSize>(&raw).ok()
}

fn current_window_size(
    window: &Window,
    config: &WindowSizePersistenceConfig,
) -> PersistedWindowSize {
    PersistedWindowSize {
        width: window.width(),
        height: window.height(),
    }
    .clamped(config)
}

fn clamp_dimension(value: f32, default_value: f32, min_value: f32) -> f32 {
    if !value.is_finite() || value <= 0.0 {
        return default_value.max(min_value);
    }
    value.max(min_value)
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}
