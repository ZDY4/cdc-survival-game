use std::collections::BTreeMap;

use game_data::{
    ActorId, GridCoord, InteractionContextSnapshot, InteractionOptionId, MapCellDefinition, MapId,
    MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps, MapTriggerProps,
    OverworldLocationKind, WorldMode,
};

use crate::overworld::{default_outdoor_spawn_cell, is_outdoor_location_cell};
use crate::overworld::{location_by_id, LocationTransitionContext, OverworldStateSnapshot};

use super::{
    level_transition::{AppliedLevelTransition, LevelTransitionTarget},
    Simulation,
};

impl Simulation {
    pub(super) fn sync_interaction_context_from_runtime(&mut self) {
        self.interaction_context = self.current_interaction_context();
    }

    pub(super) fn reset_runtime_actor_occupancy(&mut self) {
        let actor_ids: Vec<ActorId> = self.actors.ids().collect();
        for actor_id in actor_ids {
            self.grid_world.unregister_runtime_actor(actor_id);
        }
    }

    pub(super) fn load_location_map_and_place_actor(
        &mut self,
        actor_id: ActorId,
        map_id: &MapId,
        entry_point_id: &str,
    ) -> Result<game_data::MapEntryPointDefinition, String> {
        let map = self
            .map_library
            .as_ref()
            .ok_or_else(|| "map_library_missing".to_string())?
            .get(map_id)
            .ok_or_else(|| format!("unknown_map:{}", map_id.as_str()))?
            .clone();
        let entry_point = crate::overworld::find_entry_point(&map, entry_point_id)
            .ok_or_else(|| format!("unknown_entry_point:{entry_point_id}"))?
            .clone();

        self.reset_runtime_actor_occupancy();
        self.grid_world.load_map(&map);
        self.ensure_current_map_containers();
        self.update_actor_grid_position(actor_id, entry_point.grid);
        self.current_entry_point_id = Some(entry_point.id.clone());
        Ok(entry_point)
    }

    pub(super) fn load_overworld_topology(&mut self) -> Result<(), String> {
        let definition = self.current_overworld_definition()?.clone();
        let default_level = Some(0);
        let cells = definition.cells.iter().map(|cell| {
            (
                cell.grid,
                MapCellDefinition {
                    x: cell.grid.x as u32,
                    z: cell.grid.z as u32,
                    blocks_movement: cell.blocked
                        || !cell.terrain.is_passable()
                        || is_outdoor_location_cell(&definition, cell.grid),
                    blocks_sight: false,
                    terrain: cell.terrain.as_str().to_string(),
                    visual: None,
                    extra: cell.extra.clone(),
                },
            )
        });
        let objects = definition
            .locations
            .iter()
            .filter(|location| {
                location.kind == OverworldLocationKind::Outdoor
                    && self.unlocked_locations.contains(location.id.as_str())
            })
            .map(overworld_location_trigger_object)
            .collect::<Vec<_>>();

        self.grid_world
            .load_explicit_topology(default_level, cells, objects);
        Ok(())
    }

    pub(super) fn reload_overworld_topology_and_place_actor(
        &mut self,
        actor_id: ActorId,
    ) -> Result<GridCoord, String> {
        if !self.actors.contains(actor_id) {
            return Err("unknown_actor".to_string());
        }

        self.reset_runtime_actor_occupancy();
        self.load_overworld_topology()?;
        let overworld_cell = self.resolve_current_overworld_cell()?;
        self.update_actor_grid_position(actor_id, overworld_cell);
        self.sync_interaction_context_from_runtime();
        Ok(overworld_cell)
    }

    pub(super) fn refresh_overworld_topology_preserving_actor_positions(
        &mut self,
    ) -> Result<(), String> {
        let actor_positions = self
            .actors
            .ids()
            .filter_map(|actor_id| {
                self.actor_grid_position(actor_id)
                    .map(|grid| (actor_id, grid))
            })
            .collect::<Vec<_>>();
        self.reset_runtime_actor_occupancy();
        self.load_overworld_topology()?;
        for (actor_id, grid) in actor_positions {
            if self.grid_world.is_in_bounds(grid) {
                self.grid_world.set_runtime_actor_grid(actor_id, grid);
            }
        }
        self.sync_interaction_context_from_runtime();
        Ok(())
    }

    pub(super) fn resolve_current_overworld_cell(&self) -> Result<GridCoord, String> {
        self.overworld_pawn_cell
            .or_else(|| {
                self.active_location_id.as_deref().and_then(|location_id| {
                    self.current_overworld_definition()
                        .ok()
                        .and_then(|definition| {
                            location_by_id(definition, location_id).and_then(|location| {
                                if location.kind == game_data::OverworldLocationKind::Outdoor {
                                    default_outdoor_spawn_cell(definition, location)
                                } else {
                                    Some(location.overworld_cell)
                                }
                            })
                        })
                })
            })
            .or(self.interaction_context.overworld_pawn_cell)
            .ok_or_else(|| "active_overworld_cell_missing".to_string())
    }

