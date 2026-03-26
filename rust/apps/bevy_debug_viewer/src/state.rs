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
    pub zoom_factor: f32,
    pub viewport_padding_px: f32,
    pub hud_reserved_width_px: f32,
    pub camera_pitch_degrees: f32,
    pub camera_fov_degrees: f32,
    pub camera_distance_padding_world: f32,
    pub floor_thickness_world: f32,
    pub actor_radius_world: f32,
    pub actor_body_length_world: f32,
    pub actor_label_height_world: f32,
    pub label_screen_offset_px: Vec2,
}

impl Default for ViewerRenderConfig {
    fn default() -> Self {
        Self {
            zoom_factor: 1.0,
            viewport_padding_px: 72.0,
            hud_reserved_width_px: 460.0,
            camera_pitch_degrees: 35.0,
            camera_fov_degrees: 30.0,
            camera_distance_padding_world: 8.0,
            floor_thickness_world: 0.08,
            actor_radius_world: 0.22,
            actor_body_length_world: 0.52,
            actor_label_height_world: 1.3,
            label_screen_offset_px: Vec2::new(-26.0, -14.0),
        }
    }
}

impl ViewerRenderConfig {
    pub(crate) fn camera_pitch_radians(self) -> f32 {
        self.camera_pitch_degrees.to_radians()
    }

    pub(crate) fn camera_fov_radians(self) -> f32 {
        self.camera_fov_degrees.to_radians()
    }

    pub(crate) fn vertical_projection_factor(self) -> f32 {
        self.camera_pitch_radians().sin().max(0.1)
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

impl ViewerState {
    pub(crate) fn is_interaction_menu_open(&self) -> bool {
        self.interaction_menu.is_some()
    }

    pub(crate) fn interaction_locked_actor_id(
        &self,
        runtime_state: &ViewerRuntimeState,
    ) -> Option<ActorId> {
        self.active_dialogue
            .as_ref()
            .map(|dialogue| dialogue.actor_id)
            .or_else(|| {
                runtime_state
                    .runtime
                    .pending_interaction()
                    .map(|intent| intent.actor_id)
            })
    }

    pub(crate) fn is_actor_interaction_locked(
        &self,
        runtime_state: &ViewerRuntimeState,
        actor_id: ActorId,
    ) -> bool {
        self.interaction_locked_actor_id(runtime_state) == Some(actor_id)
    }
}

#[derive(Component)]
pub(crate) struct HudText;

#[derive(Component)]
pub(crate) struct HudFooterText;

#[derive(Component)]
pub(crate) struct ViewerCamera;

#[derive(Component)]
pub(crate) struct InteractionMenuRoot;

#[derive(Component)]
pub(crate) struct DialoguePanelRoot;

#[derive(Component, Debug, Clone)]
pub(crate) struct InteractionMenuButton {
    pub target_id: InteractionTargetId,
    pub option_id: game_data::InteractionOptionId,
    pub is_primary: bool,
}

#[derive(Component)]
pub(crate) struct InteractionLockedActorTag;

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
    pub actor_id: ActorId,
    pub target_id: Option<InteractionTargetId>,
    pub dialogue_key: String,
    pub dialog_id: String,
    pub data: DialogueData,
    pub current_node_id: String,
    pub target_name: String,
}
