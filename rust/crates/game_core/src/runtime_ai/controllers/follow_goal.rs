//! 运行时目标跟随控制器。
//! 负责把 runtime goal 转成移动动作，不负责高层目标选择或战斗决策。

use game_data::ActorId;

use crate::runtime_ai::{RuntimeAiController, RuntimeAiStepResult};
use crate::simulation::Simulation;

#[derive(Debug, Default)]
pub struct FollowRuntimeGoalController;

impl RuntimeAiController for FollowRuntimeGoalController {
    fn execute_turn_step(
        &mut self,
        actor_id: ActorId,
        simulation: &mut Simulation,
    ) -> RuntimeAiStepResult {
        let Some(goal) = simulation.autonomous_movement_goal(actor_id) else {
            return RuntimeAiStepResult::idle();
        };

        let Ok(outcome) = simulation.move_actor_to_reachable(actor_id, goal) else {
            return RuntimeAiStepResult::idle();
        };

        if outcome.result.success && outcome.plan.resolved_steps() > 0 {
            RuntimeAiStepResult::performed()
        } else {
            RuntimeAiStepResult::idle()
        }
    }
}

#[cfg(test)]
mod tests {
    use game_data::{ActorKind, ActorSide, GridCoord};

    use super::FollowRuntimeGoalController;
    use crate::{RegisterActor, RuntimeAiController, Simulation};

    #[test]
    fn follow_grid_goal_ai_moves_actor_toward_registered_goal() {
        let mut simulation = Simulation::new();

        let actor_id = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "guard".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.0,
            ai_controller: None,
        });
        simulation.set_actor_ap(actor_id, 2.0);
        simulation.set_actor_autonomous_movement_goal(actor_id, GridCoord::new(2, 0, 0));

        let mut controller = FollowRuntimeGoalController;
        let result = controller.execute_turn_step(actor_id, &mut simulation);

        assert!(result.performed);
        assert_eq!(
            simulation.actor_grid_position(actor_id),
            Some(GridCoord::new(1, 0, 0))
        );
    }
}
