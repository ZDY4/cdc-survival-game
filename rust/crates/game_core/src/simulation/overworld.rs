use game_data::{
    ActorId, InteractionContextSnapshot, InteractionOptionId, MapEntryPointDefinition, MapId,
    WorldMode,
};

use crate::overworld::{
    compute_location_route, find_entry_point, location_by_id, world_mode_for_location_kind,
    LocationTransitionContext, OverworldRouteSnapshot, OverworldStateSnapshot,
    OverworldTravelState,
};

use super::Simulation;

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
    ) -> Result<MapEntryPointDefinition, String> {
        let map = self
            .map_library
            .as_ref()
            .ok_or_else(|| "map_library_missing".to_string())?
            .get(map_id)
            .ok_or_else(|| format!("unknown_map:{}", map_id.as_str()))?
            .clone();
        let entry_point = find_entry_point(&map, entry_point_id)
            .ok_or_else(|| format!("unknown_entry_point:{entry_point_id}"))?
            .clone();

        self.reset_runtime_actor_occupancy();
        self.grid_world.load_map(&map);
        self.update_actor_grid_position(actor_id, entry_point.grid);
        self.current_entry_point_id = Some(entry_point.id.clone());
        Ok(entry_point)
    }

    pub(crate) fn request_overworld_route(
        &mut self,
        actor_id: ActorId,
        target_location_id: &str,
    ) -> Result<OverworldRouteSnapshot, String> {
        if !self.actors.contains(actor_id) {
            return Err("unknown_actor".to_string());
        }
        let definition = self.current_overworld_definition()?;
        let from_location_id = self
            .active_location_id
            .clone()
            .or_else(|| self.resolve_active_outdoor_location_id(definition))
            .ok_or_else(|| "active_overworld_location_missing".to_string())?;
        let from_cell = self
            .overworld_pawn_cell
            .or_else(|| {
                location_by_id(definition, &from_location_id).map(|location| location.overworld_cell)
            })
            .ok_or_else(|| "active_overworld_cell_missing".to_string())?;
        if target_location_id != from_location_id
            && !self.unlocked_locations.contains(target_location_id)
        {
            return Err(format!("location_locked:{target_location_id}"));
        }

        let route = compute_location_route(
            definition,
            actor_id,
            &from_location_id,
            from_cell,
            target_location_id,
        )?;
        self.events.push(crate::simulation::SimulationEvent::OverworldRouteComputed {
            actor_id,
            target_location_id: target_location_id.to_string(),
            travel_minutes: route.travel_minutes,
            path_length: route.cell_path.len(),
        });
        Ok(route)
    }

    pub(crate) fn start_overworld_travel(
        &mut self,
        actor_id: ActorId,
        target_location_id: &str,
    ) -> Result<OverworldStateSnapshot, String> {
        if !self.actors.contains(actor_id) {
            return Err("unknown_actor".to_string());
        }
        if self.overworld_travel.is_some() {
            return Err("overworld_travel_already_active".to_string());
        }

        let route = self.request_overworld_route(actor_id, target_location_id)?;
        let definition = self.current_overworld_definition()?.clone();
        let food_item_id = definition
            .travel_rules
            .food_item_id
            .trim()
            .parse::<u32>()
            .ok();
        let current_stamina = self.actor_resource_value(actor_id, "stamina");
        if current_stamina + f32::EPSILON < route.stamina_cost.max(0) as f32 {
            return Err("insufficient_stamina".to_string());
        }
        if let Some(food_item_id) = food_item_id {
            let available_food = self.economy.inventory_count(actor_id, food_item_id).unwrap_or(0);
            if available_food < route.food_cost.max(0) {
                return Err("insufficient_food".to_string());
            }
        }

        if let Some(food_item_id) = food_item_id {
            self.economy
                .remove_item(actor_id, food_item_id, route.food_cost.max(0))
                .map_err(|error| error.to_string())?;
        }
        if route.stamina_cost > 0 {
            self.set_actor_resource(
                actor_id,
                "stamina",
                (current_stamina - route.stamina_cost as f32).max(0.0),
            );
        }

        self.overworld_travel = Some(OverworldTravelState {
            actor_id,
            remaining_minutes: route.travel_minutes,
            progressed_minutes: 0,
            route: route.clone(),
        });
        self.interaction_context.world_mode = WorldMode::Traveling;
        self.overworld_pawn_cell = route.cell_path.first().copied();
        self.sync_interaction_context_from_runtime();
        self.events.push(crate::simulation::SimulationEvent::OverworldTravelStarted {
            actor_id,
            target_location_id: target_location_id.to_string(),
            travel_minutes: route.travel_minutes,
        });

        if route.travel_minutes == 0 {
            return self.advance_overworld_travel(actor_id, 0);
        }

        Ok(self.current_overworld_snapshot())
    }

    pub(crate) fn advance_overworld_travel(
        &mut self,
        actor_id: ActorId,
        minutes: u32,
    ) -> Result<OverworldStateSnapshot, String> {
        let Some(travel) = self.overworld_travel.as_mut() else {
            return Err("overworld_travel_missing".to_string());
        };
        if travel.actor_id != actor_id {
            return Err("travel_actor_mismatch".to_string());
        }

        let progressed_minutes = minutes.min(travel.remaining_minutes);
        travel.progressed_minutes = travel.progressed_minutes.saturating_add(progressed_minutes);
        travel.remaining_minutes = travel.remaining_minutes.saturating_sub(progressed_minutes);

        let total_minutes = travel.route.travel_minutes.max(1);
        let cell_path_len = travel.route.cell_path.len().max(1);
        let progress_ratio = travel.progressed_minutes as f32 / total_minutes as f32;
        let cell_index = ((cell_path_len - 1) as f32 * progress_ratio)
            .floor()
            .clamp(0.0, (cell_path_len - 1) as f32) as usize;
        self.overworld_pawn_cell = travel.route.cell_path.get(cell_index).copied();

        self.events
            .push(crate::simulation::SimulationEvent::OverworldTravelProgressed {
                actor_id,
                target_location_id: travel.route.to_location_id.clone(),
                progressed_minutes,
                remaining_minutes: travel.remaining_minutes,
            });

        if travel.remaining_minutes == 0 {
            let completed = self
                .overworld_travel
                .take()
                .ok_or_else(|| "overworld_travel_missing".to_string())?;
            let overworld_cell = {
                let definition = self.current_overworld_definition()?;
                location_by_id(definition, &completed.route.to_location_id)
                    .map(|location| location.overworld_cell)
                    .ok_or_else(|| format!("unknown_location:{}", completed.route.to_location_id))?
            };
            self.active_location_id = Some(completed.route.to_location_id.clone());
            self.return_outdoor_location_id = Some(completed.route.to_location_id.clone());
            self.current_entry_point_id = None;
            self.overworld_pawn_cell = Some(overworld_cell);
            self.grid_world.clear_map();
            self.reset_runtime_actor_occupancy();
            self.interaction_context.current_map_id = None;
            self.interaction_context.entry_point_id = None;
            self.interaction_context.current_subscene_location_id = None;
            self.interaction_context.world_mode = WorldMode::Outdoor;
            self.sync_interaction_context_from_runtime();
            self.events.push(crate::simulation::SimulationEvent::OverworldTravelCompleted {
                actor_id,
                target_location_id: completed.route.to_location_id,
            });
        } else {
            self.sync_interaction_context_from_runtime();
        }

        Ok(self.current_overworld_snapshot())
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
        if matches!(world_mode, WorldMode::Overworld | WorldMode::Traveling) {
            return Err(format!("invalid_world_mode:{world_mode:?}"));
        }

        let target_map_id = target_map_id.trim();
        if target_map_id.is_empty() {
            return Err("unknown_map".to_string());
        }

        let resolved_entry_point_id = entry_point_id
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or("default_entry");
        let map_id = MapId(target_map_id.to_string());
        let entry_point =
            self.load_location_map_and_place_actor(actor_id, &map_id, resolved_entry_point_id)?;

        if matches!(world_mode, WorldMode::Interior | WorldMode::Dungeon)
            && self.return_outdoor_location_id.is_none()
        {
            self.return_outdoor_location_id = self.active_location_id.clone();
        }
        self.active_location_id = None;
        self.interaction_context.world_mode = world_mode;
        self.sync_interaction_context_from_runtime();

        self.events.push(crate::simulation::SimulationEvent::SceneTransitionRequested {
            actor_id,
            option_id: InteractionOptionId("travel_to_map".into()),
            target_id: target_map_id.to_string(),
            world_mode,
            location_id: None,
            entry_point_id: Some(entry_point.id.clone()),
            return_location_id: self.return_outdoor_location_id.clone(),
        });

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
        let definition = self.current_overworld_definition()?.clone();
        let location = location_by_id(&definition, location_id)
            .ok_or_else(|| format!("unknown_location:{location_id}"))?
            .clone();
        let resolved_entry_point_id = entry_point_id
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(location.entry_point_id.as_str())
            .to_string();

        let entry_point = self.load_location_map_and_place_actor(
            actor_id,
            &location.map_id,
            &resolved_entry_point_id,
        )?;
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
        self.interaction_context.world_mode = world_mode_for_location_kind(location.kind);
        self.sync_interaction_context_from_runtime();

        let transition = LocationTransitionContext {
            location_id: location.id.as_str().to_string(),
            map_id: location.map_id.as_str().to_string(),
            entry_point_id: entry_point.id.clone(),
            return_outdoor_location_id: self.return_outdoor_location_id.clone(),
            return_entry_point_id: location.return_entry_point_id.clone(),
            world_mode: self.interaction_context.world_mode,
        };

        self.events.push(crate::simulation::SimulationEvent::SceneTransitionRequested {
            actor_id,
            option_id: InteractionOptionId("enter_location".into()),
            target_id: location.map_id.as_str().to_string(),
            world_mode: transition.world_mode,
            location_id: Some(location.id.as_str().to_string()),
            entry_point_id: Some(entry_point.id.clone()),
            return_location_id: self.return_outdoor_location_id.clone(),
        });
        self.events.push(crate::simulation::SimulationEvent::LocationEntered {
            actor_id,
            location_id: location.id.as_str().to_string(),
            map_id: location.map_id.as_str().to_string(),
            entry_point_id: entry_point.id,
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

        if let Some(outdoor_location_id) = outdoor_location_id.as_deref() {
            if let Some(location) = location_by_id(&definition, outdoor_location_id) {
                self.active_location_id = Some(outdoor_location_id.to_string());
                self.overworld_pawn_cell = Some(location.overworld_cell);
            }
        }

        self.grid_world.clear_map();
        self.reset_runtime_actor_occupancy();
        self.current_entry_point_id = None;
        self.interaction_context.current_map_id = None;
        self.interaction_context.entry_point_id = None;
        self.interaction_context.current_subscene_location_id = None;
        self.interaction_context.world_mode = WorldMode::Overworld;
        self.sync_interaction_context_from_runtime();
        self.events.push(crate::simulation::SimulationEvent::ReturnedToOverworld {
            actor_id,
            active_outdoor_location_id: self
                .current_overworld_definition()
                .ok()
                .and_then(|definition| self.resolve_active_outdoor_location_id(definition)),
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
            self.events.push(crate::simulation::SimulationEvent::LocationUnlocked {
                location_id: location_id.to_string(),
            });
        }
        Ok(self.current_overworld_snapshot())
    }
}
