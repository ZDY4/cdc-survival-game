use game_data::{ActionResult, ActorId, GridCoord, WorldCoord};

use crate::grid::GridPathfindingError;
use crate::simulation::{
    Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent, SimulationSnapshot,
};

#[derive(Debug)]
pub struct SimulationRuntime {
    simulation: Simulation,
    path_preview: Vec<GridCoord>,
    tick_count: u64,
}

impl Default for SimulationRuntime {
    fn default() -> Self {
        Self::new()
    }
}

impl SimulationRuntime {
    pub fn new() -> Self {
        Self {
            simulation: Simulation::new(),
            path_preview: Vec::new(),
            tick_count: 0,
        }
    }

    pub fn from_simulation(simulation: Simulation) -> Self {
        Self {
            simulation,
            path_preview: Vec::new(),
            tick_count: 0,
        }
    }

    pub fn tick(&mut self) {
        self.tick_count = self.tick_count.saturating_add(1);
    }

    pub fn tick_count(&self) -> u64 {
        self.tick_count
    }

    pub fn submit_command(&mut self, command: SimulationCommand) -> SimulationCommandResult {
        self.capture_path_preview(&command);
        self.simulation.apply_command(command)
    }

    pub fn drain_events(&mut self) -> Vec<SimulationEvent> {
        self.simulation.drain_events()
    }

    pub fn snapshot(&self) -> SimulationSnapshot {
        self.simulation.snapshot(self.path_preview.clone())
    }

    pub fn world_to_grid(&self, world: WorldCoord) -> GridCoord {
        self.simulation.grid_world().world_to_grid(world)
    }

    pub fn grid_to_world(&self, grid: GridCoord) -> WorldCoord {
        self.simulation.grid_world().grid_to_world(grid)
    }

    pub fn get_actor_grid_position(&self, actor_id: ActorId) -> Option<GridCoord> {
        self.simulation.actor_grid_position(actor_id)
    }

    fn capture_path_preview(&mut self, command: &SimulationCommand) {
        match command {
            SimulationCommand::FindPath {
                actor_id,
                start,
                goal,
            } => {
                self.path_preview = self
                    .simulation
                    .find_path_grid(*actor_id, *start, *goal)
                    .unwrap_or_default();
            }
            SimulationCommand::MoveActorTo { actor_id, goal } => {
                self.path_preview = self
                    .simulation
                    .actor_grid_position(*actor_id)
                    .and_then(|start| {
                        self.simulation
                            .find_path_grid(Some(*actor_id), start, *goal)
                            .ok()
                    })
                    .unwrap_or_default();
            }
            _ => {}
        }
    }
}

pub fn pathfinding_error_reason(error: &GridPathfindingError) -> &'static str {
    match error {
        GridPathfindingError::TargetNotWalkable => "target_not_walkable",
        GridPathfindingError::NoPath => "no_path",
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

#[cfg(test)]
mod tests {
    use game_data::{ActorSide, GridCoord};

    use crate::demo::create_demo_runtime;
    use crate::simulation::{SimulationCommand, SimulationCommandResult};

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
}
