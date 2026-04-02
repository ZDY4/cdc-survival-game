use super::*;

impl Simulation {
    pub fn perform_interact(&mut self, actor_id: ActorId) -> ActionResult {
        let start_result = self.request_action(ActionRequest {
            actor_id,
            action_type: ActionType::Interact,
            phase: ActionPhase::Start,
            steps: None,
            target_actor: None,
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

        let target = self.resolve_target_interaction_data(target_id)?;
        let mut options: Vec<ResolvedInteractionOption> = target
            .options
            .into_iter()
            .filter(|option| option.enabled && option.visible)
            .map(|mut option| {
                option.ensure_defaults();
                self.resolve_interaction_option_view(actor_id, target_id, option)
            })
            .collect();
        options.sort_by(|left, right| {
            right
                .priority
                .cmp(&left.priority)
                .then_with(|| left.display_name.cmp(&right.display_name))
        });
        let primary_option_id = if target.allow_primary_fallback {
            options.first().map(|option| option.id.clone())
        } else {
            None
        };

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
            self.resolve_option_definition(&request.target_id, &option.id)
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

        match option.kind {
            InteractionOptionKind::Attack => {
                let InteractionTargetId::Actor(target_actor) = request.target_id else {
                    return self.failed_interaction_execution(
                        request.actor_id,
                        prompt,
                        option.id,
                        "attack_target_invalid",
                        false,
                    );
                };
                let action = self.perform_attack(request.actor_id, target_actor);
                if !action.success {
                    return self.failed_interaction_action(
                        request.actor_id,
                        request.target_id,
                        prompt,
                        option.id,
                        action,
                    );
                }
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id: request.actor_id,
                    target_id: InteractionTargetId::Actor(target_actor),
                    option_id: option.id.clone(),
                });
                info!(
                    "core.interaction.succeeded actor={:?} target={:?} option_id={}",
                    request.actor_id,
                    InteractionTargetId::Actor(target_actor),
                    option.id.as_str()
                );
                InteractionExecutionResult {
                    success: true,
                    prompt: Some(prompt),
                    action_result: Some(action),
                    ..InteractionExecutionResult::default()
                }
            }
            InteractionOptionKind::Talk => {
                let action = self.perform_interact(request.actor_id);
                if !action.success {
                    return self.failed_interaction_action(
                        request.actor_id,
                        request.target_id,
                        prompt,
                        option.id,
                        action,
                    );
                }
                let dialogue_id = self
                    .resolve_dialogue_id(&request.target_id, &option)
                    .filter(|value| !value.trim().is_empty());
                let dialogue_state = dialogue_id.as_ref().and_then(|dialogue_id| {
                    self.start_dialogue_session(
                        request.actor_id,
                        Some(request.target_id.clone()),
                        dialogue_id,
                    )
                });
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id: request.actor_id,
                    target_id: request.target_id.clone(),
                    option_id: option.id.clone(),
                });
                info!(
                    "core.interaction.dialogue_started actor={:?} target={:?} option_id={} dialogue_id={}",
                    request.actor_id,
                    request.target_id,
                    option.id.as_str(),
                    dialogue_id.as_deref().unwrap_or("none")
                );
                InteractionExecutionResult {
                    success: true,
                    prompt: Some(prompt),
                    action_result: Some(action),
                    dialogue_id,
                    dialogue_state,
                    ..InteractionExecutionResult::default()
                }
            }
            InteractionOptionKind::Pickup => {
                let InteractionTargetId::MapObject(ref object_id) = request.target_id else {
                    return self.failed_interaction_execution(
                        request.actor_id,
                        prompt,
                        option.id,
                        "pickup_target_invalid",
                        false,
                    );
                };
                let action = self.perform_interact(request.actor_id);
                if !action.success {
                    return self.failed_interaction_action(
                        request.actor_id,
                        request.target_id,
                        prompt,
                        option.id,
                        action,
                    );
                }

                let count = option_definition
                    .max_count
                    .max(option_definition.min_count)
                    .max(1);
                let pickup_item_id = match option_definition.item_id.trim().parse::<u32>() {
                    Ok(item_id) => item_id,
                    Err(_) => {
                        return self.failed_interaction_execution(
                            request.actor_id,
                            prompt,
                            option.id,
                            "pickup_item_invalid",
                            true,
                        );
                    }
                };
                self.grid_world.remove_map_object(object_id);
                self.economy.ensure_actor(request.actor_id);
                if let Err(error) =
                    self.economy
                        .add_item_unchecked(request.actor_id, pickup_item_id, count)
                {
                    let error_message = error.to_string();
                    return self.failed_interaction_execution(
                        request.actor_id,
                        prompt,
                        option.id,
                        &error_message,
                        true,
                    );
                }
                self.advance_collect_quest_progress(request.actor_id, pickup_item_id, count);
                self.events.push(SimulationEvent::PickupGranted {
                    actor_id: request.actor_id,
                    target_id: request.target_id.clone(),
                    item_id: option_definition.item_id.clone(),
                    count,
                });
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id: request.actor_id,
                    target_id: request.target_id.clone(),
                    option_id: option.id.clone(),
                });
                info!(
                    "core.interaction.pickup_succeeded actor={:?} target={:?} option_id={} item_id={} count={}",
                    request.actor_id,
                    request.target_id,
                    option.id.as_str(),
                    option_definition.item_id,
                    count
                );
                InteractionExecutionResult {
                    success: true,
                    prompt: Some(prompt),
                    action_result: Some(action),
                    consumed_target: true,
                    ..InteractionExecutionResult::default()
                }
            }
            InteractionOptionKind::OpenDoor | InteractionOptionKind::CloseDoor => {
                let InteractionTargetId::MapObject(ref object_id) = request.target_id else {
                    return self.failed_interaction_execution(
                        request.actor_id,
                        prompt,
                        option.id,
                        "door_target_invalid",
                        false,
                    );
                };
                let Some(door) = self
                    .grid_world
                    .generated_door_by_object_id(object_id)
                    .cloned()
                else {
                    return self.failed_interaction_execution(
                        request.actor_id,
                        prompt,
                        option.id,
                        "generated_door_missing",
                        false,
                    );
                };
                if option.kind == InteractionOptionKind::OpenDoor && door.is_locked {
                    return self.failed_interaction_execution(
                        request.actor_id,
                        prompt,
                        option.id,
                        "door_locked",
                        false,
                    );
                }
                let next_open = option.kind == InteractionOptionKind::OpenDoor;
                if door.is_open == next_open {
                    return self.failed_interaction_execution(
                        request.actor_id,
                        prompt,
                        option.id,
                        if next_open {
                            "door_already_open"
                        } else {
                            "door_already_closed"
                        },
                        false,
                    );
                }

                let action = self.perform_interact(request.actor_id);
                if !action.success {
                    return self.failed_interaction_action(
                        request.actor_id,
                        request.target_id,
                        prompt,
                        option.id,
                        action,
                    );
                }

                self.grid_world
                    .set_generated_door_state(&door.door_id, next_open, door.is_locked);
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id: request.actor_id,
                    target_id: request.target_id.clone(),
                    option_id: option.id.clone(),
                });
                info!(
                    "core.interaction.generated_door actor={:?} target={:?} option_id={} open={}",
                    request.actor_id,
                    request.target_id,
                    option.id.as_str(),
                    next_open
                );
                InteractionExecutionResult {
                    success: true,
                    prompt: Some(prompt),
                    action_result: Some(action),
                    ..InteractionExecutionResult::default()
                }
            }
            InteractionOptionKind::UnlockDoor | InteractionOptionKind::PickLockDoor => self
                .failed_interaction_execution(
                    request.actor_id,
                    prompt,
                    option.id,
                    "door_interaction_not_implemented",
                    false,
                ),
            InteractionOptionKind::EnterSubscene
            | InteractionOptionKind::EnterOverworld
            | InteractionOptionKind::ExitToOutdoor
            | InteractionOptionKind::EnterOutdoorLocation => {
                let action = self.perform_interact(request.actor_id);
                if !action.success {
                    return self.failed_interaction_action(
                        request.actor_id,
                        request.target_id.clone(),
                        prompt,
                        option.id.clone(),
                        action,
                    );
                }
                let context_snapshot = match self
                    .execute_scene_transition_interaction(request.actor_id, &option_definition)
                {
                    Ok(snapshot) => snapshot,
                    Err(reason) => {
                        return self.failed_interaction_execution(
                            request.actor_id,
                            prompt,
                            option.id.clone(),
                            &reason,
                            true,
                        );
                    }
                };
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id: request.actor_id,
                    target_id: request.target_id.clone(),
                    option_id: option.id.clone(),
                });
                info!(
                    "core.interaction.scene_transition actor={:?} target={:?} option_id={} mode={:?}",
                    request.actor_id,
                    request.target_id,
                    option.id.as_str(),
                    context_snapshot.world_mode
                );
                InteractionExecutionResult {
                    success: true,
                    prompt: Some(prompt),
                    action_result: Some(action),
                    context_snapshot: Some(context_snapshot),
                    ..InteractionExecutionResult::default()
                }
            }
        }
    }

    fn resolve_target_interaction_data(
        &self,
        target_id: &InteractionTargetId,
    ) -> Option<TargetInteractionData> {
        match target_id {
            InteractionTargetId::Actor(target_actor) => {
                let actor = self.actors.get(*target_actor)?;
                let mut options = self
                    .actor_interactions
                    .get(target_actor)
                    .map(|profile| profile.options.clone())
                    .unwrap_or_default();
                if options.is_empty() {
                    options = self.default_actor_options(
                        *target_actor,
                        actor.side,
                        actor.definition_id.as_ref(),
                    );
                }
                Some(TargetInteractionData {
                    target_name: actor.display_name.clone(),
                    anchor_grid: actor.grid_position,
                    options,
                    allow_primary_fallback: true,
                })
            }
            InteractionTargetId::MapObject(object_id) => {
                let object = self.grid_world.map_object(object_id)?;
                Some(TargetInteractionData {
                    target_name: self.map_object_display_name(object),
                    anchor_grid: object.anchor,
                    options: self.map_object_options(object),
                    allow_primary_fallback: self
                        .grid_world
                        .generated_door_by_object_id(object_id)
                        .map(|door| !door.is_locked)
                        .unwrap_or(true),
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
                .map(|interactive| {
                    if interactive.display_name.trim().is_empty() {
                        object.object_id.clone()
                    } else {
                        interactive.display_name.clone()
                    }
                })
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

    fn map_object_options(&self, object: &MapObjectDefinition) -> Vec<InteractionOptionDefinition> {
        match object.kind {
            MapObjectKind::Pickup => object
                .props
                .pickup
                .as_ref()
                .map(|pickup| {
                    vec![InteractionOptionDefinition {
                        kind: InteractionOptionKind::Pickup,
                        item_id: pickup.item_id.clone(),
                        min_count: pickup.min_count.max(1),
                        max_count: pickup.max_count.max(pickup.min_count.max(1)),
                        ..InteractionOptionDefinition::default()
                    }]
                })
                .unwrap_or_default(),
            MapObjectKind::Interactive => object
                .props
                .interactive
                .as_ref()
                .map(|interactive| interactive.resolved_options())
                .unwrap_or_default(),
            MapObjectKind::Building | MapObjectKind::Trigger | MapObjectKind::AiSpawn => Vec::new(),
        }
    }

    fn map_object_trigger_options(
        &self,
        object: &MapObjectDefinition,
    ) -> Vec<InteractionOptionDefinition> {
        if object.kind != MapObjectKind::Trigger {
            return Vec::new();
        }
        object
            .props
            .trigger
            .as_ref()
            .map(|trigger| trigger.resolved_options())
            .unwrap_or_default()
    }

    pub(super) fn try_activate_map_trigger(&mut self, actor_id: ActorId, grid: GridCoord) -> bool {
        if self
            .actors
            .get(actor_id)
            .map(|actor| actor.kind != ActorKind::Player)
            .unwrap_or(true)
        {
            return false;
        }

        let triggered = self
            .grid_world
            .map_objects_at(grid)
            .into_iter()
            .find_map(|object| {
                let options = self.map_object_trigger_options(object);
                options
                    .into_iter()
                    .find(|option| self.is_scene_transition_option_kind(option.kind))
                    .map(|option| (object.object_id.clone(), option))
            });
        let Some((object_id, option)) = triggered else {
            return false;
        };

        match self.execute_scene_transition_interaction(actor_id, &option) {
            Ok(context_snapshot) => {
                self.events.push(SimulationEvent::InteractionSucceeded {
                    actor_id,
                    target_id: InteractionTargetId::MapObject(object_id.clone()),
                    option_id: option.id.clone(),
                });
                info!(
                    "core.interaction.trigger_scene_transition actor={:?} target={} option_id={} mode={:?}",
                    actor_id,
                    object_id,
                    option.id.as_str(),
                    context_snapshot.world_mode
                );
                true
            }
            Err(reason) => {
                self.events.push(SimulationEvent::InteractionFailed {
                    actor_id,
                    target_id: InteractionTargetId::MapObject(object_id.clone()),
                    option_id: option.id.clone(),
                    reason: reason.clone(),
                });
                warn!(
                    "core.interaction.trigger_scene_transition_failed actor={:?} target={} option_id={} reason={}",
                    actor_id,
                    object_id,
                    option.id.as_str(),
                    reason
                );
                false
            }
        }
    }

    fn is_scene_transition_option_kind(&self, kind: InteractionOptionKind) -> bool {
        matches!(
            kind,
            InteractionOptionKind::EnterSubscene
                | InteractionOptionKind::EnterOverworld
                | InteractionOptionKind::ExitToOutdoor
                | InteractionOptionKind::EnterOutdoorLocation
        )
    }

    fn default_actor_options(
        &self,
        actor_id: ActorId,
        side: ActorSide,
        definition_id: Option<&CharacterId>,
    ) -> Vec<InteractionOptionDefinition> {
        let mut options = Vec::new();
        if side != ActorSide::Hostile {
            let dialogue_id = definition_id
                .map(CharacterId::as_str)
                .unwrap_or_default()
                .to_string();
            let mut talk = InteractionOptionDefinition {
                kind: InteractionOptionKind::Talk,
                dialogue_id,
                priority: 800,
                ..InteractionOptionDefinition::default()
            };
            talk.ensure_defaults();
            options.push(talk);
        }

        if actor_id != ActorId(0) {
            let mut attack = InteractionOptionDefinition {
                kind: InteractionOptionKind::Attack,
                dangerous: side != ActorSide::Hostile,
                priority: if side == ActorSide::Hostile {
                    1000
                } else {
                    -100
                },
                interaction_distance: self
                    .actor_attack_ranges
                    .get(&actor_id)
                    .copied()
                    .unwrap_or(1.2)
                    .max(1.0),
                ..InteractionOptionDefinition::default()
            };
            attack.ensure_defaults();
            options.push(attack);
        }

        options
    }

    fn resolve_interaction_option_view(
        &self,
        actor_id: ActorId,
        target_id: &InteractionTargetId,
        mut option: InteractionOptionDefinition,
    ) -> ResolvedInteractionOption {
        option.ensure_defaults();
        if option.kind == InteractionOptionKind::Attack {
            option.interaction_distance = self.attack_interaction_distance(actor_id);
        }
        if matches!(target_id, InteractionTargetId::Actor(actor_id) if self.get_actor_side(*actor_id) == Some(ActorSide::Hostile))
            && option.kind == InteractionOptionKind::Attack
        {
            option.dangerous = false;
            option.priority = option.priority.max(1000);
        }
        ResolvedInteractionOption {
            id: option.id,
            display_name: option.display_name,
            description: option.description,
            priority: option.priority,
            dangerous: option.dangerous,
            requires_proximity: option.requires_proximity,
            interaction_distance: option.interaction_distance,
            kind: option.kind,
        }
    }

    fn resolve_option_definition(
        &self,
        target_id: &InteractionTargetId,
        option_id: &InteractionOptionId,
    ) -> Option<InteractionOptionDefinition> {
        let target = self.resolve_target_interaction_data(target_id)?;
        target
            .options
            .into_iter()
            .map(|mut option| {
                option.ensure_defaults();
                option
            })
            .find(|option| &option.id == option_id)
    }

    fn resolve_dialogue_id(
        &self,
        target_id: &InteractionTargetId,
        option: &ResolvedInteractionOption,
    ) -> Option<String> {
        let Some(definition) = self.resolve_option_definition(target_id, &option.id) else {
            return None;
        };
        if !definition.dialogue_id.trim().is_empty() {
            return Some(definition.dialogue_id);
        }
        match target_id {
            InteractionTargetId::Actor(actor_id) => self
                .actors
                .get(*actor_id)
                .and_then(|actor| actor.definition_id.as_ref())
                .map(CharacterId::as_str)
                .map(str::to_string),
            InteractionTargetId::MapObject(object_id) => Some(object_id.clone()),
        }
    }

    pub(super) fn resolve_scene_target_id(
        &self,
        option: &InteractionOptionDefinition,
    ) -> String {
        if !option.target_id.trim().is_empty() {
            option.target_id.clone()
        } else {
            option.target_map_id.clone()
        }
    }

    fn execute_scene_transition_interaction(
        &mut self,
        actor_id: ActorId,
        option: &InteractionOptionDefinition,
    ) -> Result<InteractionContextSnapshot, String> {
        let target_id = self.resolve_scene_target_id(option);
        let entry_point_override =
            (!option.return_spawn_id.trim().is_empty()).then_some(option.return_spawn_id.as_str());

        match option.kind {
            InteractionOptionKind::EnterSubscene
            | InteractionOptionKind::ExitToOutdoor
            | InteractionOptionKind::EnterOutdoorLocation => {
                self.enter_location(actor_id, &target_id, entry_point_override)?;
            }
            InteractionOptionKind::EnterOverworld => {
                self.return_to_overworld(actor_id)?;
            }
            InteractionOptionKind::Talk
            | InteractionOptionKind::Attack
            | InteractionOptionKind::Pickup
            | InteractionOptionKind::OpenDoor
            | InteractionOptionKind::CloseDoor
            | InteractionOptionKind::UnlockDoor
            | InteractionOptionKind::PickLockDoor => return Ok(self.current_interaction_context()),
        }
        Ok(self.current_interaction_context())
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
        let Some(target) = self.resolve_target_interaction_data(target_id) else {
            return Err("interaction_target_unavailable".to_string());
        };

        if self.is_interaction_in_range(actor_grid, target.anchor_grid, interaction_distance) {
            return Ok(None);
        }

        let max_radius =
            ((interaction_distance / self.grid_world.grid_size()).ceil() as i32).max(1);
        let mut best_goal = None;
        let mut best_path_len = usize::MAX;

        for radius in 1..=max_radius {
            for candidate in collect_interaction_ring_cells(target.anchor_grid, radius) {
                if candidate == actor_grid {
                    continue;
                }
                if !self
                    .grid_world
                    .is_walkable_for_actor(candidate, Some(actor_id))
                {
                    continue;
                }
                if !self.is_interaction_in_range(
                    candidate,
                    target.anchor_grid,
                    interaction_distance,
                ) {
                    continue;
                }
                let Ok(path) = self.find_path_grid(Some(actor_id), actor_grid, candidate) else {
                    continue;
                };
                if path.len() <= 1 || path.len() >= best_path_len {
                    continue;
                }
                best_goal = Some(candidate);
                best_path_len = path.len();
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

    fn failed_interaction_execution(
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

    fn failed_interaction_action(
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
    options: Vec<InteractionOptionDefinition>,
    allow_primary_fallback: bool,
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
