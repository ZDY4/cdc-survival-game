//! 交互流程编排层：负责目标解析、选项整理、主交互判定与执行分发。

use game_data::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, GridCoord,
    InteractionExecutionRequest, InteractionExecutionResult, InteractionOptionDefinition,
    InteractionOptionId, InteractionPrompt, InteractionTargetId, MapObjectDefinition,
    MapObjectKind, ResolvedInteractionOption,
};
use tracing::{error, info, warn};

use super::{interaction_behaviors, Simulation, SimulationEvent};

impl Simulation {
    pub fn perform_interact(&mut self, actor_id: ActorId) -> ActionResult {
        self.perform_interact_with_cost(actor_id, None)
    }

    pub fn perform_interact_with_cost(
        &mut self,
        actor_id: ActorId,
        cost_override: Option<f32>,
    ) -> ActionResult {
        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Interact,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: None,
            cost_override,
            success: true,
        });
        if !start_result.success {
            return start_result;
        }

        self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Interact,
            phase: ActionPhase::Complete,
            steps: None,
            target_actor: None,
            cost_override,
            success: true,
        })
    }

    pub fn query_interaction_options(
        &self,
        actor_id: ActorId,
        target_id: &InteractionTargetId,
    ) -> Option<InteractionPrompt> {
        if !self.actors.contains(actor_id) {
            return None;
        }

        let target = self.resolve_target_interaction_data(actor_id, target_id)?;
        let mut option_views: Vec<(InteractionOptionDefinition, ResolvedInteractionOption)> =
            target
                .options
                .into_iter()
                .filter(|option| option.enabled && option.visible)
                .map(|mut option| {
                    option.ensure_defaults();
                    let resolved = interaction_behaviors::resolve_interaction_option_view(
                        self,
                        actor_id,
                        target_id,
                        option.clone(),
                    );
                    (option, resolved)
                })
                .collect();
        option_views.sort_by(|(_, left), (_, right)| {
            right
                .priority
                .cmp(&left.priority)
                .then_with(|| left.display_name.cmp(&right.display_name))
        });
        let primary_option_id = option_views
            .iter()
            .find(|(definition, option)| {
                interaction_behaviors::allows_primary_option(
                    self, actor_id, target_id, option, definition,
                )
            })
            .map(|(_, option)| option.id.clone());
        let options = option_views.into_iter().map(|(_, option)| option).collect();

        Some(InteractionPrompt {
            actor_id,
            target_id: target_id.clone(),
            target_name: target.target_name,
            anchor_grid: target.anchor_grid,
            options,
            primary_option_id,
        })
    }

    pub fn execute_interaction(
        &mut self,
        request: InteractionExecutionRequest,
    ) -> InteractionExecutionResult {
        info!(
            "core.interaction.execute actor={:?} target={:?} option_id={}",
            request.actor_id,
            request.target_id,
            request.option_id.as_str()
        );
        let Some(prompt) = self.query_interaction_options(request.actor_id, &request.target_id)
        else {
            warn!(
                "core.interaction.target_unavailable actor={:?} target={:?} option_id={}",
                request.actor_id,
                request.target_id,
                request.option_id.as_str()
            );
            return InteractionExecutionResult {
                success: false,
                reason: Some("interaction_target_unavailable".to_string()),
                ..InteractionExecutionResult::default()
            };
        };

        let Some(option) = prompt
            .options
            .iter()
            .find(|option| option.id == request.option_id)
            .cloned()
        else {
            warn!(
                "core.interaction.option_unavailable actor={:?} target={:?} option_id={}",
                request.actor_id,
                request.target_id,
                request.option_id.as_str()
            );
            return InteractionExecutionResult {
                success: false,
                reason: Some("interaction_option_unavailable".to_string()),
                prompt: Some(prompt),
                ..InteractionExecutionResult::default()
            };
        };
        let Some(option_definition) =
            self.resolve_option_definition(request.actor_id, &request.target_id, &option.id)
        else {
            warn!(
                "core.interaction.option_definition_missing actor={:?} target={:?} option_id={}",
                request.actor_id,
                request.target_id,
                option.id.as_str()
            );
            return InteractionExecutionResult {
                success: false,
                reason: Some("interaction_option_unavailable".to_string()),
                prompt: Some(prompt),
                ..InteractionExecutionResult::default()
            };
        };

        if option.requires_proximity {
            match self.plan_interaction_approach(
                request.actor_id,
                &request.target_id,
                option.interaction_distance,
            ) {
                Ok(Some((goal, path_length))) => {
                    info!(
                        "core.interaction.approach_planned actor={:?} target={:?} option_id={} goal=({}, {}, {}) path_length={}",
                        request.actor_id,
                        request.target_id,
                        option.id.as_str(),
                        goal.x,
                        goal.y,
                        goal.z,
                        path_length
                    );
                    self.events
                        .push(SimulationEvent::InteractionApproachPlanned {
                            actor_id: request.actor_id,
                            target_id: request.target_id.clone(),
                            option_id: option.id.clone(),
                            goal,
                            path_length,
                        });
                    return InteractionExecutionResult {
                        success: true,
                        prompt: Some(prompt),
                        approach_required: true,
                        approach_goal: Some(goal),
                        ..InteractionExecutionResult::default()
                    };
                }
                Ok(None) => {}
                Err(reason) => {
                    warn!(
                        "core.interaction.approach_unavailable actor={:?} target={:?} option_id={} reason={}",
                        request.actor_id,
                        request.target_id,
                        option.id.as_str(),
                        reason
                    );
                    self.events.push(SimulationEvent::InteractionFailed {
                        actor_id: request.actor_id,
                        target_id: request.target_id.clone(),
                        option_id: option.id.clone(),
                        reason: reason.clone(),
                    });
                    return InteractionExecutionResult {
                        success: false,
                        reason: Some(reason),
                        prompt: Some(prompt),
                        ..InteractionExecutionResult::default()
                    };
                }
            }
        }

        self.events.push(SimulationEvent::InteractionStarted {
            actor_id: request.actor_id,
            target_id: request.target_id.clone(),
            option_id: option.id.clone(),
        });

        interaction_behaviors::execute_behavior(
            self,
            interaction_behaviors::InteractionExecutionContext {
                actor_id: request.actor_id,
                target_id: request.target_id,
                prompt,
                option,
                option_definition,
            },
        )
    }

    fn resolve_target_interaction_data(
        &self,
        actor_id: ActorId,
        target_id: &InteractionTargetId,
    ) -> Option<TargetInteractionData> {
        match target_id {
            InteractionTargetId::Actor(target_actor) => {
                let actor = self.actors.get(*target_actor)?;
                let options = if *target_actor == actor_id {
                    interaction_behaviors::build_self_actor_options()
                } else {
                    let mut options = self
                        .actor_interactions
                        .get(target_actor)
                        .map(|profile| profile.options.clone())
                        .unwrap_or_default();
                    if options.is_empty() {
                        options = interaction_behaviors::build_default_actor_options(
                            self,
                            *target_actor,
                            actor.side,
                            actor.definition_id.as_ref(),
                        );
                    }
                    options
                };
                Some(TargetInteractionData {
                    target_name: actor.display_name.clone(),
                    anchor_grid: actor.grid_position,
                    interaction_grids: vec![actor.grid_position],
                    options,
                })
            }
            InteractionTargetId::MapObject(object_id) => {
                let object = self.grid_world.map_object(object_id)?;
                let interaction_grids = self.grid_world.map_object_footprint_cells(object_id);
                Some(TargetInteractionData {
                    target_name: self.map_object_display_name(object),
                    anchor_grid: object.anchor,
                    interaction_grids: if interaction_grids.is_empty() {
                        vec![object.anchor]
                    } else {
                        interaction_grids
                    },
                    options: interaction_behaviors::resolve_map_object_options(object),
                })
            }
        }
    }

    fn map_object_display_name(&self, object: &MapObjectDefinition) -> String {
        match object.kind {
            MapObjectKind::Pickup => object
                .props
                .pickup
                .as_ref()
                .map(|pickup| {
                    if pickup.item_id.trim().is_empty() {
                        object.object_id.clone()
                    } else {
                        format!("Pickup {}", pickup.item_id)
                    }
                })
                .unwrap_or_else(|| object.object_id.clone()),
            MapObjectKind::Interactive => object
                .props
                .interactive
                .as_ref()
                .map(|_| interaction_behaviors::interactive_object_display_name(object))
                .unwrap_or_else(|| object.object_id.clone()),
            MapObjectKind::Trigger => object
                .props
                .trigger
                .as_ref()
                .map(|trigger| {
                    if trigger.display_name.trim().is_empty() {
                        object.object_id.clone()
                    } else {
                        trigger.display_name.clone()
                    }
                })
                .unwrap_or_else(|| object.object_id.clone()),
            _ => object.object_id.clone(),
        }
    }

    fn resolve_option_definition(
        &self,
        actor_id: ActorId,
        target_id: &InteractionTargetId,
        option_id: &InteractionOptionId,
    ) -> Option<InteractionOptionDefinition> {
        let target = self.resolve_target_interaction_data(actor_id, target_id)?;
        target
            .options
            .into_iter()
            .map(|mut option| {
                option.ensure_defaults();
                option
            })
            .find(|option| &option.id == option_id)
    }

    pub(crate) fn plan_interaction_approach(
        &self,
        actor_id: ActorId,
        target_id: &InteractionTargetId,
        interaction_distance: f32,
    ) -> Result<Option<(GridCoord, usize)>, String> {
        let Some(actor_grid) = self.actor_grid_position(actor_id) else {
            return Err("unknown_actor".to_string());
        };
        let Some(target) = self.resolve_target_interaction_data(actor_id, target_id) else {
            return Err("interaction_target_unavailable".to_string());
        };

        if target.interaction_grids.iter().copied().any(|target_grid| {
            self.is_interaction_in_range(actor_grid, target_grid, interaction_distance)
        }) {
            return Ok(None);
        }

        let max_radius =
            ((interaction_distance / self.grid_world.grid_size()).ceil() as i32).max(1);
        let mut best_goal = None;
        let mut best_path_len = usize::MAX;

        let start_radius = if interaction_distance <= 0.05 { 0 } else { 1 };
        for radius in start_radius..=max_radius {
            for target_grid in &target.interaction_grids {
                for candidate in collect_interaction_ring_cells(*target_grid, radius) {
                    if candidate == actor_grid {
                        continue;
                    }
                    if !self
                        .grid_world
                        .is_walkable_for_actor(candidate, Some(actor_id))
                    {
                        continue;
                    }
                    if !target
                        .interaction_grids
                        .iter()
                        .copied()
                        .any(|interaction_grid| {
                            self.is_interaction_in_range(
                                candidate,
                                interaction_grid,
                                interaction_distance,
                            )
                        })
                    {
                        continue;
                    }
                    let Ok(path) = self.find_path_grid(Some(actor_id), actor_grid, candidate)
                    else {
                        continue;
                    };
                    if path.len() <= 1 || path.len() >= best_path_len {
                        continue;
                    }
                    best_goal = Some(candidate);
                    best_path_len = path.len();
                }
            }
            if best_goal.is_some() {
                break;
            }
        }

        best_goal
            .map(|goal| (goal, best_path_len))
            .ok_or_else(|| "no_interaction_path".to_string())
            .map(Some)
    }

    pub(super) fn is_interaction_in_range(
        &self,
        actor_grid: GridCoord,
        target_grid: GridCoord,
        interaction_distance: f32,
    ) -> bool {
        let actor_world = self.grid_world.grid_to_world(actor_grid);
        let target_world = self.grid_world.grid_to_world(target_grid);
        let dx = actor_world.x - target_world.x;
        let dz = actor_world.z - target_world.z;
        (dx * dx + dz * dz).sqrt() <= interaction_distance + 0.05
    }

    pub(super) fn failed_interaction_execution(
        &mut self,
        actor_id: ActorId,
        prompt: InteractionPrompt,
        option_id: InteractionOptionId,
        reason: &str,
        log_as_error: bool,
    ) -> InteractionExecutionResult {
        if log_as_error {
            error!(
                "core.interaction.execution_failed actor={actor_id:?} target={:?} option_id={} reason={reason}",
                prompt.target_id,
                option_id.as_str()
            );
        } else {
            warn!(
                "core.interaction.execution_failed actor={actor_id:?} target={:?} option_id={} reason={reason}",
                prompt.target_id,
                option_id.as_str()
            );
        }
        self.events.push(SimulationEvent::InteractionFailed {
            actor_id,
            target_id: prompt.target_id.clone(),
            option_id,
            reason: reason.to_string(),
        });
        InteractionExecutionResult {
            success: false,
            reason: Some(reason.to_string()),
            prompt: Some(prompt),
            ..InteractionExecutionResult::default()
        }
    }

    pub(super) fn failed_interaction_action(
        &mut self,
        actor_id: ActorId,
        target_id: InteractionTargetId,
        prompt: InteractionPrompt,
        option_id: InteractionOptionId,
        action: ActionResult,
    ) -> InteractionExecutionResult {
        let reason = action
            .reason
            .clone()
            .unwrap_or_else(|| "interaction_failed".to_string());
        warn!(
            "core.interaction.action_failed actor={actor_id:?} target={target_id:?} option_id={} reason={reason}",
            option_id.as_str()
        );
        self.events.push(SimulationEvent::InteractionFailed {
            actor_id,
            target_id,
            option_id,
            reason: reason.clone(),
        });
        InteractionExecutionResult {
            success: false,
            reason: Some(reason),
            prompt: Some(prompt),
            action_result: Some(action),
            ..InteractionExecutionResult::default()
        }
    }
}

#[derive(Debug, Clone)]
struct TargetInteractionData {
    target_name: String,
    anchor_grid: GridCoord,
    interaction_grids: Vec<GridCoord>,
    options: Vec<InteractionOptionDefinition>,
}

pub(super) fn collect_interaction_ring_cells(center: GridCoord, radius: i32) -> Vec<GridCoord> {
    let mut cells = Vec::new();
    for x in (center.x - radius)..=(center.x + radius) {
        for z in (center.z - radius)..=(center.z + radius) {
            if (x - center.x).abs() + (z - center.z).abs() != radius {
                continue;
            }
            cells.push(GridCoord::new(x, center.y, z));
        }
    }
    cells
}
