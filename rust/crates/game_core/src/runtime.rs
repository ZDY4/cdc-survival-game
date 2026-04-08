use std::collections::BTreeSet;

use game_data::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, ActorSide, CharacterId,
    DialogueLibrary, DialogueRuleLibrary, EffectLibrary, GridCoord, InteractionContextSnapshot,
    InteractionExecutionRequest, InteractionExecutionResult, InteractionOptionId,
    InteractionPrompt, InteractionTargetId, ItemFragment, ItemLibrary, MapLibrary,
    OverworldLibrary, QuestLibrary, RecipeLibrary, ShopLibrary, SkillLibrary, SkillTargetRequest,
    WorldCoord, WorldMode,
};
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

use crate::economy::{CraftOutcome, EconomyRuntimeError, HeadlessEconomyRuntime, TradeOutcome};
use crate::grid::GridPathfindingError;
use crate::movement::{
    AutoMoveInterruptReason, MovementCommandOutcome, MovementPlan, MovementPlanError,
    PendingInteractionIntent, PendingMovementIntent, PendingProgressionStep,
    ProgressionAdvanceResult, RecentOverworldArrival,
};
use crate::simulation::{
    RegisterActor, Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent,
    SimulationSnapshot, SimulationStateSnapshot, SkillActivationResult, SkillRuntimeState,
};
use crate::vision::{
    ActorVisionSnapshot, ActorVisionUpdate, VisionRuntimeSnapshot, VisionRuntimeState,
};
use crate::{NpcBackgroundState, NpcRuntimeActionState};

mod dialogue;
mod interaction;
mod overworld;
mod runtime_actions;
mod runtime_economy;
mod runtime_facade;
mod runtime_movement;
mod runtime_queries;
mod runtime_snapshots;

pub const RUNTIME_SNAPSHOT_SCHEMA_VERSION: u32 = 1;

const fn default_runtime_snapshot_schema_version() -> u32 {
    RUNTIME_SNAPSHOT_SCHEMA_VERSION
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RuntimeSnapshot {
    #[serde(default = "default_runtime_snapshot_schema_version")]
    pub schema_version: u32,
    pub(crate) simulation: SimulationStateSnapshot,
    #[serde(default)]
    pub vision: VisionRuntimeSnapshot,
    #[serde(default)]
    pub pending_movement: Option<PendingMovementIntent>,
    #[serde(default)]
    pub pending_interaction: Option<PendingInteractionIntent>,
    #[serde(default)]
    pub pending_movement_stop_requested: bool,
    #[serde(default)]
    pub path_preview: Vec<GridCoord>,
    #[serde(default)]
    pub tick_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DropItemOutcome {
    pub object_id: String,
    pub item_id: u32,
    pub count: i32,
    pub grid: GridCoord,
}

#[derive(Debug)]
pub struct SimulationRuntime {
    simulation: Simulation,
    vision: VisionRuntimeState,
    pending_movement: Option<PendingMovementIntent>,
    pending_interaction: Option<PendingInteractionIntent>,
    pending_movement_stop_requested: bool,
    recent_overworld_arrival: Option<RecentOverworldArrival>,
    path_preview: Vec<GridCoord>,
    tick_count: u64,
}

impl Default for SimulationRuntime {
    fn default() -> Self {
        Self::new()
    }
}

pub fn pathfinding_error_reason(error: &GridPathfindingError) -> &'static str {
    match error {
        GridPathfindingError::TargetOutOfBounds => "target_out_of_bounds",
        GridPathfindingError::TargetInvalidLevel => "target_invalid_level",
        GridPathfindingError::TargetBlocked => "target_blocked",
        GridPathfindingError::TargetOccupied => "target_occupied",
        GridPathfindingError::NoPath => "no_path",
    }
}

pub fn movement_plan_error_reason(error: &MovementPlanError) -> &'static str {
    match error {
        MovementPlanError::UnknownActor { .. } => "unknown_actor",
        MovementPlanError::ActorNotPlayerControlled => "actor_not_player_controlled",
        MovementPlanError::InputNotAllowed => "input_not_allowed",
        MovementPlanError::TargetOutOfBounds => "target_out_of_bounds",
        MovementPlanError::TargetInvalidLevel => "target_invalid_level",
        MovementPlanError::TargetBlocked => "target_blocked",
        MovementPlanError::TargetOccupied => "target_occupied",
        MovementPlanError::NoPath => "no_path",
    }
}

fn action_result_reason(result: ActionResult, fallback: &str) -> String {
    result.reason.unwrap_or_else(|| fallback.to_string())
}

fn string_action_error(_actor_id: ActorId, result: ActionResult) -> String {
    action_result_reason(result, "action_rejected")
}

fn economy_action_error(actor_id: ActorId, result: ActionResult) -> EconomyRuntimeError {
    match result.reason.as_deref() {
        Some("unknown_actor") => EconomyRuntimeError::UnknownActor { actor_id },
        Some(reason) => EconomyRuntimeError::ActionRejected {
            reason: reason.to_string(),
        },
        None => EconomyRuntimeError::ActionRejected {
            reason: "action_rejected".to_string(),
        },
    }
}

pub fn action_result_status(result: &ActionResult) -> String {
    if result.success {
        format!(
            "ok ap_before={:.1} ap_after={:.1} consumed={:.1}",
            result.ap_before, result.ap_after, result.consumed
        )
    } else {
        format!(
            "rejected reason={}",
            result.reason.as_deref().unwrap_or("unknown")
        )
    }
}

fn movement_plan_error_to_interrupt_reason(error: &MovementPlanError) -> AutoMoveInterruptReason {
    match error {
        MovementPlanError::UnknownActor { .. } => AutoMoveInterruptReason::UnknownActor,
        MovementPlanError::ActorNotPlayerControlled => {
            AutoMoveInterruptReason::ActorNotPlayerControlled
        }
        MovementPlanError::InputNotAllowed => AutoMoveInterruptReason::InputNotAllowed,
        MovementPlanError::TargetOutOfBounds => AutoMoveInterruptReason::TargetOutOfBounds,
        MovementPlanError::TargetInvalidLevel => AutoMoveInterruptReason::TargetInvalidLevel,
        MovementPlanError::TargetBlocked => AutoMoveInterruptReason::TargetBlocked,
        MovementPlanError::TargetOccupied => AutoMoveInterruptReason::TargetOccupied,
        MovementPlanError::NoPath => AutoMoveInterruptReason::NoPath,
    }
}

