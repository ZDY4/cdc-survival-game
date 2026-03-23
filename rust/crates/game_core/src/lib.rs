use bevy_app::prelude::*;

pub mod actor;
pub mod demo;
pub mod goap;
pub mod grid;
pub mod movement;
pub mod runtime;
pub mod simulation;
pub mod turn;

pub use actor::{AiController, AiStepResult, InteractOnceAiController, NoopAiController};
pub use demo::{create_demo_runtime, seed_demo_scenario, DemoScenarioHandles};
pub use goap::{
    advance_offline_sim, build_plan, rebuild_facts, tick_offline_action, ActionExecutionPhase,
    ActionTickResult, NpcActionKey, NpcFact, NpcFactInput, NpcGoalKey, NpcOfflineSimState,
    NpcPlanRequest, NpcPlanResult, NpcPlanStep, OfflineActionState, OfflineSimAdvanceResult,
};
pub use movement::{
    AutoMoveInterruptReason, MovementCommandOutcome, MovementPlan, MovementPlanError,
    PendingMovementIntent, PendingProgressionStep, ProgressionAdvanceResult,
};
pub use runtime::{action_result_status, SimulationRuntime};
pub use simulation::{
    ActorDebugState, CombatDebugState, GridDebugState, MapCellDebugState, MapObjectDebugState,
    RegisterActor, Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent,
    SimulationSnapshot,
};

pub struct GameCorePlugin;

impl Plugin for GameCorePlugin {
    fn build(&self, _app: &mut App) {}
}
