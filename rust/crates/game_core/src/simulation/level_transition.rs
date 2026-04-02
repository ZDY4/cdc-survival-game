use game_data::{ActorId, GridCoord, MapId, WorldMode};

use crate::overworld::{location_by_id, world_mode_for_location_kind, LocationTransitionContext};

use super::Simulation;

#[derive(Debug, Clone, PartialEq)]
pub(super) enum LevelTransitionTarget {
    DirectMap {
        map_id: MapId,
        entry_point_id: String,
        world_mode: WorldMode,
    },
    Location {
        location_id: String,
        entry_point_id: Option<String>,
    },
    Overworld {
        active_location_id: Option<String>,
        overworld_cell: Option<GridCoord>,
        world_mode: WorldMode,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub(super) enum AppliedLevelTransition {
    DirectMap {
        map_id: String,
        entry_point_id: String,
        world_mode: WorldMode,
    },
    Location(LocationTransitionContext),
    Overworld {
        active_outdoor_location_id: Option<String>,
        world_mode: WorldMode,
    },
}

impl Simulation {
    pub(super) fn apply_seeded_overworld_transition(
        &mut self,
        world_mode: WorldMode,
        active_location_id: Option<String>,
        entry_point_id: Option<String>,
    ) -> Result<AppliedLevelTransition, String> {
        let clear_loaded_map = matches!(world_mode, WorldMode::Overworld);
        self.apply_overworld_transition_with_options(
            active_location_id,
            None,
            world_mode,
            entry_point_id,
            clear_loaded_map,
        )
    }

    pub(super) fn apply_level_transition(
        &mut self,
        actor_id: ActorId,
        target: LevelTransitionTarget,
    ) -> Result<AppliedLevelTransition, String> {
        match target {
            LevelTransitionTarget::DirectMap {
                map_id,
                entry_point_id,
                world_mode,
            } => self.apply_direct_map_transition(actor_id, &map_id, &entry_point_id, world_mode),
            LevelTransitionTarget::Location {
                location_id,
                entry_point_id,
            } => self.apply_location_transition(actor_id, &location_id, entry_point_id.as_deref()),
            LevelTransitionTarget::Overworld {
                active_location_id,
                overworld_cell,
                world_mode,
            } => self.apply_overworld_transition(active_location_id, overworld_cell, world_mode),
        }
    }

    fn apply_direct_map_transition(
        &mut self,
        actor_id: ActorId,
        map_id: &MapId,
        entry_point_id: &str,
        world_mode: WorldMode,
    ) -> Result<AppliedLevelTransition, String> {
        if matches!(world_mode, WorldMode::Overworld) {
            return Err(format!("invalid_world_mode:{world_mode:?}"));
        }

        let entry_point =
            self.load_location_map_and_place_actor(actor_id, map_id, entry_point_id)?;

        if matches!(world_mode, WorldMode::Interior | WorldMode::Dungeon)
            && self.return_outdoor_location_id.is_none()
        {
            self.return_outdoor_location_id = self.active_location_id.clone();
        }

        self.active_location_id = None;
        self.interaction_context.world_mode = world_mode;
        self.sync_interaction_context_from_runtime();

        Ok(AppliedLevelTransition::DirectMap {
            map_id: map_id.as_str().to_string(),
            entry_point_id: entry_point.id,
            world_mode,
        })
    }

    fn apply_location_transition(
        &mut self,
        actor_id: ActorId,
        location_id: &str,
        entry_point_id: Option<&str>,
    ) -> Result<AppliedLevelTransition, String> {
        let definition = self.current_overworld_definition()?.clone();
        let location = location_by_id(&definition, location_id)
            .ok_or_else(|| format!("unknown_location:{location_id}"))?
            .clone();
        let resolved_entry_point_id = entry_point_id
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(location.entry_point_id.as_str())
            .to_string();
        let world_mode = world_mode_for_location_kind(location.kind);

        let AppliedLevelTransition::DirectMap { entry_point_id, .. } = self
            .apply_direct_map_transition(
                actor_id,
                &location.map_id,
                &resolved_entry_point_id,
                world_mode,
            )?
        else {
            unreachable!("direct map transition should return direct map result");
        };

        self.active_location_id = Some(location.id.as_str().to_string());
        self.overworld_pawn_cell = Some(location.overworld_cell);
        self.return_outdoor_location_id = match location.kind {
            game_data::OverworldLocationKind::Outdoor => Some(location.id.as_str().to_string()),
            game_data::OverworldLocationKind::Interior
            | game_data::OverworldLocationKind::Dungeon => location
                .parent_outdoor_location_id
                .as_ref()
                .map(|location_id| location_id.as_str().to_string()),
        };
        self.sync_interaction_context_from_runtime();

        Ok(AppliedLevelTransition::Location(
            LocationTransitionContext {
                location_id: location.id.as_str().to_string(),
                map_id: location.map_id.as_str().to_string(),
                entry_point_id,
                return_outdoor_location_id: self.return_outdoor_location_id.clone(),
                return_entry_point_id: location.return_entry_point_id.clone(),
                world_mode,
            },
        ))
    }

    fn apply_overworld_transition(
        &mut self,
        active_location_id: Option<String>,
        overworld_cell: Option<GridCoord>,
        world_mode: WorldMode,
    ) -> Result<AppliedLevelTransition, String> {
        self.apply_overworld_transition_with_options(
            active_location_id,
            overworld_cell,
            world_mode,
            None,
            true,
        )
    }

    fn apply_overworld_transition_with_options(
        &mut self,
        active_location_id: Option<String>,
        overworld_cell: Option<GridCoord>,
        world_mode: WorldMode,
        entry_point_id: Option<String>,
        clear_loaded_map: bool,
    ) -> Result<AppliedLevelTransition, String> {
        if !matches!(world_mode, WorldMode::Overworld | WorldMode::Outdoor) {
            return Err(format!("invalid_world_mode:{world_mode:?}"));
        }

        let has_active_location = active_location_id.is_some();
        let (resolved_overworld_cell, resolved_return_outdoor_location_id) = self
            .resolve_overworld_transition_anchor(active_location_id.as_deref(), overworld_cell)?;

        self.active_location_id = active_location_id;
        self.overworld_pawn_cell = resolved_overworld_cell;

        if has_active_location {
            self.return_outdoor_location_id = resolved_return_outdoor_location_id;
        }

        if clear_loaded_map {
            self.grid_world.clear_map();
            self.reset_runtime_actor_occupancy();
            self.current_entry_point_id = None;
            self.interaction_context.current_map_id = None;
            self.interaction_context.entry_point_id = None;
            self.interaction_context.current_subscene_location_id = None;
        } else {
            self.current_entry_point_id = entry_point_id;
        }

        self.interaction_context.world_mode = world_mode;
        self.sync_interaction_context_from_runtime();

        let active_outdoor_location_id = self
            .current_overworld_definition()
            .ok()
            .and_then(|definition| self.resolve_active_outdoor_location_id(definition));

        Ok(AppliedLevelTransition::Overworld {
            active_outdoor_location_id,
            world_mode,
        })
    }

    fn resolve_overworld_transition_anchor(
        &self,
        active_location_id: Option<&str>,
        overworld_cell: Option<GridCoord>,
    ) -> Result<(Option<GridCoord>, Option<String>), String> {
        let Some(location_id) = active_location_id else {
            return Ok((overworld_cell, None));
        };

        let definition = self.current_overworld_definition()?;
        let location = location_by_id(definition, location_id)
            .ok_or_else(|| format!("unknown_location:{location_id}"))?;
        let return_outdoor_location_id = match location.kind {
            game_data::OverworldLocationKind::Outdoor => Some(location.id.as_str().to_string()),
            game_data::OverworldLocationKind::Interior
            | game_data::OverworldLocationKind::Dungeon => location
                .parent_outdoor_location_id
                .as_ref()
                .map(|location_id| location_id.as_str().to_string()),
        };

        Ok((
            Some(overworld_cell.unwrap_or(location.overworld_cell)),
            return_outdoor_location_id,
        ))
    }
}
