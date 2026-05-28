use std::collections::BTreeSet;

use game_data::{ActorId, ActorSide, GridCoord};

use crate::vision::has_grid_line_of_sight;

use super::{AttackTargetingQueryResult, Simulation};

impl Simulation {
    pub fn attack_range(&self, actor_id: ActorId) -> f32 {
        self.attack_interaction_distance(actor_id)
    }

    pub fn query_attack_targeting(&self, actor_id: ActorId) -> AttackTargetingQueryResult {
        if !self.actors.contains(actor_id) {
            return AttackTargetingQueryResult {
                valid_grids: Vec::new(),
                valid_actor_ids: Vec::new(),
                invalid_reason: Some("unknown_actor".to_string()),
            };
        }

        let mut valid_grids = self
            .actors
            .values()
            .filter(|actor| actor.actor_id != actor_id && actor.side == ActorSide::Hostile)
            .filter_map(|actor| {
                self.validate_attack_target_spatial(actor_id, actor.actor_id)
                    .ok()
                    .map(|_| actor)
            })
            .map(|actor| actor.grid_position)
            .collect::<Vec<_>>();
        valid_grids.sort_by_key(|grid| (grid.y, grid.z, grid.x));
        valid_grids.dedup();

        let mut valid_actor_ids = self
            .actors
            .values()
            .filter(|actor| actor.actor_id != actor_id && actor.side == ActorSide::Hostile)
            .filter_map(|actor| {
                self.validate_attack_target_spatial(actor_id, actor.actor_id)
                    .ok()
                    .map(|_| actor.actor_id)
            })
            .collect::<Vec<_>>();
        valid_actor_ids.sort_by_key(|candidate| candidate.0);

        let invalid_reason = valid_actor_ids
            .is_empty()
            .then_some("no_attack_targets".to_string());

        AttackTargetingQueryResult {
            valid_grids,
            valid_actor_ids,
            invalid_reason,
        }
    }

    pub(super) fn attack_interaction_distance(&self, actor_id: ActorId) -> f32 {
        let default_range = self
            .actor_attack_ranges
            .get(&actor_id)
            .copied()
            .unwrap_or(1.2)
            .max(1.0);
        let Some(items) = self.item_library.as_ref() else {
            return default_range;
        };
        match self.economy.equipped_weapon(actor_id, "main_hand", items) {
            Ok(Some(weapon)) => (weapon.range as f32).max(1.0),
            _ => default_range,
        }
    }

    pub(super) fn attack_range_cells(&self, actor_id: ActorId) -> i32 {
        self.attack_interaction_distance(actor_id).floor().max(1.0) as i32
    }

    pub(super) fn validate_attack_target_spatial(
        &self,
        actor_id: ActorId,
        target_actor: ActorId,
    ) -> Result<(), &'static str> {
        let Some(actor_grid) = self.actor_grid_position(actor_id) else {
            return Err("unknown_actor");
        };
        let Some(target_grid) = self.actor_grid_position(target_actor) else {
            return Err("unknown_target");
        };
        self.validate_target_center_spatial(
            actor_grid,
            target_grid,
            self.attack_range_cells(actor_id),
        )
    }

    pub(super) fn validate_target_center_spatial(
        &self,
        actor_grid: GridCoord,
        target_grid: GridCoord,
        range_cells: i32,
    ) -> Result<(), &'static str> {
        if !self.grid_world.is_in_bounds(target_grid) {
            return Err("target_out_of_bounds");
        }
        if actor_grid.y != target_grid.y {
            return Err("target_invalid_level");
        }
        if manhattan_grid_distance(actor_grid, target_grid) > range_cells.max(0) {
            return Err("target_out_of_range");
        }
        if !has_grid_line_of_sight(&self.grid_world, actor_grid, target_grid) {
            return Err("target_blocked_by_los");
        }

        Ok(())
    }

    pub(super) fn iter_level_grids(&self, level: i32) -> Vec<GridCoord> {
        if let Some(size) = self.grid_world.map_size() {
            return (0..size.width as i32)
                .flat_map(|x| (0..size.height as i32).map(move |z| GridCoord::new(x, level, z)))
                .collect();
        }

        self.actors
            .values()
            .filter(|actor| actor.grid_position.y == level)
            .map(|actor| actor.grid_position)
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect()
    }
}

pub(super) fn manhattan_grid_distance(left: GridCoord, right: GridCoord) -> i32 {
    (left.x - right.x).abs() + (left.y - right.y).abs() + (left.z - right.z).abs()
}