fn interaction_approach_error_to_interrupt_reason(reason: &str) -> AutoMoveInterruptReason {
    match reason {
        "unknown_actor" => AutoMoveInterruptReason::UnknownActor,
        "interaction_target_unavailable" | "interaction_option_unavailable" => {
            AutoMoveInterruptReason::InteractionTargetUnavailable
        }
        "no_interaction_path" => AutoMoveInterruptReason::NoPath,
        _ => AutoMoveInterruptReason::NoPath,
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use game_data::{
        ActionType, ActorId, ActorKind, ActorSide, CharacterId, DialogueAction, DialogueData,
        DialogueLibrary, DialogueNode, DialogueOption, GridCoord, InteractionExecutionRequest,
        InteractionOptionId, InteractionTargetId, ItemDefinition, ItemFragment, ItemLibrary,
        MapDefinition, MapEntryPointDefinition, MapId, MapInteractiveProps, MapLevelDefinition,
        MapLibrary, MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps,
        MapPickupProps, MapRotation, MapSize, OverworldCellDefinition, OverworldDefinition,
        OverworldId, OverworldLibrary, OverworldLocationDefinition, OverworldLocationId,
        OverworldLocationKind, OverworldTerrainKind, OverworldTravelRuleSet, QuestConnection,
        QuestDefinition, QuestFlow, QuestLibrary, QuestNode, QuestRewards, RecipeDefinition,
        RecipeLibrary, RecipeMaterial, RecipeOutput, ShopDefinition, ShopInventoryEntry,
        ShopLibrary, SkillActivationDefinition, SkillActivationEffect, SkillDefinition,
        SkillLibrary, SkillModifierDefinition, SkillTargetRequest, SkillTargetingDefinition,
        WorldMode,
    };

    use super::SimulationRuntime;
    use crate::demo::create_demo_runtime;
    use crate::movement::{AutoMoveInterruptReason, PendingProgressionStep};
    use crate::simulation::{
        RegisterActor, Simulation, SimulationCommand, SimulationCommandResult,
    };

    #[test]
    fn demo_runtime_boots_with_player_turn_open() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        assert!(snapshot.combat.in_combat == false);
        assert_eq!(snapshot.actors.len(), 3);
        assert!(snapshot.actors.iter().any(|actor| {
            actor.actor_id == handles.player
                && actor.side == ActorSide::Player
                && actor.turn_open
                && (actor.ap - 1.0).abs() < f32::EPSILON
        }));
    }

    fn set_runtime_actor_ap(runtime: &mut SimulationRuntime, actor_id: ActorId, ap: f32) {
        let mut snapshot = runtime.save_snapshot();
        snapshot.simulation.config.turn_ap_max = snapshot.simulation.config.turn_ap_max.max(ap);
        runtime
            .load_snapshot(snapshot)
            .expect("runtime snapshot should reload");
        runtime.simulation.set_actor_ap(actor_id, ap);
    }

    #[test]
    fn move_actor_to_command_updates_path_preview_and_position() {
        let (mut runtime, handles) = create_demo_runtime();
        let result = runtime.submit_command(SimulationCommand::MoveActorTo {
            actor_id: handles.player,
            goal: GridCoord::new(0, 0, 1),
        });

        match result {
            SimulationCommandResult::Action(action) => {
                assert!(action.success);
            }
            other => panic!("unexpected command result: {other:?}"),
        }

        let snapshot = runtime.snapshot();
        assert_eq!(
            snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == handles.player)
                .map(|actor| actor.grid_position),
            Some(GridCoord::new(0, 0, 1))
        );
        assert_eq!(
            snapshot.path_preview.last().copied(),
            Some(GridCoord::new(0, 0, 1))
        );
    }

    #[test]
    fn runtime_exposes_turn_query_helpers() {
        let (runtime, handles) = create_demo_runtime();

        assert!(runtime.can_actor_afford(handles.player, ActionType::Move, Some(1)));
        assert!(!runtime.can_actor_afford(handles.player, ActionType::Move, Some(2)));
        assert_eq!(runtime.get_actor_available_steps(handles.player), 1);
        assert_eq!(runtime.get_actor_group_id(handles.player), Some("player"));
        assert_eq!(
            runtime.get_actor_side(handles.player),
            Some(ActorSide::Player)
        );
        assert!(runtime.actor_turn_open(handles.player));
        assert!(!runtime.is_in_combat());
        assert!(!runtime.is_actor_current_turn(handles.player));
        assert!(runtime.is_actor_input_allowed(handles.player));
    }

    #[test]
    fn move_actor_to_reachable_truncates_by_available_steps() {
        let (mut runtime, handles) = create_demo_runtime();

        let outcome = runtime
            .move_actor_to_reachable(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");

        assert!(outcome.result.success);
        assert!(outcome.plan.is_truncated());
        assert_eq!(outcome.plan.requested_steps(), 2);
        assert_eq!(outcome.plan.resolved_steps(), 1);
        assert_eq!(outcome.plan.resolved_goal, GridCoord::new(0, 0, 1));

        let snapshot = runtime.snapshot();
        assert_eq!(
            snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == handles.player)
                .map(|actor| actor.grid_position),
            Some(GridCoord::new(0, 0, 1))
        );
        assert_eq!(
            snapshot.path_preview.last().copied(),
            Some(GridCoord::new(0, 0, 2))
        );
    }

    #[test]
    fn move_actor_to_reachable_rejects_when_ap_is_zero() {
        let (mut runtime, handles) = create_demo_runtime();
        runtime.submit_command(SimulationCommand::SetActorAp {
            actor_id: handles.player,
            ap: 0.0,
        });

        let outcome = runtime
            .move_actor_to_reachable(handles.player, GridCoord::new(0, 0, 1))
            .expect("planning should still succeed");

        assert!(!outcome.result.success);
        assert_eq!(outcome.result.reason.as_deref(), Some("insufficient_ap"));
        assert_eq!(outcome.plan.resolved_steps(), 0);
        assert_eq!(
            runtime.get_actor_grid_position(handles.player),
            Some(GridCoord::new(0, 0, 0))
        );
    }

    #[test]
    fn issue_actor_move_enqueues_discrete_progression() {
        let (mut runtime, handles) = create_demo_runtime();

        let outcome = runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");

        assert!(outcome.result.success);
        assert!(outcome.plan.is_truncated());
        assert_eq!(
            runtime.pending_movement(),
            Some(&crate::movement::PendingMovementIntent {
                actor_id: handles.player,
                requested_goal: GridCoord::new(0, 0, 2),
            })
        );
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert_eq!(
            runtime.get_actor_grid_position(handles.player),
            Some(GridCoord::new(0, 0, 1))
        );
        assert_eq!(
            runtime.snapshot().path_preview.last().copied(),
            Some(GridCoord::new(0, 0, 2))
        );
    }

    #[test]
    fn advance_pending_progression_moves_one_stage_at_a_time() {
        let (mut runtime, handles) = create_demo_runtime();

        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");

        let world_cycle = runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert!(!runtime.actor_turn_open(handles.player));
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );

        let next_turn = runtime.advance_pending_progression();
        assert_eq!(
            next_turn.applied_step,
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
        assert!(runtime.actor_turn_open(handles.player));
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::ContinuePendingMovement)
        );

        let continue_move = runtime.advance_pending_progression();
        assert_eq!(
            continue_move.applied_step,
            Some(PendingProgressionStep::ContinuePendingMovement)
        );
        assert!(continue_move.reached_goal);
        assert_eq!(
            continue_move.interrupt_reason,
            Some(AutoMoveInterruptReason::ReachedGoal)
        );
        assert_eq!(
            runtime.get_actor_grid_position(handles.player),
            Some(GridCoord::new(0, 0, 2))
        );
        assert!(runtime.pending_movement().is_none());
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
    }

    #[test]
    fn issue_actor_move_noop_does_not_create_pending_state() {
        let (mut runtime, handles) = create_demo_runtime();

        let outcome = runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 0))
            .expect("no-op move should still plan");

        assert!(outcome.result.success);
        assert_eq!(outcome.plan.requested_steps(), 0);
        assert!(runtime.pending_movement().is_none());
        assert!(!runtime.has_pending_progression());
    }

    #[test]
    fn explicit_commands_cancel_pending_movement() {
        let (mut runtime, handles) = create_demo_runtime();

        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");
        let result = runtime.submit_command(SimulationCommand::EndTurn {
            actor_id: handles.player,
        });

        match result {
            SimulationCommandResult::Action(action) => assert!(action.success),
            other => panic!("unexpected command result: {other:?}"),
        }

        assert!(runtime.pending_movement().is_none());
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
    }

    #[test]
    fn query_interaction_prompt_cancels_pending_movement() {
        let (mut runtime, handles) = create_demo_runtime();

        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");

        let prompt = runtime
            .query_interaction_prompt(handles.player, InteractionTargetId::Actor(handles.friendly));

        assert!(prompt.is_some());
        assert!(runtime.pending_movement().is_none());
        assert!(!runtime.has_pending_progression());
        assert_eq!(
            runtime.get_actor_grid_position(handles.player),
            Some(GridCoord::new(0, 0, 1))
        );
    }

    #[test]
    fn deferred_stop_finishes_current_pending_step_then_clears_remaining_path() {
        let (mut runtime, handles) = create_demo_runtime();

        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 3))
            .expect("path should be planned");

        let world_cycle = runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        let next_turn = runtime.advance_pending_progression();
        assert_eq!(
            next_turn.applied_step,
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::ContinuePendingMovement)
        );

        assert!(runtime.request_pending_movement_stop(handles.player));
        assert!(runtime.pending_movement().is_some());

        let continue_move = runtime.advance_pending_progression();
        assert_eq!(
            continue_move.applied_step,
            Some(PendingProgressionStep::ContinuePendingMovement)
        );
        assert!(continue_move.interrupted);
        assert_eq!(
            continue_move.interrupt_reason,
            Some(AutoMoveInterruptReason::CancelledByNewCommand)
        );
        assert_eq!(
            runtime.get_actor_grid_position(handles.player),
            Some(GridCoord::new(0, 0, 2))
        );
        assert!(runtime.pending_movement().is_none());
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert!(runtime.actor_turn_open(handles.player));

        let world_cycle = runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert!(!runtime.actor_turn_open(handles.player));
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
    }

    #[test]
    fn runtime_inventory_query_reads_through_simulation_economy() {
        let mut simulation = Simulation::new();
        simulation
            .grid_world_mut()
            .load_map(&sample_interaction_map_definition());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(1, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let mut runtime = SimulationRuntime::from_simulation(simulation);
        let set_ap = runtime.submit_command(SimulationCommand::SetActorAp {
            actor_id: player,
            ap: 2.0,
        });
        assert!(matches!(set_ap, SimulationCommandResult::None));

        let result = runtime.issue_interaction(
            player,
            game_data::InteractionTargetId::MapObject("pickup".into()),
            game_data::InteractionOptionId("pickup".into()),
        );

        assert!(result.success);
        assert_eq!(runtime.get_actor_inventory_count(player, "1005"), 2);
    }

    #[test]
    fn issue_interaction_executes_immediately_after_synchronous_approach() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(2, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_ap(player, 2.0);

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        let result = runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );

        assert!(result.success);
        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 1))
        );
    }

    #[test]
    fn pending_interaction_opens_dialogue_immediately_when_approach_used_last_ap() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(2, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_ap(player, 1.0);

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        let result = runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );

        assert!(result.success);
        assert!(!result.approach_required);
        assert_eq!(
            result.action_result.as_ref().map(|action| action.consumed),
            Some(0.0)
        );
        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 1))
        );
        assert!(runtime.pending_movement().is_none());
        assert!(runtime.pending_interaction().is_none());
        assert_eq!(
            runtime
                .active_dialogue_state(player)
                .and_then(|state| state.current_node)
                .map(|node| node.id),
            Some("start".to_string())
        );
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );

        let world_cycle = runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert!(runtime.pending_interaction().is_none());
        assert!(world_cycle.interaction_outcome.is_none());

        let next_turn = runtime.advance_pending_progression();
        assert_eq!(
            next_turn.applied_step,
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
        assert!(next_turn.interaction_outcome.is_none());
        assert_eq!(
            runtime
                .active_dialogue_state(player)
                .and_then(|state| state.current_node)
                .map(|node| node.id),
            Some("start".to_string())
        );
    }

    #[test]
    fn immediate_talk_result_supports_viewer_fallback_when_runtime_session_is_missing() {
        let mut simulation = Simulation::new();
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(2, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_ap(player, 1.0);

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        let result = runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );

        assert!(result.success);
        assert_eq!(result.dialogue_id.as_deref(), Some("trader_lao_wang"));
        assert!(result.dialogue_state.is_none());
        assert!(runtime.pending_interaction().is_none());
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
    }

    #[test]
    fn pending_interaction_retargets_when_target_actor_moves() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(4, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        let result = runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );

        assert!(result.success);
        assert!(result.approach_required);
        assert_eq!(
            runtime
                .pending_movement()
                .map(|intent| intent.requested_goal),
            Some(GridCoord::new(3, 0, 1))
        );
        assert_eq!(
            runtime
                .pending_interaction()
                .map(|intent| intent.approach_goal),
            Some(GridCoord::new(3, 0, 1))
        );

        let move_target = runtime.submit_command(SimulationCommand::UpdateActorGridPosition {
            actor_id: npc,
            grid: GridCoord::new(6, 0, 1),
        });
        assert!(matches!(move_target, SimulationCommandResult::None));

        let world_cycle = runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        let next_turn = runtime.advance_pending_progression();
        assert_eq!(
            next_turn.applied_step,
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );

        let progression = runtime.advance_pending_progression();

        assert_eq!(progression.final_position, Some(GridCoord::new(2, 0, 1)));
        assert_eq!(
            runtime
                .pending_movement()
                .map(|intent| intent.requested_goal),
            Some(GridCoord::new(5, 0, 1))
        );
        assert_eq!(
            runtime
                .pending_interaction()
                .map(|intent| intent.approach_goal),
            Some(GridCoord::new(5, 0, 1))
        );
        assert_eq!(
            runtime.snapshot().path_preview.last().copied(),
            Some(GridCoord::new(5, 0, 1))
        );
    }

    #[test]
    fn pending_interaction_executes_when_target_moves_into_range() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(4, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let mut runtime = SimulationRuntime::from_simulation(simulation);

        let result = runtime.issue_interaction(
            player,
            InteractionTargetId::Actor(npc),
            InteractionOptionId("talk".into()),
        );

        assert!(result.success);
        assert!(result.approach_required);

        let move_target = runtime.submit_command(SimulationCommand::UpdateActorGridPosition {
            actor_id: npc,
            grid: GridCoord::new(1, 0, 1),
        });
        assert!(matches!(move_target, SimulationCommandResult::None));

        let world_cycle = runtime.advance_pending_progression();
        assert_eq!(
            world_cycle.applied_step,
            Some(PendingProgressionStep::RunNonCombatWorldCycle)
        );
        let next_turn = runtime.advance_pending_progression();
        assert_eq!(
            next_turn.applied_step,
            Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );

        let progression = runtime.advance_pending_progression();

        assert!(progression.reached_goal);
        assert_eq!(progression.final_position, Some(GridCoord::new(1, 0, 1)));
        assert!(runtime.pending_movement().is_none());
        assert!(runtime.pending_interaction().is_none());
        assert!(runtime.snapshot().path_preview.is_empty());
    }

    #[test]
    fn runtime_start_quest_completes_kill_objective_and_rewards_actor() {
        let mut simulation = Simulation::new();
        simulation.set_item_library(sample_reward_item_library());
        simulation.set_quest_library(sample_runtime_quest_library());
        simulation.set_recipe_library(RecipeLibrary::default());

        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.5,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("zombie_walker".into())),
            display_name: "Zombie".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.0,
            ai_controller: None,
        });
        simulation.seed_actor_progression(player, 1, 0);
        simulation.seed_actor_progression(hostile, 1, 25);
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        set_runtime_actor_ap(&mut runtime, player, 2.0);

        assert!(runtime.start_quest(player, "zombie_hunter"));
        assert!(runtime.is_quest_active("zombie_hunter"));

        let result = runtime.submit_command(SimulationCommand::PerformAttack {
            actor_id: player,
            target_actor: hostile,
        });

        match result {
            SimulationCommandResult::Action(action) => assert!(action.success),
            other => panic!("unexpected command result: {other:?}"),
        }

        assert!(runtime.is_quest_completed("zombie_hunter"));
        assert_eq!(runtime.get_actor_inventory_count(player, "1006"), 3);
        assert_eq!(runtime.get_actor_current_xp(player), 35);
    }

    #[test]
    fn runtime_equip_reload_and_unequip_use_runtime_surface() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 3.0);

        runtime.economy_mut().set_actor_level(handles.player, 8);
        runtime
            .economy_mut()
            .add_item(handles.player, 1004, 1, &items)
            .expect("pistol should be added");
        runtime
            .economy_mut()
            .add_ammo(handles.player, 1009, 12, &items)
            .expect("ammo should be added");

        let previous = runtime
            .equip_item(handles.player, 1004, Some("main_hand"), &items)
            .expect("equip should succeed");
        assert_eq!(previous, None);

        let loaded = runtime
            .reload_equipped_weapon(handles.player, "main_hand", &items)
            .expect("reload should succeed");
        assert_eq!(loaded, 6);

        let profile = runtime
            .economy()
            .equipped_weapon(handles.player, "main_hand", &items)
            .expect("weapon should resolve")
            .expect("weapon should exist");
        assert_eq!(profile.item_id, 1004);
        assert_eq!(profile.ammo_loaded, 6);

        let unequipped = runtime
            .unequip_item(handles.player, "main_hand")
            .expect("unequip should succeed");
        assert_eq!(unequipped, 1004);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1004"), 1);
    }

    #[test]
    fn runtime_item_action_keeps_turn_open_when_remaining_ap_meets_threshold() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 2.0);

        runtime.economy_mut().set_actor_level(handles.player, 8);
        runtime
            .economy_mut()
            .add_item(handles.player, 1004, 1, &items)
            .expect("pistol should be added");

        runtime
            .equip_item(handles.player, 1004, Some("main_hand"), &items)
            .expect("equip should succeed");

        assert_eq!(runtime.get_actor_ap(handles.player), 1.0);
        assert!(runtime.actor_turn_open(handles.player));
        assert!(!runtime.has_pending_progression());
    }

    #[test]
    fn runtime_item_action_rejects_on_insufficient_ap_without_mutation() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 0.0);

        runtime.economy_mut().set_actor_level(handles.player, 8);
        runtime
            .economy_mut()
            .add_item(handles.player, 1004, 1, &items)
            .expect("pistol should be added");

        let result = runtime.equip_item(handles.player, 1004, Some("main_hand"), &items);
        let error = result.expect_err("equip should be rejected without AP");
        assert_eq!(error.to_string(), "action rejected: insufficient_ap");
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1004"), 1);
        assert!(runtime
            .economy()
            .equipped_item(handles.player, "main_hand")
            .is_none());
    }

    #[test]
    fn runtime_learn_skill_and_craft_use_runtime_surface() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        let skills = sample_runtime_skill_library();
        let recipes = sample_runtime_recipe_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 2.0);

        runtime
            .economy_mut()
            .set_actor_attribute(handles.player, "intelligence", 3);
        runtime
            .economy_mut()
            .add_skill_points(handles.player, 1)
            .expect("skill points should be granted");
        runtime
            .economy_mut()
            .add_item(handles.player, 1001, 2, &items)
            .expect("materials should be added");
        runtime
            .economy_mut()
            .add_item(handles.player, 1002, 1, &items)
            .expect("tool should be added");
        runtime
            .economy_mut()
            .grant_station_tag(handles.player, "workbench")
            .expect("station tag should be granted");

        let level = runtime
            .learn_skill(handles.player, "crafting_basics", &skills)
            .expect("skill should be learnable");
        assert_eq!(level, 1);

        let outcome = runtime
            .craft_recipe(handles.player, "bandage_recipe", &recipes, &items)
            .expect("recipe should craft");
        assert_eq!(outcome.output_item_id, 1003);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1001"), 0);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1003"), 1);
    }

    #[test]
    fn runtime_activate_targeted_single_skill_hits_actor_and_starts_cooldown() {
        let (mut runtime, handles) = create_demo_runtime();
        let skills = sample_runtime_skill_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 2.0);
        runtime.set_skill_library(skills.clone());
        runtime
            .economy_mut()
            .add_skill_points(handles.player, 1)
            .expect("skill points should be granted");
        runtime
            .learn_skill(handles.player, "fire_bolt", &skills)
            .expect("fire bolt should learn");
        runtime
            .simulation
            .set_actor_combat_attribute(handles.hostile, "max_hp", 12.0);
        runtime.set_actor_resource(handles.hostile, "hp", 12.0);

        let result = runtime.activate_skill(
            handles.player,
            "fire_bolt",
            SkillTargetRequest::Actor(handles.hostile),
        );

        assert!(result.action_result.success);
        assert_eq!(result.hit_actor_ids, vec![handles.hostile]);
        assert!(runtime.skill_cooldown_remaining(handles.player, "fire_bolt") > 0.0);
        assert!(runtime.get_actor_resource(handles.hostile, "hp") < 12.0);

        let cooldown_result = runtime.activate_skill(
            handles.player,
            "fire_bolt",
            SkillTargetRequest::Actor(handles.hostile),
        );
        assert!(!cooldown_result.action_result.success);
        assert_eq!(
            cooldown_result.failure_reason.as_deref(),
            Some("skill_on_cooldown")
        );
    }

    #[test]
    fn runtime_activate_targeted_aoe_skill_uses_grid_target() {
        let (mut runtime, handles) = create_demo_runtime();
        let skills = sample_runtime_skill_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 2.0);
        runtime.set_skill_library(skills.clone());
        runtime
            .economy_mut()
            .add_skill_points(handles.player, 1)
            .expect("skill points should be granted");
        runtime
            .learn_skill(handles.player, "shockwave", &skills)
            .expect("shockwave should learn");
        runtime
            .simulation
            .set_actor_combat_attribute(handles.friendly, "max_hp", 10.0);
        runtime.set_actor_resource(handles.friendly, "hp", 10.0);

        let result = runtime.activate_skill(
            handles.player,
            "shockwave",
            SkillTargetRequest::Grid(GridCoord::new(1, 0, 0)),
        );

        assert!(result.action_result.success);
        assert!(result.hit_actor_ids.contains(&handles.friendly));
        assert!(runtime.get_actor_resource(handles.friendly, "hp") < 10.0);
    }

    #[test]
    fn runtime_buy_and_sell_use_runtime_surface() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        let shops = sample_runtime_shop_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 2.0);
        runtime.set_shop_library(shops);
        runtime
            .economy_mut()
            .grant_money(handles.player, 100)
            .expect("money should be granted");

        let buy = runtime
            .buy_item_from_shop(handles.player, "survivor_outpost_01_shop", 1031, 2, &items)
            .expect("buy should succeed");
        assert_eq!(buy.total_price, 30);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1031"), 2);

        let sell = runtime
            .sell_item_to_shop(handles.player, "survivor_outpost_01_shop", 1031, 1, &items)
            .expect("sell should succeed");
        assert_eq!(sell.total_price, 5);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1031"), 1);
        assert_eq!(runtime.economy().actor_money(handles.player), Some(75));
    }

    #[test]
    fn runtime_drop_item_to_ground_creates_pickup_and_removes_single_item() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 2.0);
        runtime
            .economy_mut()
            .add_item(handles.player, 1002, 1, &items)
            .expect("knife should be added");

        let outcome = runtime
            .drop_item_to_ground(handles.player, 1002, 1, &items)
            .expect("drop should succeed");

        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1002"), 0);
        assert_eq!(outcome.grid, GridCoord::new(-1, 0, 0));
        let object = runtime
            .simulation
            .grid_world()
            .map_object(&outcome.object_id)
            .expect("pickup object should exist");
        let pickup = object
            .props
            .pickup
            .as_ref()
            .expect("pickup payload should exist");
        assert_eq!(object.kind, MapObjectKind::Pickup);
        assert_eq!(object.anchor, outcome.grid);
        assert_eq!(pickup.item_id, "1002");
        assert_eq!(pickup.min_count, 1);
        assert_eq!(pickup.max_count, 1);
    }

    #[test]
    fn runtime_drop_item_to_ground_supports_partial_stack_drops() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 2.0);
        runtime
            .economy_mut()
            .add_item(handles.player, 1003, 5, &items)
            .expect("bandage should be added");

        let outcome = runtime
            .drop_item_to_ground(handles.player, 1003, 2, &items)
            .expect("drop should succeed");

        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1003"), 3);
        let pickup = runtime
            .simulation
            .grid_world()
            .map_object(&outcome.object_id)
            .and_then(|object| object.props.pickup.as_ref())
            .expect("pickup payload should exist");
        assert_eq!(pickup.item_id, "1003");
        assert_eq!(pickup.min_count, 2);
        assert_eq!(pickup.max_count, 2);
    }

    #[test]
    fn runtime_drop_item_to_ground_falls_back_to_actor_grid_when_ring_search_misses() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 2.0);
        runtime
            .economy_mut()
            .add_item(handles.player, 1003, 1, &items)
            .expect("bandage should be added");
        runtime
            .simulation
            .grid_world_mut()
            .load_map(&single_tile_map_definition());

        let outcome = runtime
            .drop_item_to_ground(handles.player, 1003, 1, &items)
            .expect("drop should succeed");

        assert_eq!(outcome.grid, GridCoord::new(0, 0, 0));
        let object = runtime
            .simulation
            .grid_world()
            .map_object(&outcome.object_id)
            .expect("pickup object should exist");
        assert_eq!(object.anchor, GridCoord::new(0, 0, 0));
    }

    #[test]
    fn runtime_drop_item_to_ground_rejects_invalid_count_without_mutation() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_runtime_economy_item_library();
        set_runtime_actor_ap(&mut runtime, handles.player, 2.0);
        runtime
            .economy_mut()
            .add_item(handles.player, 1003, 3, &items)
            .expect("bandage should be added");

        let zero_error = runtime
            .drop_item_to_ground(handles.player, 1003, 0, &items)
            .expect_err("zero-count drop should fail");
        let overflow_error = runtime
            .drop_item_to_ground(handles.player, 1003, 4, &items)
            .expect_err("overflow drop should fail");

        assert_eq!(zero_error, "invalid_drop_count");
        assert_eq!(overflow_error, "insufficient_item_count:1003");
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1003"), 3);
    }

    #[test]
    fn runtime_travel_to_map_and_return_to_overworld_preserve_scene_context() {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_runtime_map_library());
        simulation.set_overworld_library(sample_runtime_overworld_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation
            .seed_overworld_state(
                WorldMode::Outdoor,
                Some("survivor_outpost_01".into()),
                Some("default_entry".into()),
                [
                    "survivor_outpost_01".to_string(),
                    "survivor_outpost_01_interior".to_string(),
                ],
            )
            .expect("overworld state should seed");

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        set_runtime_actor_ap(&mut runtime, player, 2.0);

        let context = runtime
            .travel_to_map(
                player,
                "survivor_outpost_01_interior",
                Some("clinic_entry"),
                WorldMode::Interior,
            )
            .expect("travel to map should succeed");
        assert_eq!(
            context.current_map_id.as_deref(),
            Some("survivor_outpost_01_interior")
        );
        assert_eq!(context.entry_point_id.as_deref(), Some("clinic_entry"));
        assert_eq!(
            context.return_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(context.world_mode, WorldMode::Interior);

        let overworld = runtime
            .return_to_overworld(player)
            .expect("return to overworld should succeed");
        assert_eq!(overworld.world_mode, WorldMode::Overworld);
        assert_eq!(
            overworld.active_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            overworld.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(overworld.current_map_id, None);
        assert_eq!(
            runtime
                .current_interaction_context()
                .return_outdoor_location_id
                .as_deref(),
            Some("survivor_outpost_01")
        );
    }

    #[test]
    fn runtime_start_quest_rejects_on_insufficient_ap_without_state_change() {
        let mut simulation = Simulation::new();
        simulation.set_quest_library(sample_runtime_quest_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        set_runtime_actor_ap(&mut runtime, player, 0.0);

        assert!(!runtime.start_quest(player, "zombie_hunter"));
        assert!(!runtime.is_quest_active("zombie_hunter"));
        assert_eq!(runtime.get_actor_ap(player), 0.0);
    }

    #[test]
    fn runtime_travel_rejects_on_insufficient_ap_without_context_change() {
        let (mut runtime, player) = sample_runtime_with_overworld();
        set_runtime_actor_ap(&mut runtime, player, 0.0);
        let before = runtime.current_interaction_context();

        let error = runtime
            .travel_to_map(
                player,
                "clinic_interior_map",
                Some("clinic_entry"),
                WorldMode::Interior,
            )
            .expect_err("travel should be rejected without AP");

        assert_eq!(error, "insufficient_ap");
        assert_eq!(runtime.current_interaction_context(), before);
    }

    #[test]
    fn runtime_advance_dialogue_does_not_consume_additional_ap() {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        set_runtime_actor_ap(&mut runtime, player, 2.0);

        let talk = runtime.submit_command(SimulationCommand::ExecuteInteraction(
            InteractionExecutionRequest {
                actor_id: player,
                target_id: InteractionTargetId::Actor(trader),
                option_id: InteractionOptionId("talk".into()),
            },
        ));
        match talk {
            SimulationCommandResult::InteractionExecution(result) => assert!(result.success),
            other => panic!("unexpected talk result: {other:?}"),
        }
        assert_eq!(runtime.get_actor_ap(player), 2.0);

        let dialogue = runtime
            .advance_dialogue(
                player,
                Some(InteractionTargetId::Actor(trader)),
                "trader_lao_wang",
                None,
                None,
            )
            .expect("dialogue should advance");

        assert_eq!(
            dialogue.current_node.as_ref().map(|node| node.id.as_str()),
            Some("choice_1")
        );
        assert_eq!(runtime.get_actor_ap(player), 2.0);
    }

    #[test]
    fn runtime_headless_smoke_covers_core_progression_loop() {
        let items = sample_runtime_smoke_item_library();
        let skills = sample_runtime_skill_library();
        let recipes = sample_runtime_recipe_library();
        let shops = sample_runtime_shop_library();
        let quests = sample_runtime_quest_library();
        let maps = sample_runtime_smoke_map_library();
        let interaction_map = sample_interaction_map_definition();

        let mut simulation = Simulation::new();
        simulation.set_item_library(items.clone());
        simulation.set_skill_library(skills.clone());
        simulation.set_recipe_library(recipes.clone());
        simulation.set_shop_library(shops.clone());
        simulation.set_quest_library(quests.clone());
        simulation.set_dialogue_library(sample_runtime_dialogue_library());
        simulation.set_map_library(maps.clone());
        simulation.set_overworld_library(sample_runtime_overworld_library());
        simulation.grid_world_mut().load_map(&interaction_map);
        simulation
            .seed_overworld_state(
                WorldMode::Outdoor,
                Some("survivor_outpost_01".into()),
                Some("default_entry".into()),
                [
                    "survivor_outpost_01".to_string(),
                    "survivor_outpost_01_interior".to_string(),
                ],
            )
            .expect("overworld state should seed");

        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.5,
            ai_controller: None,
        });
        let trader = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 2),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("zombie_walker".into())),
            display_name: "Zombie".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.0,
            ai_controller: None,
        });
        simulation.seed_actor_progression(player, 1, 0);
        simulation.seed_actor_progression(hostile, 1, 25);
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        set_runtime_actor_ap(&mut runtime, player, 10.0);

        let move_result = runtime.submit_command(SimulationCommand::MoveActorTo {
            actor_id: player,
            goal: GridCoord::new(1, 0, 1),
        });
        match move_result {
            SimulationCommandResult::Action(action) => assert!(action.success),
            other => panic!("unexpected move result: {other:?}"),
        }
        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 1))
        );
        set_runtime_actor_ap(&mut runtime, player, 10.0);

        let pickup = runtime.submit_command(SimulationCommand::ExecuteInteraction(
            InteractionExecutionRequest {
                actor_id: player,
                target_id: InteractionTargetId::MapObject("pickup".into()),
                option_id: InteractionOptionId("pickup".into()),
            },
        ));
        match pickup {
            SimulationCommandResult::InteractionExecution(result) => assert!(result.success),
            other => panic!("unexpected pickup result: {other:?}"),
        }
        assert!(runtime.get_actor_inventory_count(player, "1005") >= 1);

        assert!(runtime.start_quest(player, "zombie_hunter"));
        set_runtime_actor_ap(&mut runtime, player, 10.0);
        let attack = runtime.submit_command(SimulationCommand::PerformAttack {
            actor_id: player,
            target_actor: hostile,
        });
        match attack {
            SimulationCommandResult::Action(action) => assert!(action.success),
            other => panic!("unexpected attack result: {other:?}"),
        }
        assert!(runtime.is_quest_completed("zombie_hunter"));
        assert_eq!(runtime.get_actor_inventory_count(player, "1006"), 3);

        set_runtime_actor_ap(&mut runtime, player, 10.0);
        let talk = runtime.submit_command(SimulationCommand::ExecuteInteraction(
            InteractionExecutionRequest {
                actor_id: player,
                target_id: InteractionTargetId::Actor(trader),
                option_id: InteractionOptionId("talk".into()),
            },
        ));
        match talk {
            SimulationCommandResult::InteractionExecution(result) => {
                assert_eq!(result.dialogue_id.as_deref(), Some("trader_lao_wang"));
            }
            other => panic!("unexpected talk result: {other:?}"),
        }
        let dialogue = runtime
            .advance_dialogue(
                player,
                Some(InteractionTargetId::Actor(trader)),
                "trader_lao_wang",
                None,
                None,
            )
            .expect("dialogue should advance");
        assert_eq!(
            dialogue.current_node.as_ref().map(|node| node.id.as_str()),
            Some("choice_1")
        );
        runtime.advance_pending_progression();
        runtime.advance_pending_progression();

        runtime.economy_mut().set_actor_level(player, 8);
        runtime
            .economy_mut()
            .set_actor_attribute(player, "intelligence", 3);
        runtime
            .economy_mut()
            .add_skill_points(player, 1)
            .expect("skill points should be granted");
        runtime
            .economy_mut()
            .add_item(player, 1001, 2, &items)
            .expect("materials should be granted");
        runtime
            .economy_mut()
            .add_item(player, 1002, 1, &items)
            .expect("tool should be granted");
        runtime
            .economy_mut()
            .grant_station_tag(player, "workbench")
            .expect("station tag should be granted");
        runtime
            .economy_mut()
            .grant_money(player, 100)
            .expect("money should be granted");

        assert_eq!(
            runtime
                .learn_skill(player, "crafting_basics", &skills)
                .expect("skill should learn"),
            1
        );
        let craft = runtime
            .craft_recipe(player, "bandage_recipe", &recipes, &items)
            .expect("recipe should craft");
        assert_eq!(craft.output_item_id, 1003);
        let buy = runtime
            .buy_item_from_shop(player, "survivor_outpost_01_shop", 1031, 2, &items)
            .expect("buy should succeed");
        assert_eq!(buy.total_price, 30);
        let sell = runtime
            .sell_item_to_shop(player, "survivor_outpost_01_shop", 1031, 1, &items)
            .expect("sell should succeed");
        assert_eq!(sell.total_price, 5);

        let map_context = runtime
            .travel_to_map(
                player,
                "survivor_outpost_01_interior",
                Some("clinic_entry"),
                WorldMode::Interior,
            )
            .expect("travel to map should succeed");
        assert_eq!(
            map_context.current_map_id.as_deref(),
            Some("survivor_outpost_01_interior")
        );
        assert_eq!(map_context.world_mode, WorldMode::Interior);

        let overworld = runtime
            .return_to_overworld(player)
            .expect("return to overworld should succeed");
        assert_eq!(overworld.world_mode, WorldMode::Overworld);
        assert_eq!(overworld.current_map_id, None);

        let saved = runtime.save_snapshot();
        let mut restored = SimulationRuntime::new();
        restored.set_item_library(items);
        restored.set_skill_library(skills);
        restored.set_recipe_library(recipes);
        restored.set_shop_library(shops);
        restored.set_quest_library(quests);
        restored.set_dialogue_library(sample_runtime_dialogue_library());
        restored.set_map_library(maps);
        restored.set_overworld_library(sample_runtime_overworld_library());
        restored
            .load_snapshot(saved.clone())
            .expect("snapshot should restore");
        assert_eq!(restored.save_snapshot(), saved);
        assert!(restored.is_quest_completed("zombie_hunter"));
        assert_eq!(
            restored.current_interaction_context().world_mode,
            WorldMode::Overworld
        );
    }

    #[test]
    fn runtime_snapshot_round_trip_restores_runtime_state() {
        let items = sample_runtime_economy_item_library();
        let quests = sample_runtime_quest_library();
        let map = sample_interaction_map_definition();
        let map_library = MapLibrary::from(BTreeMap::from([(map.id.clone(), map.clone())]));

        let mut simulation = Simulation::new();
        simulation.set_item_library(items.clone());
        simulation.set_quest_library(quests.clone());
        simulation.set_map_library(map_library.clone());
        simulation.grid_world_mut().load_map(&map);

        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(1, 0, 1),
            interaction: None,
            attack_range: 1.5,
            ai_controller: None,
        });
        let hostile = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("zombie_walker".into())),
            display_name: "Zombie".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Hostile,
            group_id: "hostile".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.0,
            ai_controller: None,
        });
        simulation.seed_actor_progression(player, 1, 0);
        simulation.seed_actor_progression(hostile, 1, 25);
        simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
        simulation.set_actor_resource(hostile, "hp", 5.0);
        assert!(simulation.start_quest(player, "zombie_hunter"));
        assert!(simulation
            .grid_world_mut()
            .remove_map_object("pickup")
            .is_some());
        simulation
            .economy_mut()
            .add_item_unchecked(player, 1005, 2)
            .expect("pickup item should be granted");
        let attack = simulation.perform_attack(player, hostile);
        assert!(attack.success);

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        runtime.tick();
        runtime.tick();
        assert_eq!(runtime.get_actor_inventory_count(player, "1005"), 2);
        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 1))
        );
        assert!(runtime.is_quest_completed("zombie_hunter"));

        let saved = runtime.save_snapshot();

        let mut restored = SimulationRuntime::new();
        restored.set_item_library(items);
        restored.set_quest_library(quests);
        restored.set_map_library(map_library);
        restored
            .load_snapshot(saved.clone())
            .expect("snapshot should load");

        assert_eq!(restored.save_snapshot(), saved);
        assert_eq!(restored.tick_count(), 2);
        assert_eq!(restored.get_actor_inventory_count(player, "1005"), 2);
        assert!(restored.is_quest_completed("zombie_hunter"));
        assert_eq!(
            restored.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 1))
        );

        let restored_debug = restored.snapshot();
        assert_eq!(
            restored_debug.grid.map_id,
            Some(MapId("interaction_map".into()))
        );
        assert!(restored_debug
            .grid
            .map_objects
            .iter()
            .all(|object| object.object_id != "pickup"));
    }

    #[test]
    fn runtime_snapshot_load_rejects_legacy_traveling_world_mode() {
        let (runtime, _handles) = create_demo_runtime();
        let mut snapshot = runtime.save_snapshot();
        snapshot.simulation.interaction_context.world_mode = WorldMode::Traveling;

        let mut restored = SimulationRuntime::new();
        let error = restored
            .load_snapshot(snapshot)
            .expect_err("legacy traveling snapshot should be rejected");

        assert_eq!(error, "unsupported_runtime_snapshot_world_mode:Traveling");
    }

    #[test]
    fn runtime_snapshot_round_trip_preserves_actor_vision_state() {
        let map = sample_interaction_map_definition();
        let map_library = MapLibrary::from(BTreeMap::from([(map.id.clone(), map.clone())]));

        let mut simulation = Simulation::new();
        simulation.set_map_library(map_library.clone());
        simulation.grid_world_mut().load_map(&map);

        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(1, 0, 1),
            interaction: None,
            attack_range: 1.5,
            ai_controller: None,
        });

        let mut runtime = SimulationRuntime::from_simulation(simulation);
        runtime.set_actor_vision_radius(player, 5);
        let update = runtime
            .refresh_actor_vision(player)
            .expect("vision should refresh");
        assert!(!update.visible_cells.is_empty());
        assert!(!update.explored_cells.is_empty());

        let saved = runtime.save_snapshot();
        let mut restored = SimulationRuntime::new();
        restored.set_map_library(map_library);
        restored
            .load_snapshot(saved.clone())
            .expect("snapshot should restore");

        assert_eq!(restored.save_snapshot(), saved);
        let restored_vision = restored
            .actor_vision_snapshot(player)
            .expect("vision snapshot should restore");
        assert_eq!(restored_vision.radius, 5);
        assert_eq!(
            restored_vision.active_map_id.as_ref().map(MapId::as_str),
            Some("interaction_map")
        );
        assert!(!restored_vision.visible_cells.is_empty());
        assert!(!restored_vision.explored_maps.is_empty());
    }

    fn sample_reward_item_library() -> ItemLibrary {
        ItemLibrary::from(BTreeMap::from([(
            1006,
            ItemDefinition {
                id: 1006,
                name: "Rewards".into(),
                ..ItemDefinition::default()
            },
        )]))
    }

    fn sample_runtime_economy_item_library() -> ItemLibrary {
        ItemLibrary::from(BTreeMap::from([
            (
                1001,
                ItemDefinition {
                    id: 1001,
                    name: "Cloth".to_string(),
                    value: 2,
                    weight: 0.1,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 99,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1002,
                ItemDefinition {
                    id: 1002,
                    name: "Knife".to_string(),
                    value: 8,
                    weight: 0.5,
                    fragments: vec![
                        ItemFragment::Stacking {
                            stackable: false,
                            max_stack: 1,
                        },
                        ItemFragment::Equip {
                            slots: vec!["main_hand".to_string()],
                            level_requirement: 1,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                    ],
                    ..ItemDefinition::default()
                },
            ),
            (
                1003,
                ItemDefinition {
                    id: 1003,
                    name: "Bandage".to_string(),
                    value: 12,
                    weight: 0.2,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 20,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1004,
                ItemDefinition {
                    id: 1004,
                    name: "Pistol".to_string(),
                    value: 120,
                    weight: 1.2,
                    fragments: vec![
                        ItemFragment::Equip {
                            slots: vec!["main_hand".to_string()],
                            level_requirement: 2,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                        ItemFragment::Weapon {
                            subtype: "pistol".to_string(),
                            damage: 18,
                            attack_speed: 1.0,
                            range: 12,
                            stamina_cost: 2,
                            crit_chance: 0.1,
                            crit_multiplier: 1.8,
                            accuracy: Some(70),
                            ammo_type: Some(1009),
                            max_ammo: Some(6),
                            reload_time: Some(1.5),
                            on_hit_effect_ids: Vec::new(),
                        },
                    ],
                    ..ItemDefinition::default()
                },
            ),
            (
                1009,
                ItemDefinition {
                    id: 1009,
                    name: "Pistol Ammo".to_string(),
                    value: 5,
                    weight: 0.1,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 50,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1031,
                ItemDefinition {
                    id: 1031,
                    name: "Antibiotics".to_string(),
                    value: 10,
                    weight: 0.2,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 10,
                    }],
                    ..ItemDefinition::default()
                },
            ),
        ]))
    }

    fn sample_runtime_skill_library() -> SkillLibrary {
        SkillLibrary::from(BTreeMap::from([
            (
                "crafting_basics".to_string(),
                SkillDefinition {
                    id: "crafting_basics".to_string(),
                    name: "Crafting Basics".to_string(),
                    tree_id: "survival".to_string(),
                    max_level: 3,
                    prerequisites: Vec::new(),
                    attribute_requirements: BTreeMap::from([("intelligence".to_string(), 3)]),
                    ..SkillDefinition::default()
                },
            ),
            (
                "fire_bolt".to_string(),
                SkillDefinition {
                    id: "fire_bolt".to_string(),
                    name: "Fire Bolt".to_string(),
                    tree_id: "combat".to_string(),
                    max_level: 3,
                    activation: Some(SkillActivationDefinition {
                        mode: "active".to_string(),
                        cooldown: 3.0,
                        effect: Some(SkillActivationEffect {
                            modifiers: BTreeMap::from([(
                                "damage".to_string(),
                                SkillModifierDefinition {
                                    base: 4.0,
                                    per_level: 1.0,
                                    max_value: 6.0,
                                    ..SkillModifierDefinition::default()
                                },
                            )]),
                            ..SkillActivationEffect::default()
                        }),
                        targeting: Some(SkillTargetingDefinition {
                            enabled: true,
                            range_cells: 5,
                            shape: "single".to_string(),
                            radius: 0,
                            handler_script: "damage_single".to_string(),
                            ..SkillTargetingDefinition::default()
                        }),
                        ..SkillActivationDefinition::default()
                    }),
                    ..SkillDefinition::default()
                },
            ),
            (
                "shockwave".to_string(),
                SkillDefinition {
                    id: "shockwave".to_string(),
                    name: "Shockwave".to_string(),
                    tree_id: "combat".to_string(),
                    max_level: 3,
                    activation: Some(SkillActivationDefinition {
                        mode: "active".to_string(),
                        cooldown: 2.0,
                        effect: Some(SkillActivationEffect {
                            modifiers: BTreeMap::from([(
                                "damage".to_string(),
                                SkillModifierDefinition {
                                    base: 2.0,
                                    per_level: 0.5,
                                    max_value: 3.0,
                                    ..SkillModifierDefinition::default()
                                },
                            )]),
                            ..SkillActivationEffect::default()
                        }),
                        targeting: Some(SkillTargetingDefinition {
                            enabled: true,
                            range_cells: 3,
                            shape: "diamond".to_string(),
                            radius: 1,
                            handler_script: "damage_aoe".to_string(),
                            ..SkillTargetingDefinition::default()
                        }),
                        ..SkillActivationDefinition::default()
                    }),
                    ..SkillDefinition::default()
                },
            ),
        ]))
    }

    fn sample_runtime_recipe_library() -> RecipeLibrary {
        RecipeLibrary::from(BTreeMap::from([(
            "bandage_recipe".to_string(),
            RecipeDefinition {
                id: "bandage_recipe".to_string(),
                name: "Craft Bandage".to_string(),
                output: RecipeOutput {
                    item_id: 1003,
                    count: 1,
                    quality_bonus: 0,
                    extra: BTreeMap::new(),
                },
                materials: vec![RecipeMaterial {
                    item_id: 1001,
                    count: 2,
                    extra: BTreeMap::new(),
                }],
                required_tools: vec!["1002".to_string()],
                required_station: "workbench".to_string(),
                skill_requirements: BTreeMap::from([("crafting_basics".to_string(), 1)]),
                is_default_unlocked: true,
                ..RecipeDefinition::default()
            },
        )]))
    }

    fn sample_runtime_shop_library() -> ShopLibrary {
        ShopLibrary::from(BTreeMap::from([(
            "survivor_outpost_01_shop".to_string(),
            ShopDefinition {
                id: "survivor_outpost_01_shop".to_string(),
                buy_price_modifier: 1.5,
                sell_price_modifier: 0.5,
                money: 100,
                inventory: vec![ShopInventoryEntry {
                    item_id: 1031,
                    count: 3,
                    price: 15,
                }],
            },
        )]))
    }

    fn sample_runtime_map_library() -> MapLibrary {
        MapLibrary::from(BTreeMap::from([
            (
                MapId("survivor_outpost_01".into()),
                MapDefinition {
                    id: MapId("survivor_outpost_01".into()),
                    name: "Survivor Outpost".into(),
                    size: MapSize {
                        width: 12,
                        height: 12,
                    },
                    default_level: 0,
                    levels: vec![MapLevelDefinition {
                        y: 0,
                        cells: Vec::new(),
                    }],
                    entry_points: vec![MapEntryPointDefinition {
                        id: "default_entry".into(),
                        grid: GridCoord::new(1, 0, 1),
                        facing: None,
                        extra: BTreeMap::new(),
                    }],
                    objects: Vec::new(),
                },
            ),
            (
                MapId("survivor_outpost_01_interior".into()),
                MapDefinition {
                    id: MapId("survivor_outpost_01_interior".into()),
                    name: "Outpost Interior".into(),
                    size: MapSize {
                        width: 8,
                        height: 8,
                    },
                    default_level: 0,
                    levels: vec![MapLevelDefinition {
                        y: 0,
                        cells: Vec::new(),
                    }],
                    entry_points: vec![
                        MapEntryPointDefinition {
                            id: "default_entry".into(),
                            grid: GridCoord::new(0, 0, 0),
                            facing: None,
                            extra: BTreeMap::new(),
                        },
                        MapEntryPointDefinition {
                            id: "clinic_entry".into(),
                            grid: GridCoord::new(2, 0, 2),
                            facing: None,
                            extra: BTreeMap::new(),
                        },
                    ],
                    objects: Vec::new(),
                },
            ),
        ]))
    }

    fn single_tile_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("single_tile_drop_test".into()),
            name: "Single Tile".into(),
            size: MapSize {
                width: 1,
                height: 1,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: Vec::new(),
        }
    }

    fn sample_runtime_overworld_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("main_overworld".into()),
            OverworldDefinition {
                id: OverworldId("main_overworld".into()),
                size: MapSize {
                    width: 1,
                    height: 1,
                },
                locations: vec![
                    OverworldLocationDefinition {
                        id: OverworldLocationId("survivor_outpost_01".into()),
                        name: "Survivor Outpost".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Outdoor,
                        map_id: MapId("survivor_outpost_01".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: None,
                        return_entry_point_id: None,
                        default_unlocked: true,
                        visible: true,
                        overworld_cell: GridCoord::new(0, 0, 0),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                    OverworldLocationDefinition {
                        id: OverworldLocationId("survivor_outpost_01_interior".into()),
                        name: "Outpost Interior".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Interior,
                        map_id: MapId("survivor_outpost_01_interior".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: Some(OverworldLocationId(
                            "survivor_outpost_01".into(),
                        )),
                        return_entry_point_id: Some("default_entry".into()),
                        default_unlocked: true,
                        visible: false,
                        overworld_cell: GridCoord::new(0, 0, 0),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                ],
                cells: vec![OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: OverworldTerrainKind::Road,
                    blocked: false,
                    extra: BTreeMap::new(),
                }],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
    }

    fn sample_runtime_smoke_item_library() -> ItemLibrary {
        let mut definitions = BTreeMap::new();
        for (item_id, definition) in sample_runtime_economy_item_library().iter() {
            definitions.insert(*item_id, definition.clone());
        }
        for (item_id, definition) in sample_reward_item_library().iter() {
            definitions.insert(*item_id, definition.clone());
        }
        definitions.insert(
            1005,
            ItemDefinition {
                id: 1005,
                name: "Scrap".to_string(),
                fragments: vec![ItemFragment::Stacking {
                    stackable: true,
                    max_stack: 20,
                }],
                ..ItemDefinition::default()
            },
        );
        ItemLibrary::from(definitions)
    }

    fn sample_runtime_smoke_map_library() -> MapLibrary {
        let mut definitions = BTreeMap::new();
        for (map_id, definition) in sample_runtime_map_library().iter() {
            definitions.insert(map_id.clone(), definition.clone());
        }
        let interaction_map = sample_interaction_map_definition();
        definitions.insert(interaction_map.id.clone(), interaction_map);
        MapLibrary::from(definitions)
    }

    fn sample_runtime_dialogue_library() -> DialogueLibrary {
        DialogueLibrary::from(BTreeMap::from([(
            "trader_lao_wang".to_string(),
            DialogueData {
                dialog_id: "trader_lao_wang".to_string(),
                nodes: vec![
                    DialogueNode {
                        id: "start".to_string(),
                        node_type: "dialog".to_string(),
                        is_start: true,
                        next: "choice_1".to_string(),
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "choice_1".to_string(),
                        node_type: "choice".to_string(),
                        options: vec![
                            DialogueOption {
                                text: "Trade".to_string(),
                                next: "trade_action".to_string(),
                                ..DialogueOption::default()
                            },
                            DialogueOption {
                                text: "Leave".to_string(),
                                next: "leave_end".to_string(),
                                ..DialogueOption::default()
                            },
                        ],
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "trade_action".to_string(),
                        node_type: "action".to_string(),
                        actions: vec![DialogueAction {
                            action_type: "open_trade".to_string(),
                            extra: BTreeMap::new(),
                        }],
                        next: "trade_end".to_string(),
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "trade_end".to_string(),
                        node_type: "end".to_string(),
                        end_type: "trade".to_string(),
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "leave_end".to_string(),
                        node_type: "end".to_string(),
                        end_type: "leave".to_string(),
                        ..DialogueNode::default()
                    },
                ],
                ..DialogueData::default()
            },
        )]))
    }

    fn sample_runtime_quest_library() -> QuestLibrary {
        QuestLibrary::from(BTreeMap::from([(
            "zombie_hunter".to_string(),
            QuestDefinition {
                quest_id: "zombie_hunter".to_string(),
                title: "僵尸猎人".to_string(),
                description: "击败一只僵尸".to_string(),
                flow: QuestFlow {
                    start_node_id: "start".to_string(),
                    nodes: BTreeMap::from([
                        (
                            "start".to_string(),
                            QuestNode {
                                id: "start".to_string(),
                                node_type: "start".to_string(),
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "kill_one".to_string(),
                            QuestNode {
                                id: "kill_one".to_string(),
                                node_type: "objective".to_string(),
                                objective_type: "kill".to_string(),
                                count: 1,
                                extra: BTreeMap::from([(
                                    "enemy_type".to_string(),
                                    serde_json::Value::String("zombie".to_string()),
                                )]),
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "reward".to_string(),
                            QuestNode {
                                id: "reward".to_string(),
                                node_type: "reward".to_string(),
                                rewards: QuestRewards {
                                    items: vec![game_data::QuestRewardItem {
                                        id: 1006,
                                        count: 3,
                                        extra: BTreeMap::new(),
                                    }],
                                    experience: 10,
                                    ..QuestRewards::default()
                                },
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "end".to_string(),
                            QuestNode {
                                id: "end".to_string(),
                                node_type: "end".to_string(),
                                ..QuestNode::default()
                            },
                        ),
                    ]),
                    connections: vec![
                        QuestConnection {
                            from: "start".to_string(),
                            to: "kill_one".to_string(),
                            from_port: 0,
                            to_port: 0,
                            extra: BTreeMap::new(),
                        },
                        QuestConnection {
                            from: "kill_one".to_string(),
                            to: "reward".to_string(),
                            from_port: 0,
                            to_port: 0,
                            extra: BTreeMap::new(),
                        },
                        QuestConnection {
                            from: "reward".to_string(),
                            to: "end".to_string(),
                            from_port: 0,
                            to_port: 0,
                            extra: BTreeMap::new(),
                        },
                    ],
                    ..QuestFlow::default()
                },
                ..QuestDefinition::default()
            },
        )]))
    }

    #[test]
    fn runtime_travel_to_map_updates_scene_context_and_return_anchor() {
        let (mut runtime, player) = sample_runtime_with_overworld();
        set_runtime_actor_ap(&mut runtime, player, 1.0);

        let context = runtime
            .travel_to_map(
                player,
                "clinic_interior_map",
                Some("clinic_entry"),
                WorldMode::Interior,
            )
            .expect("travel_to_map should succeed");

        assert_eq!(
            context.current_map_id.as_deref(),
            Some("clinic_interior_map")
        );
        assert_eq!(context.entry_point_id.as_deref(), Some("clinic_entry"));
        assert_eq!(context.world_mode, WorldMode::Interior);
        assert_eq!(
            context.return_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );

        let snapshot = runtime.current_interaction_context();
        assert_eq!(
            snapshot.current_map_id.as_deref(),
            Some("clinic_interior_map")
        );
        assert_eq!(snapshot.world_mode, WorldMode::Interior);
    }

    #[test]
    fn runtime_enter_location_and_return_to_overworld_restore_context() {
        let (mut runtime, player) = sample_runtime_with_overworld();
        set_runtime_actor_ap(&mut runtime, player, 2.0);

        let entered = runtime
            .enter_location(player, "clinic_interior", None)
            .expect("enter_location should succeed");
        assert_eq!(entered.location_id, "clinic_interior");
        assert_eq!(entered.map_id, "clinic_interior_map");
        assert_eq!(entered.entry_point_id, "clinic_entry");
        assert_eq!(
            entered.return_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(entered.world_mode, WorldMode::Interior);

        let returned = runtime
            .return_to_overworld(player)
            .expect("return_to_overworld should succeed");
        assert_eq!(
            returned.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(returned.current_map_id, None);
        assert_eq!(returned.world_mode, WorldMode::Overworld);

        let context = runtime.current_interaction_context();
        assert_eq!(
            context.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(context.current_map_id, None);
        assert_eq!(context.world_mode, WorldMode::Overworld);
    }

    #[test]
    fn overworld_exact_goal_arrival_records_recent_arrival_without_auto_entering_location() {
        let (mut runtime, player) = sample_runtime_with_overworld_prompt();
        set_runtime_actor_ap(&mut runtime, player, 2.0);

        let outcome = runtime
            .issue_actor_move(player, GridCoord::new(2, 0, 0))
            .expect("move should succeed");

        assert!(outcome.result.success);
        assert!(runtime.pending_movement().is_none());
        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 0))
        );
        assert_eq!(
            runtime.current_interaction_context().world_mode,
            WorldMode::Overworld
        );
        assert_eq!(runtime.current_interaction_context().current_map_id, None);
        assert_eq!(
            runtime.overworld_outdoor_location_id_at(GridCoord::new(1, 0, 0)),
            Some("prompt_outpost".to_string())
        );
        assert_eq!(
            runtime.recent_overworld_arrival(),
            Some(&crate::RecentOverworldArrival {
                actor_id: player,
                requested_goal: GridCoord::new(1, 0, 0),
                final_position: GridCoord::new(1, 0, 0),
                arrived_exactly: true,
            })
        );
    }

    #[test]
    fn overworld_passing_through_trigger_only_records_final_goal_tile() {
        let (mut runtime, player) = sample_runtime_with_overworld_prompt();
        set_runtime_actor_ap(&mut runtime, player, 3.0);

        runtime
            .issue_actor_move(player, GridCoord::new(3, 0, 0))
            .expect("move should succeed");

        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(3, 0, 0))
        );
        assert_eq!(
            runtime.recent_overworld_arrival(),
            Some(&crate::RecentOverworldArrival {
                actor_id: player,
                requested_goal: GridCoord::new(3, 0, 0),
                final_position: GridCoord::new(3, 0, 0),
                arrived_exactly: true,
            })
        );
        assert_eq!(
            runtime.overworld_outdoor_location_id_at(GridCoord::new(3, 0, 0)),
            None
        );
    }

    #[test]
    fn overworld_recent_arrival_is_cleared_by_cancel_enter_and_restore() {
        let (mut runtime, player) = sample_runtime_with_overworld_prompt();
        set_runtime_actor_ap(&mut runtime, player, 3.0);

        runtime
            .issue_actor_move(player, GridCoord::new(2, 0, 0))
            .expect("first move should succeed");
        assert!(runtime.recent_overworld_arrival().is_some());

        runtime
            .issue_actor_move(player, GridCoord::new(3, 0, 0))
            .expect("second move should succeed");
        assert_eq!(
            runtime
                .recent_overworld_arrival()
                .expect("second move should refresh arrival")
                .requested_goal,
            GridCoord::new(3, 0, 0)
        );

        let saved = runtime.save_snapshot();
        let mut restored = SimulationRuntime::new();
        restored.set_map_library(sample_prompt_map_library());
        restored.set_overworld_library(sample_prompt_overworld_library());
        restored
            .load_snapshot(saved)
            .expect("snapshot should restore without prompt state");
        assert!(restored.recent_overworld_arrival().is_none());

        restored
            .issue_actor_move(player, GridCoord::new(2, 0, 0))
            .expect("move after restore should succeed");
        assert!(restored.recent_overworld_arrival().is_some());
        set_runtime_actor_ap(&mut restored, player, 1.0);

        restored
            .enter_location(player, "prompt_outpost", None)
            .expect("manual enter should succeed");
        assert!(restored.recent_overworld_arrival().is_none());
        assert_eq!(
            restored.current_interaction_context().world_mode,
            WorldMode::Outdoor
        );
    }

    fn sample_runtime_with_overworld() -> (SimulationRuntime, game_data::ActorId) {
        let mut runtime = SimulationRuntime::new();
        runtime.set_map_library(sample_scene_context_map_library());
        runtime.set_overworld_library(sample_scene_context_overworld_library());
        let actor_id = runtime.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        runtime
            .seed_overworld_state(
                WorldMode::Outdoor,
                Some("survivor_outpost_01".into()),
                Some("default_entry".into()),
                ["survivor_outpost_01".into(), "clinic_interior".into()],
            )
            .expect("overworld state should seed");
        (runtime, actor_id)
    }

    fn sample_runtime_with_overworld_prompt() -> (SimulationRuntime, game_data::ActorId) {
        let mut runtime = SimulationRuntime::new();
        runtime.set_map_library(sample_prompt_map_library());
        runtime.set_overworld_library(sample_prompt_overworld_library());
        runtime
            .seed_overworld_state(
                WorldMode::Overworld,
                Some("prompt_outpost".into()),
                None,
                ["prompt_outpost".into()],
            )
            .expect("overworld state should seed");
        let actor_id = runtime.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        (runtime, actor_id)
    }

    fn sample_scene_context_map_library() -> MapLibrary {
        MapLibrary::from(BTreeMap::from([
            (
                MapId("survivor_outpost_01_map".into()),
                MapDefinition {
                    id: MapId("survivor_outpost_01_map".into()),
                    name: "Survivor Outpost".into(),
                    size: MapSize {
                        width: 12,
                        height: 12,
                    },
                    default_level: 0,
                    levels: vec![MapLevelDefinition {
                        y: 0,
                        cells: Vec::new(),
                    }],
                    entry_points: vec![
                        MapEntryPointDefinition {
                            id: "default_entry".into(),
                            grid: GridCoord::new(1, 0, 1),
                            facing: None,
                            extra: BTreeMap::new(),
                        },
                        MapEntryPointDefinition {
                            id: "outdoor_return".into(),
                            grid: GridCoord::new(2, 0, 2),
                            facing: None,
                            extra: BTreeMap::new(),
                        },
                    ],
                    objects: Vec::new(),
                },
            ),
            (
                MapId("clinic_interior_map".into()),
                MapDefinition {
                    id: MapId("clinic_interior_map".into()),
                    name: "Clinic Interior".into(),
                    size: MapSize {
                        width: 8,
                        height: 8,
                    },
                    default_level: 0,
                    levels: vec![MapLevelDefinition {
                        y: 0,
                        cells: Vec::new(),
                    }],
                    entry_points: vec![MapEntryPointDefinition {
                        id: "clinic_entry".into(),
                        grid: GridCoord::new(3, 0, 3),
                        facing: None,
                        extra: BTreeMap::new(),
                    }],
                    objects: Vec::new(),
                },
            ),
        ]))
    }

    fn sample_prompt_map_library() -> MapLibrary {
        MapLibrary::from(BTreeMap::from([(
            MapId("prompt_outpost_map".into()),
            MapDefinition {
                id: MapId("prompt_outpost_map".into()),
                name: "Prompt Outpost".into(),
                size: MapSize {
                    width: 8,
                    height: 8,
                },
                default_level: 0,
                levels: vec![MapLevelDefinition {
                    y: 0,
                    cells: Vec::new(),
                }],
                entry_points: vec![MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(1, 0, 1),
                    facing: None,
                    extra: BTreeMap::new(),
                }],
                objects: Vec::new(),
            },
        )]))
    }

    fn sample_scene_context_overworld_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("scene_context_world".into()),
            OverworldDefinition {
                id: OverworldId("scene_context_world".into()),
                size: MapSize {
                    width: 3,
                    height: 3,
                },
                locations: vec![
                    OverworldLocationDefinition {
                        id: OverworldLocationId("survivor_outpost_01".into()),
                        name: "Survivor Outpost".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Outdoor,
                        map_id: MapId("survivor_outpost_01_map".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: None,
                        return_entry_point_id: Some("outdoor_return".into()),
                        default_unlocked: true,
                        visible: true,
                        overworld_cell: GridCoord::new(1, 0, 1),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                    OverworldLocationDefinition {
                        id: OverworldLocationId("clinic_interior".into()),
                        name: "Clinic Interior".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Interior,
                        map_id: MapId("clinic_interior_map".into()),
                        entry_point_id: "clinic_entry".into(),
                        parent_outdoor_location_id: Some(OverworldLocationId(
                            "survivor_outpost_01".into(),
                        )),
                        return_entry_point_id: Some("outdoor_return".into()),
                        default_unlocked: true,
                        visible: false,
                        overworld_cell: GridCoord::new(1, 0, 1),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                ],
                cells: (0..3)
                    .flat_map(|z| {
                        (0..3).map(move |x| OverworldCellDefinition {
                            grid: GridCoord::new(x, 0, z),
                            terrain: if x == 1 && z == 1 {
                                OverworldTerrainKind::Urban
                            } else {
                                OverworldTerrainKind::Road
                            },
                            blocked: false,
                            extra: BTreeMap::new(),
                        })
                    })
                    .collect(),
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
    }

    fn sample_prompt_overworld_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("prompt_world".into()),
            OverworldDefinition {
                id: OverworldId("prompt_world".into()),
                size: MapSize {
                    width: 4,
                    height: 1,
                },
                locations: vec![OverworldLocationDefinition {
                    id: OverworldLocationId("prompt_outpost".into()),
                    name: "Prompt Outpost".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("prompt_outpost_map".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(2, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                }],
                cells: vec![
                    OverworldCellDefinition {
                        grid: GridCoord::new(0, 0, 0),
                        terrain: OverworldTerrainKind::Road,
                        blocked: false,
                        extra: BTreeMap::new(),
                    },
                    OverworldCellDefinition {
                        grid: GridCoord::new(1, 0, 0),
                        terrain: OverworldTerrainKind::Road,
                        blocked: false,
                        extra: BTreeMap::new(),
                    },
                    OverworldCellDefinition {
                        grid: GridCoord::new(2, 0, 0),
                        terrain: OverworldTerrainKind::Urban,
                        blocked: false,
                        extra: BTreeMap::new(),
                    },
                    OverworldCellDefinition {
                        grid: GridCoord::new(3, 0, 0),
                        terrain: OverworldTerrainKind::Road,
                        blocked: false,
                        extra: BTreeMap::new(),
                    },
                ],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
    }

    fn sample_interaction_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("interaction_map".into()),
            name: "Interaction".into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(4, 0, 7),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![
                MapObjectDefinition {
                    object_id: "pickup".into(),
                    kind: MapObjectKind::Pickup,
                    anchor: GridCoord::new(2, 0, 1),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    props: MapObjectProps {
                        pickup: Some(MapPickupProps {
                            item_id: "1005".into(),
                            min_count: 1,
                            max_count: 2,
                            extra: BTreeMap::new(),
                        }),
                        ..MapObjectProps::default()
                    },
                },
                MapObjectDefinition {
                    object_id: "exit".into(),
                    kind: MapObjectKind::Interactive,
                    anchor: GridCoord::new(5, 0, 7),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    props: MapObjectProps {
                        interactive: Some(MapInteractiveProps {
                            display_name: "Exit".into(),
                            interaction_distance: 1.4,
                            interaction_kind: "enter_outdoor_location".into(),
                            target_id: Some("survivor_outpost_01".into()),
                            options: Vec::new(),
                            extra: BTreeMap::new(),
                        }),
                        ..MapObjectProps::default()
                    },
                },
            ],
        }
    }
}
