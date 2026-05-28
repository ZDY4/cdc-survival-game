//! 角色成长规则：负责经验、等级、属性点和击杀经验奖励。

use game_data::ActorId;

use super::{ActorProgressionState, Simulation, SimulationEvent};

impl Simulation {
    pub fn seed_actor_progression(&mut self, actor_id: ActorId, level: i32, xp_reward: i32) {
        if !self.actors.contains(actor_id) {
            return;
        }
        let normalized_level = level.max(1);
        self.actor_progression.insert(
            actor_id,
            ActorProgressionState {
                level: normalized_level,
                ..ActorProgressionState::default()
            },
        );
        self.actor_xp_rewards.insert(actor_id, xp_reward.max(0));
        self.economy.set_actor_level(actor_id, normalized_level);
    }

    pub fn actor_level(&self, actor_id: ActorId) -> i32 {
        self.actor_progression
            .get(&actor_id)
            .map(|state| state.level.max(1))
            .unwrap_or(1)
    }

    pub fn actor_current_xp(&self, actor_id: ActorId) -> i32 {
        self.actor_progression
            .get(&actor_id)
            .map(|state| state.current_xp.max(0))
            .unwrap_or(0)
    }

    pub fn allocate_attribute_point(
        &mut self,
        actor_id: ActorId,
        attribute: &str,
    ) -> Result<i32, String> {
        let normalized = attribute.trim().to_ascii_lowercase();
        if normalized.is_empty() {
            return Err("attribute_missing".to_string());
        }

        let progression = self
            .actor_progression
            .get_mut(&actor_id)
            .ok_or_else(|| format!("unknown_actor:{actor_id:?}"))?;
        if progression.available_stat_points <= 0 {
            return Err("attribute_points_unavailable".to_string());
        }

        let current = self
            .economy
            .actor(actor_id)
            .and_then(|actor| actor.attributes.get(&normalized))
            .copied()
            .unwrap_or(0);
        progression.available_stat_points -= 1;
        self.economy
            .set_actor_attribute(actor_id, normalized.clone(), current + 1);
        Ok(current + 1)
    }

    pub(super) fn award_kill_experience(&mut self, actor_id: ActorId, target_actor: ActorId) {
        if !self.actors.contains(actor_id) {
            return;
        }
        let amount = self
            .actor_xp_rewards
            .get(&target_actor)
            .copied()
            .unwrap_or(0)
            .max(0);
        self.grant_experience(actor_id, amount);
    }

    pub(super) fn grant_experience(&mut self, actor_id: ActorId, amount: i32) {
        if amount <= 0 || !self.actors.contains(actor_id) {
            return;
        }

        let (total_xp_after, level_up_event) = {
            let state = self.actor_progression.entry(actor_id).or_insert_with(|| {
                let level = self
                    .economy
                    .actor(actor_id)
                    .map(|actor| actor.level)
                    .unwrap_or(1)
                    .max(1);
                ActorProgressionState {
                    level,
                    ..ActorProgressionState::default()
                }
            });
            state.current_xp += amount;
            state.total_xp_earned += amount;
            let mut level_up_event = None;

            while state.current_xp >= xp_to_next_level(state.level) {
                let required = xp_to_next_level(state.level);
                state.current_xp -= required;
                state.level += 1;
                state.available_stat_points += 3;
                state.available_skill_points += 1;
                state.total_stat_points_earned += 3;
                state.total_skill_points_earned += 1;
                let _ = self.economy.add_skill_points(actor_id, 1);
                level_up_event = Some((
                    state.level,
                    state.available_stat_points,
                    state.available_skill_points,
                ));
            }
            let total_xp_after = state.current_xp;
            self.economy.set_actor_level(actor_id, state.level);
            (total_xp_after, level_up_event)
        };

        self.events.push(SimulationEvent::ExperienceGranted {
            actor_id,
            amount,
            total_xp: total_xp_after,
        });
        if let Some((new_level, available_stat_points, available_skill_points)) = level_up_event {
            self.events.push(SimulationEvent::ActorLeveledUp {
                actor_id,
                new_level,
                available_stat_points,
                available_skill_points,
            });
        }
    }
}

fn xp_to_next_level(level: i32) -> i32 {
    let normalized_level = level.max(1) as f32;
    (100.0 * normalized_level.powf(1.2)).round() as i32
}
