use std::collections::BTreeMap;

use game_data::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, ActorSide, GridCoord,
    MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps, MapPickupProps,
    MapRotation, WorldMode,
};

use crate::grid::GridPathfindingError;
use crate::movement::PendingProgressionStep;
use crate::runtime::DropItemOutcome;
use crate::turn::ActiveActionState;

use super::{interaction_flow, Simulation, SimulationEvent, DROP_ITEM_SEARCH_RADIUS};

impl Simulation {
    pub fn actor_turn_open(&self, actor_id: ActorId) -> bool {
        self.actors
            .get(actor_id)
            .map(|actor| actor.turn_open)
            .unwrap_or(false)
    }

    pub fn request_action(&mut self, request: ActionRequest) -> ActionResult {
        let actor_id = request.actor_id;
        let result = match request.phase {
            ActionPhase::Start => {
                self.request_action_start(actor_id, request.action_type, &request)
            }
            ActionPhase::Step => self.request_action_step(actor_id, request.action_type, &request),
            ActionPhase::Complete => {
                self.request_action_complete(actor_id, request.action_type, &request)
            }
        };

        if result.success {
            self.events.push(SimulationEvent::ActionResolved {
                actor_id,
                action_type: request.action_type,
                result: result.clone(),
            });
        } else {
            self.events.push(SimulationEvent::ActionRejected {
                actor_id,
                action_type: request.action_type,
                reason: result.reason.clone().unwrap_or_default(),
            });
        }

        result
    }

