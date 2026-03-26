use std::collections::HashMap;

use bevy::prelude::*;
use game_bevy::SettlementDebugSnapshot;
use game_core::SimulationRuntime;
use game_core::SimulationSnapshot;
use game_data::{
    ActorId, ActorSide, DialogueData, GridCoord, InteractionPrompt, InteractionTargetId, WorldCoord,
};

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
pub(crate) enum ViewerControlMode {
    #[default]
    PlayerControl,
    FreeObserve,
}

impl ViewerControlMode {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::PlayerControl => "Player Control",
            Self::FreeObserve => "Free Observe",
        }
    }

    pub(crate) fn toggle(self) -> Self {
        match self {
            Self::PlayerControl => Self::FreeObserve,
            Self::FreeObserve => Self::PlayerControl,
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

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct ActorMotionTrack {
    pub from_world: WorldCoord,
    pub to_world: WorldCoord,
    pub current_world: WorldCoord,
    pub elapsed_sec: f32,
    pub duration_sec: f32,
    pub level: i32,
    pub active: bool,
}

impl ActorMotionTrack {
    pub(crate) fn new(
        from_world: WorldCoord,
        to_world: WorldCoord,
        level: i32,
        duration_sec: f32,
    ) -> Self {
        Self {
            from_world,
            to_world,
            current_world: from_world,
            elapsed_sec: 0.0,
            duration_sec,
            level,
            active: true,
        }
    }

    pub(crate) fn advance(&mut self, delta_sec: f32) {
        if !self.active {
            return;
        }

        self.elapsed_sec = (self.elapsed_sec + delta_sec).min(self.duration_sec.max(0.0));
        let progress = if self.duration_sec <= f32::EPSILON {
            1.0
        } else {
            (self.elapsed_sec / self.duration_sec).clamp(0.0, 1.0)
        };
        self.current_world = lerp_world_coord(self.from_world, self.to_world, progress);
        if progress >= 1.0 {
            self.current_world = self.to_world;
            self.active = false;
        }
    }

    pub(crate) fn snap_to(&mut self, world: WorldCoord, level: i32) {
        self.from_world = world;
        self.to_world = world;
        self.current_world = world;
        self.elapsed_sec = 0.0;
        self.level = level;
        self.active = false;
    }
}

#[derive(Resource, Debug, Default)]
pub(crate) struct ViewerActorMotionState {
    pub tracks: HashMap<ActorId, ActorMotionTrack>,
}

impl ViewerActorMotionState {
    pub(crate) fn current_world(&self, actor_id: ActorId) -> Option<WorldCoord> {
        self.tracks.get(&actor_id).map(|track| track.current_world)
    }

    pub(crate) fn track_movement(
        &mut self,
        actor_id: ActorId,
        from_world: WorldCoord,
        to_world: WorldCoord,
        level: i32,
        duration_sec: f32,
    ) {
        self.tracks.insert(
            actor_id,
            ActorMotionTrack::new(from_world, to_world, level, duration_sec),
        );
    }
}

fn lerp_world_coord(start: WorldCoord, end: WorldCoord, t: f32) -> WorldCoord {
    WorldCoord::new(
        start.x + (end.x - start.x) * t,
        start.y + (end.y - start.y) * t,
        start.z + (end.z - start.z) * t,
    )
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
            hud_reserved_width_px: 620.0,
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
    pub controlled_player_actor: Option<ActorId>,
    pub focused_target: Option<InteractionTargetId>,
    pub current_prompt: Option<InteractionPrompt>,
    pub interaction_menu: Option<InteractionMenuState>,
    pub active_dialogue: Option<ActiveDialogueState>,
    pub hud_page: ViewerHudPage,
    pub control_mode: ViewerControlMode,
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
            controlled_player_actor: None,
            focused_target: None,
            current_prompt: None,
            interaction_menu: None,
            active_dialogue: None,
            hud_page: ViewerHudPage::Overview,
            control_mode: ViewerControlMode::PlayerControl,
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
    pub(crate) fn select_actor(&mut self, actor_id: ActorId, side: ActorSide) {
        self.selected_actor = Some(actor_id);
        if side == ActorSide::Player {
            self.controlled_player_actor = Some(actor_id);
        }
    }

    pub(crate) fn is_free_observe(self: &Self) -> bool {
        self.control_mode == ViewerControlMode::FreeObserve
    }

    pub(crate) fn can_issue_player_commands(self: &Self) -> bool {
        self.control_mode == ViewerControlMode::PlayerControl
    }

    pub(crate) fn command_actor_id(&self, snapshot: &SimulationSnapshot) -> Option<ActorId> {
        if !self.can_issue_player_commands() {
            return None;
        }

        self.selected_actor
            .filter(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == *actor_id && actor.side == ActorSide::Player)
            })
            .or(self.controlled_player_actor.filter(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == *actor_id && actor.side == ActorSide::Player)
            }))
            .or_else(|| {
                snapshot
                    .actors
                    .iter()
                    .find(|actor| actor.side == ActorSide::Player)
                    .map(|actor| actor.actor_id)
            })
    }

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

