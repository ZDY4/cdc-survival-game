//! 运行时基础状态：定义场景、配置、字体、保存路径和事件日志资源。

use std::collections::BTreeMap;

use bevy::prelude::*;
use game_bevy::SettlementDebugSnapshot;
use game_core::SimulationRuntime;
use serde::{Deserialize, Serialize};

#[derive(Resource, Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ViewerSceneKind {
    #[default]
    MainMenu,
    Gameplay,
}

impl ViewerSceneKind {
    pub(crate) fn is_main_menu(self) -> bool {
        matches!(self, Self::MainMenu)
    }

    pub(crate) fn is_gameplay(self) -> bool {
        matches!(self, Self::Gameplay)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ViewerOverlayMode {
    Minimal,
    #[default]
    Gameplay,
    AiDebug,
}

impl ViewerOverlayMode {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Minimal => "Minimal",
            Self::Gameplay => "Gameplay",
            Self::AiDebug => "AI Debug",
        }
    }

    pub(crate) fn next(self) -> Self {
        match self {
            Self::Minimal => Self::Gameplay,
            Self::Gameplay => Self::AiDebug,
            Self::AiDebug => Self::Minimal,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum HudEventCategory {
    Combat,
    Interaction,
    World,
}

impl HudEventCategory {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Combat => "Combat",
            Self::Interaction => "Interaction",
            Self::World => "World",
        }
    }
}

#[derive(Debug, Clone)]
pub(crate) struct ViewerEventEntry {
    pub category: HudEventCategory,
    pub turn_index: u64,
    pub text: String,
}

#[derive(Resource, Debug)]
pub(crate) struct ViewerRuntimeState {
    pub runtime: SimulationRuntime,
    pub recent_events: Vec<ViewerEventEntry>,
    pub ai_snapshot: SettlementDebugSnapshot,
}

#[derive(Resource, Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct ViewerUiSettings {
    pub master_volume: f32,
    pub music_volume: f32,
    pub sfx_volume: f32,
    pub window_mode: String,
    pub vsync: bool,
    pub ui_scale: f32,
    pub action_bindings: BTreeMap<String, String>,
}

impl Default for ViewerUiSettings {
    fn default() -> Self {
        Self {
            master_volume: 1.0,
            music_volume: 1.0,
            sfx_volume: 1.0,
            window_mode: "windowed".to_string(),
            vsync: true,
            ui_scale: 1.0,
            action_bindings: BTreeMap::from([
                ("menu_inventory".to_string(), "KeyI".to_string()),
                ("menu_character".to_string(), "KeyC".to_string()),
                ("menu_map".to_string(), "KeyM".to_string()),
                ("menu_journal".to_string(), "KeyJ".to_string()),
                ("menu_skills".to_string(), "KeyK".to_string()),
                ("menu_crafting".to_string(), "KeyL".to_string()),
                ("menu_settings".to_string(), "Escape".to_string()),
            ]),
        }
    }
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct ViewerUiSettingsPath(pub std::path::PathBuf);

impl Default for ViewerUiSettingsPath {
    fn default() -> Self {
        Self(
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../../config/bevy_viewer_ui_settings.json"),
        )
    }
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct ViewerRuntimeSavePath(pub std::path::PathBuf);

impl Default for ViewerRuntimeSavePath {
    fn default() -> Self {
        Self(
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../../saves/bevy_viewer_latest.json"),
        )
    }
}

#[derive(Resource, Clone)]
pub(crate) struct ViewerUiFont(pub Handle<Font>);