    pub(crate) fn travel_to_map(
        &mut self,
        actor_id: ActorId,
        target_map_id: &str,
        entry_point_id: Option<&str>,
        world_mode: WorldMode,
    ) -> Result<InteractionContextSnapshot, String> {
        if !self.actors.contains(actor_id) {
            return Err("unknown_actor".to_string());
        }
        if matches!(world_mode, WorldMode::Overworld) {
            return Err(format!("invalid_world_mode:{world_mode:?}"));
        }

        let target_map_id = target_map_id.trim();
        if target_map_id.is_empty() {
            return Err("unknown_map".to_string());
        }

        let resolved_entry_point_id = entry_point_id
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or("default_entry")
            .to_string();
        let map_id = MapId(target_map_id.to_string());
        let AppliedLevelTransition::DirectMap {
            map_id,
            entry_point_id,
            world_mode,
        } = self.apply_level_transition(
            actor_id,
            LevelTransitionTarget::DirectMap {
                map_id,
                entry_point_id: resolved_entry_point_id,
                world_mode,
            },
        )?
        else {
            unreachable!("direct map transition should return direct map result");
        };

        self.events.push(
            crate::simulation::SimulationEvent::SceneTransitionRequested {
                actor_id,
                option_id: InteractionOptionId("travel_to_map".into()),
                target_id: map_id.clone(),
                world_mode,
                location_id: None,
                entry_point_id: Some(entry_point_id.clone()),
                return_location_id: self.return_outdoor_location_id.clone(),
            },
        );

        Ok(self.current_interaction_context())
    }

    pub(crate) fn enter_location(
        &mut self,
        actor_id: ActorId,
        location_id: &str,
        entry_point_id: Option<&str>,
    ) -> Result<LocationTransitionContext, String> {
        if !self.actors.contains(actor_id) {
            return Err("unknown_actor".to_string());
        }
        let AppliedLevelTransition::Location(transition) = self.apply_level_transition(
            actor_id,
            LevelTransitionTarget::Location {
                location_id: location_id.to_string(),
                entry_point_id: entry_point_id.map(str::to_string),
            },
        )?
        else {
            unreachable!("location transition should return location result");
        };

        self.events.push(
            crate::simulation::SimulationEvent::SceneTransitionRequested {
                actor_id,
                option_id: InteractionOptionId("enter_location".into()),
                target_id: transition.map_id.clone(),
                world_mode: transition.world_mode,
                location_id: Some(transition.location_id.clone()),
                entry_point_id: Some(transition.entry_point_id.clone()),
                return_location_id: self.return_outdoor_location_id.clone(),
            },
        );
        self.events
            .push(crate::simulation::SimulationEvent::LocationEntered {
                actor_id,
                location_id: transition.location_id.clone(),
                map_id: transition.map_id.clone(),
                entry_point_id: transition.entry_point_id.clone(),
                world_mode: transition.world_mode,
            });

        Ok(transition)
    }

    pub(crate) fn return_to_overworld(
        &mut self,
        actor_id: ActorId,
    ) -> Result<OverworldStateSnapshot, String> {
        if !self.actors.contains(actor_id) {
            return Err("unknown_actor".to_string());
        }
        let definition = self.current_overworld_definition()?.clone();
        let outdoor_location_id = self
            .active_location_id
            .as_deref()
            .and_then(|location_id| location_by_id(&definition, location_id))
            .map(|location| match location.kind {
                game_data::OverworldLocationKind::Outdoor => Some(location.id.as_str().to_string()),
                game_data::OverworldLocationKind::Interior
                | game_data::OverworldLocationKind::Dungeon => location
                    .parent_outdoor_location_id
                    .as_ref()
                    .map(|location_id| location_id.as_str().to_string()),
            })
            .flatten()
            .or_else(|| self.return_outdoor_location_id.clone());

        let overworld_cell = self.overworld_pawn_cell.or_else(|| {
            outdoor_location_id
                .as_deref()
                .and_then(|location_id| location_by_id(&definition, location_id))
                .and_then(|location| default_outdoor_spawn_cell(&definition, location))
        });
        let AppliedLevelTransition::Overworld {
            active_outdoor_location_id,
            ..
        } = self.apply_level_transition(
            actor_id,
            LevelTransitionTarget::Overworld {
                active_location_id: outdoor_location_id,
                overworld_cell,
                world_mode: WorldMode::Overworld,
            },
        )?
        else {
            unreachable!("overworld transition should return overworld result");
        };
        self.reload_overworld_topology_and_place_actor(actor_id)?;
        self.events
            .push(crate::simulation::SimulationEvent::ReturnedToOverworld {
                actor_id,
                active_outdoor_location_id,
            });
        Ok(self.current_overworld_snapshot())
    }

    pub(crate) fn unlock_location(
        &mut self,
        location_id: &str,
    ) -> Result<OverworldStateSnapshot, String> {
        let definition = self.current_overworld_definition()?;
        if location_by_id(definition, location_id).is_none() {
            return Err(format!("unknown_location:{location_id}"));
        }
        if self.unlocked_locations.insert(location_id.to_string()) {
            if self.interaction_context.world_mode == WorldMode::Overworld {
                self.refresh_overworld_topology_preserving_actor_positions()?;
            }
            self.events
                .push(crate::simulation::SimulationEvent::LocationUnlocked {
                    location_id: location_id.to_string(),
                });
        }
        Ok(self.current_overworld_snapshot())
    }
}

fn overworld_location_trigger_object(
    location: &game_data::OverworldLocationDefinition,
) -> MapObjectDefinition {
    MapObjectDefinition {
        object_id: format!("overworld_trigger::{}", location.id.as_str()),
        kind: MapObjectKind::Trigger,
        anchor: location.overworld_cell,
        footprint: MapObjectFootprint::default(),
        rotation: game_data::MapRotation::North,
        blocks_movement: false,
        blocks_sight: false,
        props: MapObjectProps {
            trigger: Some(MapTriggerProps {
                display_name: location.name.clone(),
                interaction_distance: 0.6,
                interaction_kind: "enter_outdoor_location".into(),
                target_id: Some(location.id.as_str().to_string()),
                options: Vec::new(),
                extra: BTreeMap::new(),
            }),
            ..MapObjectProps::default()
        },
    }
}
