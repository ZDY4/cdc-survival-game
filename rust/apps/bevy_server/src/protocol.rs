use std::collections::BTreeMap;

use bevy_ecs::message::{MessageReader, MessageWriter};
use bevy_ecs::prelude::{Message, Res, ResMut, Resource};
use game_bevy::{ItemDefinitions, RecipeDefinitions, ShopDefinitions, SkillDefinitions};
use game_core::{
    action_result_status, EconomyRuntimeError, RuntimeSnapshot, SimulationCommand,
    SimulationCommandResult, SimulationEvent,
};
use game_data::{
    InteractionExecutionRequest, ItemLibrary, RecipeLibrary, ShopLibrary, SkillLibrary, WorldMode,
};
use game_protocol::{
    ActorSnapshot, BuyItemRequest, ClientMessage, CraftRecipeRequest, DialogueAdvanceRequest,
    EnterLocationRequest, EquipItemRequest, ItemEquippedPayload, ItemUnequippedPayload,
    LearnSkillRequest, MapTravelRequest, ProtocolActorVisionMapSnapshot,
    ProtocolActorVisionSnapshot, ProtocolError, ProtocolLocationTransitionContext,
    ProtocolOverworldStateSnapshot, ProtocolVisionRuntimeSnapshot, QuestStartedPayload,
    RecipeCraftedPayload, ReloadEquippedWeaponRequest, ReturnToOverworldRequest,
    RuntimeEventEnvelope, RuntimeSnapshotLoadRequest, RuntimeSnapshotPayload,
    RuntimeSnapshotSaveRequest, SceneTransitionNotice, SellItemRequest, ServerMessage,
    SkillLearnedPayload, StartQuestRequest, TradeResolvedPayload, UnequipItemRequest,
    WeaponReloadedPayload, WorldSnapshotEnvelope,
};
use serde_json::json;
use tracing::warn;

use crate::config::{ServerSimulationRuntime, ServerStartupState};
use crate::progression::drain_runtime_progression;

mod dispatch;
mod errors;
mod projections;
mod subscriptions;

use dispatch::{
    advance_dialogue, buy_item, craft_recipe, enter_location, equip_item, execute_interaction,
    learn_skill, load_runtime_snapshot, reload_equipped_weapon, return_to_overworld,
    save_runtime_snapshot, sell_item, start_quest, travel_to_map, unequip_item,
};
use errors::protocol_error;
use projections::{protocol_overworld_state, runtime_snapshot_envelope, world_snapshot_message};
use subscriptions::{mark_subscription_if_requested, next_sequence};

#[derive(Resource, Debug, Default)]
pub struct RuntimeSnapshotStore {
    snapshots: BTreeMap<String, RuntimeSnapshot>,
    next_id: u64,
}

#[derive(Resource, Debug, Default)]
pub struct RuntimeProtocolPushState {
    pub subscribed: bool,
}

#[derive(Resource, Debug, Default)]
pub struct RuntimeProtocolSequence {
    next: u64,
}

#[derive(Debug, Default, Clone, Copy)]
pub struct ServerProtocolDefinitions<'a> {
    pub items: Option<&'a ItemLibrary>,
    pub skills: Option<&'a SkillLibrary>,
    pub recipes: Option<&'a RecipeLibrary>,
    pub shops: Option<&'a ShopLibrary>,
}

#[derive(Message, Debug, Clone)]
pub struct ServerProtocolRequest {
    pub message: ClientMessage,
}

#[derive(Message, Debug, Clone)]
pub struct ServerProtocolResponse {
    pub message: Result<ServerMessage, ProtocolError>,
}

impl RuntimeSnapshotStore {
    pub fn save(
        &mut self,
        requested_id: Option<String>,
        snapshot: RuntimeSnapshot,
    ) -> Result<RuntimeSnapshotPayload, ProtocolError> {
        let snapshot_id = normalize_snapshot_id(requested_id).unwrap_or_else(|| {
            self.next_id = self.next_id.saturating_add(1);
            format!("runtime_snapshot_{}", self.next_id)
        });
        self.snapshots.insert(snapshot_id.clone(), snapshot.clone());
        snapshot_payload(Some(snapshot_id), snapshot)
    }

    pub fn load(&self, snapshot_id: &str) -> Option<RuntimeSnapshot> {
        self.snapshots.get(snapshot_id).cloned()
    }

    #[cfg(test)]
    pub fn has_snapshot(&self, snapshot_id: &str) -> bool {
        self.snapshots.contains_key(snapshot_id)
    }
}

#[cfg(test)]
pub fn handle_client_message(
    runtime: &mut ServerSimulationRuntime,
    snapshots: &mut RuntimeSnapshotStore,
    message: ClientMessage,
) -> Result<ServerMessage, ProtocolError> {
    handle_client_message_with_definitions(
        runtime,
        snapshots,
        ServerProtocolDefinitions::default(),
        message,
    )
}

