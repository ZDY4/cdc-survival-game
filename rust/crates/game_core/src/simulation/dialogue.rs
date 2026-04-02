use game_data::{
    advance_dialogue as advance_dialogue_runtime, current_dialogue_node, dialogue_runtime_state,
    resolve_dialogue_preview, resolve_dialogue_start_node_id, CharacterId, DialogueAction,
    DialogueData, DialogueResolutionContext, DialogueRuntimeState, DialogueSessionState,
    InteractionTargetId,
};
use tracing::warn;

use crate::simulation::{
    dialogue_advance_error_reason, npc_action_key_name, Simulation, SimulationEvent,
};

impl Simulation {
    pub fn active_dialogue_state(
        &self,
        actor_id: game_data::ActorId,
    ) -> Option<DialogueRuntimeState> {
        self.active_dialogues.get(&actor_id).and_then(|session| {
            self.dialogue_state_from_session(session.clone(), Vec::new(), false, None)
        })
    }

    fn dialogue_state_from_session(
        &self,
        session: DialogueSessionState,
        emitted_actions: Vec<DialogueAction>,
        finished: bool,
        end_type: Option<String>,
    ) -> Option<DialogueRuntimeState> {
        let (dialogue, resolved_dialogue_id) = self.resolve_dialogue_content(
            session.actor_id,
            session.target_id.as_ref(),
            &session.dialogue_key,
            Some(&session.dialogue_id),
        )?;
        let mut session = session;
        if session.dialogue_id.trim().is_empty() {
            session.dialogue_id = resolved_dialogue_id;
        }
        Some(dialogue_runtime_state(
            &dialogue,
            session,
            emitted_actions,
            finished,
            end_type,
        ))
    }

    fn build_dialogue_resolution_context(
        &self,
        actor_id: game_data::ActorId,
        target_id: Option<&InteractionTargetId>,
    ) -> DialogueResolutionContext {
        let max_hp = self.actor_max_hit_points(actor_id);
        let player_hp_ratio = if max_hp <= 0.0 {
            1.0
        } else {
            (self.actor_hit_points(actor_id) / max_hp).clamp(0.0, 1.0)
        };

        let (relation_score, npc_definition_id, npc_action, npc_morale) = match target_id {
            Some(InteractionTargetId::Actor(target_actor_id)) => {
                let npc_definition_id = self
                    .actors
                    .get(*target_actor_id)
                    .and_then(|actor| actor.definition_id.as_ref())
                    .map(CharacterId::as_str)
                    .map(str::to_string);
                let npc_action = self
                    .actor_runtime_actions
                    .get(target_actor_id)
                    .map(|state| npc_action_key_name(state.step.action.clone()));
                let npc_morale = self
                    .actor_resources
                    .get(target_actor_id)
                    .and_then(|resources| resources.get("morale"))
                    .copied();
                (
                    Some(self.get_relationship_score(actor_id, *target_actor_id)),
                    npc_definition_id,
                    npc_action,
                    npc_morale,
                )
            }
            _ => (None, None, None, None),
        };

        DialogueResolutionContext {
            world_mode: self.interaction_context.world_mode,
            map_id: self.interaction_context.current_map_id.clone(),
            outdoor_location_id: self.interaction_context.active_outdoor_location_id.clone(),
            subscene_location_id: self
                .interaction_context
                .current_subscene_location_id
                .clone(),
            player_level: self.actor_level(actor_id),
            player_hp_ratio,
            player_active_quests: self.active_quest_ids_for_actor(actor_id),
            player_completed_quests: self.completed_quest_ids(),
            relation_score,
            npc_definition_id,
            npc_role: None,
            npc_on_shift: None,
            npc_schedule_labels: Vec::new(),
            npc_action,
            npc_morale,
        }
    }

    fn resolve_dialogue_content(
        &self,
        actor_id: game_data::ActorId,
        target_id: Option<&InteractionTargetId>,
        dialogue_key: &str,
        preferred_dialogue_id: Option<&str>,
    ) -> Option<(DialogueData, String)> {
        let dialogue_library = self.dialogue_library.as_ref()?;

        let preferred_dialogue_id = preferred_dialogue_id
            .map(str::trim)
            .filter(|value| !value.is_empty());
        if let Some(dialogue_id) = preferred_dialogue_id {
            if let Some(dialogue) = dialogue_library.get(dialogue_id) {
                let resolved_dialogue_id = if dialogue.dialog_id.trim().is_empty() {
                    dialogue_id.to_string()
                } else {
                    dialogue.dialog_id.clone()
                };
                return Some((dialogue.clone(), resolved_dialogue_id));
            }
        }

        let dialogue_key = dialogue_key.trim();
        if dialogue_key.is_empty() {
            return None;
        }

        if let Some(definition) = self
            .dialogue_rule_library
            .as_ref()
            .and_then(|library| library.get(dialogue_key))
        {
            let preview = resolve_dialogue_preview(
                definition,
                &self.build_dialogue_resolution_context(actor_id, target_id),
            );
            if let Some(dialogue_id) = preview
                .resolved_dialogue_id
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
            {
                if let Some(dialogue) = dialogue_library.get(dialogue_id) {
                    let resolved_dialogue_id = if dialogue.dialog_id.trim().is_empty() {
                        dialogue_id.to_string()
                    } else {
                        dialogue.dialog_id.clone()
                    };
                    return Some((dialogue.clone(), resolved_dialogue_id));
                }
            }
        }

        dialogue_library.get(dialogue_key).map(|dialogue| {
            let resolved_dialogue_id = if dialogue.dialog_id.trim().is_empty() {
                dialogue_key.to_string()
            } else {
                dialogue.dialog_id.clone()
            };
            (dialogue.clone(), resolved_dialogue_id)
        })
    }

