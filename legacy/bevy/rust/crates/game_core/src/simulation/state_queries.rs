use game_data::{InteractionContextSnapshot, OverworldDefinition, WorldMode};

use crate::overworld::{location_by_id, OverworldStateSnapshot};

use super::Simulation;

impl Simulation {
    pub(crate) fn current_interaction_context(&self) -> InteractionContextSnapshot {
        let mut snapshot = self.interaction_context.clone();
        let overworld = self.current_overworld_snapshot();
        snapshot.current_map_id = overworld.current_map_id;
        snapshot.active_outdoor_location_id = overworld.active_outdoor_location_id;
        snapshot.active_location_id = overworld.active_location_id;
        snapshot.current_subscene_location_id = match overworld.world_mode {
            WorldMode::Interior | WorldMode::Dungeon => self.active_location_id.clone(),
            _ => None,
        };
        snapshot.return_outdoor_location_id = self.return_outdoor_location_id.clone();
        snapshot.return_outdoor_spawn_id = self.current_return_entry_point_id();
        snapshot.overworld_pawn_cell = overworld.current_overworld_cell;
        snapshot.entry_point_id = overworld.current_entry_point_id;
        snapshot.world_mode = overworld.world_mode;
        snapshot
    }

    pub(crate) fn current_overworld_snapshot(&self) -> OverworldStateSnapshot {
        let runtime_world_mode = self.interaction_context.world_mode;
        let active_location_id = self
            .active_location_id
            .clone()
            .or_else(|| self.interaction_context.active_location_id.clone());
        let active_outdoor_location_id = self
            .current_overworld_definition()
            .ok()
            .and_then(|definition| self.resolve_active_outdoor_location_id(definition))
            .or_else(|| self.interaction_context.active_outdoor_location_id.clone());

        OverworldStateSnapshot {
            overworld_id: self.active_overworld_id.clone(),
            active_location_id,
            active_outdoor_location_id,
            current_map_id: if matches!(runtime_world_mode, WorldMode::Overworld) {
                None
            } else {
                self.grid_world
                    .map_id()
                    .map(|map_id| map_id.as_str().to_string())
                    .or_else(|| self.interaction_context.current_map_id.clone())
            },
            current_entry_point_id: if matches!(runtime_world_mode, WorldMode::Overworld) {
                None
            } else {
                self.current_entry_point_id
                    .clone()
                    .or_else(|| self.interaction_context.entry_point_id.clone())
            },
            current_overworld_cell: self
                .overworld_pawn_cell
                .or(self.interaction_context.overworld_pawn_cell),
            unlocked_locations: self.unlocked_locations.iter().cloned().collect(),
            world_mode: runtime_world_mode,
        }
    }

    pub(super) fn resolve_active_outdoor_location_id(
        &self,
        definition: &OverworldDefinition,
    ) -> Option<String> {
        let active_location_id = self.active_location_id.as_deref()?;
        let location = location_by_id(definition, active_location_id)?;
        match location.kind {
            game_data::OverworldLocationKind::Outdoor => Some(active_location_id.to_string()),
            game_data::OverworldLocationKind::Interior
            | game_data::OverworldLocationKind::Dungeon => location
                .parent_outdoor_location_id
                .as_ref()
                .map(|location_id| location_id.as_str().to_string())
                .or_else(|| self.return_outdoor_location_id.clone()),
        }
    }

    fn current_return_entry_point_id(&self) -> Option<String> {
        let definition = self.current_overworld_definition().ok()?;
        let location_id = self.active_location_id.as_deref()?;
        let location = location_by_id(definition, location_id)?;
        location.return_entry_point_id.clone()
    }
}
