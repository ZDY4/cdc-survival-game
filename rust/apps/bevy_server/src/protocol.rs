use std::collections::BTreeMap;

use bevy_ecs::message::{MessageReader, MessageWriter};
use bevy_ecs::prelude::{Message, Res, ResMut, Resource};
use game_bevy::{ItemDefinitions, RecipeDefinitions, ShopDefinitions, SkillDefinitions};
use game_core::{
    action_result_status, EconomyRuntimeError, RuntimeSnapshot, SimulationCommand,
    SimulationCommandResult, SimulationEvent,
};
use game_data::{
    InteractionExecutionRequest, ItemLibrary, RecipeLibrary, ShopLibrary, SkillLibrary,
    WorldMode,
};
use game_protocol::{
    ActorSnapshot, AdvanceOverworldTravelRequest, BuyItemRequest, ClientMessage,
    CraftRecipeRequest, DialogueAdvanceRequest, EnterLocationRequest, EquipItemRequest,
    ItemEquippedPayload, ItemUnequippedPayload, LearnSkillRequest, MapTravelRequest,
    OverworldRouteRequest, ProtocolError, QuestStartedPayload, RecipeCraftedPayload,
    ReloadEquippedWeaponRequest, ReturnToOverworldRequest, RuntimeEventEnvelope,
    RuntimeSnapshotLoadRequest, RuntimeSnapshotPayload, RuntimeSnapshotSaveRequest,
    SceneTransitionNotice, SellItemRequest, ServerMessage, SkillLearnedPayload,
    StartQuestRequest, TradeResolvedPayload, UnequipItemRequest, WeaponReloadedPayload,
    WorldSnapshotEnvelope,
};
use serde_json::json;

use crate::config::ServerSimulationRuntime;

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
        ClientMessage::SubscribeRuntime(_request) => {
            Ok(ServerMessage::Snapshot(runtime_snapshot_envelope(runtime, 0)))
        }
        ClientMessage::RequestOverworldSnapshot => {
            Ok(ServerMessage::OverworldState(runtime.0.snapshot().overworld))
        }
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
        ClientMessage::RequestOverworldRoute(request) => request_overworld_route(runtime, request),
        ClientMessage::StartOverworldTravel(request) => start_overworld_travel(runtime, request),
        ClientMessage::AdvanceOverworldTravel(request) => {
            advance_overworld_travel(runtime, request)
        }
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
        if matches!(request.message, ClientMessage::SubscribeRuntime(_)) {
            push_state.subscribed = true;
        }
        let message = handle_client_message_with_definitions(
            &mut runtime,
            &mut snapshots,
            definitions,
            request.message.clone(),
        );
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
            eprintln!(
                "bevy_server protocol error code={} retryable={} message={}",
                error.code, error.retryable, error.message
            );
        }
    }
}

fn world_snapshot_message(runtime: &ServerSimulationRuntime) -> ServerMessage {
    let snapshot = runtime.0.snapshot();
    let actors = snapshot
        .actors
        .into_iter()
        .map(|actor| ActorSnapshot {
            actor_id: actor.actor_id,
            kind: actor.kind,
            position: runtime.0.grid_to_world(actor.grid_position),
        })
        .collect::<Vec<_>>();
    ServerMessage::WorldSnapshot {
        actors,
        turn_state: snapshot.turn,
    }
}

fn runtime_snapshot_envelope(
    runtime: &ServerSimulationRuntime,
    sequence: u64,
) -> WorldSnapshotEnvelope {
    let snapshot = runtime.0.snapshot();
    let overworld = snapshot.overworld.clone();
    let actors = snapshot
        .actors
        .into_iter()
        .map(|actor| ActorSnapshot {
            actor_id: actor.actor_id,
            kind: actor.kind,
            position: runtime.0.grid_to_world(actor.grid_position),
        })
        .collect::<Vec<_>>();
    WorldSnapshotEnvelope {
        sequence,
        actors,
        turn_state: snapshot.turn,
        interaction_context: Some(snapshot.interaction_context),
        active_map_id: snapshot.grid.map_id.map(|value| value.as_str().to_string()),
        active_location_id: overworld.active_location_id.clone(),
        overworld_state: Some(overworld),
    }
}

