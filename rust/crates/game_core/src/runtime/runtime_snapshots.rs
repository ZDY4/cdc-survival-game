use super::*;

impl SimulationRuntime {
    pub fn current_interaction_context(&self) -> InteractionContextSnapshot {
        self.snapshot().interaction_context
    }

    pub fn snapshot(&self) -> SimulationSnapshot {
        self.simulation
            .snapshot(self.path_preview.clone(), self.vision.snapshot())
    }

    pub fn save_snapshot(&self) -> RuntimeSnapshot {
        RuntimeSnapshot {
            schema_version: RUNTIME_SNAPSHOT_SCHEMA_VERSION,
            simulation: self.simulation.save_snapshot(),
            vision: self.vision.snapshot(),
            pending_movement: self.pending_movement,
            pending_interaction: self.pending_interaction.clone(),
            pending_movement_stop_requested: self.pending_movement_stop_requested,
            path_preview: self.path_preview.clone(),
            tick_count: self.tick_count,
        }
    }

    pub fn load_snapshot(&mut self, snapshot: RuntimeSnapshot) -> Result<(), String> {
        if snapshot.schema_version != RUNTIME_SNAPSHOT_SCHEMA_VERSION {
            return Err(format!(
                "unsupported_runtime_snapshot_schema_version:{}",
                snapshot.schema_version
            ));
        }
        if snapshot.simulation.interaction_context.world_mode == WorldMode::Traveling {
            return Err("unsupported_runtime_snapshot_world_mode:Traveling".to_string());
        }
        self.simulation.load_snapshot(snapshot.simulation);
        self.vision.load_snapshot(snapshot.vision);
        self.pending_movement = snapshot.pending_movement;
        self.pending_interaction = snapshot.pending_interaction;
        self.pending_movement_stop_requested = snapshot.pending_movement_stop_requested;
        self.recent_overworld_arrival = None;
        self.path_preview = snapshot.path_preview;
        self.tick_count = snapshot.tick_count;
        Ok(())
    }

    pub fn vision_snapshot(&self) -> VisionRuntimeSnapshot {
        self.vision.snapshot()
    }

    pub fn actor_vision_snapshot(&self, actor_id: ActorId) -> Option<ActorVisionSnapshot> {
        self.vision.actor_snapshot(actor_id)
    }

    pub fn set_actor_vision_radius(&mut self, actor_id: ActorId, radius: i32) {
        if self.simulation.get_actor_side(actor_id).is_none() {
            return;
        }
        self.vision.set_actor_radius(actor_id, radius);
    }

    pub fn clear_actor_vision(&mut self, actor_id: ActorId) {
        self.vision.clear_actor(actor_id);
    }

    pub fn refresh_actor_vision(&mut self, actor_id: ActorId) -> Option<ActorVisionUpdate> {
        if self.simulation.get_actor_side(actor_id).is_none() {
            self.vision.clear_actor(actor_id);
            return None;
        }
        let active_map_id = self.simulation.grid_world().map_id().cloned();
        let center = self.simulation.actor_grid_position(actor_id);
        self.vision.recompute_actor(
            actor_id,
            active_map_id.as_ref(),
            center,
            self.simulation.grid_world(),
        )
    }

    pub fn pending_movement(&self) -> Option<&PendingMovementIntent> {
        self.pending_movement.as_ref()
    }

    pub fn recent_overworld_arrival(&self) -> Option<&RecentOverworldArrival> {
        self.recent_overworld_arrival.as_ref()
    }

    pub fn has_pending_progression(&self) -> bool {
        self.simulation.has_pending_progression()
    }

    pub fn peek_pending_progression(&self) -> Option<&PendingProgressionStep> {
        self.simulation.peek_pending_progression()
    }

    pub fn pending_interaction(&self) -> Option<&PendingInteractionIntent> {
        self.pending_interaction.as_ref()
    }

    pub fn clear_gameplay_entry_transients(&mut self) {
        self.pending_movement = None;
        self.pending_interaction = None;
        self.pending_movement_stop_requested = false;
        self.recent_overworld_arrival = None;
        self.path_preview.clear();
    }
}