pub fn handle_client_message_with_definitions(
    runtime: &mut ServerSimulationRuntime,
    snapshots: &mut RuntimeSnapshotStore,
    definitions: ServerProtocolDefinitions<'_>,
    message: ClientMessage,
) -> Result<ServerMessage, ProtocolError> {
    match message {
        ClientMessage::Ping => Ok(ServerMessage::Pong),
        ClientMessage::RequestWorldSnapshot => Ok(world_snapshot_message(runtime)),
        ClientMessage::SubscribeRuntime(_request) => Ok(ServerMessage::Snapshot(
            runtime_snapshot_envelope(runtime, 0),
        )),
        ClientMessage::RequestOverworldSnapshot => Ok(ServerMessage::OverworldState(
            protocol_overworld_state(runtime.0.snapshot().overworld),
        )),
        ClientMessage::QueryInteractionOptions {
            actor_id,
            target_id,
        } => {
            let result = runtime
                .0
                .submit_command(SimulationCommand::QueryInteractionOptions {
                    actor_id,
                    target_id,
                });
            match result {
                SimulationCommandResult::InteractionPrompt(prompt) => {
                    Ok(ServerMessage::InteractionPrompt(prompt))
                }
                other => Err(protocol_error(
                    "interaction_prompt_unavailable",
                    format!("expected interaction prompt, got {:?}", other),
                    false,
                )),
            }
        }
        ClientMessage::ExecuteInteraction(request) => execute_interaction(runtime, request),
        ClientMessage::AdvanceDialogue(request) => advance_dialogue(runtime, request),
        ClientMessage::TravelToMap(request) => travel_to_map(runtime, request),
        ClientMessage::EnterLocation(request) => enter_location(runtime, request),
        ClientMessage::ReturnToOverworld(request) => return_to_overworld(runtime, request),
        ClientMessage::RequestEquipItem(request) => equip_item(runtime, definitions, request),
        ClientMessage::RequestUnequipItem(request) => unequip_item(runtime, request),
        ClientMessage::RequestReloadEquippedWeapon(request) => {
            reload_equipped_weapon(runtime, definitions, request)
        }
        ClientMessage::RequestLearnSkill(request) => learn_skill(runtime, definitions, request),
        ClientMessage::RequestCraftRecipe(request) => craft_recipe(runtime, definitions, request),
        ClientMessage::RequestBuyItem(request) => buy_item(runtime, definitions, request),
        ClientMessage::RequestSellItem(request) => sell_item(runtime, definitions, request),
        ClientMessage::RequestStartQuest(request) => start_quest(runtime, request),
        ClientMessage::RequestRuntimeSnapshotSave(request) => {
            save_runtime_snapshot(runtime, snapshots, request)
        }
        ClientMessage::RequestRuntimeSnapshotLoad(request) => {
            load_runtime_snapshot(runtime, snapshots, request)
        }
        other => Err(protocol_error(
            "unsupported_message",
            format!("bevy_server protocol handler does not support {:?}", other),
            false,
        )),
    }
}

pub fn dispatch_protocol_requests(
    mut requests: MessageReader<ServerProtocolRequest>,
    mut responses: MessageWriter<ServerProtocolResponse>,
    mut runtime: ResMut<ServerSimulationRuntime>,
    startup: Res<ServerStartupState>,
    mut snapshots: ResMut<RuntimeSnapshotStore>,
    mut push_state: ResMut<RuntimeProtocolPushState>,
    items: Option<Res<ItemDefinitions>>,
    skills: Option<Res<SkillDefinitions>>,
    recipes: Option<Res<RecipeDefinitions>>,
    shops: Option<Res<ShopDefinitions>>,
) {
    let definitions = ServerProtocolDefinitions {
        items: items.as_ref().map(|value| &value.0),
        skills: skills.as_ref().map(|value| &value.0),
        recipes: recipes.as_ref().map(|value| &value.0),
        shops: shops.as_ref().map(|value| &value.0),
    };

    for request in requests.read() {
        if let ServerStartupState::Failed { error } = startup.as_ref() {
            let message = match &request.message {
                ClientMessage::Ping => Ok(ServerMessage::Pong),
                ClientMessage::Handshake { protocol_version } => Ok(ServerMessage::Hello {
                    protocol_version: *protocol_version,
                }),
                _ => Err(protocol_error("startup_failed", error.clone(), false)),
            };
            responses.write(ServerProtocolResponse { message });
            continue;
        }

        drain_runtime_progression(&mut runtime);
        mark_subscription_if_requested(&mut push_state, &request.message);
        let message = handle_client_message_with_definitions(
            &mut runtime,
            &mut snapshots,
            definitions,
            request.message.clone(),
        );
        drain_runtime_progression(&mut runtime);
        responses.write(ServerProtocolResponse { message });
    }
}

pub fn emit_runtime_protocol_events(
    mut runtime: ResMut<ServerSimulationRuntime>,
    push_state: Res<RuntimeProtocolPushState>,
    mut sequence: ResMut<RuntimeProtocolSequence>,
    mut responses: MessageWriter<ServerProtocolResponse>,
) {
    if !push_state.subscribed {
        return;
    }

    for event in runtime.0.drain_events() {
        responses.write(ServerProtocolResponse {
            message: Ok(ServerMessage::Delta(runtime_event_envelope(
                next_sequence(&mut sequence),
                event,
            ))),
        });
    }
}

pub fn drain_protocol_responses(mut responses: MessageReader<ServerProtocolResponse>) {
    for response in responses.read() {
        if let Err(error) = &response.message {
            warn!(
                "bevy_server protocol error code={} retryable={} message={}",
                error.code, error.retryable, error.message
            );
        }
    }
}

fn snapshot_payload(
    snapshot_id: Option<String>,
    snapshot: RuntimeSnapshot,
) -> Result<RuntimeSnapshotPayload, ProtocolError> {
    let schema_version = snapshot.schema_version;
    let snapshot = serde_json::to_value(snapshot).map_err(|error| {
        protocol_error(
            "runtime_snapshot_serialize_failed",
            format!("failed to serialize runtime snapshot: {error}"),
            false,
        )
    })?;
    Ok(RuntimeSnapshotPayload {
        snapshot_id,
        schema_version,
        snapshot,
    })
}

