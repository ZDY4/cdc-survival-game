use game_data::{ActionType, ActorId, SkillTargetRequest};

use crate::simulation::Simulation;

use super::{CombatAiSnapshot, CombatSkillOption, CombatTargetOption};

impl Simulation {
    pub(crate) fn build_combat_ai_snapshot(&self, actor_id: ActorId) -> Option<CombatAiSnapshot> {
        if self.get_actor_side(actor_id) == Some(game_data::ActorSide::Player) {
            return None;
        }

        let actor_grid = self.actor_grid_position(actor_id)?;
        let actor_ap = self.get_actor_ap(actor_id);
        let attack_ap_cost = self.attack_action_cost(actor_id);
        let actor_max_hp = self.max_hit_points(actor_id).max(1.0);
        let actor_hp_ratio = (self.actor_hit_points(actor_id) / actor_max_hp).clamp(0.0, 1.0);
        let mut target_options = self
            .actors
            .values()
            .filter(|candidate| candidate.actor_id != actor_id)
            .filter(|candidate| self.are_actors_hostile(actor_id, candidate.actor_id))
            .map(|candidate| {
                let dx = i64::from((candidate.grid_position.x - actor_grid.x).abs());
                let dz = i64::from((candidate.grid_position.z - actor_grid.z).abs());
                let dy = i64::from((candidate.grid_position.y - actor_grid.y).abs()) * 100;
                let (approach_goals, approach_distance_steps) =
                    self.collect_combat_approach_goals(actor_id, candidate.actor_id);
                let target_max_hp = self.max_hit_points(candidate.actor_id).max(1.0);
                CombatTargetOption {
                    target_actor_id: candidate.actor_id,
                    distance_score: dx + dz + dy,
                    target_hp_ratio: (self.actor_hit_points(candidate.actor_id) / target_max_hp)
                        .clamp(0.0, 1.0),
                    can_basic_attack: self
                        .validate_attack_preconditions(actor_id, candidate.actor_id)
                        .is_ok()
                        && self.can_actor_afford(actor_id, ActionType::Attack, None),
                    approach_distance_steps,
                    skill_options: self.collect_combat_skill_options(actor_id, candidate.actor_id),
                    approach_goals,
                }
            })
            .collect::<Vec<_>>();
        target_options.sort_by_key(|option| (option.distance_score, option.target_actor_id.0));

        Some(CombatAiSnapshot {
            actor_id,
            actor_ap,
            attack_ap_cost,
            actor_hp_ratio,
            target_options,
        })
    }

    fn collect_combat_skill_options(
        &self,
        actor_id: ActorId,
        target_actor: ActorId,
    ) -> Vec<CombatSkillOption> {
        let Some(actor) = self.economy.actor(actor_id) else {
            return Vec::new();
        };

        actor.learned_skills
            .iter()
            .filter(|(_, level)| **level > 0)
            .filter_map(|(skill_id, _)| {
                let skill = self
                    .skill_library
                    .as_ref()
                    .and_then(|skills| skills.get(skill_id))?;
                let activation = skill.activation.as_ref()?;
                if activation.mode.trim() != "active"
                    || self.skill_cooldown_remaining(actor_id, skill_id) > 0.0
                    || !self.can_actor_afford(actor_id, ActionType::Skill, None)
                {
                    return None;
                }

                let target_request = SkillTargetRequest::Actor(target_actor);
                let preview = self.preview_skill_target(actor_id, skill_id, target_request);
                if preview.invalid_reason.is_some()
                    || !preview.preview_hit_actor_ids.contains(&target_actor)
                {
                    return None;
                }

                Some(CombatSkillOption {
                    skill_id: skill_id.clone(),
                })
            })
            .collect()
    }

    fn collect_combat_approach_goals(
        &self,
        actor_id: ActorId,
        target_actor: ActorId,
    ) -> (Vec<game_data::GridCoord>, Option<u32>) {
        let Some(target_grid) = self.actor_grid_position(target_actor) else {
            return (Vec::new(), None);
        };

        let Some(actor_grid) = self.actor_grid_position(actor_id) else {
            return (Vec::new(), None);
        };

        let mut candidate_goals =
            super::super::interaction_flow::collect_interaction_ring_cells(target_grid, 1)
                .into_iter()
                .filter(|candidate| self.grid_walkable_for_actor(*candidate, Some(actor_id)))
                .filter_map(|candidate| {
                    self.find_path_grid(Some(actor_id), actor_grid, candidate)
                        .ok()
                        .map(|path| {
                            let step_count = path.len().saturating_sub(1) as u32;
                            (candidate, step_count)
                        })
                })
                .collect::<Vec<_>>();
        candidate_goals.sort_by_key(|(candidate, step_count)| (*step_count, *candidate));
        let approach_distance_steps = candidate_goals.first().map(|(_, step_count)| *step_count);
        (
            candidate_goals
                .into_iter()
                .map(|(candidate, _)| candidate)
                .collect(),
            approach_distance_steps,
        )
    }
}
