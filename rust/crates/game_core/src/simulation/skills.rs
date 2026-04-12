use std::collections::BTreeSet;

use game_data::{
    ActionPhase, ActionRequest, ActionType, ActorId, GridCoord, SkillExecutionKind,
    SkillTargetRequest, SkillTargetSideRule,
};

use crate::vision::has_grid_line_of_sight;

use super::{
    Simulation, SimulationEvent, SkillActivationResult, SkillRuntimeState,
    SkillSpatialPreviewResult, SkillTargetingQueryResult,
};

#[derive(Debug, Clone)]
struct ResolvedSkillTargetContext {
    hit_grids: Vec<GridCoord>,
    hit_actor_ids: Vec<ActorId>,
    target: SkillTargetRequest,
}

impl ResolvedSkillTargetContext {
    fn primary_actor_target(&self) -> Option<ActorId> {
        match self.target {
            SkillTargetRequest::Actor(actor_id) => Some(actor_id),
            SkillTargetRequest::Grid(_) => None,
        }
    }
}

#[derive(Debug, Clone)]
struct SkillHandlerPreview {
    hit_actor_ids: Vec<ActorId>,
}

#[derive(Debug, Clone)]
struct AppliedSkillHandler {
    hit_actor_ids: Vec<ActorId>,
}

impl Simulation {
    pub fn query_skill_targeting(
        &self,
        actor_id: ActorId,
        skill_id: &str,
    ) -> SkillTargetingQueryResult {
        let Some(skill) = self
            .skill_library
            .as_ref()
            .and_then(|skills| skills.get(skill_id))
        else {
            return SkillTargetingQueryResult {
                shape: "single".to_string(),
                radius: 0,
                valid_grids: Vec::new(),
                valid_actor_ids: Vec::new(),
                invalid_reason: Some("unknown_skill".to_string()),
            };
        };
        let Some(targeting) = skill
            .activation
            .as_ref()
            .and_then(|activation| activation.targeting.as_ref())
            .filter(|targeting| targeting.enabled)
        else {
            return SkillTargetingQueryResult {
                shape: "single".to_string(),
                radius: 0,
                valid_grids: Vec::new(),
                valid_actor_ids: Vec::new(),
                invalid_reason: Some("skill_targeting_disabled".to_string()),
            };
        };

        let Some(actor_grid) = self.actor_grid_position(actor_id) else {
            return SkillTargetingQueryResult {
                shape: targeting.shape.trim().to_string(),
                radius: targeting.radius.max(0),
                valid_grids: Vec::new(),
                valid_actor_ids: Vec::new(),
                invalid_reason: Some("unknown_actor".to_string()),
            };
        };

        let valid_grids = self
            .iter_level_grids(actor_grid.y)
            .into_iter()
            .filter(|grid| grid.y == actor_grid.y)
            .filter(|grid| {
                self.validate_skill_target_center(actor_grid, *grid, targeting)
                    .is_ok()
            })
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();

        let mut valid_actor_ids = self
            .actors
            .values()
            .filter(|actor| valid_grids.contains(&actor.grid_position))
            .filter(|actor| self.skill_target_actor_allowed(actor_id, actor.actor_id, targeting))
            .map(|actor| actor.actor_id)
            .collect::<Vec<_>>();
        valid_actor_ids.sort_by_key(|candidate| candidate.0);
        valid_actor_ids.dedup();

        let invalid_reason = valid_grids
            .is_empty()
            .then_some("no_skill_targets".to_string());

        SkillTargetingQueryResult {
            shape: targeting.shape.trim().to_string(),
            radius: targeting.radius.max(0),
            valid_grids,
            valid_actor_ids,
            invalid_reason,
        }
    }