fn next_sequence(sequence: &mut RuntimeProtocolSequence) -> u64 {
    sequence.next = sequence.next.saturating_add(1);
    sequence.next
}

fn equip_item(
    runtime: &mut ServerSimulationRuntime,
    definitions: ServerProtocolDefinitions<'_>,
    request: EquipItemRequest,
) -> Result<ServerMessage, ProtocolError> {
    let items = require_items(definitions)?;
    let replaced_item_id = runtime
        .0
        .equip_item(
            request.actor_id,
            request.item_id,
            request.target_slot.as_deref(),
            items,
        )
        .map_err(|error| economy_protocol_error("equip_item", error))?;
    Ok(ServerMessage::ItemEquipped(ItemEquippedPayload {
        actor_id: request.actor_id,
        item_id: request.item_id,
        slot: request.target_slot,
        replaced_item_id,
    }))
}

fn unequip_item(
    runtime: &mut ServerSimulationRuntime,
    request: UnequipItemRequest,
) -> Result<ServerMessage, ProtocolError> {
    let item_id = runtime
        .0
        .unequip_item(request.actor_id, &request.slot)
        .map_err(|error| economy_protocol_error("unequip_item", error))?;
    Ok(ServerMessage::ItemUnequipped(ItemUnequippedPayload {
        actor_id: request.actor_id,
        slot: request.slot,
        item_id,
    }))
}

fn reload_equipped_weapon(
    runtime: &mut ServerSimulationRuntime,
    definitions: ServerProtocolDefinitions<'_>,
    request: ReloadEquippedWeaponRequest,
) -> Result<ServerMessage, ProtocolError> {
    let items = require_items(definitions)?;
    let ammo_loaded = runtime
        .0
        .reload_equipped_weapon(request.actor_id, &request.slot, items)
        .map_err(|error| economy_protocol_error("reload_equipped_weapon", error))?;
    Ok(ServerMessage::WeaponReloaded(WeaponReloadedPayload {
        actor_id: request.actor_id,
        slot: request.slot,
        ammo_loaded,
    }))
}

fn learn_skill(
    runtime: &mut ServerSimulationRuntime,
    definitions: ServerProtocolDefinitions<'_>,
    request: LearnSkillRequest,
) -> Result<ServerMessage, ProtocolError> {
    let skills = require_skills(definitions)?;
    let level = runtime
        .0
        .learn_skill(request.actor_id, &request.skill_id, skills)
        .map_err(|error| economy_protocol_error("learn_skill", error))?;
    Ok(ServerMessage::SkillLearned(SkillLearnedPayload {
        actor_id: request.actor_id,
        skill_id: request.skill_id,
        level,
    }))
}

fn craft_recipe(
    runtime: &mut ServerSimulationRuntime,
    definitions: ServerProtocolDefinitions<'_>,
    request: CraftRecipeRequest,
) -> Result<ServerMessage, ProtocolError> {
    let recipes = require_recipes(definitions)?;
    let items = require_items(definitions)?;
    let outcome = runtime
        .0
        .craft_recipe(request.actor_id, &request.recipe_id, recipes, items)
        .map_err(|error| economy_protocol_error("craft_recipe", error))?;
    Ok(ServerMessage::RecipeCrafted(RecipeCraftedPayload {
        actor_id: request.actor_id,
        recipe_id: outcome.recipe_id,
        output_item_id: outcome.output_item_id,
        output_count: outcome.output_count,
    }))
}

fn buy_item(
    runtime: &mut ServerSimulationRuntime,
    definitions: ServerProtocolDefinitions<'_>,
    request: BuyItemRequest,
) -> Result<ServerMessage, ProtocolError> {
    let items = require_items(definitions)?;
    let _shops = require_shops(definitions)?;
    let outcome = runtime
        .0
        .buy_item_from_shop(
            request.actor_id,
            &request.shop_id,
            request.item_id,
            request.count,
            items,
        )
        .map_err(|error| economy_protocol_error("buy_item", error))?;
    Ok(ServerMessage::ItemBought(TradeResolvedPayload {
        actor_id: request.actor_id,
        shop_id: outcome.shop_id,
        item_id: outcome.item_id,
        count: outcome.count,
        total_price: outcome.total_price,
    }))
}

