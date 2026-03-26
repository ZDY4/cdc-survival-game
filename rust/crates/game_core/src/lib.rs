use bevy_app::prelude::*;

pub mod actor;
pub mod demo;
pub mod economy;
pub mod goap;
pub mod grid;
pub mod movement;
pub mod overworld;
pub mod runtime;
pub mod simulation;
pub mod survival;
pub mod turn;
pub mod utility;

pub use actor::{
    AiController, AiStepResult, FollowGridGoalAiController, InteractOnceAiController,
    NoopAiController,
};
pub use demo::{create_demo_runtime, seed_demo_scenario, DemoScenarioHandles};
pub use economy::{
    ActorEconomyState, CraftOutcome, EconomyRuntimeError, EquippedItemState, EquippedWeaponProfile,
    HeadlessEconomyRuntime, MissingMaterial, MissingSkill, RecipeCraftCheck, ShopRuntimeEntry,
    ShopRuntimeState as EconomyShopRuntimeState, TradeOutcome,
};
pub use game_data::{
    InteractionContextSnapshot, InteractionExecutionRequest, InteractionExecutionResult,
    InteractionOptionDefinition, InteractionOptionId, InteractionOptionKind, InteractionPrompt,
    InteractionTargetId, ResolvedInteractionOption, WorldMode,
};
pub use goap::{
    advance_offline_sim, apply_npc_action_effects, build_plan, build_plan_for_context,
    build_plan_for_goal, build_plan_for_goal_with_context, rebuild_facts, tick_offline_action,
    ActionExecutionPhase, ActionTickResult, NpcActionKey, NpcBackgroundState, NpcExecutionMode,
    NpcFact, NpcFactInput, NpcGoalKey, NpcOfflineSimState, NpcPlanRequest, NpcPlanResult,
    NpcPlanStep, NpcPlanningContext, NpcRuntimeActionState, OfflineActionState,
    OfflineSimAdvanceResult,
};
pub use movement::{
    AutoMoveInterruptReason, MovementCommandOutcome, MovementPlan, MovementPlanError,
    PendingInteractionIntent, PendingMovementIntent, PendingProgressionStep,
    ProgressionAdvanceResult,
};
pub use overworld::{
    compute_cell_path, compute_location_route, find_entry_point, location_by_id,
    world_mode_for_location_kind, LocationTransitionContext, OverworldRouteSnapshot,
    OverworldStateSnapshot, OverworldTravelState, UnlockedLocationSet,
};
pub use runtime::{
    action_result_status, RuntimeSnapshot, SimulationRuntime, RUNTIME_SNAPSHOT_SCHEMA_VERSION,
};
pub use simulation::{
    ActorDebugState, CombatDebugState, GridDebugState, MapCellDebugState, MapObjectDebugState,
    RegisterActor, Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent,
    SimulationSnapshot,
};
pub use survival::{
    ActorSurvivalState, CraftingCheck, CraftingResult, MissingInventoryEntry,
    MissingSkillRequirement, ShopInventoryState, ShopRuntimeState, SurvivalRuntime,
    SurvivalRuntimeError, TradeQuote, TradeResult,
};
pub use utility::{
    score_goal, score_goal_for_context, score_goals, score_goals_for_context, select_goal,
    select_goal_for_context, NpcGoalScore, NpcUtilityContext,
};

pub struct GameCorePlugin;

impl Plugin for GameCorePlugin {
    fn build(&self, _app: &mut App) {}
}
