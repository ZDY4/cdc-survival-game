//! Actor 关系值规则：负责默认阵营关系、读取、设置和增量调整。

use game_data::{ActorId, ActorSide};

use super::Simulation;

impl Simulation {
    pub fn get_relationship_score(&self, actor_id: ActorId, target_actor_id: ActorId) -> i32 {
        self.actor_relationships
            .get(&(actor_id, target_actor_id))
            .copied()
            .unwrap_or_else(|| self.default_relationship_score(actor_id, target_actor_id))
    }

    pub(super) fn default_relationship_score(
        &self,
        actor_id: ActorId,
        target_actor_id: ActorId,
    ) -> i32 {
        let actor_side = self.get_actor_side(actor_id).unwrap_or(ActorSide::Neutral);
        let target_side = self
            .get_actor_side(target_actor_id)
            .unwrap_or(ActorSide::Neutral);
        default_relationship_score_for_sides(actor_side, target_side)
    }

    pub fn set_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        score: i32,
    ) -> i32 {
        let score = score.clamp(-100, 100);
        self.actor_relationships
            .insert((actor_id, target_actor_id), score);
        score
    }

    pub fn adjust_relationship_score(
        &mut self,
        actor_id: ActorId,
        target_actor_id: ActorId,
        delta: i32,
    ) -> i32 {
        let next = self
            .get_relationship_score(actor_id, target_actor_id)
            .saturating_add(delta)
            .clamp(-100, 100);
        self.actor_relationships
            .insert((actor_id, target_actor_id), next);
        next
    }
}

fn default_relationship_score_for_sides(actor_side: ActorSide, target_side: ActorSide) -> i32 {
    match (actor_side, target_side) {
        (ActorSide::Player, ActorSide::Player) => 60,
        (ActorSide::Hostile, _) | (_, ActorSide::Hostile) => -60,
        (ActorSide::Neutral, _) | (_, ActorSide::Neutral) => 0,
        (ActorSide::Friendly, _) | (_, ActorSide::Friendly) => 40,
    }
}
