use std::collections::HashMap;

use bevy::prelude::*;
use game_bevy::SettlementDebugSnapshot;
use game_core::SimulationRuntime;
use game_data::{ActorId, DialogueData, GridCoord, InteractionPrompt, InteractionTargetId};

pub(crate) const VIEWER_FONT_PATH: &str = "fonts/NotoSansCJKsc-Regular.otf";

#[derive(Resource, Debug)]
pub(crate) struct ViewerRuntimeState {
    pub runtime: SimulationRuntime,
    pub recent_events: Vec<ViewerEventEntry>,
    pub ai_snapshot: SettlementDebugSnapshot,
}

#[derive(Resource, Clone)]
pub(crate) struct ViewerUiFont(pub Handle<Font>);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ViewerHudPage {
    #[default]
    Overview,
    SelectedActor,
    World,
    Interaction,
    Events,
    Ai,
}

impl ViewerHudPage {
    pub(crate) fn title(self) -> &'static str {
        match self {
            Self::Overview => "Overview",
            Self::SelectedActor => "Selected Actor",
            Self::World => "World",
            Self::Interaction => "Interaction",
            Self::Events => "Events",
            Self::Ai => "AI",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum HudEventFilter {
    #[default]
    All,
    Combat,
    Interaction,
    World,
}

impl HudEventFilter {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::All => "All",
            Self::Combat => "Combat",
            Self::Interaction => "Interaction",
            Self::World => "World",
        }
    }

    pub(crate) fn previous(self) -> Self {
        match self {
            Self::All => Self::World,
            Self::Combat => Self::All,
            Self::Interaction => Self::Combat,
            Self::World => Self::Interaction,
        }
    }

    pub(crate) fn next(self) -> Self {
        match self {
            Self::All => Self::Combat,
            Self::Combat => Self::Interaction,
            Self::Interaction => Self::World,
            Self::World => Self::All,
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

#[derive(Resource, Debug, Default)]
pub(crate) struct ActorLabelEntities {
    pub by_actor: HashMap<ActorId, Entity>,
}

#[derive(Resource, Debug, Clone, Copy)]
pub(crate) struct ViewerRenderConfig {
    pub pixels_per_world_unit: f32,
    pub zoom_factor: f32,
    pub min_pixels_per_world_unit: f32,
    pub max_pixels_per_world_unit: f32,
    pub viewport_padding_px: f32,
    pub hud_reserved_width_px: f32,
}

impl Default for ViewerRenderConfig {
    fn default() -> Self {
        Self {
            pixels_per_world_unit: 96.0,
            zoom_factor: 1.0,
            min_pixels_per_world_unit: 24.0,
            max_pixels_per_world_unit: 160.0,
            viewport_padding_px: 72.0,
            hud_reserved_width_px: 460.0,
        }
    }
}

#[derive(Resource, Debug)]
pub(crate) struct ViewerState {
    pub selected_actor: Option<ActorId>,
    pub focused_target: Option<InteractionTargetId>,
    pub current_prompt: Option<InteractionPrompt>,
    pub interaction_menu: Option<InteractionMenuState>,
    pub active_dialogue: Option<ActiveDialogueState>,
    pub hud_page: ViewerHudPage,
    pub event_filter: HudEventFilter,
    pub show_hud: bool,
    pub show_controls: bool,
    pub hovered_grid: Option<GridCoord>,
    pub current_level: i32,
    pub auto_tick: bool,
    pub end_turn_repeat_delay_sec: f32,
    pub end_turn_repeat_interval_sec: f32,
    pub end_turn_hold_sec: f32,
    pub end_turn_repeat_elapsed_sec: f32,
    pub min_progression_interval_sec: f32,
    pub progression_elapsed_sec: f32,
    pub camera_pan_offset: Vec2,
    pub camera_drag_cursor: Option<Vec2>,
    pub status_line: String,
}

impl Default for ViewerState {
    fn default() -> Self {
        Self {
            selected_actor: None,
            focused_target: None,
            current_prompt: None,
            interaction_menu: None,
            active_dialogue: None,
            hud_page: ViewerHudPage::Overview,
            event_filter: HudEventFilter::All,
            show_hud: true,
            show_controls: false,
            hovered_grid: None,
            current_level: 0,
            auto_tick: false,
            end_turn_repeat_delay_sec: 0.2,
            end_turn_repeat_interval_sec: 0.1,
            end_turn_hold_sec: 0.0,
            end_turn_repeat_elapsed_sec: 0.0,
            min_progression_interval_sec: 0.1,
            progression_elapsed_sec: 0.0,
            camera_pan_offset: Vec2::ZERO,
            camera_drag_cursor: None,
            status_line: String::new(),
        }
    }
}

#[derive(Component)]
pub(crate) struct HudText;

#[derive(Component)]
pub(crate) struct HudFooterText;

#[derive(Component)]
pub(crate) struct ViewerCamera;

#[derive(Component)]
pub(crate) struct InteractionMenuText;

#[derive(Component)]
pub(crate) struct ActorLabel {
    pub actor_id: ActorId,
}

#[derive(Debug, Clone)]
pub(crate) struct InteractionMenuState {
    pub target_id: InteractionTargetId,
    pub cursor_position: Vec2,
}

#[derive(Debug, Clone)]
pub(crate) struct ActiveDialogueState {
    pub dialog_id: String,
    pub data: DialogueData,
    pub current_node_id: String,
    pub target_name: String,
}
