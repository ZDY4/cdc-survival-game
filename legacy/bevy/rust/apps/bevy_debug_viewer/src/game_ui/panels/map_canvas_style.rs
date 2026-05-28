//! 地图画布颜色策略：把数据语义映射成低网格感的 2D 俯视图配色。

use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum TerrainVisualKind {
    Unknown,
    Blocked,
    Road,
    Grass,
    Forest,
    Water,
    Urban,
    Default,
}

impl TerrainVisualKind {
    pub(super) fn from_cell(cell: Option<&game_core::MapCellDebugState>) -> Self {
        let Some(cell) = cell else {
            return Self::Unknown;
        };
        if cell.blocks_movement {
            return Self::Blocked;
        }
        match cell.terrain.as_str() {
            "road" | "asphalt" | "concrete" => Self::Road,
            "grass" | "plain" | "field" => Self::Grass,
            "forest" => Self::Forest,
            "water" => Self::Water,
            "urban" => Self::Urban,
            _ => Self::Default,
        }
    }

    pub(super) fn color(self) -> Color {
        match self {
            Self::Unknown => Color::srgba(0.065, 0.065, 0.06, 1.0),
            Self::Blocked => Color::srgba(0.12, 0.115, 0.105, 1.0),
            Self::Road => Color::srgba(0.23, 0.235, 0.23, 1.0),
            Self::Grass => Color::srgba(0.16, 0.24, 0.15, 1.0),
            Self::Forest => Color::srgba(0.10, 0.19, 0.12, 1.0),
            Self::Water => Color::srgba(0.08, 0.19, 0.28, 1.0),
            Self::Urban => Color::srgba(0.20, 0.20, 0.19, 1.0),
            Self::Default => Color::srgba(0.18, 0.18, 0.165, 1.0),
        }
    }
}

pub(super) fn object_cell_color(object: &game_core::MapObjectDebugState) -> Color {
    match object.kind {
        game_data::MapObjectKind::Building => Color::srgba(0.47, 0.42, 0.34, 0.95),
        game_data::MapObjectKind::Trigger => Color::srgba(0.70, 0.56, 0.18, 0.38),
        game_data::MapObjectKind::Interactive => Color::srgba(0.36, 0.46, 0.56, 0.50),
        game_data::MapObjectKind::AiSpawn => Color::srgba(0.48, 0.28, 0.58, 0.42),
        game_data::MapObjectKind::Pickup => Color::srgba(0.56, 0.44, 0.25, 0.42),
        game_data::MapObjectKind::Prop => Color::srgba(0.28, 0.27, 0.25, 0.50),
    }
}

pub(super) fn object_outline_color(object: &game_core::MapObjectDebugState) -> Color {
    match object.kind {
        game_data::MapObjectKind::Building => Color::srgba(0.18, 0.15, 0.12, 0.95),
        _ => Color::srgba(0.02, 0.02, 0.018, 0.62),
    }
}

pub(super) fn actor_marker_color(side: game_data::ActorSide) -> Color {
    match side {
        game_data::ActorSide::Player => Color::srgba(0.24, 0.56, 0.95, 1.0),
        game_data::ActorSide::Friendly => Color::srgba(0.24, 0.68, 0.34, 1.0),
        game_data::ActorSide::Hostile => Color::srgba(0.90, 0.24, 0.20, 1.0),
        game_data::ActorSide::Neutral => Color::srgba(0.74, 0.72, 0.66, 1.0),
    }
}
