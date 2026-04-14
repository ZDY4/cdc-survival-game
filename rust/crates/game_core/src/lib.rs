use bevy_app::prelude::*;

pub mod actor;
pub mod building;
pub mod building_geometry;
pub mod demo;
pub mod economy;
pub mod goap;
pub mod grid;
pub mod movement;
pub mod overworld;
pub mod runtime;
pub mod runtime_ai;
pub mod simulation;
pub mod survival;
pub mod turn;
pub mod utility;
pub mod vision;

pub use actor::{ActorRecord, ActorRegistry};
pub use building::{
    generate_building_layout, BuildingLayoutError, GeneratedBuildingDebugState,
    GeneratedBuildingLayout, GeneratedBuildingStory, GeneratedDoorDebugState, GeneratedOutlineEdge,
    GeneratedRoom, GeneratedStairConnection,
};
pub use building_geometry::{
    triangulate_polygon, triangulate_polygon_with_holes, BuildingFootprint2d,
    BuildingGeometryValidationError, DoorOpeningKind, GeneratedDoorOpening, GeneratedRoomPolygon,
    GeneratedWalkablePolygons, GeometryAxis, GeometryMultiPolygon2, GeometryPoint2,
    GeometryPolygon2, GeometrySegment2,
};
pub use demo::{create_demo_runtime, seed_demo_scenario, DemoScenarioHandles};
pub use economy::{
    ActorEconomyState, ContainerRuntimeState, CraftOutcome, EconomyRuntimeError, EquippedItemState,
    EquippedWeaponProfile, HeadlessEconomyRuntime, MissingMaterial, MissingSkill, RecipeCraftCheck,
    ShopRuntimeEntry, ShopRuntimeState as EconomyShopRuntimeState, TradeOutcome,
};
pub use game_data::{
    AttackHitKind, AttackOutcome, InteractionContextSnapshot, InteractionExecutionRequest,
    InteractionExecutionResult, InteractionOptionDefinition, InteractionOptionId,
    InteractionOptionKind, InteractionPrompt, InteractionTargetId, ResolvedInteractionOption,
    SkillExecutionKind, SkillTargetSideRule, WorldMode,
};
pub use goap::{
    advance_offline_sim, apply_npc_action_effects, build_plan, build_plan_for_context,
    build_plan_for_goal, build_plan_for_goal_with_context, rebuild_facts, tick_offline_action,
    ActionExecutionPhase, ActionTickResult, AiBlackboard, NpcActionKey, NpcBackgroundState,
    NpcExecutionMode, NpcFact, NpcGoalKey, NpcGoalScore, NpcOfflineSimState, NpcPlanRequest,
    NpcPlanResult, NpcPlanStep, NpcPlanningContext, NpcRuntimeActionState, OfflineActionState,
    OfflineSimAdvanceResult,
};
pub use movement::{
    AutoMoveInterruptReason, MovementCommandOutcome, MovementPlan, MovementPlanError,
    PendingInteractionIntent, PendingMovementIntent, PendingProgressionStep,
    ProgressionAdvanceResult, RecentOverworldArrival,
};
pub use overworld::{
    compute_cell_path, find_entry_point, location_by_id, world_mode_for_location_kind,
    LocationTransitionContext, OverworldStateSnapshot, UnlockedLocationSet,
};
pub use runtime::{
    action_result_status, DropItemOutcome, RuntimeSnapshot, SimulationRuntime,
    RUNTIME_SNAPSHOT_SCHEMA_VERSION,
};
pub use runtime_ai::{
    FollowRuntimeGoalController, NoopAiController, OneShotInteractController, RuntimeAiController,
    RuntimeAiStepResult,
};
pub use simulation::{
    resolve_combat_tactic_profile_id, select_combat_ai_intent_for_profile,
    select_default_combat_ai_intent, ActorDebugState, CombatAiExecutionResult, CombatAiIntent,
    CombatAiSnapshot, CombatDebugState, CombatSkillOption, CombatTargetOption, GridDebugState,
    MapCellDebugState, MapObjectDebugState, RegisterActor, Simulation, SimulationCommand,
    SimulationCommandResult, SimulationEvent, SimulationSnapshot, SkillActivationResult,
    SkillRuntimeState,
};
pub use survival::{
    ActorSurvivalState, CraftingCheck, CraftingResult, MissingInventoryEntry,
    MissingSkillRequirement, ShopInventoryState, ShopRuntimeState, SurvivalRuntime,
    SurvivalRuntimeError, TradeQuote, TradeResult,
};
pub use utility::{
    score_goal, score_goal_for_context, score_goals, score_goals_for_context, select_goal,
    select_goal_for_context, NpcUtilityContext,
};
pub use vision::{
    ActorVisionMapSnapshot, ActorVisionSnapshot, ActorVisionUpdate, VisionRuntimeSnapshot,
};

pub struct GameCorePlugin;

impl Plugin for GameCorePlugin {
    fn build(&self, _app: &mut App) {}
}