fn normalize_snapshot_id(snapshot_id: Option<String>) -> Option<String> {
    snapshot_id.and_then(|id| {
        let trimmed = id.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

fn world_mode_name(world_mode: WorldMode) -> &'static str {
    match world_mode {
        WorldMode::Overworld => "overworld",
        WorldMode::Traveling => "traveling_legacy",
        WorldMode::Outdoor => "outdoor",
        WorldMode::Interior => "interior",
        WorldMode::Dungeon => "dungeon",
        WorldMode::Unknown => "unknown",
    }
}

fn runtime_event_envelope(sequence: u64, event: SimulationEvent) -> RuntimeEventEnvelope {
    match event {
        SimulationEvent::GroupRegistered { group_id, order } => RuntimeEventEnvelope {
            sequence,
            event_type: "group_registered".into(),
            payload: json!({ "groupId": group_id, "order": order }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActorRegistered {
            actor_id,
            group_id,
            side,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "actor_registered".into(),
            actor_id: Some(actor_id),
            payload: json!({ "groupId": group_id, "side": side }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActorUnregistered { actor_id } => RuntimeEventEnvelope {
            sequence,
            event_type: "actor_unregistered".into(),
            actor_id: Some(actor_id),
            payload: json!({}),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActorTurnStarted {
            actor_id,
            group_id,
            ap,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "actor_turn_started".into(),
            actor_id: Some(actor_id),
            payload: json!({ "groupId": group_id, "ap": ap }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActorTurnEnded {
            actor_id,
            group_id,
            remaining_ap,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "actor_turn_ended".into(),
            actor_id: Some(actor_id),
            payload: json!({ "groupId": group_id, "remainingAp": remaining_ap }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActorVisionUpdated {
            actor_id,
            active_map_id,
            visible_cells,
            explored_cells,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "actor_vision_updated".into(),
            actor_id: Some(actor_id),
            map_id: active_map_id
                .as_ref()
                .map(|map_id| map_id.as_str().to_string()),
            payload: json!({
                "activeMapId": active_map_id.as_ref().map(|map_id| map_id.as_str().to_string()),
                "visibleCells": visible_cells,
                "exploredCells": explored_cells
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::CombatStateChanged { in_combat } => RuntimeEventEnvelope {
            sequence,
            event_type: "combat_state_changed".into(),
            payload: json!({ "inCombat": in_combat }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActionRejected {
            actor_id,
            action_type,
            reason,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "action_rejected".into(),
            actor_id: Some(actor_id),
            payload: json!({ "actionType": format!("{action_type:?}"), "reason": reason }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActionResolved {
            actor_id,
            action_type,
            result,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "action_resolved".into(),
            actor_id: Some(actor_id),
            payload: json!({ "actionType": format!("{action_type:?}"), "result": result }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::SkillActivated {
            actor_id,
            skill_id,
            target,
            hit_actor_ids,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "skill_activated".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "skillId": skill_id,
                "target": target,
                "hitActorIds": hit_actor_ids
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::SkillActivationFailed {
            actor_id,
            skill_id,
            reason,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "skill_activation_failed".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "skillId": skill_id,
                "reason": reason
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::WorldCycleCompleted => RuntimeEventEnvelope {
            sequence,
            event_type: "world_cycle_completed".into(),
            payload: json!({}),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::NpcActionStarted {
            actor_id,
            action,
            phase,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "npc_action_started".into(),
            actor_id: Some(actor_id),
            payload: json!({ "action": format!("{action:?}"), "phase": format!("{phase:?}") }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::NpcActionPhaseChanged {
            actor_id,
            action,
            phase,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "npc_action_phase_changed".into(),
            actor_id: Some(actor_id),
            payload: json!({ "action": format!("{action:?}"), "phase": format!("{phase:?}") }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::NpcActionCompleted { actor_id, action } => RuntimeEventEnvelope {
            sequence,
            event_type: "npc_action_completed".into(),
            actor_id: Some(actor_id),
            payload: json!({ "action": format!("{action:?}") }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::NpcActionFailed {
            actor_id,
            action,
            reason,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "npc_action_failed".into(),
            actor_id: Some(actor_id),
            payload: json!({ "action": format!("{action:?}"), "reason": reason }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActorMoved {
            actor_id,
            from,
            to,
            step_index,
            total_steps,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "actor_moved".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "from": from,
                "to": to,
                "stepIndex": step_index,
                "totalSteps": total_steps
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::PathComputed {
            actor_id,
            path_length,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "path_computed".into(),
            actor_id,
            payload: json!({ "pathLength": path_length }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::InteractionOptionsResolved {
            actor_id,
            target_id,
            option_count,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "interaction_options_resolved".into(),
            actor_id: Some(actor_id),
            target_id: Some(target_id),
            payload: json!({ "optionCount": option_count }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::InteractionApproachPlanned {
            actor_id,
            target_id,
            option_id,
            goal,
            path_length,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "interaction_approach_planned".into(),
            actor_id: Some(actor_id),
            target_id: Some(target_id),
            payload: json!({
                "optionId": option_id,
                "goal": goal,
                "pathLength": path_length
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::InteractionStarted {
            actor_id,
            target_id,
            option_id,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "interaction_started".into(),
            actor_id: Some(actor_id),
            target_id: Some(target_id),
            payload: json!({ "optionId": option_id }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::InteractionSucceeded {
            actor_id,
            target_id,
            option_id,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "interaction_succeeded".into(),
            actor_id: Some(actor_id),
            target_id: Some(target_id),
            payload: json!({ "optionId": option_id }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ContainerOpened {
            actor_id,
            target_id,
            container_id,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "container_opened".into(),
            actor_id: Some(actor_id),
            target_id: Some(target_id),
            payload: json!({ "containerId": container_id }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::InteractionFailed {
            actor_id,
            target_id,
            option_id,
            reason,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "interaction_failed".into(),
            actor_id: Some(actor_id),
            target_id: Some(target_id),
            payload: json!({ "optionId": option_id, "reason": reason }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::DialogueStarted {
            actor_id,
            target_id,
            dialogue_id,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "dialogue_started".into(),
            actor_id: Some(actor_id),
            target_id: Some(target_id),
            dialogue_id: Some(dialogue_id),
            payload: json!({}),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::DialogueAdvanced {
            actor_id,
            dialogue_id,
            node_id,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "dialogue_advanced".into(),
            actor_id: Some(actor_id),
            dialogue_id: Some(dialogue_id),
            payload: json!({ "nodeId": node_id }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::SceneTransitionRequested {
            actor_id,
            option_id,
            target_id,
            world_mode,
            location_id,
            entry_point_id,
            return_location_id,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "scene_transition_requested".into(),
            actor_id: Some(actor_id),
            map_id: Some(target_id.clone()),
            payload: json!({
                "optionId": option_id,
                "targetId": target_id,
                "worldMode": world_mode_name(world_mode),
                "locationId": location_id,
                "entryPointId": entry_point_id,
                "returnLocationId": return_location_id
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::LocationEntered {
            actor_id,
            location_id,
            map_id,
            entry_point_id,
            world_mode,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "location_entered".into(),
            actor_id: Some(actor_id),
            map_id: Some(map_id.clone()),
            payload: json!({
                "locationId": location_id,
                "mapId": map_id,
                "entryPointId": entry_point_id,
                "worldMode": world_mode_name(world_mode)
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ReturnedToOverworld {
            actor_id,
            active_outdoor_location_id,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "returned_to_overworld".into(),
            actor_id: Some(actor_id),
            payload: json!({ "activeOutdoorLocationId": active_outdoor_location_id }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::LocationUnlocked { location_id } => RuntimeEventEnvelope {
            sequence,
            event_type: "location_unlocked".into(),
            payload: json!({ "locationId": location_id }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::PickupGranted {
            actor_id,
            target_id,
            item_id,
            count,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "pickup_granted".into(),
            actor_id: Some(actor_id),
            target_id: Some(target_id),
            payload: json!({ "itemId": item_id, "count": count }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActorDamaged {
            actor_id,
            target_actor,
            damage,
            remaining_hp,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "actor_damaged".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "targetActor": target_actor,
                "damage": damage,
                "remainingHp": remaining_hp
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActorDefeated {
            actor_id,
            target_actor,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "actor_defeated".into(),
            actor_id: Some(actor_id),
            payload: json!({ "targetActor": target_actor }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::LootDropped {
            actor_id,
            target_actor,
            object_id,
            item_id,
            count,
            grid,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "loot_dropped".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "targetActor": target_actor,
                "objectId": object_id,
                "itemId": item_id,
                "count": count,
                "grid": grid
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ExperienceGranted {
            actor_id,
            amount,
            total_xp,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "experience_granted".into(),
            actor_id: Some(actor_id),
            payload: json!({ "amount": amount, "totalXp": total_xp }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::ActorLeveledUp {
            actor_id,
            new_level,
            available_stat_points,
            available_skill_points,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "actor_leveled_up".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "newLevel": new_level,
                "availableStatPoints": available_stat_points,
                "availableSkillPoints": available_skill_points
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::QuestStarted { actor_id, quest_id } => RuntimeEventEnvelope {
            sequence,
            event_type: "quest_started".into(),
            actor_id: Some(actor_id),
            payload: json!({ "questId": quest_id }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::QuestObjectiveProgressed {
            actor_id,
            quest_id,
            node_id,
            current,
            target,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "quest_objective_progressed".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "questId": quest_id,
                "nodeId": node_id,
                "current": current,
                "target": target
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::QuestCompleted { actor_id, quest_id } => RuntimeEventEnvelope {
            sequence,
            event_type: "quest_completed".into(),
            actor_id: Some(actor_id),
            payload: json!({ "questId": quest_id }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::RelationChanged {
            actor_id,
            target_id,
            disposition,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "relation_changed".into(),
            actor_id: Some(actor_id),
            target_id: Some(target_id),
            payload: json!({ "disposition": disposition }),
            ..RuntimeEventEnvelope::default()
        },
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::{
        dispatch_protocol_requests, emit_runtime_protocol_events, handle_client_message,
        handle_client_message_with_definitions, RuntimeProtocolPushState, RuntimeProtocolSequence,
        RuntimeSnapshotStore, ServerProtocolDefinitions, ServerProtocolRequest,
        ServerProtocolResponse,
    };
    use crate::config::{ServerSimulationRuntime, ServerStartupState};
    use bevy_app::{App, Update};
    use bevy_ecs::message::MessageReader;
    use bevy_ecs::prelude::*;
    use game_core::{RegisterActor, Simulation, SimulationEvent, SimulationRuntime};
    use game_data::{
        ActorKind, ActorSide, CharacterId, DialogueAction, DialogueData, DialogueLibrary,
        DialogueNode, DialogueOption, GridCoord, InteractionExecutionRequest, InteractionOptionId,
        InteractionTargetId, ItemDefinition, ItemFragment, ItemLibrary, MapDefinition,
        MapEntryPointDefinition, MapId, MapLevelDefinition, MapLibrary, MapSize, QuestConnection,
        QuestDefinition, QuestFlow, QuestLibrary, QuestNode, RecipeDefinition, RecipeLibrary,
        RecipeMaterial, RecipeOutput, ShopDefinition, ShopInventoryEntry, ShopLibrary,
        SkillDefinition, SkillLibrary, WorldMode,
    };
    use game_protocol::{
        BuyItemRequest, ClientMessage, CraftRecipeRequest, DialogueAdvanceRequest,
        EquipItemRequest, LearnSkillRequest, MapTravelRequest, ReloadEquippedWeaponRequest,
        RuntimeSnapshotLoadRequest, RuntimeSnapshotSaveRequest, SellItemRequest, ServerMessage,
        StartQuestRequest, UnequipItemRequest,
    };

    fn sample_runtime_with_player_and_npc() -> (
        ServerSimulationRuntime,
        game_data::ActorId,
        game_data::ActorId,
    ) {
        let mut simulation = Simulation::new();
        simulation.set_dialogue_library(sample_dialogue_library());
        let player = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let npc = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("trader_lao_wang".into())),
            display_name: "Trader".into(),
            kind: ActorKind::Npc,
            side: ActorSide::Friendly,
            group_id: "friendly".into(),
            grid_position: GridCoord::new(1, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        (
            ServerSimulationRuntime(SimulationRuntime::from_simulation(simulation)),
            player,
            npc,
        )
    }

    fn advance_runtime_turn(runtime: &mut ServerSimulationRuntime) {
        while runtime.0.has_pending_progression() {
            runtime.0.advance_pending_progression();
        }
    }

    fn sample_runtime_with_map() -> (ServerSimulationRuntime, game_data::ActorId) {
        let mut simulation = Simulation::new();
        simulation.set_map_library(sample_map_library());
        let actor_id = simulation.register_actor(RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        let mut runtime = ServerSimulationRuntime(SimulationRuntime::from_simulation(simulation));
        runtime.0.drain_events();
        (runtime, actor_id)
    }

    #[test]
    fn protocol_snapshot_store_save_and_load_round_trip() {
        let (mut runtime, _, _) = sample_runtime_with_player_and_npc();
        runtime.0.tick();

        let mut store = RuntimeSnapshotStore::default();
        let save = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::RequestRuntimeSnapshotSave(RuntimeSnapshotSaveRequest {
                snapshot_id: Some("slot_alpha".into()),
            }),
        )
        .expect("snapshot save should succeed");

        let saved_payload = match save {
            ServerMessage::RuntimeSnapshotSaved(payload) => payload,
            other => panic!("unexpected server message: {other:?}"),
        };
        assert_eq!(saved_payload.snapshot_id.as_deref(), Some("slot_alpha"));
        assert!(store.has_snapshot("slot_alpha"));
        assert_eq!(runtime.0.tick_count(), 1);

        runtime.0.tick();
        assert_eq!(runtime.0.tick_count(), 2);

        let load = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::RequestRuntimeSnapshotLoad(RuntimeSnapshotLoadRequest {
                snapshot_id: Some("slot_alpha".into()),
                snapshot: None,
            }),
        )
        .expect("snapshot load should succeed");

        match load {
            ServerMessage::RuntimeSnapshotLoaded(payload) => {
                assert_eq!(payload.snapshot_id.as_deref(), Some("slot_alpha"));
            }
            other => panic!("unexpected server message: {other:?}"),
        }
        assert_eq!(runtime.0.tick_count(), 1);
    }

    #[test]
    fn protocol_query_and_execute_interaction_path() {
        let (mut runtime, player, npc) = sample_runtime_with_player_and_npc();
        let mut store = RuntimeSnapshotStore::default();

        let query = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::QueryInteractionOptions {
                actor_id: player,
                target_id: InteractionTargetId::Actor(npc),
            },
        )
        .expect("query interaction options should succeed");

        match query {
            ServerMessage::InteractionPrompt(prompt) => {
                assert!(
                    prompt
                        .options
                        .iter()
                        .any(|option| option.id.as_str() == "talk"),
                    "expected talk option in prompt"
                );
            }
            other => panic!("unexpected server message: {other:?}"),
        }

        let execute = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::ExecuteInteraction(InteractionExecutionRequest {
                actor_id: player,
                target_id: InteractionTargetId::Actor(npc),
                option_id: InteractionOptionId("talk".into()),
            }),
        )
        .expect("execute interaction should succeed");

        match execute {
            ServerMessage::InteractionExecution(result) => {
                assert!(result.success);
                assert_eq!(result.dialogue_id.as_deref(), Some("trader_lao_wang"));
                assert_eq!(
                    result
                        .dialogue_state
                        .as_ref()
                        .and_then(|state| state.current_node.as_ref())
                        .map(|node| node.id.as_str()),
                    Some("start")
                );
            }
            other => panic!("unexpected server message: {other:?}"),
        }
    }

    #[test]
    fn protocol_advance_dialogue_returns_authoritative_state() {
        let (mut runtime, player, npc) = sample_runtime_with_player_and_npc();
        let mut store = RuntimeSnapshotStore::default();

        let opened = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::ExecuteInteraction(InteractionExecutionRequest {
                actor_id: player,
                target_id: InteractionTargetId::Actor(npc),
                option_id: InteractionOptionId("talk".into()),
            }),
        )
        .expect("execute interaction should succeed");
        assert!(matches!(opened, ServerMessage::InteractionExecution(_)));

        let advanced = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::AdvanceDialogue(DialogueAdvanceRequest {
                actor_id: player,
                target_id: Some(InteractionTargetId::Actor(npc)),
                dialogue_id: "trader_lao_wang".into(),
                option_id: None,
                option_index: None,
            }),
        )
        .expect("dialogue advance should succeed");

        match advanced {
            ServerMessage::DialogueState(state) => {
                assert_eq!(
                    state.current_node.as_ref().map(|node| node.id.as_str()),
                    Some("choice_1")
                );
                assert_eq!(state.available_options.len(), 2);
            }
            other => panic!("unexpected server message: {other:?}"),
        }
    }

    #[derive(Resource, Debug, Default)]
    struct CapturedResponses(Vec<ServerProtocolResponse>);

    #[test]
    fn protocol_dispatch_system_processes_in_process_requests() {
        let (runtime, _, _) = sample_runtime_with_player_and_npc();
        let mut app = App::new();
        app.insert_resource(runtime);
        app.insert_resource(ServerStartupState::Ready);
        app.insert_resource(RuntimeSnapshotStore::default());
        app.insert_resource(RuntimeProtocolPushState::default());
        app.insert_resource(RuntimeProtocolSequence::default());
        app.insert_resource(CapturedResponses::default());
        app.add_message::<ServerProtocolRequest>();
        app.add_message::<ServerProtocolResponse>();
        app.add_systems(
            Update,
            (dispatch_protocol_requests, capture_protocol_responses).chain(),
        );

        app.world_mut().write_message(ServerProtocolRequest {
            message: ClientMessage::RequestRuntimeSnapshotSave(RuntimeSnapshotSaveRequest {
                snapshot_id: Some("slot_beta".into()),
            }),
        });

        app.update();

        let captured = app.world().resource::<CapturedResponses>();
        assert_eq!(captured.0.len(), 1);
        match &captured.0[0].message {
            Ok(ServerMessage::RuntimeSnapshotSaved(payload)) => {
                assert_eq!(payload.snapshot_id.as_deref(), Some("slot_beta"));
            }
            other => panic!("unexpected protocol response: {other:?}"),
        }
    }

    #[test]
    fn protocol_dispatch_system_drains_pending_progression_after_interaction() {
        let (runtime, player, npc) = sample_runtime_with_player_and_npc();
        let mut app = App::new();
        app.insert_resource(runtime);
        app.insert_resource(ServerStartupState::Ready);
        app.insert_resource(RuntimeSnapshotStore::default());
        app.insert_resource(RuntimeProtocolPushState::default());
        app.insert_resource(RuntimeProtocolSequence::default());
        app.insert_resource(CapturedResponses::default());
        app.add_message::<ServerProtocolRequest>();
        app.add_message::<ServerProtocolResponse>();
        app.add_systems(
            Update,
            (dispatch_protocol_requests, capture_protocol_responses).chain(),
        );

        app.world_mut().write_message(ServerProtocolRequest {
            message: ClientMessage::ExecuteInteraction(InteractionExecutionRequest {
                actor_id: player,
                target_id: InteractionTargetId::Actor(npc),
                option_id: InteractionOptionId("talk".into()),
            }),
        });

        app.update();

        let captured = app.world().resource::<CapturedResponses>();
        assert_eq!(captured.0.len(), 1);
        match &captured.0[0].message {
            Ok(ServerMessage::InteractionExecution(result)) => assert!(result.success),
            other => panic!("unexpected protocol response: {other:?}"),
        }

        let runtime = app.world().resource::<ServerSimulationRuntime>();
        assert!(!runtime.0.has_pending_progression());
        assert!(runtime.0.actor_turn_open(player));
        assert_eq!(runtime.0.get_actor_ap(player), 1.0);
    }

    #[test]
    fn protocol_supports_runtime_snapshot_and_map_travel_requests() {
        let (mut runtime, actor_id) = sample_runtime_with_map();
        let mut store = RuntimeSnapshotStore::default();

        let subscribed = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::SubscribeRuntime(Default::default()),
        )
        .expect("subscribe runtime should succeed");
        match subscribed {
            ServerMessage::Snapshot(snapshot) => {
                assert_eq!(snapshot.sequence, 0);
                assert_eq!(snapshot.active_map_id.as_deref(), None);
            }
            other => panic!("unexpected server message: {other:?}"),
        }

        let traveled = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::TravelToMap(MapTravelRequest {
                actor_id,
                target_map_id: "protocol_test_map".into(),
                entry_point: Some("default_entry".into()),
                world_mode: Some("interior".into()),
            }),
        )
        .expect("travel to map should succeed");
        match traveled {
            ServerMessage::SceneTransitionRequested(notice) => {
                assert_eq!(notice.target_map_id, "protocol_test_map");
                assert_eq!(notice.entry_point.as_deref(), Some("default_entry"));
                assert_eq!(notice.world_mode.as_deref(), Some("interior"));
            }
            other => panic!("unexpected server message: {other:?}"),
        }

        runtime.0.set_actor_vision_radius(actor_id, 10);
        let vision = runtime
            .0
            .refresh_actor_vision(actor_id)
            .expect("vision should refresh after map travel");
        assert_eq!(
            vision.active_map_id.as_ref().map(game_data::MapId::as_str),
            Some("protocol_test_map")
        );

        let subscribed_after_travel = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::SubscribeRuntime(Default::default()),
        )
        .expect("subscribe runtime should include vision snapshot");
        match subscribed_after_travel {
            ServerMessage::Snapshot(snapshot) => {
                let vision_state = snapshot.vision_state.expect("vision snapshot should exist");
                assert_eq!(vision_state.actors.len(), 1);
                assert_eq!(
                    vision_state.actors[0]
                        .active_map_id
                        .as_ref()
                        .map(game_data::MapId::as_str),
                    Some("protocol_test_map")
                );
                assert!(!vision_state.actors[0].visible_cells.is_empty());
            }
            other => panic!("unexpected server message: {other:?}"),
        }

        let overworld = handle_client_message(
            &mut runtime,
            &mut store,
            ClientMessage::RequestOverworldSnapshot,
        )
        .expect("overworld snapshot should succeed");
        match overworld {
            ServerMessage::OverworldState(state) => {
                assert_eq!(state.current_map_id.as_deref(), Some("protocol_test_map"));
                assert_eq!(state.world_mode, WorldMode::Interior);
            }
            other => panic!("unexpected server message: {other:?}"),
        }
    }

    #[test]
    fn protocol_pushes_runtime_deltas_after_subscription() {
        let (mut runtime, actor_id, _) = sample_runtime_with_player_and_npc();
        runtime.0.drain_events();

        let mut app = App::new();
        app.insert_resource(runtime);
        app.insert_resource(RuntimeProtocolPushState { subscribed: true });
        app.insert_resource(RuntimeProtocolSequence::default());
        app.insert_resource(CapturedResponses::default());
        app.add_message::<ServerProtocolResponse>();
        app.add_systems(
            Update,
            (emit_runtime_protocol_events, capture_protocol_responses).chain(),
        );

        app.world_mut()
            .resource_mut::<ServerSimulationRuntime>()
            .0
            .push_event(SimulationEvent::DialogueAdvanced {
                actor_id,
                dialogue_id: "trader_lao_wang".into(),
                node_id: "choice_1".into(),
            });

        app.update();

        let captured = app.world().resource::<CapturedResponses>();
        assert_eq!(captured.0.len(), 1);
        match &captured.0[0].message {
            Ok(ServerMessage::Delta(delta)) => {
                assert_eq!(delta.sequence, 1);
                assert_eq!(delta.event_type, "dialogue_advanced");
                assert_eq!(delta.dialogue_id.as_deref(), Some("trader_lao_wang"));
            }
            other => panic!("unexpected protocol response: {other:?}"),
        }
    }

    #[test]
    fn protocol_handles_economy_and_quest_requests() {
        let (mut runtime, player, _) = sample_runtime_with_player_and_npc();
        let items = sample_item_library();
        let skills = sample_skill_library();
        let recipes = sample_recipe_library();
        let shops = sample_shop_library();
        let quests = sample_quest_library();
        runtime.0.set_item_library(items.clone());
        runtime.0.set_skill_library(skills.clone());
        runtime.0.set_recipe_library(recipes.clone());
        runtime.0.set_shop_library(shops.clone());
        runtime.0.set_quest_library(quests);
        runtime.0.economy_mut().set_actor_level(player, 8);
        runtime
            .0
            .economy_mut()
            .set_actor_attribute(player, "intelligence", 3);
        runtime
            .0
            .economy_mut()
            .add_skill_points(player, 1)
            .expect("skill points should be granted");
        runtime
            .0
            .economy_mut()
            .add_item(player, 1001, 2, &items)
            .expect("materials should be granted");
        runtime
            .0
            .economy_mut()
            .add_item(player, 1002, 1, &items)
            .expect("tool should be granted");
        runtime
            .0
            .economy_mut()
            .grant_station_tag(player, "workbench")
            .expect("station tag should be granted");
        runtime
            .0
            .economy_mut()
            .grant_money(player, 100)
            .expect("money should be granted");
        runtime
            .0
            .economy_mut()
            .add_item(player, 1004, 1, &items)
            .expect("weapon should be granted");
        runtime
            .0
            .economy_mut()
            .add_ammo(player, 1009, 12, &items)
            .expect("ammo should be granted");

        let defs = ServerProtocolDefinitions {
            items: Some(&items),
            skills: Some(&skills),
            recipes: Some(&recipes),
            shops: Some(&shops),
        };
        let mut store = RuntimeSnapshotStore::default();

        let equip = handle_client_message_with_definitions(
            &mut runtime,
            &mut store,
            defs,
            ClientMessage::RequestEquipItem(EquipItemRequest {
                actor_id: player,
                item_id: 1004,
                target_slot: Some("main_hand".into()),
            }),
        )
        .expect("equip should succeed");
        assert!(matches!(equip, ServerMessage::ItemEquipped(_)));
        advance_runtime_turn(&mut runtime);

        let reload = handle_client_message_with_definitions(
            &mut runtime,
            &mut store,
            defs,
            ClientMessage::RequestReloadEquippedWeapon(ReloadEquippedWeaponRequest {
                actor_id: player,
                slot: "main_hand".into(),
            }),
        )
        .expect("reload should succeed");
        match reload {
            ServerMessage::WeaponReloaded(payload) => assert_eq!(payload.ammo_loaded, 6),
            other => panic!("unexpected server message: {other:?}"),
        }
        advance_runtime_turn(&mut runtime);

        let learn = handle_client_message_with_definitions(
            &mut runtime,
            &mut store,
            defs,
            ClientMessage::RequestLearnSkill(LearnSkillRequest {
                actor_id: player,
                skill_id: "crafting_basics".into(),
            }),
        )
        .expect("learn skill should succeed");
        match learn {
            ServerMessage::SkillLearned(payload) => assert_eq!(payload.level, 1),
            other => panic!("unexpected server message: {other:?}"),
        }
        advance_runtime_turn(&mut runtime);

        let craft = handle_client_message_with_definitions(
            &mut runtime,
            &mut store,
            defs,
            ClientMessage::RequestCraftRecipe(CraftRecipeRequest {
                actor_id: player,
                recipe_id: "bandage_recipe".into(),
            }),
        )
        .expect("craft should succeed");
        match craft {
            ServerMessage::RecipeCrafted(payload) => {
                assert_eq!(payload.output_item_id, 1003);
                assert_eq!(payload.output_count, 1);
            }
            other => panic!("unexpected server message: {other:?}"),
        }
        advance_runtime_turn(&mut runtime);

        let buy = handle_client_message_with_definitions(
            &mut runtime,
            &mut store,
            defs,
            ClientMessage::RequestBuyItem(BuyItemRequest {
                actor_id: player,
                shop_id: "survivor_outpost_01_shop".into(),
                item_id: 1031,
                count: 2,
            }),
        )
        .expect("buy should succeed");
        match buy {
            ServerMessage::ItemBought(payload) => assert_eq!(payload.total_price, 30),
            other => panic!("unexpected server message: {other:?}"),
        }
        advance_runtime_turn(&mut runtime);

        let sell = handle_client_message_with_definitions(
            &mut runtime,
            &mut store,
            defs,
            ClientMessage::RequestSellItem(SellItemRequest {
                actor_id: player,
                shop_id: "survivor_outpost_01_shop".into(),
                item_id: 1031,
                count: 1,
            }),
        )
        .expect("sell should succeed");
        match sell {
            ServerMessage::ItemSold(payload) => assert_eq!(payload.total_price, 5),
            other => panic!("unexpected server message: {other:?}"),
        }
        advance_runtime_turn(&mut runtime);

        let start_quest = handle_client_message_with_definitions(
            &mut runtime,
            &mut store,
            defs,
            ClientMessage::RequestStartQuest(StartQuestRequest {
                actor_id: player,
                quest_id: "zombie_hunter".into(),
            }),
        )
        .expect("start quest should succeed");
        match start_quest {
            ServerMessage::QuestStarted(payload) => assert!(payload.started),
            other => panic!("unexpected server message: {other:?}"),
        }
        advance_runtime_turn(&mut runtime);

        let unequip = handle_client_message_with_definitions(
            &mut runtime,
            &mut store,
            defs,
            ClientMessage::RequestUnequipItem(UnequipItemRequest {
                actor_id: player,
                slot: "main_hand".into(),
            }),
        )
        .expect("unequip should succeed");
        match unequip {
            ServerMessage::ItemUnequipped(payload) => assert_eq!(payload.item_id, 1004),
            other => panic!("unexpected server message: {other:?}"),
        }
    }

    fn sample_item_library() -> ItemLibrary {
        ItemLibrary::from(BTreeMap::from([
            (
                1001,
                ItemDefinition {
                    id: 1001,
                    name: "Cloth".into(),
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 99,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1002,
                ItemDefinition {
                    id: 1002,
                    name: "Knife".into(),
                    fragments: vec![
                        ItemFragment::Stacking {
                            stackable: false,
                            max_stack: 1,
                        },
                        ItemFragment::Equip {
                            slots: vec!["main_hand".into()],
                            level_requirement: 1,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                    ],
                    ..ItemDefinition::default()
                },
            ),
            (
                1003,
                ItemDefinition {
                    id: 1003,
                    name: "Bandage".into(),
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 20,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1004,
                ItemDefinition {
                    id: 1004,
                    name: "Pistol".into(),
                    fragments: vec![
                        ItemFragment::Equip {
                            slots: vec!["main_hand".into()],
                            level_requirement: 2,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                        ItemFragment::Weapon {
                            subtype: "pistol".into(),
                            damage: 18,
                            attack_speed: 1.0,
                            range: 12,
                            stamina_cost: 2,
                            crit_chance: 0.1,
                            crit_multiplier: 1.8,
                            accuracy: Some(70),
                            ammo_type: Some(1009),
                            max_ammo: Some(6),
                            reload_time: Some(1.5),
                            on_hit_effect_ids: Vec::new(),
                        },
                    ],
                    ..ItemDefinition::default()
                },
            ),
            (
                1009,
                ItemDefinition {
                    id: 1009,
                    name: "Pistol Ammo".into(),
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 50,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1031,
                ItemDefinition {
                    id: 1031,
                    name: "Antibiotics".into(),
                    value: 10,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 10,
                    }],
                    ..ItemDefinition::default()
                },
            ),
        ]))
    }

    fn sample_map_library() -> MapLibrary {
        MapLibrary::from(BTreeMap::from([(
            MapId("protocol_test_map".into()),
            MapDefinition {
                id: MapId("protocol_test_map".into()),
                name: "Protocol Test Map".into(),
                size: MapSize {
                    width: 8,
                    height: 8,
                },
                default_level: 0,
                levels: vec![MapLevelDefinition {
                    y: 0,
                    cells: Vec::new(),
                }],
                entry_points: vec![MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(2, 0, 3),
                    facing: None,
                    extra: BTreeMap::new(),
                }],
                objects: Vec::new(),
            },
        )]))
    }

    fn sample_skill_library() -> SkillLibrary {
        SkillLibrary::from(BTreeMap::from([(
            "crafting_basics".into(),
            SkillDefinition {
                id: "crafting_basics".into(),
                name: "Crafting Basics".into(),
                tree_id: "survival".into(),
                max_level: 3,
                prerequisites: Vec::new(),
                attribute_requirements: BTreeMap::from([("intelligence".into(), 3)]),
                ..SkillDefinition::default()
            },
        )]))
    }

    fn sample_recipe_library() -> RecipeLibrary {
        RecipeLibrary::from(BTreeMap::from([(
            "bandage_recipe".into(),
            RecipeDefinition {
                id: "bandage_recipe".into(),
                name: "Craft Bandage".into(),
                output: RecipeOutput {
                    item_id: 1003,
                    count: 1,
                    quality_bonus: 0,
                    extra: BTreeMap::new(),
                },
                materials: vec![RecipeMaterial {
                    item_id: 1001,
                    count: 2,
                    extra: BTreeMap::new(),
                }],
                required_tools: vec!["1002".into()],
                required_station: "workbench".into(),
                skill_requirements: BTreeMap::from([("crafting_basics".into(), 1)]),
                is_default_unlocked: true,
                ..RecipeDefinition::default()
            },
        )]))
    }

    fn sample_shop_library() -> ShopLibrary {
        ShopLibrary::from(BTreeMap::from([(
            "survivor_outpost_01_shop".into(),
            ShopDefinition {
                id: "survivor_outpost_01_shop".into(),
                buy_price_modifier: 1.5,
                sell_price_modifier: 0.5,
                money: 100,
                inventory: vec![ShopInventoryEntry {
                    item_id: 1031,
                    count: 3,
                    price: 15,
                }],
            },
        )]))
    }

    fn sample_quest_library() -> QuestLibrary {
        QuestLibrary::from(BTreeMap::from([(
            "zombie_hunter".into(),
            QuestDefinition {
                quest_id: "zombie_hunter".into(),
                title: "Zombie Hunter".into(),
                description: "Defeat one zombie".into(),
                flow: QuestFlow {
                    start_node_id: "start".into(),
                    nodes: BTreeMap::from([
                        (
                            "start".into(),
                            QuestNode {
                                id: "start".into(),
                                node_type: "start".into(),
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "end".into(),
                            QuestNode {
                                id: "end".into(),
                                node_type: "end".into(),
                                ..QuestNode::default()
                            },
                        ),
                    ]),
                    connections: vec![QuestConnection {
                        from: "start".into(),
                        to: "end".into(),
                        from_port: 0,
                        to_port: 0,
                        extra: BTreeMap::new(),
                    }],
                    ..QuestFlow::default()
                },
                ..QuestDefinition::default()
            },
        )]))
    }

    fn sample_dialogue_library() -> DialogueLibrary {
        DialogueLibrary::from(BTreeMap::from([(
            "trader_lao_wang".into(),
            DialogueData {
                dialog_id: "trader_lao_wang".into(),
                nodes: vec![
                    DialogueNode {
                        id: "start".into(),
                        node_type: "dialog".into(),
                        is_start: true,
                        next: "choice_1".into(),
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "choice_1".into(),
                        node_type: "choice".into(),
                        options: vec![
                            DialogueOption {
                                text: "Trade".into(),
                                next: "trade_action".into(),
                                ..DialogueOption::default()
                            },
                            DialogueOption {
                                text: "Leave".into(),
                                next: "leave_end".into(),
                                ..DialogueOption::default()
                            },
                        ],
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "trade_action".into(),
                        node_type: "action".into(),
                        actions: vec![DialogueAction {
                            action_type: "open_trade".into(),
                            extra: BTreeMap::new(),
                        }],
                        next: "trade_end".into(),
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "trade_end".into(),
                        node_type: "end".into(),
                        end_type: "trade".into(),
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "leave_end".into(),
                        node_type: "end".into(),
                        end_type: "leave".into(),
                        ..DialogueNode::default()
                    },
                ],
                ..DialogueData::default()
            },
        )]))
    }

    fn capture_protocol_responses(
        mut reader: MessageReader<ServerProtocolResponse>,
        mut captured: ResMut<CapturedResponses>,
    ) {
        captured.0.extend(reader.read().cloned());
    }
}