fn sell_item(
    runtime: &mut ServerSimulationRuntime,
    definitions: ServerProtocolDefinitions<'_>,
    request: SellItemRequest,
) -> Result<ServerMessage, ProtocolError> {
    let items = require_items(definitions)?;
    let _shops = require_shops(definitions)?;
    let outcome = runtime
        .0
        .sell_item_to_shop(
            request.actor_id,
            &request.shop_id,
            request.item_id,
            request.count,
            items,
        )
        .map_err(|error| economy_protocol_error("sell_item", error))?;
    Ok(ServerMessage::ItemSold(TradeResolvedPayload {
        actor_id: request.actor_id,
        shop_id: outcome.shop_id,
        item_id: outcome.item_id,
        count: outcome.count,
        total_price: outcome.total_price,
    }))
}

fn start_quest(
    runtime: &mut ServerSimulationRuntime,
    request: StartQuestRequest,
) -> Result<ServerMessage, ProtocolError> {
    let started = runtime.0.start_quest(request.actor_id, &request.quest_id);
    Ok(ServerMessage::QuestStarted(QuestStartedPayload {
        actor_id: request.actor_id,
        quest_id: request.quest_id,
        started,
    }))
}

fn execute_interaction(
    runtime: &mut ServerSimulationRuntime,
    request: InteractionExecutionRequest,
) -> Result<ServerMessage, ProtocolError> {
    let result = runtime
        .0
        .submit_command(SimulationCommand::ExecuteInteraction(request));
    match result {
        SimulationCommandResult::InteractionExecution(execution) => {
            Ok(ServerMessage::InteractionExecution(execution))
        }
        SimulationCommandResult::Action(action) => Err(protocol_error(
            "interaction_execution_failed",
            format!(
                "interaction resolved as action: {}",
                action_result_status(&action)
            ),
            false,
        )),
        other => Err(protocol_error(
            "interaction_execution_unavailable",
            format!("expected interaction execution result, got {:?}", other),
            false,
        )),
    }
}

fn advance_dialogue(
    runtime: &mut ServerSimulationRuntime,
    request: DialogueAdvanceRequest,
) -> Result<ServerMessage, ProtocolError> {
    let state = runtime
        .0
        .advance_dialogue(
            request.actor_id,
            request.target_id,
            &request.dialogue_id,
            request.option_id.as_deref(),
            request.option_index,
        )
        .map_err(|error| runtime_protocol_error("dialogue_advance", error))?;
    Ok(ServerMessage::DialogueState(state))
}

fn request_overworld_route(
    runtime: &mut ServerSimulationRuntime,
    request: OverworldRouteRequest,
) -> Result<ServerMessage, ProtocolError> {
    let route = runtime
        .0
        .request_overworld_route(request.actor_id, &request.target_location_id)
        .map_err(|error| runtime_protocol_error("overworld_route", error))?;
    Ok(ServerMessage::OverworldRouteComputed(route))
}

fn start_overworld_travel(
    runtime: &mut ServerSimulationRuntime,
    request: OverworldRouteRequest,
) -> Result<ServerMessage, ProtocolError> {
    let state = runtime
        .0
        .start_overworld_travel(request.actor_id, &request.target_location_id)
        .map_err(|error| runtime_protocol_error("overworld_travel_start", error))?;
    Ok(ServerMessage::OverworldState(state))
}

fn advance_overworld_travel(
    runtime: &mut ServerSimulationRuntime,
    request: AdvanceOverworldTravelRequest,
) -> Result<ServerMessage, ProtocolError> {
    let state = runtime
        .0
        .advance_overworld_travel(request.actor_id, request.minutes)
        .map_err(|error| runtime_protocol_error("overworld_travel_advance", error))?;
    Ok(ServerMessage::OverworldState(state))
}