    pub fn move_actor_to(&mut self, actor_id: ActorId, goal: GridCoord) -> ActionResult {
        let Some(start) = self.actor_grid_position(actor_id) else {
            return ActionResult::rejected("unknown_actor", 0.0, 0.0, self.turn.combat_active);
        };

        let path = if self.interaction_context.world_mode == WorldMode::Overworld {
            let Ok(definition) = self.current_overworld_definition() else {
                return self.reject_action("no_path", actor_id);
            };
            let Some(resolved_goal) =
                crate::overworld::resolve_overworld_goal(definition, start, goal)
            else {
                return self.reject_action("no_path", actor_id);
            };
            let Some(path) = crate::overworld::compute_cell_path(definition, start, resolved_goal)
            else {
                return self.reject_action("no_path", actor_id);
            };
            path
        } else {
            match self.find_path_grid(Some(actor_id), start, goal) {
                Ok(path) => path,
                Err(error) => {
                    return self.reject_action(pathfinding_error_reason(&error), actor_id);
                }
            }
        };

        self.events.push(SimulationEvent::PathComputed {
            actor_id: Some(actor_id),
            path_length: path.len(),
        });

        if path.len() <= 1 {
            let ap = self.get_actor_ap(actor_id);
            return ActionResult::accepted(ap, ap, 0.0, self.turn.combat_active);
        }

        let steps = (path.len() - 1) as u32;
        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Start,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        });
        if !start_result.success {
            return start_result;
        }

        let step_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Step,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        });
        if !step_result.success {
            return step_result;
        }

        self.apply_actor_movement_path(actor_id, &path);
        self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Complete,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        })
    }

    pub fn end_turn(&mut self, actor_id: ActorId) -> ActionResult {
        if !self.actors.contains(actor_id) {
            return ActionResult::rejected("unknown_actor", 0.0, 0.0, self.turn.combat_active);
        }
        if !self.validate_turn_access(actor_id) {
            return self.reject_action("not_actor_turn", actor_id);
        }

        let ap_before = self.get_actor_ap(actor_id);
        self.queue_turn_end_for_actor(actor_id);

        ActionResult::accepted(ap_before, self.get_actor_ap(actor_id), 0.0, false)
    }

    pub(crate) fn abort_action(&mut self, actor_id: ActorId, action_type: ActionType) {
        if self
            .active_actions
            .by_actor
            .get(&actor_id)
            .is_some_and(|state| state.action_type == action_type)
        {
            self.release_action_slot_if_needed(actor_id);
        }
    }

    pub(super) fn maybe_start_initial_player_turn(&mut self, actor_id: ActorId) {
        if self.turn.combat_active {
            return;
        }

        let Some(actor) = self.actors.get(actor_id) else {
            return;
        };
        if actor.side != ActorSide::Player || actor.turn_open || self.has_open_player_turn() {
            return;
        }

        self.start_actor_turn(actor_id);
    }

    fn has_open_player_turn(&self) -> bool {
        self.actors
            .values()
            .any(|actor| actor.side == ActorSide::Player && actor.turn_open)
    }

    pub(super) fn start_next_noncombat_player_turn(&mut self) {
        if self.turn.combat_active || self.has_open_player_turn() {
            return;
        }

        for group_id in self.sorted_group_ids() {
            for actor_id in self.group_actor_ids(&group_id) {
                if self.get_actor_side(actor_id) == Some(ActorSide::Player) {
                    self.start_actor_turn(actor_id);
                    return;
                }
            }
        }
    }

    pub(super) fn run_world_cycle(&mut self) {
        if self.turn.combat_active {
            return;
        }

        for group_id in self.sorted_group_ids() {
            if group_id == "player" {
                continue;
            }

            let actor_ids = self.group_actor_ids(&group_id);
            for actor_id in actor_ids {
                let hostile_saw_player_before =
                    self.first_player_seen_by_hostile(actor_id).is_some();
                self.run_actor_turn(actor_id);
                if self.turn.combat_active {
                    return;
                }
                if !hostile_saw_player_before {
                    if let Some(player_id) = self.first_player_seen_by_hostile(actor_id) {
                        self.enter_combat_without_starting_turn(actor_id, player_id);
                        self.queue_pending_progression_once(
                            PendingProgressionStep::EndCurrentCombatTurn,
                        );
                        return;
                    }
                }
            }
        }

        self.reset_noncombat_turns();
        self.events.push(SimulationEvent::WorldCycleCompleted);
    }

    fn run_actor_turn(&mut self, actor_id: ActorId) {
        if !self.actors.contains(actor_id) {
            return;
        }

        self.start_actor_turn(actor_id);
        while !self.turn.combat_active
            && self.get_actor_ap(actor_id) >= self.config.affordable_threshold
        {
            if !self.execute_actor_turn_step(actor_id) {
                break;
            }
        }
        if self.turn.combat_active {
            return;
        }
        self.end_actor_turn(actor_id);
    }

    pub(super) fn execute_actor_turn_step(&mut self, actor_id: ActorId) -> bool {
        let Some(mut controller) = self.ai_controllers.remove(&actor_id) else {
            return false;
        };

        let result = controller.execute_turn_step(actor_id, self);
        self.ai_controllers.insert(actor_id, controller);
        result.performed
    }

    pub(super) fn start_actor_turn(&mut self, actor_id: ActorId) {
        let Some(actor) = self.actors.get_mut(actor_id) else {
            return;
        };

        let old_ap = actor.ap;
        actor.ap = (old_ap + self.config.turn_ap_gain).clamp(0.0, self.config.turn_ap_max);
        actor.turn_open = true;
        self.events.push(SimulationEvent::ActorTurnStarted {
            actor_id,
            group_id: actor.group_id.clone(),
            ap: actor.ap,
        });
    }

    pub(super) fn end_actor_turn(&mut self, actor_id: ActorId) {
        let Some(actor) = self.actors.get_mut(actor_id) else {
            return;
        };

        actor.turn_open = false;
        self.events.push(SimulationEvent::ActorTurnEnded {
            actor_id,
            group_id: actor.group_id.clone(),
            remaining_ap: actor.ap,
        });
    }

    pub(super) fn sorted_group_ids(&self) -> Vec<String> {
        let mut group_ids: Vec<String> = self.group_orders.orders.keys().cloned().collect();
        group_ids.sort_by(|a, b| {
            let order_a = self.group_orders.orders.get(a).copied().unwrap_or(9999);
            let order_b = self.group_orders.orders.get(b).copied().unwrap_or(9999);
            order_a.cmp(&order_b).then_with(|| a.cmp(b))
        });
        group_ids
    }

    pub(super) fn group_actor_ids(&self, group_id: &str) -> Vec<ActorId> {
        let mut actor_ids: Vec<ActorId> = self
            .actors
            .values()
            .filter(|actor| actor.group_id == group_id)
            .map(|actor| actor.actor_id)
            .collect();
        actor_ids.sort_by_key(|actor_id| {
            self.actors
                .get(*actor_id)
                .map(|actor| actor.registration_index)
                .unwrap_or(usize::MAX)
        });
        actor_ids
    }

    fn reset_noncombat_turns(&mut self) {
        let actor_ids: Vec<ActorId> = self.actors.ids().collect();
        for actor_id in actor_ids {
            if let Some(actor) = self.actors.get_mut(actor_id) {
                actor.turn_open = false;
            }
        }
    }

    pub(super) fn queue_turn_end_for_actor(&mut self, actor_id: ActorId) {
        if self.turn.combat_active {
            if self.turn.current_actor_id == Some(actor_id) {
                self.queue_pending_progression_once(PendingProgressionStep::EndCurrentCombatTurn);
            }
        } else if self.get_actor_side(actor_id) == Some(ActorSide::Player) {
            if self.actor_turn_open(actor_id) {
                self.end_actor_turn(actor_id);
            }
            self.queue_pending_progression_once(PendingProgressionStep::RunNonCombatWorldCycle);
            self.queue_pending_progression_once(
                PendingProgressionStep::StartNextNonCombatPlayerTurn,
            );
        } else if self.actor_turn_open(actor_id) {
            self.end_actor_turn(actor_id);
        }
    }

    pub(super) fn queue_pending_progression_once(&mut self, step: PendingProgressionStep) {
        if self
            .pending_progression
            .iter()
            .any(|queued| *queued == step)
        {
            return;
        }
        self.queue_pending_progression(step);
    }

    fn request_action_start(
        &mut self,
        actor_id: ActorId,
        action_type: ActionType,
        request: &ActionRequest,
    ) -> ActionResult {
        if !self.actors.contains(actor_id) {
            return ActionResult::rejected("unknown_actor", 0.0, 0.0, false);
        }
        if !self.validate_turn_access(actor_id) {
            return self.reject_action("not_actor_turn", actor_id);
        }

        if !self.actor_turn_open(actor_id) {
            self.start_actor_turn(actor_id);
        }
        if action_type == ActionType::Attack {
            let Some(target_actor) = request.target_actor else {
                return self.reject_action("missing_target_actor", actor_id);
            };
            if let Err(reason) = self.validate_attack_preconditions(actor_id, target_actor) {
                return self.reject_action(reason, actor_id);
            }
        }

        let old_ap = self.get_actor_ap(actor_id);
        let action_cost = self.resolve_action_cost(action_type, request);
        if old_ap < action_cost {
            return self.reject_action_with_ap("insufficient_ap", old_ap, old_ap);
        }
        if self.is_action_limit_reached(action_type) {
            return self.reject_action_with_ap("action_limit_reached", old_ap, old_ap);
        }
        if self.active_actions.by_actor.contains_key(&actor_id) {
            return self.reject_action_with_ap("action_in_progress", old_ap, old_ap);
        }

        self.claim_action_slot(actor_id, action_type, old_ap);

        let mut entered_combat = false;
        if action_type == ActionType::Attack && !self.turn.combat_active {
            if let Some(target_actor) = request.target_actor {
                self.enter_combat(actor_id, target_actor);
                entered_combat = self.turn.combat_active;
            }
        }

        ActionResult::accepted(old_ap, old_ap, 0.0, entered_combat)
    }

    fn request_action_step(
        &mut self,
        actor_id: ActorId,
        action_type: ActionType,
        request: &ActionRequest,
    ) -> ActionResult {
        let Some(active_action) = self.active_actions.by_actor.get(&actor_id).cloned() else {
            return self.reject_action("action_not_started", actor_id);
        };

        if active_action.action_type != action_type {
            return self.reject_action("action_type_mismatch", actor_id);
        }

        let old_ap = self.get_actor_ap(actor_id);
        let cost = self.resolve_action_cost(action_type, request);
        if old_ap < cost {
            return self.reject_action_with_ap("insufficient_ap", old_ap, old_ap);
        }

        let new_ap = (old_ap - cost).clamp(0.0, self.config.turn_ap_max);
        if let Some(actor) = self.actors.get_mut(actor_id) {
            actor.ap = new_ap;
        }
        if let Some(action_state) = self.active_actions.by_actor.get_mut(&actor_id) {
            action_state.consumed += cost;
        }

        ActionResult::accepted(old_ap, new_ap, cost, self.turn.combat_active)
    }

    fn request_action_complete(
        &mut self,
        actor_id: ActorId,
        action_type: ActionType,
        request: &ActionRequest,
    ) -> ActionResult {
        let Some(active_action) = self.active_actions.by_actor.get(&actor_id).cloned() else {
            return self.reject_action("action_not_started", actor_id);
        };

        if active_action.action_type != action_type {
            return self.reject_action("action_type_mismatch", actor_id);
        }

        let mut total_consumed = active_action.consumed;
        let old_ap = self.get_actor_ap(actor_id);
        if action_type != ActionType::Move && request.success {
            let remaining_cost =
                (self.resolve_action_cost(action_type, request) - total_consumed).max(0.0);
            if remaining_cost > 0.0 {
                if old_ap < remaining_cost {
                    self.release_action_slot_if_needed(actor_id);
                    return self.reject_action_with_ap("insufficient_ap", old_ap, old_ap);
                }

                let new_ap = (old_ap - remaining_cost).clamp(0.0, self.config.turn_ap_max);
                if let Some(actor) = self.actors.get_mut(actor_id) {
                    actor.ap = new_ap;
                }
                total_consumed += remaining_cost;
            }
        }

        self.release_action_slot_if_needed(actor_id);

        if request.success {
            let mut entered_combat = false;
            if action_type == ActionType::Move
                && !self.turn.combat_active
                && self.get_actor_side(actor_id) == Some(ActorSide::Player)
            {
                if let Some((hostile_id, _player_id)) = self.hostile_player_visibility_pair() {
                    self.enter_combat(actor_id, hostile_id);
                    entered_combat = self.turn.combat_active;
                }
            }

            let ap_after = self.get_actor_ap(actor_id);
            if ap_after < self.config.affordable_threshold {
                if self.turn.combat_active && self.turn.current_actor_id == Some(actor_id) {
                    self.queue_pending_progression_once(
                        PendingProgressionStep::EndCurrentCombatTurn,
                    );
                } else if !self.turn.combat_active
                    && self.get_actor_side(actor_id) == Some(ActorSide::Player)
                {
                    self.queue_pending_progression_once(
                        PendingProgressionStep::RunNonCombatWorldCycle,
                    );
                    self.queue_pending_progression_once(
                        PendingProgressionStep::StartNextNonCombatPlayerTurn,
                    );
                }
            }
            return ActionResult::accepted(
                active_action.ap_before,
                self.get_actor_ap(actor_id),
                total_consumed,
                entered_combat,
            );
        }

        ActionResult::accepted(
            active_action.ap_before,
            self.get_actor_ap(actor_id),
            total_consumed,
            false,
        )
    }

    pub(super) fn resolve_action_cost(
        &self,
        action_type: ActionType,
        request: &ActionRequest,
    ) -> f32 {
        if let Some(cost_override) = request.cost_override {
            return cost_override.max(0.0);
        }
        if action_type == ActionType::Move {
            request.steps.unwrap_or(1) as f32 * self.config.action_cost
        } else {
            self.config.action_cost
        }
    }

    pub(super) fn validate_turn_access(&self, actor_id: ActorId) -> bool {
        if !self.turn.combat_active {
            return true;
        }
        self.turn.current_actor_id == Some(actor_id)
    }

    fn claim_action_slot(&mut self, actor_id: ActorId, action_type: ActionType, ap_before: f32) {
        self.active_actions.by_actor.insert(
            actor_id,
            ActiveActionState {
                action_type,
                consumed: 0.0,
                ap_before,
            },
        );

        *self
            .active_actions
            .counts_by_type
            .entry(action_type)
            .or_insert(0) += 1;
    }

    fn release_action_slot_if_needed(&mut self, actor_id: ActorId) {
        let Some(action_state) = self.active_actions.by_actor.remove(&actor_id) else {
            return;
        };

        if let Some(count) = self
            .active_actions
            .counts_by_type
            .get_mut(&action_state.action_type)
        {
            *count = count.saturating_sub(1);
        }
    }

    fn is_action_limit_reached(&self, action_type: ActionType) -> bool {
        if action_type != ActionType::Attack {
            return false;
        }

        self.active_actions
            .counts_by_type
            .get(&action_type)
            .copied()
            .unwrap_or(0)
            >= self.config.attack_concurrency_limit
    }

    pub(super) fn reject_action(&self, reason: &str, actor_id: ActorId) -> ActionResult {
        let ap = self.get_actor_ap(actor_id);
        self.reject_action_with_ap(reason, ap, ap)
    }

    pub(super) fn reject_action_with_ap(
        &self,
        reason: &str,
        ap_before: f32,
        ap_after: f32,
    ) -> ActionResult {
        ActionResult::rejected(reason, ap_before, ap_after, self.turn.combat_active)
    }

    pub(super) fn move_actor_along_path(
        &mut self,
        actor_id: ActorId,
        path: &[GridCoord],
    ) -> ActionResult {
        if path.len() <= 1 {
            let ap = self.get_actor_ap(actor_id);
            return ActionResult::accepted(ap, ap, 0.0, self.turn.combat_active);
        }

        self.events.push(SimulationEvent::PathComputed {
            actor_id: Some(actor_id),
            path_length: path.len(),
        });

        let steps = (path.len() - 1) as u32;
        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Start,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        });
        if !start_result.success {
            return start_result;
        }

        let step_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Step,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        });
        if !step_result.success {
            return step_result;
        }

        self.apply_actor_movement_path(actor_id, path);
        self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Move,
            phase: ActionPhase::Complete,
            steps: Some(steps),
            target_actor: None,
            cost_override: None,
            success: true,
        })
    }

    pub(super) fn find_ground_drop_grid(&self, actor_grid: GridCoord) -> GridCoord {
        for radius in 1..=DROP_ITEM_SEARCH_RADIUS {
            for candidate in interaction_flow::collect_interaction_ring_cells(actor_grid, radius) {
                let occupied_by_actor = self
                    .actors
                    .values()
                    .any(|actor| actor.grid_position == candidate);
                if self.grid_world.is_in_bounds(candidate)
                    && self.grid_world.is_walkable(candidate)
                    && !occupied_by_actor
                {
                    return candidate;
                }
            }
        }

        actor_grid
    }

    pub(super) fn spawn_drop_pickup(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        count: i32,
        drop_grid: GridCoord,
    ) -> DropItemOutcome {
        let object_id = self.next_drop_pickup_object_id(actor_id, item_id);
        self.grid_world.upsert_map_object(MapObjectDefinition {
            object_id: object_id.clone(),
            kind: MapObjectKind::Pickup,
            anchor: drop_grid,
            footprint: MapObjectFootprint::default(),
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                pickup: Some(MapPickupProps {
                    item_id: item_id.to_string(),
                    min_count: count,
                    max_count: count,
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        });

        DropItemOutcome {
            object_id,
            item_id,
            count,
            grid: drop_grid,
        }
    }

    fn next_drop_pickup_object_id(&self, actor_id: ActorId, item_id: u32) -> String {
        let base = format!("drop_{}_{}_{}", actor_id.0, item_id, self.events.len());
        if self.grid_world.map_object(&base).is_none() {
            return base;
        }

        let mut suffix = 1u32;
        loop {
            let candidate = format!("{base}_{suffix}");
            if self.grid_world.map_object(&candidate).is_none() {
                return candidate;
            }
            suffix = suffix.saturating_add(1);
        }
    }
}

pub(super) fn pathfinding_error_reason(error: &GridPathfindingError) -> &'static str {
    match error {
        GridPathfindingError::TargetOutOfBounds => "target_out_of_bounds",
        GridPathfindingError::TargetInvalidLevel => "target_invalid_level",
        GridPathfindingError::TargetBlocked => "target_blocked",
        GridPathfindingError::TargetOccupied => "target_occupied",
        GridPathfindingError::NoPath => "no_path",
    }
}
