use super::errors::{
    economy_protocol_error, protocol_error, require_items, require_recipes, require_shops,
    require_skills, runtime_protocol_error,
};
use super::projections::{
    protocol_location_transition, protocol_overworld_route, protocol_overworld_state,
};
use super::*;

pub(super) fn equip_item(
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

pub(super) fn unequip_item(
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

pub(super) fn reload_equipped_weapon(
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

pub(super) fn learn_skill(
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

pub(super) fn craft_recipe(
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

pub(super) fn buy_item(
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

pub(super) fn sell_item(
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

pub(super) fn start_quest(
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

pub(super) fn execute_interaction(
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

pub(super) fn advance_dialogue(
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

pub(super) fn request_overworld_route(
    runtime: &mut ServerSimulationRuntime,
    request: OverworldRouteRequest,
) -> Result<ServerMessage, ProtocolError> {
    let route = runtime
        .0
        .request_overworld_route(request.actor_id, &request.target_location_id)
        .map_err(|error| runtime_protocol_error("overworld_route", error))?;
    Ok(ServerMessage::OverworldRouteComputed(
        protocol_overworld_route(route),
    ))
}

pub(super) fn start_overworld_travel(
    runtime: &mut ServerSimulationRuntime,
    request: OverworldRouteRequest,
) -> Result<ServerMessage, ProtocolError> {
    let state = runtime
        .0
        .start_overworld_travel(request.actor_id, &request.target_location_id)
        .map_err(|error| runtime_protocol_error("overworld_travel_start", error))?;
    Ok(ServerMessage::OverworldState(protocol_overworld_state(
        state,
    )))
}

pub(super) fn advance_overworld_travel(
    runtime: &mut ServerSimulationRuntime,
    request: AdvanceOverworldTravelRequest,
) -> Result<ServerMessage, ProtocolError> {
    let state = runtime
        .0
        .advance_overworld_travel(request.actor_id, request.minutes)
        .map_err(|error| runtime_protocol_error("overworld_travel_advance", error))?;
    Ok(ServerMessage::OverworldState(protocol_overworld_state(
        state,
    )))
}

pub(super) fn travel_to_map(
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
    Ok(ServerMessage::SceneTransitionRequested(
        SceneTransitionNotice {
            actor_id: request.actor_id,
            target_map_id: context
                .current_map_id
                .clone()
                .unwrap_or(request.target_map_id),
            entry_point: context.entry_point_id.clone(),
            location_id: context.active_location_id.clone(),
            entry_point_id: context.entry_point_id,
            return_location_id: context.return_outdoor_location_id.clone(),
            world_mode: Some(super::world_mode_name(context.world_mode).to_string()),
        },
    ))
}

pub(super) fn enter_location(
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
    Ok(ServerMessage::LocationTransition(
        protocol_location_transition(transition),
    ))
}

pub(super) fn return_to_overworld(
    runtime: &mut ServerSimulationRuntime,
    request: ReturnToOverworldRequest,
) -> Result<ServerMessage, ProtocolError> {
    let state = runtime
        .0
        .return_to_overworld(request.actor_id)
        .map_err(|error| runtime_protocol_error("return_to_overworld", error))?;
    Ok(ServerMessage::OverworldState(protocol_overworld_state(
        state,
    )))
}

pub(super) fn save_runtime_snapshot(
    runtime: &mut ServerSimulationRuntime,
    snapshots: &mut RuntimeSnapshotStore,
    request: RuntimeSnapshotSaveRequest,
) -> Result<ServerMessage, ProtocolError> {
    let snapshot = runtime.0.save_snapshot();
    let payload = snapshots.save(request.snapshot_id, snapshot)?;
    Ok(ServerMessage::RuntimeSnapshotSaved(payload))
}

pub(super) fn load_runtime_snapshot(
    runtime: &mut ServerSimulationRuntime,
    snapshots: &mut RuntimeSnapshotStore,
    request: RuntimeSnapshotLoadRequest,
) -> Result<ServerMessage, ProtocolError> {
    let (snapshot_id, snapshot) = resolve_runtime_snapshot_to_load(snapshots, request)?;
    runtime
        .0
        .load_snapshot(snapshot.clone())
        .map_err(|error| runtime_protocol_error("runtime_snapshot_load", error))?;
    let payload = super::snapshot_payload(snapshot_id, snapshot)?;
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
            let snapshot_id = super::normalize_snapshot_id(request.snapshot_id);
            if let Some(snapshot_id) = snapshot_id.as_ref() {
                snapshots
                    .snapshots
                    .insert(snapshot_id.clone(), snapshot.clone());
            }
            Ok((snapshot_id, snapshot))
        }
        None => {
            let snapshot_id =
                super::normalize_snapshot_id(request.snapshot_id).ok_or_else(|| {
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
