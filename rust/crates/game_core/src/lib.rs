use bevy_app::prelude::*;

pub mod actor;
pub mod demo;
pub mod grid;
pub mod runtime;
pub mod simulation;
pub mod turn;

pub use actor::{AiController, AiStepResult, InteractOnceAiController, NoopAiController};
pub use demo::{create_demo_runtime, seed_demo_scenario, DemoScenarioHandles};
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