    pub(super) fn start_dialogue_session(
        &mut self,
        actor_id: game_data::ActorId,
        target_id: Option<InteractionTargetId>,
        dialogue_key: &str,
    ) -> Option<DialogueRuntimeState> {
        let (dialogue, resolved_dialogue_id) =
            self.resolve_dialogue_content(actor_id, target_id.as_ref(), dialogue_key, None)?;
        let current_node_id = resolve_dialogue_start_node_id(&dialogue)?;
        let session = DialogueSessionState {
            actor_id,
            target_id: target_id.clone(),
            dialogue_key: dialogue_key.to_string(),
            dialogue_id: resolved_dialogue_id,
            current_node_id: current_node_id.clone(),
        };

        self.active_dialogues.insert(actor_id, session.clone());
        if let Some(target_id) = target_id {
            self.events.push(SimulationEvent::DialogueStarted {
                actor_id,
                target_id,
                dialogue_id: dialogue_key.to_string(),
            });
        }
        self.events.push(SimulationEvent::DialogueAdvanced {
            actor_id,
            dialogue_id: dialogue_key.to_string(),
            node_id: current_node_id,
        });

        Some(dialogue_runtime_state(
            &dialogue,
            session,
            Vec::new(),
            false,
            None,
        ))
    }

    fn resolve_dialogue_choice_index(
        &self,
        dialogue: &DialogueData,
        current_node_id: &str,
        option_id: Option<&str>,
        option_index: Option<usize>,
    ) -> Result<Option<usize>, String> {
        if let Some(option_index) = option_index {
            return Ok(Some(option_index));
        }

        let Some(trimmed) = option_id.map(str::trim).filter(|value| !value.is_empty()) else {
            return Ok(None);
        };
        let Some(node) = current_dialogue_node(dialogue, current_node_id) else {
            return Err(format!("dialogue_node_missing:{current_node_id}"));
        };

        if let Some(index) = trimmed
            .strip_prefix("choice_")
            .and_then(|value| value.parse::<usize>().ok())
            .and_then(|value| value.checked_sub(1))
        {
            return Ok(Some(index));
        }

        if let Ok(parsed) = trimmed.parse::<usize>() {
            if parsed == 0 {
                return Ok(Some(0));
            }
            if parsed <= node.options.len() {
                return Ok(Some(parsed - 1));
            }
        }

        let Some(index) = node.options.iter().position(|option| {
            option.extra.get("id").and_then(|value| value.as_str()) == Some(trimmed)
                || option.next == trimmed
                || option.text == trimmed
        }) else {
            return Err(format!("dialogue_option_unresolved:{trimmed}"));
        };

        Ok(Some(index))
    }