fn travel_to_map(
    runtime: &mut ServerSimulationRuntime,
    request: MapTravelRequest,
) -> Result<ServerMessage, ProtocolError> {
    let requested_world_mode = parse_world_mode(
        request.world_mode.as_deref(),
        WorldMode::Interior,
        "travel_to_map",
    )?;
    let context = runtime
        .0
        .travel_to_map(
            request.actor_id,
            &request.target_map_id,
            request.entry_point.as_deref(),
            requested_world_mode,
        )
        .map_err(|error| runtime_protocol_error("travel_to_map", error))?;
    Ok(ServerMessage::SceneTransitionRequested(SceneTransitionNotice {
        actor_id: request.actor_id,
        target_map_id: context
            .current_map_id
            .clone()
            .unwrap_or(request.target_map_id),
        entry_point: context.entry_point_id.clone(),
        location_id: context.active_location_id.clone(),
        entry_point_id: context.entry_point_id,
        return_location_id: context.return_outdoor_location_id.clone(),
        world_mode: Some(world_mode_name(context.world_mode).to_string()),
    }))
}

fn enter_location(
    runtime: &mut ServerSimulationRuntime,
    request: EnterLocationRequest,
) -> Result<ServerMessage, ProtocolError> {
    let transition = runtime
        .0
        .enter_location(
            request.actor_id,
            &request.location_id,
            request.entry_point_id.as_deref(),
        )
        .map_err(|error| runtime_protocol_error("enter_location", error))?;
    Ok(ServerMessage::LocationTransition(transition))
}

fn return_to_overworld(
    runtime: &mut ServerSimulationRuntime,
    request: ReturnToOverworldRequest,
) -> Result<ServerMessage, ProtocolError> {
    let state = runtime
        .0
        .return_to_overworld(request.actor_id)
        .map_err(|error| runtime_protocol_error("return_to_overworld", error))?;
    Ok(ServerMessage::OverworldState(state))
}

fn save_runtime_snapshot(
    runtime: &mut ServerSimulationRuntime,
    snapshots: &mut RuntimeSnapshotStore,
    request: RuntimeSnapshotSaveRequest,
) -> Result<ServerMessage, ProtocolError> {
    let snapshot = runtime.0.save_snapshot();
    let payload = snapshots.save(request.snapshot_id, snapshot)?;
    Ok(ServerMessage::RuntimeSnapshotSaved(payload))
}

fn load_runtime_snapshot(
    runtime: &mut ServerSimulationRuntime,
    snapshots: &mut RuntimeSnapshotStore,
    request: RuntimeSnapshotLoadRequest,
) -> Result<ServerMessage, ProtocolError> {
    let (snapshot_id, snapshot) = resolve_runtime_snapshot_to_load(snapshots, request)?;
    runtime
        .0
        .load_snapshot(snapshot.clone())
        .map_err(|error| runtime_protocol_error("runtime_snapshot_load", error))?;
    let payload = snapshot_payload(snapshot_id, snapshot)?;
    Ok(ServerMessage::RuntimeSnapshotLoaded(payload))
}