    pub fn preview_skill_target(
        &self,
        actor_id: ActorId,
        skill_id: &str,
        target: SkillTargetRequest,
    ) -> SkillSpatialPreviewResult {
        let Some(skill) = self
            .skill_library
            .as_ref()
            .and_then(|skills| skills.get(skill_id))
        else {
            return SkillSpatialPreviewResult {
                resolved_target: None,
                preview_hit_grids: Vec::new(),
                preview_hit_actor_ids: Vec::new(),
                invalid_reason: Some("unknown_skill".to_string()),
            };
        };
        let Some(targeting) = skill
            .activation
            .as_ref()
            .and_then(|activation| activation.targeting.as_ref())
            .filter(|targeting| targeting.enabled)
        else {
            return SkillSpatialPreviewResult {
                resolved_target: None,
                preview_hit_grids: Vec::new(),
                preview_hit_actor_ids: Vec::new(),
                invalid_reason: Some("skill_targeting_disabled".to_string()),
            };
        };

        match self.resolve_skill_target_context(actor_id, Some(targeting), &target) {
            Ok(context) => SkillSpatialPreviewResult {
                resolved_target: Some(context.target),
                preview_hit_grids: context.hit_grids,
                preview_hit_actor_ids: context.hit_actor_ids,
                invalid_reason: None,
            },
            Err(reason) => SkillSpatialPreviewResult {
                resolved_target: None,
                preview_hit_grids: Vec::new(),
                preview_hit_actor_ids: Vec::new(),
                invalid_reason: Some(reason.to_string()),
            },
        }
    }

    pub fn skill_state(&self, actor_id: ActorId, skill_id: &str) -> SkillRuntimeState {
        self.actor_skill_states
            .get(&actor_id)
            .and_then(|states| states.get(skill_id))
            .cloned()
            .unwrap_or_default()
    }

    pub fn skill_cooldown_remaining(&self, actor_id: ActorId, skill_id: &str) -> f32 {
        self.skill_state(actor_id, skill_id).cooldown_remaining
    }

    pub fn is_skill_toggled_active(&self, actor_id: ActorId, skill_id: &str) -> bool {
        self.skill_state(actor_id, skill_id).toggled_active
    }

    pub fn advance_skill_timers(&mut self, delta_sec: f32) {
        if delta_sec <= 0.0 {
            return;
        }

        for states in self.actor_skill_states.values_mut() {
            for state in states.values_mut() {
                state.cooldown_remaining = (state.cooldown_remaining - delta_sec).max(0.0);
            }
        }
    }

    pub fn activate_skill(
        &mut self,
        actor_id: ActorId,
        skill_id: &str,
        target: SkillTargetRequest,
    ) -> SkillActivationResult {
        let Some(skill) = self
            .skill_library
            .as_ref()
            .and_then(|skills| skills.get(skill_id))
            .cloned()
        else {
            let action_result = self.reject_action("unknown_skill", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "unknown_skill".to_string(),
            });
            return SkillActivationResult::failure(skill_id, action_result, "unknown_skill");
        };

