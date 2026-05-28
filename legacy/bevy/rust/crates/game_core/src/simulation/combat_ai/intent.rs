//! 战斗 AI 意图执行模块。
//! 负责把战斗意图落到运行时动作，不负责目标评价或 profile 策略选择。

use game_data::{ActorId, SkillTargetRequest};

use crate::simulation::Simulation;

use super::{CombatAiExecutionResult, CombatAiIntent};

impl Simulation {
    pub(crate) fn execute_combat_ai_intent(
        &mut self,
        actor_id: ActorId,
        intent: CombatAiIntent,
    ) -> CombatAiExecutionResult {
        let performed = match intent {
            CombatAiIntent::UseSkill {
                target_actor,
                skill_id,
            } => {
                self.activate_skill(actor_id, &skill_id, SkillTargetRequest::Actor(target_actor))
                    .action_result
                    .success
            }
            CombatAiIntent::Attack { target_actor } => {
                self.validate_attack_preconditions(actor_id, target_actor)
                    .is_ok()
                    && self.perform_attack(actor_id, target_actor).success
            }
            CombatAiIntent::Approach { target_actor, goal } => {
                if self.actor_grid_position(target_actor).is_none() {
                    return CombatAiExecutionResult::idle();
                }

                self.move_actor_to_reachable(actor_id, goal)
                    .map(|outcome| outcome.result.success && outcome.plan.resolved_steps() > 0)
                    .unwrap_or(false)
            }
            CombatAiIntent::Retreat { target_actor, goal } => {
                if self.actor_grid_position(target_actor).is_none() {
                    return CombatAiExecutionResult::idle();
                }

                self.move_actor_to_reachable(actor_id, goal)
                    .map(|outcome| outcome.result.success && outcome.plan.resolved_steps() > 0)
                    .unwrap_or(false)
            }
        };

        if performed {
            CombatAiExecutionResult::performed()
        } else {
            CombatAiExecutionResult::idle()
        }
    }
}