    pub(crate) fn advance_dialogue(
        &mut self,
        actor_id: game_data::ActorId,
        target_id: Option<&InteractionTargetId>,
        dialogue_id: &str,
        option_id: Option<&str>,
        option_index: Option<usize>,
    ) -> Result<DialogueRuntimeState, String> {
        if !self.actors.contains(actor_id) {
            return Err("dialogue_actor_missing".to_string());
        }

        let session = match self.active_dialogues.get(&actor_id).cloned() {
            Some(session)
                if dialogue_id.trim().is_empty()
                    || session.dialogue_key == dialogue_id
                    || session.dialogue_id == dialogue_id =>
            {
                session
            }
            _ if !dialogue_id.trim().is_empty() => {
                return self
                    .start_dialogue_session(actor_id, target_id.cloned(), dialogue_id)
                    .ok_or_else(|| format!("dialogue_definition_missing:{dialogue_id}"));
            }
            _ => return Err("dialogue_session_missing".to_string()),
        };

        let (dialogue, resolved_dialogue_id) = self
            .resolve_dialogue_content(
                actor_id,
                session.target_id.as_ref().or(target_id),
                &session.dialogue_key,
                Some(&session.dialogue_id),
            )
            .ok_or_else(|| format!("dialogue_definition_missing:{}", session.dialogue_key))?;

        let choice_index = self.resolve_dialogue_choice_index(
            &dialogue,
            &session.current_node_id,
            option_id,
            option_index,
        )?;
        let outcome = advance_dialogue_runtime(&dialogue, &session.current_node_id, choice_index)
            .map_err(dialogue_advance_error_reason)?;
        self.apply_dialogue_actions(actor_id, &outcome.emitted_actions);

        if let Some(next_node_id) = outcome.next_node_id.clone() {
            let next_session = DialogueSessionState {
                actor_id,
                target_id: session.target_id.clone().or_else(|| target_id.cloned()),
                dialogue_key: session.dialogue_key.clone(),
                dialogue_id: resolved_dialogue_id,
                current_node_id: next_node_id.clone(),
            };
            self.active_dialogues.insert(actor_id, next_session.clone());
            self.events.push(SimulationEvent::DialogueAdvanced {
                actor_id,
                dialogue_id: next_session.dialogue_key.clone(),
                node_id: next_node_id,
            });
            return self
                .dialogue_state_from_session(
                    next_session,
                    outcome.emitted_actions,
                    outcome.finished,
                    outcome.end_type,
                )
                .ok_or_else(|| "dialogue_state_unavailable".to_string());
        }

        self.active_dialogues.remove(&actor_id);
        self.dialogue_state_from_session(session, outcome.emitted_actions, true, outcome.end_type)
            .ok_or_else(|| "dialogue_state_unavailable".to_string())
    }

    fn apply_dialogue_actions(&mut self, actor_id: game_data::ActorId, actions: &[DialogueAction]) {
        for action in actions {
            match action.action_type.trim() {
                "start_quest" => {
                    let Some(quest_id) =
                        super::dialogue_action_string(action, &["quest_id", "questId"])
                    else {
                        warn!("dialogue action missing quest id: {:?}", action);
                        continue;
                    };
                    if !self.start_quest(actor_id, &quest_id) {
                        warn!(
                            "dialogue start_quest rejected actor={actor_id:?} quest_id={quest_id}"
                        );
                    }
                }
                "grant_item" => {
                    let Some(item_id) =
                        super::dialogue_action_u32(action, &["item_id", "itemId", "id"])
                    else {
                        warn!("dialogue action missing item id: {:?}", action);
                        continue;
                    };
                    let count = super::dialogue_action_i32(action, &["count", "amount"])
                        .unwrap_or(1)
                        .max(1);
                    let Some(items) = self.item_library.as_ref() else {
                        warn!("dialogue grant_item skipped without item library");
                        continue;
                    };
                    if let Err(error) = self.economy.add_item(actor_id, item_id, count, items) {
                        warn!(
                            "dialogue grant_item failed actor={actor_id:?} item_id={item_id} count={count}: {error}"
                        );
                    }
                }
                "grant_money" => {
                    let amount = super::dialogue_action_i32(action, &["amount", "money", "count"])
                        .unwrap_or(0)
                        .max(0);
                    if amount == 0 {
                        warn!(
                            "dialogue grant_money skipped with non-positive amount: {:?}",
                            action
                        );
                        continue;
                    }
                    if let Err(error) = self.economy.grant_money(actor_id, amount) {
                        warn!(
                            "dialogue grant_money failed actor={actor_id:?} amount={amount}: {error}"
                        );
                    }
                }
                "unlock_location" => {
                    let Some(location_id) =
                        super::dialogue_action_string(action, &["location_id", "locationId"])
                    else {
                        warn!("dialogue unlock_location missing location id: {:?}", action);
                        continue;
                    };
                    if let Err(error) = self.unlock_location(&location_id) {
                        warn!(
                            "dialogue unlock_location failed actor={actor_id:?} location_id={location_id}: {error}"
                        );
                    }
                }
                "enter_location" => {
                    let Some(location_id) =
                        super::dialogue_action_string(action, &["location_id", "locationId"])
                    else {
                        warn!("dialogue enter_location missing location id: {:?}", action);
                        continue;
                    };
                    let entry_point_id =
                        super::dialogue_action_string(action, &["entry_point_id", "entryPointId"]);
                    if let Err(error) =
                        self.enter_location(actor_id, &location_id, entry_point_id.as_deref())
                    {
                        warn!(
                            "dialogue enter_location failed actor={actor_id:?} location_id={location_id}: {error}"
                        );
                    }
                }
                "return_to_overworld" => {
                    if let Err(error) = self.return_to_overworld(actor_id) {
                        warn!("dialogue return_to_overworld failed actor={actor_id:?}: {error}");
                    }
                }
                _ => {}
            }
        }
    }
}
