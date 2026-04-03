//! Viewer 交互状态：定义控制模式、目标选择、交互菜单和对话状态。

use std::collections::BTreeSet;

use bevy::prelude::*;
use game_core::SimulationSnapshot;
use game_data::{
    ActorId, ActorSide, DialogueData, GridCoord, InteractionPrompt, InteractionTargetId,
    SkillTargetRequest,
};

use super::runtime::ViewerRuntimeState;

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
pub(crate) enum ViewerCameraMode {
    #[default]
    FollowSelectedActor,
    ManualPan,
}

impl ViewerCameraMode {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::FollowSelectedActor => "Follow Selected Actor",
            Self::ManualPan => "Manual Pan",
        }
    }
}

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum HudEventFilter {
    #[default]
    All,
    Combat,
    Interaction,
    World,
}

#[allow(dead_code)]
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

#[derive(Resource, Debug)]
pub(crate) struct ViewerState {
    pub selected_actor: Option<ActorId>,
    pub controlled_player_actor: Option<ActorId>,
    pub focused_target: Option<InteractionTargetId>,
    pub current_prompt: Option<InteractionPrompt>,
    pub interaction_menu: Option<InteractionMenuState>,
    pub active_dialogue: Option<ActiveDialogueState>,
    pub control_mode: ViewerControlMode,
    pub camera_mode: ViewerCameraMode,
    pub event_filter: HudEventFilter,
    pub show_fps_overlay: bool,
    pub show_walkable_tiles_overlay: bool,
    pub show_controls: bool,
    pub hovered_grid: Option<GridCoord>,
    pub targeting_state: Option<ViewerTargetingState>,
    pub current_level: i32,
    pub auto_tick: bool,
    pub end_turn_repeat_delay_sec: f32,
    pub end_turn_repeat_interval_sec: f32,
    pub end_turn_hold_sec: f32,
    pub end_turn_repeat_elapsed_sec: f32,
    pub auto_end_turn_after_stop: bool,
    pub min_progression_interval_sec: f32,
    pub progression_elapsed_sec: f32,
    pub camera_pan_offset: Vec2,
    pub camera_drag_cursor: Option<Vec2>,
    pub camera_drag_anchor_world: Option<Vec2>,
    pub pending_open_trade_target: Option<InteractionTargetId>,
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
            control_mode: ViewerControlMode::PlayerControl,
            camera_mode: ViewerCameraMode::FollowSelectedActor,
            event_filter: HudEventFilter::All,
            show_fps_overlay: false,
            show_walkable_tiles_overlay: false,
            show_controls: false,
            hovered_grid: None,
            targeting_state: None,
            current_level: 0,
            auto_tick: false,
            end_turn_repeat_delay_sec: 0.2,
            end_turn_repeat_interval_sec: 0.1,
            end_turn_hold_sec: 0.0,
            end_turn_repeat_elapsed_sec: 0.0,
            auto_end_turn_after_stop: false,
            min_progression_interval_sec: 0.1,
            progression_elapsed_sec: 0.0,
            camera_pan_offset: Vec2::ZERO,
            camera_drag_cursor: None,
            camera_drag_anchor_world: None,
            pending_open_trade_target: None,
            status_line: String::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ViewerTargetingAction {
    Attack,
    Skill {
        skill_id: String,
        skill_name: String,
    },
}

impl ViewerTargetingAction {
    pub(crate) fn label(&self) -> &str {
        match self {
            Self::Attack => "普通攻击",
            Self::Skill { skill_name, .. } => skill_name.as_str(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ViewerTargetingSource {
    AttackButton,
    HotbarSlot(usize),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ViewerTargetingState {
    pub actor_id: ActorId,
    pub action: ViewerTargetingAction,
    pub source: ViewerTargetingSource,
    pub shape: String,
    pub radius: i32,
    pub valid_grids: BTreeSet<GridCoord>,
    pub valid_actor_ids: BTreeSet<ActorId>,
    pub hovered_grid: Option<GridCoord>,
    pub preview_target: Option<SkillTargetRequest>,
    pub preview_hit_grids: Vec<GridCoord>,
    pub preview_hit_actor_ids: Vec<ActorId>,
    pub prompt_text: String,
}

impl ViewerTargetingState {
    pub(crate) fn is_attack(&self) -> bool {
        matches!(self.action, ViewerTargetingAction::Attack)
    }
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

impl ViewerState {
    pub(crate) fn select_actor(&mut self, actor_id: ActorId, side: ActorSide) {
        if self.is_free_observe() {
            self.selected_actor = Some(actor_id);
            return;
        }

        self.selected_actor = None;
        if side == ActorSide::Player {
            self.controlled_player_actor = Some(actor_id);
        }
    }

    pub(crate) fn is_free_observe(&self) -> bool {
        self.control_mode == ViewerControlMode::FreeObserve
    }

    pub(crate) fn can_issue_player_commands(&self) -> bool {
        self.control_mode == ViewerControlMode::PlayerControl
    }

    pub(crate) fn is_player_control(&self) -> bool {
        self.can_issue_player_commands()
    }

    pub(crate) fn is_camera_following_selected_actor(&self) -> bool {
        self.camera_mode == ViewerCameraMode::FollowSelectedActor
    }

    pub(crate) fn disable_camera_follow(&mut self) {
        self.camera_mode = ViewerCameraMode::ManualPan;
    }

    pub(crate) fn resume_camera_follow(&mut self) {
        self.camera_mode = ViewerCameraMode::FollowSelectedActor;
        self.camera_pan_offset = Vec2::ZERO;
        self.camera_drag_cursor = None;
        self.camera_drag_anchor_world = None;
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

    pub(crate) fn focus_actor_id(&self, snapshot: &SimulationSnapshot) -> Option<ActorId> {
        self.selected_actor
            .filter(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == *actor_id)
            })
            .or(self.controlled_player_actor.filter(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == *actor_id)
            }))
            .or_else(|| {
                snapshot
                    .actors
                    .iter()
                    .find(|actor| actor.side == ActorSide::Player)
                    .map(|actor| actor.actor_id)
            })
            .or_else(|| snapshot.actors.first().map(|actor| actor.actor_id))
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