fn resolve_runtime_snapshot_to_load(
    snapshots: &mut RuntimeSnapshotStore,
    request: RuntimeSnapshotLoadRequest,
) -> Result<(Option<String>, RuntimeSnapshot), ProtocolError> {
    match request.snapshot {
        Some(raw) => {
            let snapshot: RuntimeSnapshot = serde_json::from_value(raw).map_err(|error| {
                protocol_error(
                    "runtime_snapshot_payload_invalid",
                    format!("failed to decode snapshot payload: {error}"),
                    false,
                )
            })?;
            let snapshot_id = normalize_snapshot_id(request.snapshot_id);
            if let Some(snapshot_id) = snapshot_id.as_ref() {
                snapshots
                    .snapshots
                    .insert(snapshot_id.clone(), snapshot.clone());
            }
            Ok((snapshot_id, snapshot))
        }
        None => {
            let snapshot_id = normalize_snapshot_id(request.snapshot_id).ok_or_else(|| {
                protocol_error(
                    "runtime_snapshot_missing_id",
                    "snapshot_id is required when snapshot payload is omitted",
                    false,
                )
            })?;
            let snapshot = snapshots.load(&snapshot_id).ok_or_else(|| {
                protocol_error(
                    "runtime_snapshot_not_found",
                    format!("snapshot {snapshot_id} does not exist"),
                    false,
                )
            })?;
            Ok((Some(snapshot_id), snapshot))
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

fn parse_world_mode(
    raw: Option<&str>,
    default_mode: WorldMode,
    operation: &str,
) -> Result<WorldMode, ProtocolError> {
    let Some(raw) = raw.map(str::trim).filter(|value| !value.is_empty()) else {
        return Ok(default_mode);
    };
    match raw {
        "overworld" => Ok(WorldMode::Overworld),
        "traveling" => Ok(WorldMode::Traveling),
        "outdoor" => Ok(WorldMode::Outdoor),
        "interior" => Ok(WorldMode::Interior),
        "dungeon" => Ok(WorldMode::Dungeon),
        "unknown" => Ok(WorldMode::Unknown),
        _ => Err(protocol_error(
            format!("{operation}_invalid_world_mode"),
            format!("unsupported world_mode: {raw}"),
            false,
        )),
    }
}

fn world_mode_name(world_mode: WorldMode) -> &'static str {
    match world_mode {
        WorldMode::Overworld => "overworld",
        WorldMode::Traveling => "traveling",
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
        SimulationEvent::OverworldRouteComputed {
            actor_id,
            target_location_id,
            travel_minutes,
            path_length,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "overworld_route_computed".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "targetLocationId": target_location_id,
                "travelMinutes": travel_minutes,
                "pathLength": path_length
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::OverworldTravelStarted {
            actor_id,
            target_location_id,
            travel_minutes,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "overworld_travel_started".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "targetLocationId": target_location_id,
                "travelMinutes": travel_minutes
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::OverworldTravelProgressed {
            actor_id,
            target_location_id,
            progressed_minutes,
            remaining_minutes,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "overworld_travel_progressed".into(),
            actor_id: Some(actor_id),
            payload: json!({
                "targetLocationId": target_location_id,
                "progressedMinutes": progressed_minutes,
                "remainingMinutes": remaining_minutes
            }),
            ..RuntimeEventEnvelope::default()
        },
        SimulationEvent::OverworldTravelCompleted {
            actor_id,
            target_location_id,
        } => RuntimeEventEnvelope {
            sequence,
            event_type: "overworld_travel_completed".into(),
            actor_id: Some(actor_id),
            payload: json!({ "targetLocationId": target_location_id }),
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

fn runtime_protocol_error(operation: &str, error: String) -> ProtocolError {
    let stable = stable_runtime_error_code(&error).unwrap_or("failed");
    protocol_error(format!("{operation}_{stable}"), error, false)
}

fn stable_runtime_error_code(error: &str) -> Option<&str> {
    let prefix = error.split(':').next().unwrap_or(error).trim();
    if prefix.is_empty() {
        return None;
    }
    if prefix
        .chars()
        .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_')
    {
        Some(prefix)
    } else {
        None
    }
}

fn require_items(
    definitions: ServerProtocolDefinitions<'_>,
) -> Result<&ItemLibrary, ProtocolError> {
    definitions.items.ok_or_else(|| {
        protocol_error(
            "missing_item_library",
            "server protocol handler requires item definitions for this message",
            false,
        )
    })
}

fn require_skills(
    definitions: ServerProtocolDefinitions<'_>,
) -> Result<&SkillLibrary, ProtocolError> {
    definitions.skills.ok_or_else(|| {
        protocol_error(
            "missing_skill_library",
            "server protocol handler requires skill definitions for this message",
            false,
        )
    })
}

fn require_recipes(
    definitions: ServerProtocolDefinitions<'_>,
) -> Result<&RecipeLibrary, ProtocolError> {
    definitions.recipes.ok_or_else(|| {
        protocol_error(
            "missing_recipe_library",
            "server protocol handler requires recipe definitions for this message",
            false,
        )
    })
}

fn require_shops(
    definitions: ServerProtocolDefinitions<'_>,
) -> Result<&ShopLibrary, ProtocolError> {
    definitions.shops.ok_or_else(|| {
        protocol_error(
            "missing_shop_library",
            "server protocol handler requires shop definitions for this message",
            false,
        )
    })
}

fn economy_protocol_error(operation: &str, error: EconomyRuntimeError) -> ProtocolError {
    let code = match error {
        EconomyRuntimeError::UnknownActor { .. } => "unknown_actor",
        EconomyRuntimeError::UnknownItem { .. } => "unknown_item",
        EconomyRuntimeError::UnknownSkill { .. } => "unknown_skill",
        EconomyRuntimeError::UnknownRecipe { .. } => "unknown_recipe",
        EconomyRuntimeError::UnknownShop { .. } => "unknown_shop",
        EconomyRuntimeError::InvalidCount { .. } => "invalid_count",
        EconomyRuntimeError::NotEnoughItems { .. } => "not_enough_items",
        EconomyRuntimeError::NotEnoughMoney { .. } => "not_enough_money",
        EconomyRuntimeError::ShopInventoryInsufficient { .. } => "shop_inventory_insufficient",
        EconomyRuntimeError::ShopOutOfMoney { .. } => "shop_out_of_money",
        EconomyRuntimeError::SkillPrerequisiteMissing { .. } => "skill_prerequisite_missing",
        EconomyRuntimeError::SkillAttributeRequirementMissing { .. } => {
            "skill_attribute_requirement_missing"
        }
        EconomyRuntimeError::MissingSkillPoints { .. } => "missing_skill_points",
        EconomyRuntimeError::SkillAlreadyMaxed { .. } => "skill_already_maxed",
        EconomyRuntimeError::ItemNotEquippable { .. } => "item_not_equippable",
        EconomyRuntimeError::InvalidEquipmentSlot { .. } => "invalid_equipment_slot",
        EconomyRuntimeError::ItemLevelRequirementMissing { .. } => "item_level_requirement_missing",
        EconomyRuntimeError::EmptyEquipmentSlot { .. } => "empty_equipment_slot",
        EconomyRuntimeError::ItemNotWeapon { .. } => "item_not_weapon",
        EconomyRuntimeError::WeaponDoesNotUseAmmo { .. } => "weapon_does_not_use_ammo",
        EconomyRuntimeError::NotEnoughAmmo { .. } => "not_enough_ammo",
        EconomyRuntimeError::RecipeLocked { .. } => "recipe_locked",
        EconomyRuntimeError::MissingRecipeMaterials { .. } => "missing_recipe_materials",
        EconomyRuntimeError::MissingRecipeTools { .. } => "missing_recipe_tools",
        EconomyRuntimeError::MissingRecipeSkills { .. } => "missing_recipe_skills",
        EconomyRuntimeError::MissingRecipeStation { .. } => "missing_recipe_station",
        EconomyRuntimeError::MissingRecipeUnlock { .. } => "missing_recipe_unlock",
        EconomyRuntimeError::UnsupportedRepairRecipe { .. } => "unsupported_repair_recipe",
    };
    protocol_error(format!("{operation}_{code}"), error.to_string(), false)
}

fn protocol_error(
    code: impl Into<String>,
    message: impl Into<String>,
    retryable: bool,
) -> ProtocolError {
    ProtocolError {
        code: code.into(),
        message: message.into(),
        retryable,
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::{
        dispatch_protocol_requests, emit_runtime_protocol_events, handle_client_message,
        handle_client_message_with_definitions, RuntimeProtocolPushState,
        RuntimeProtocolSequence, RuntimeSnapshotStore, ServerProtocolDefinitions,
        ServerProtocolRequest, ServerProtocolResponse,
    };
    use crate::config::ServerSimulationRuntime;
    use bevy_app::{App, Update};
    use bevy_ecs::message::MessageReader;
    use bevy_ecs::prelude::*;
    use game_core::{RegisterActor, Simulation, SimulationEvent, SimulationRuntime};
    use game_data::{
        ActorKind, ActorSide, CharacterId, DialogueAction, DialogueData, DialogueLibrary,
        DialogueNode, DialogueOption, GridCoord, InteractionExecutionRequest, InteractionOptionId,
        InteractionTargetId, ItemDefinition, ItemFragment, ItemLibrary, MapDefinition,
        MapEntryPointDefinition, MapId, MapLibrary, MapLevelDefinition, MapSize,
        QuestConnection, QuestDefinition, QuestFlow, QuestLibrary, QuestNode, RecipeDefinition,
        RecipeLibrary, RecipeMaterial, RecipeOutput, ShopDefinition, ShopInventoryEntry,
        ShopLibrary, SkillDefinition, SkillLibrary, WorldMode,
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
