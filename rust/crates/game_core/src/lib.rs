use bevy_app::prelude::*;

pub mod actor;
pub mod demo;
pub mod goap;
pub mod grid;
pub mod movement;
pub mod runtime;
pub mod simulation;
pub mod turn;
pub mod utility;

pub use actor::{AiController, AiStepResult, InteractOnceAiController, NoopAiController};
pub use demo::{create_demo_runtime, seed_demo_scenario, DemoScenarioHandles};
pub use game_data::{
    InteractionContextSnapshot, InteractionExecutionRequest, InteractionExecutionResult,
    InteractionOptionDefinition, InteractionOptionId, InteractionOptionKind, InteractionPrompt,
    InteractionTargetId, ResolvedInteractionOption, WorldMode,
};
pub use goap::{
    advance_offline_sim, build_plan, build_plan_for_goal, rebuild_facts, tick_offline_action,
    ActionExecutionPhase, ActionTickResult, NpcActionKey, NpcFact, NpcFactInput, NpcGoalKey,
    NpcOfflineSimState, NpcPlanRequest, NpcPlanResult, NpcPlanStep, OfflineActionState,
    OfflineSimAdvanceResult,
};
pub use movement::{
    AutoMoveInterruptReason, MovementCommandOutcome, MovementPlan, MovementPlanError,
    PendingInteractionIntent, PendingMovementIntent, PendingProgressionStep,
    ProgressionAdvanceResult,
};
pub use runtime::{action_result_status, SimulationRuntime};
pub use simulation::{
    ActorDebugState, CombatDebugState, GridDebugState, MapCellDebugState, MapObjectDebugState,
    RegisterActor, Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent,
    SimulationSnapshot,
};
pub use utility::{
    score_goal, score_goal_for_context, score_goals, score_goals_for_context, select_goal,
    select_goal_for_context, NpcGoalScore, NpcUtilityContext,
};

pub struct GameCorePlugin;

impl Plugin for GameCorePlugin {
    fn build(&self, _app: &mut App) {}
}