        let learned_level = self
            .economy
            .actor(actor_id)
            .and_then(|actor| actor.learned_skills.get(skill_id))
            .copied()
            .unwrap_or(0);
        if learned_level <= 0 {
            let action_result = self.reject_action("skill_not_learned", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "skill_not_learned".to_string(),
            });
            return SkillActivationResult::failure(skill_id, action_result, "skill_not_learned");
        }

        let Some(activation) = skill.activation.as_ref() else {
            let action_result = self.reject_action("skill_has_no_activation", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "skill_has_no_activation".to_string(),
            });
            return SkillActivationResult::failure(
                skill_id,
                action_result,
                "skill_has_no_activation",
            );
        };

        if !matches!(activation.mode.trim(), "active" | "toggle") {
            let action_result = self.reject_action("skill_not_activatable", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "skill_not_activatable".to_string(),
            });
            return SkillActivationResult::failure(
                skill_id,
                action_result,
                "skill_not_activatable",
            );
        }

        let skill_state = self.skill_state(actor_id, skill_id);
        if skill_state.cooldown_remaining > 0.0 {
            let action_result = self.reject_action("skill_on_cooldown", actor_id);
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: "skill_on_cooldown".to_string(),
            });
            return SkillActivationResult::failure(skill_id, action_result, "skill_on_cooldown");
        }

        let targeting = activation
            .targeting
            .as_ref()
            .filter(|targeting| targeting.enabled);
        let resolved_target = match self.resolve_skill_target_context(actor_id, targeting, &target)
        {
            Ok(context) => context,
            Err(reason) => {
                let action_result = self.reject_action(reason, actor_id);
                self.events.push(SimulationEvent::SkillActivationFailed {
                    actor_id,
                    skill_id: skill_id.to_string(),
                    reason: reason.to_string(),
                });
                return SkillActivationResult::failure(skill_id, action_result, reason);
            }
        };

        let dispatch_preview = match self.preview_skill_handler(
            actor_id,
            learned_level,
            &skill,
            activation,
            &resolved_target,
        ) {
            Ok(preview) => preview,
            Err(reason) => {
                let action_result = self.reject_action(reason, actor_id);
                self.events.push(SimulationEvent::SkillActivationFailed {
                    actor_id,
                    skill_id: skill_id.to_string(),
                    reason: reason.to_string(),
                });
                return SkillActivationResult::failure(skill_id, action_result, reason);
            }
        };

        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Skill,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: resolved_target.primary_actor_target(),
            cost_override: None,
            success: true,
        });
        if !start_result.success {
            let reason = start_result
                .reason
                .clone()
                .unwrap_or_else(|| "skill_start_failed".to_string());
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: reason.clone(),
            });
            return SkillActivationResult::failure(skill_id, start_result, reason);
        }

        if !self.turn.combat_active {
            if let Some(hostile_target) = self.first_hostile_target(&dispatch_preview.hit_actor_ids)
            {
                self.enter_combat(actor_id, hostile_target);
            }
        }

        let complete_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Skill,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: resolved_target.primary_actor_target(),
            cost_override: None,
            success: true,
        });
        if !complete_result.success {
            let reason = complete_result
                .reason
                .clone()
                .unwrap_or_else(|| "skill_complete_failed".to_string());
            self.events.push(SimulationEvent::SkillActivationFailed {
                actor_id,
                skill_id: skill_id.to_string(),
                reason: reason.clone(),
            });
            return SkillActivationResult::failure(skill_id, complete_result, reason);
        }

        let applied = self.apply_skill_handler(actor_id, skill_id, activation, dispatch_preview);
        let state = self
            .actor_skill_states
            .entry(actor_id)
            .or_default()
            .entry(skill_id.to_string())
            .or_default();
        let mut toggled_active = None;
        if activation.mode.trim() == "toggle" {
            state.toggled_active = !state.toggled_active;
            toggled_active = Some(state.toggled_active);
        }
        if activation.cooldown > 0.0 {
            state.cooldown_remaining = activation.cooldown.max(0.0);
        }

        self.events.push(SimulationEvent::SkillActivated {
            actor_id,
            skill_id: skill_id.to_string(),
            target,
            hit_actor_ids: applied.hit_actor_ids.clone(),
        });
        SkillActivationResult::success(
            skill_id,
            complete_result,
            applied.hit_actor_ids,
            activation.cooldown > 0.0,
            toggled_active,
        )
    }

    fn resolve_skill_target_context(
        &self,
        actor_id: ActorId,
        targeting: Option<&game_data::SkillTargetingDefinition>,
        target: &SkillTargetRequest,
    ) -> Result<ResolvedSkillTargetContext, &'static str> {
        let Some(actor_grid) = self.actor_grid_position(actor_id) else {
            return Err("unknown_actor");
        };

        let center_grid = match target {
            SkillTargetRequest::Actor(target_actor) => self
                .actor_grid_position(*target_actor)
                .ok_or("unknown_target")?,
            SkillTargetRequest::Grid(grid) => *grid,
        };
        let (shape, radius, resolved_target) = if let Some(targeting) = targeting {
            (
                targeting.shape.trim(),
                targeting.radius.max(0) as i32,
                match targeting.shape.trim() {
                    "single" => self
                        .actors
                        .values()
                        .find(|actor| actor.grid_position == center_grid)
                        .map(|actor| SkillTargetRequest::Actor(actor.actor_id))
                        .unwrap_or(SkillTargetRequest::Grid(center_grid)),
                    _ => SkillTargetRequest::Grid(center_grid),
                },
            )
        } else {
            ("single", 0, *target)
        };

        let range_cells = targeting
            .map(|targeting| targeting.range_cells.max(0))
            .unwrap_or(0);
        if let Some(targeting) = targeting {
            self.validate_skill_target_center(actor_grid, center_grid, targeting)?;
        } else {
            self.validate_target_center_spatial(actor_grid, center_grid, range_cells)?;
        }

        if let SkillTargetRequest::Actor(target_actor) = resolved_target {
            if let Some(targeting) = targeting {
                if !self.skill_target_actor_allowed(actor_id, target_actor, targeting) {
                    return Err("skill_target_not_allowed");
                }
            }
        }

        let hit_grids = self.skill_affected_grids(
            center_grid,
            shape,
            radius,
            targeting.is_none_or(|definition| definition.require_los),
        );
        let mut hit_actor_ids = self
            .actors
            .values()
            .filter(|actor| hit_grids.contains(&actor.grid_position))
            .filter(|actor| {
                targeting.is_none_or(|definition| {
                    self.skill_splash_actor_allowed(actor_id, actor.actor_id, definition)
                })
            })
            .map(|actor| actor.actor_id)
            .collect::<Vec<_>>();
        hit_actor_ids.sort_by_key(|candidate| candidate.0);
        hit_actor_ids.dedup();

        Ok(ResolvedSkillTargetContext {
            hit_grids,
            hit_actor_ids,
            target: resolved_target,
        })
    }

    fn preview_skill_handler(
        &self,
        _actor_id: ActorId,
        _learned_level: i32,
        _skill: &game_data::SkillDefinition,
        activation: &game_data::SkillActivationDefinition,
        target: &ResolvedSkillTargetContext,
    ) -> Result<SkillHandlerPreview, &'static str> {
        if activation
            .targeting
            .as_ref()
            .is_none_or(|targeting| !targeting.enabled)
        {
            return Ok(SkillHandlerPreview {
                hit_actor_ids: Vec::new(),
            });
        }

        let execution_kind = self.resolve_skill_execution_kind(activation);
        if execution_kind == SkillExecutionKind::None {
            return Err("skill_handler_missing");
        }

        match execution_kind {
            SkillExecutionKind::DamageSingle => {
                let hit_actor_ids = target
                    .primary_actor_target()
                    .or_else(|| target.hit_actor_ids.first().copied())
                    .into_iter()
                    .collect::<Vec<_>>();
                if hit_actor_ids.is_empty() {
                    Err("skill_target_requires_actor")
                } else {
                    Ok(SkillHandlerPreview { hit_actor_ids })
                }
            }
            SkillExecutionKind::DamageAoe | SkillExecutionKind::ToggleStatus => {
                Ok(SkillHandlerPreview {
                    hit_actor_ids: target.hit_actor_ids.clone(),
                })
            }
            SkillExecutionKind::None => Err("skill_handler_missing"),
        }
    }

    fn apply_skill_handler(
        &mut self,
        actor_id: ActorId,
        skill_id: &str,
        activation: &game_data::SkillActivationDefinition,
        preview: SkillHandlerPreview,
    ) -> AppliedSkillHandler {
        if activation
            .targeting
            .as_ref()
            .is_none_or(|targeting| !targeting.enabled)
        {
            return AppliedSkillHandler {
                hit_actor_ids: preview.hit_actor_ids,
            };
        }

        match self.resolve_skill_execution_kind(activation) {
            SkillExecutionKind::DamageSingle | SkillExecutionKind::DamageAoe => {
                let damage = self.resolve_skill_damage(actor_id, skill_id);
                for target_actor in &preview.hit_actor_ids {
                    self.apply_damage_to_actor(actor_id, *target_actor, damage);
                }
            }
            SkillExecutionKind::ToggleStatus | SkillExecutionKind::None => {}
        }

        AppliedSkillHandler {
            hit_actor_ids: preview.hit_actor_ids,
        }
    }

    fn resolve_skill_damage(&self, actor_id: ActorId, skill_id: &str) -> f32 {
        let Some(skill) = self
            .skill_library
            .as_ref()
            .and_then(|skills| skills.get(skill_id))
        else {
            return 1.0;
        };
        let level = self
            .economy
            .actor(actor_id)
            .and_then(|actor| actor.learned_skills.get(skill_id))
            .copied()
            .unwrap_or(1)
            .max(1) as f32;
        let configured_damage = skill
            .activation
            .as_ref()
            .and_then(|activation| activation.effect.as_ref())
            .and_then(|effect| effect.modifiers.get("damage"))
            .map(|modifier| {
                let value = modifier.base + modifier.per_level * (level - 1.0);
                if modifier.max_value > 0.0 {
                    value.min(modifier.max_value)
                } else {
                    value
                }
            })
            .unwrap_or(0.0);
        configured_damage
            .max(self.actor_combat_attribute_value(actor_id, "attack_power"))
            .max(1.0)
    }

    fn skill_affected_grids(
        &self,
        center: GridCoord,
        shape: &str,
        radius: i32,
        require_los: bool,
    ) -> Vec<GridCoord> {
        let radius = radius.max(0);
        let mut grids = Vec::new();
        for dx in -radius..=radius {
            for dz in -radius..=radius {
                let include = match shape {
                    "diamond" => dx.abs() + dz.abs() <= radius,
                    "square" => true,
                    _ => dx == 0 && dz == 0,
                };
                if !include {
                    continue;
                }
                let grid = GridCoord::new(center.x + dx, center.y, center.z + dz);
                if self.grid_world.is_in_bounds(grid)
                    && (!require_los || has_grid_line_of_sight(&self.grid_world, center, grid))
                {
                    grids.push(grid);
                }
            }
        }
        if grids.is_empty() && self.grid_world.is_in_bounds(center) {
            grids.push(center);
        }
        grids
    }

    fn first_hostile_target(&self, hit_actor_ids: &[ActorId]) -> Option<ActorId> {
        hit_actor_ids.iter().copied().find(|actor_id| {
            self.get_actor_side(*actor_id)
                .is_some_and(|side| side == game_data::ActorSide::Hostile)
        })
    }

    fn resolve_skill_execution_kind(
        &self,
        activation: &game_data::SkillActivationDefinition,
    ) -> SkillExecutionKind {
        if let Some(kind) = activation
            .targeting
            .as_ref()
            .map(|targeting| targeting.execution_kind)
            .filter(|kind| *kind != SkillExecutionKind::None)
        {
            return kind;
        }

        let legacy_handler = activation
            .targeting
            .as_ref()
            .map(|targeting| targeting.handler_script.trim())
            .filter(|handler| !handler.is_empty())
            .or_else(|| {
                activation
                    .extra
                    .get("handler_script")
                    .and_then(|value| value.as_str())
                    .map(str::trim)
                    .filter(|handler| !handler.is_empty())
            })
            .unwrap_or("");

        match legacy_handler {
            "damage_single" => SkillExecutionKind::DamageSingle,
            "damage_aoe" => SkillExecutionKind::DamageAoe,
            "toggle_status" => SkillExecutionKind::ToggleStatus,
            _ => SkillExecutionKind::None,
        }
    }

    fn validate_skill_target_center(
        &self,
        actor_grid: GridCoord,
        target_grid: GridCoord,
        targeting: &game_data::SkillTargetingDefinition,
    ) -> Result<(), &'static str> {
        if !self.grid_world.is_in_bounds(target_grid) {
            return Err("target_out_of_bounds");
        }
        if actor_grid.y != target_grid.y {
            return Err("target_invalid_level");
        }
        if crate::simulation::spatial::manhattan_grid_distance(actor_grid, target_grid)
            > targeting.range_cells.max(0)
        {
            return Err("target_out_of_range");
        }
        if targeting.require_los
            && !has_grid_line_of_sight(&self.grid_world, actor_grid, target_grid)
        {
            return Err("target_blocked_by_los");
        }

        Ok(())
    }

    fn skill_target_actor_allowed(
        &self,
        actor_id: ActorId,
        target_actor: ActorId,
        targeting: &game_data::SkillTargetingDefinition,
    ) -> bool {
        if actor_id == target_actor && !targeting.allow_self {
            return false;
        }

        self.skill_target_side_matches(actor_id, target_actor, targeting.target_side_rule)
    }

    fn skill_splash_actor_allowed(
        &self,
        actor_id: ActorId,
        target_actor: ActorId,
        targeting: &game_data::SkillTargetingDefinition,
    ) -> bool {
        if actor_id == target_actor && !targeting.allow_self {
            return false;
        }
        if !targeting.allow_friendly_fire
            && !self.are_actors_hostile(actor_id, target_actor)
            && actor_id != target_actor
        {
            return false;
        }

        self.skill_target_side_matches(actor_id, target_actor, targeting.target_side_rule)
    }

    fn skill_target_side_matches(
        &self,
        actor_id: ActorId,
        target_actor: ActorId,
        rule: SkillTargetSideRule,
    ) -> bool {
        match rule {
            SkillTargetSideRule::Any => true,
            SkillTargetSideRule::HostileOnly => self.are_actors_hostile(actor_id, target_actor),
            SkillTargetSideRule::FriendlyOnly => {
                actor_id == target_actor || !self.are_actors_hostile(actor_id, target_actor)
            }
            SkillTargetSideRule::PlayerOnly => {
                self.get_actor_side(target_actor) == Some(game_data::ActorSide::Player)
            }
        }
    }
}