#[cfg(test)]
mod tests {
    use super::{ActorMotionTrack, ViewerControlMode, ViewerState};
    use game_core::{
        ActorDebugState, CombatDebugState, GridDebugState, OverworldStateSnapshot,
        SimulationSnapshot,
    };
    use game_data::{
        ActorId, ActorKind, ActorSide, CharacterId, GridCoord, InteractionContextSnapshot,
        TurnState, WorldCoord,
    };

    #[test]
    fn command_actor_uses_selected_player_in_player_control_mode() {
        let snapshot = snapshot_with_actors(vec![
            actor(ActorId(1), ActorSide::Player, "player"),
            actor(ActorId(2), ActorSide::Friendly, "guard"),
        ]);
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(ActorId(1), ActorSide::Player);

        assert_eq!(viewer_state.command_actor_id(&snapshot), Some(ActorId(1)));
    }

    #[test]
    fn command_actor_is_disabled_in_free_observe_mode() {
        let snapshot = snapshot_with_actors(vec![actor(ActorId(1), ActorSide::Player, "player")]);
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(ActorId(1), ActorSide::Player);
        viewer_state.control_mode = ViewerControlMode::FreeObserve;

        assert_eq!(viewer_state.command_actor_id(&snapshot), None);
    }

    #[test]
    fn actor_motion_track_interpolates_linearly() {
        let mut track = ActorMotionTrack::new(
            WorldCoord::new(0.5, 0.5, 0.5),
            WorldCoord::new(1.5, 0.5, 0.5),
            0,
            0.1,
        );

        track.advance(0.05);

        assert_eq!(track.current_world, WorldCoord::new(1.0, 0.5, 0.5));
        assert!(track.active);

        track.advance(0.05);

        assert_eq!(track.current_world, WorldCoord::new(1.5, 0.5, 0.5));
        assert!(!track.active);
    }

    #[test]
    fn actor_motion_track_snaps_to_authoritative_world() {
        let mut track = ActorMotionTrack::new(
            WorldCoord::new(0.5, 0.5, 0.5),
            WorldCoord::new(1.5, 0.5, 0.5),
            0,
            0.1,
        );

        track.advance(0.03);
        track.snap_to(WorldCoord::new(4.5, 1.5, 2.5), 1);

        assert_eq!(track.current_world, WorldCoord::new(4.5, 1.5, 2.5));
        assert_eq!(track.level, 1);
        assert_eq!(track.elapsed_sec, 0.0);
        assert!(!track.active);
    }

    fn actor(actor_id: ActorId, side: ActorSide, definition_id: &str) -> ActorDebugState {
        ActorDebugState {
            actor_id,
            definition_id: Some(CharacterId(definition_id.into())),
            display_name: definition_id.into(),
            kind: ActorKind::Npc,
            side,
            group_id: "group".into(),
            ap: 6.0,
            available_steps: 3,
            turn_open: false,
            in_combat: false,
            grid_position: GridCoord::new(0, 0, 0),
            level: 1,
            current_xp: 0,
            available_stat_points: 0,
            available_skill_points: 0,
            hp: 10.0,
            max_hp: 10.0,
        }
    }

    fn snapshot_with_actors(actors: Vec<ActorDebugState>) -> SimulationSnapshot {
        SimulationSnapshot {
            turn: TurnState::default(),
            actors,
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(8),
                map_height: Some(8),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: Vec::new(),
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        }
    }
}
