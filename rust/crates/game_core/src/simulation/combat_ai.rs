use game_data::{ActionType, ActorId, ActorSide, SkillTargetRequest};

use super::{interaction_flow, Simulation};

impl Simulation {
    pub(super) fn execute_combat_ai_step(&mut self, actor_id: ActorId) -> bool {
        if self.get_actor_side(actor_id) == Some(ActorSide::Player) {
            return false;
        }

        let Some(target_actor) = self.combat_ai_select_target(actor_id) else {
            return false;
        };

        if self.combat_ai_try_use_skill(actor_id, target_actor) {
            return true;
        }
        if self
            .validate_attack_preconditions(actor_id, target_actor)
            .is_ok()
            && self.can_actor_afford(actor_id, ActionType::Attack, None)
        {
            return self.perform_attack(actor_id, target_actor).success;
        }

        self.combat_ai_try_approach_target(actor_id, target_actor)
    }

    fn combat_ai_select_target(&self, actor_id: ActorId) -> Option<ActorId> {
        let actor_side = self.get_actor_side(actor_id)?;
        let actor_grid = self.actor_grid_position(actor_id)?;

        self.actors
            .values()
            .filter(|candidate| candidate.actor_id != actor_id)
            .filter(|candidate| self.combat_ai_is_hostile_pair(actor_side, candidate.side))
            .min_by_key(|candidate| {
                let dx = i64::from((candidate.grid_position.x - actor_grid.x).abs());
                let dz = i64::from((candidate.grid_position.z - actor_grid.z).abs());
                let dy = i64::from((candidate.grid_position.y - actor_grid.y).abs()) * 100;
                dx + dz + dy
            })
            .map(|candidate| candidate.actor_id)
    }

    fn combat_ai_is_hostile_pair(&self, actor_side: ActorSide, target_side: ActorSide) -> bool {
        matches!(
            (actor_side, target_side),
            (ActorSide::Hostile, ActorSide::Player | ActorSide::Friendly)
                | (ActorSide::Friendly | ActorSide::Player, ActorSide::Hostile)
        )
    }

    fn combat_ai_try_use_skill(&mut self, actor_id: ActorId, target_actor: ActorId) -> bool {
        let Some(actor) = self.economy.actor(actor_id) else {
            return false;
        };
        let learned_skill_ids = actor
            .learned_skills
            .iter()
            .filter(|(_, level)| **level > 0)
            .map(|(skill_id, _)| skill_id.clone())
            .collect::<Vec<_>>();

        for skill_id in learned_skill_ids {
            let Some(skill) = self
                .skill_library
                .as_ref()
                .and_then(|skills| skills.get(&skill_id))
            else {
                continue;
            };
            let Some(activation) = skill.activation.as_ref() else {
                continue;
            };
            if activation.mode.trim() != "active"
                || self.skill_cooldown_remaining(actor_id, &skill_id) > 0.0
            {
                continue;
            }
            if !self.can_actor_afford(actor_id, ActionType::Skill, None) {
                continue;
            }

            let target_request = SkillTargetRequest::Actor(target_actor);
            let preview = self.preview_skill_target(actor_id, &skill_id, target_request);
            if preview.invalid_reason.is_some()
                || !preview.preview_hit_actor_ids.contains(&target_actor)
            {
                continue;
            }

            if self
                .activate_skill(actor_id, &skill_id, target_request)
                .action_result
                .success
            {
                return true;
            }
        }

        false
    }

    fn combat_ai_try_approach_target(&mut self, actor_id: ActorId, target_actor: ActorId) -> bool {
        let Some(target_grid) = self.actor_grid_position(target_actor) else {
            return false;
        };

        let mut candidate_goals = interaction_flow::collect_interaction_ring_cells(target_grid, 1)
            .into_iter()
            .filter(|candidate| self.grid_walkable_for_actor(*candidate, Some(actor_id)))
            .collect::<Vec<_>>();
        candidate_goals.sort_by_key(|candidate| {
            self.find_path_grid(
                Some(actor_id),
                self.actor_grid_position(actor_id).unwrap_or(*candidate),
                *candidate,
            )
            .map(|path| path.len())
            .unwrap_or(usize::MAX)
        });

        for goal in candidate_goals {
            if let Ok(outcome) = self.move_actor_to_reachable(actor_id, goal) {
                if outcome.result.success && outcome.plan.resolved_steps() > 0 {
                    return true;
                }
            }
        }

        false
    }
}
