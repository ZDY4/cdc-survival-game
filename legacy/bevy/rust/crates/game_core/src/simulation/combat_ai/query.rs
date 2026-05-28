//! 战斗 AI 查询模块。
//! 负责构建战斗快照和候选目标评价数据，不负责 profile 策略选择或动作执行。

use game_data::{ActionType, ActorId, GridCoord, SkillTargetRequest};

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
        let combat_origin_grid = self.actor_combat_origin_grid(actor_id);
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
                let retreat_goals = self.collect_combat_retreat_goals(actor_id, candidate.actor_id);
                let candidate_direct_attack = self
                    .validate_attack_preconditions(candidate.actor_id, actor_id)
                    .is_ok()
                    && self.can_actor_afford(candidate.actor_id, ActionType::Attack, None);
                let candidate_skill_threat = !self
                    .collect_combat_skill_options(candidate.actor_id, actor_id)
                    .is_empty();
                let target_max_hp = self.max_hit_points(candidate.actor_id).max(1.0);
                CombatTargetOption {
                    target_actor_id: candidate.actor_id,
                    distance_score: dx + dz + dy,
                    threat_score: combat_threat_score(
                        dx + dz + dy,
                        candidate_direct_attack,
                        candidate_skill_threat,
                        self.actor_hit_points(candidate.actor_id) / target_max_hp,
                    ),
                    guard_distance_score: combat_origin_grid
                        .map(|origin| grid_distance_score(origin, candidate.grid_position)),
                    target_hp_ratio: (self.actor_hit_points(candidate.actor_id) / target_max_hp)
                        .clamp(0.0, 1.0),
                    can_basic_attack: self
                        .validate_attack_preconditions(actor_id, candidate.actor_id)
                        .is_ok()
                        && self.can_actor_afford(actor_id, ActionType::Attack, None),
                    approach_distance_steps,
                    skill_options: self.collect_combat_skill_options(actor_id, candidate.actor_id),
                    approach_goals,
                    retreat_goals,
                }
            })
            .collect::<Vec<_>>();
        target_options.sort_by_key(|option| (option.distance_score, option.target_actor_id.0));

        Some(CombatAiSnapshot {
            actor_id,
            actor_ap,
            attack_ap_cost,
            actor_hp_ratio,
            combat_origin_grid,
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

        actor
            .learned_skills
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

                let hostile_hit_count = preview
                    .preview_hit_actor_ids
                    .iter()
                    .filter(|hit_actor_id| self.are_actors_hostile(actor_id, **hit_actor_id))
                    .count();
                let friendly_hit_count = preview
                    .preview_hit_actor_ids
                    .iter()
                    .filter(|hit_actor_id| {
                        **hit_actor_id != actor_id
                            && !self.are_actors_hostile(actor_id, **hit_actor_id)
                    })
                    .count();

                Some(CombatSkillOption {
                    skill_id: skill_id.clone(),
                    hit_actor_count: preview.preview_hit_actor_ids.len(),
                    hostile_hit_count,
                    friendly_hit_count,
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

    fn collect_combat_retreat_goals(
        &self,
        actor_id: ActorId,
        target_actor: ActorId,
    ) -> Vec<GridCoord> {
        let Some(actor_grid) = self.actor_grid_position(actor_id) else {
            return Vec::new();
        };
        let Some(target_grid) = self.actor_grid_position(target_actor) else {
            return Vec::new();
        };

        let max_steps = self.get_actor_available_steps(actor_id).max(0) as u32;
        if max_steps == 0 {
            return Vec::new();
        }

        let combat_origin_grid = self.actor_combat_origin_grid(actor_id);
        let mut candidate_goals = self
            .iter_level_grids(actor_grid.y)
            .into_iter()
            .filter(|candidate| *candidate != actor_grid)
            .filter(|candidate| self.grid_walkable_for_actor(*candidate, Some(actor_id)))
            .filter_map(|candidate| {
                self.find_path_grid(Some(actor_id), actor_grid, candidate)
                    .ok()
                    .and_then(|path| {
                        let step_count = path.len().saturating_sub(1) as u32;
                        if step_count == 0 || step_count > max_steps {
                            return None;
                        }
                        Some((
                            candidate,
                            step_count,
                            grid_distance_score(candidate, target_grid),
                            combat_origin_grid.map(|origin| grid_distance_score(origin, candidate)),
                        ))
                    })
            })
            .collect::<Vec<_>>();
        candidate_goals.sort_by(|left, right| {
            right
                .2
                .cmp(&left.2)
                .then_with(|| left.1.cmp(&right.1))
                .then_with(|| left.3.unwrap_or(i64::MAX).cmp(&right.3.unwrap_or(i64::MAX)))
                .then_with(|| left.0.cmp(&right.0))
        });
        candidate_goals
            .into_iter()
            .map(|(candidate, _, _, _)| candidate)
            .collect()
    }
}

fn grid_distance_score(left: GridCoord, right: GridCoord) -> i64 {
    let dx = i64::from((left.x - right.x).abs());
    let dz = i64::from((left.z - right.z).abs());
    let dy = i64::from((left.y - right.y).abs()) * 100;
    dx + dz + dy
}

fn combat_threat_score(
    distance_score: i64,
    direct_attack_threat: bool,
    direct_skill_threat: bool,
    candidate_hp_ratio: f32,
) -> i32 {
    let mut score = ((1.0 - (distance_score.min(6) as f32 / 6.0)) * 3.0).round() as i32;
    if direct_attack_threat {
        score += 4;
    }
    if direct_skill_threat {
        score += 5;
    }
    score + (candidate_hp_ratio.clamp(0.0, 1.0) * 3.0).round() as i32
}
