//! 在线 NPC 在场同步模块。
//! 负责在线/离线 presence 与 runtime actor 生命周期同步，不负责 life action 或 combat 决策执行。

use bevy::prelude::*;
use game_bevy::{
    register_runtime_actor_from_definition, BackgroundLifeState, CharacterDefinitionId,
    CharacterDefinitions, DisplayName, GridPosition, NeedState, NpcActiveOfflineAction,
    NpcLifeState, NpcPlannedActionQueue, NpcRuntimeAiMode, NpcRuntimeBridgeState, ReservationState,
    RuntimeActorLink, ScheduleState, SettlementDefinitions, SmartObjectReservations,
};
use game_core::NpcRuntimeActionState;
use game_data::SettlementId;

use crate::state::{ViewerRuntimeState, ViewerSceneKind};

use super::{
    build_background_state, quantize_need, resolve_anchor_grid, resolve_reachable_runtime_grid,
};

pub(crate) fn sync_npc_runtime_presence(
    mut commands: Commands,
    definitions: Option<Res<CharacterDefinitions>>,
    settlements: Option<Res<SettlementDefinitions>>,
    mut reservations: ResMut<SmartObjectReservations>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
    mut query: Query<(
        Entity,
        &CharacterDefinitionId,
        &DisplayName,
        &mut GridPosition,
        &mut NpcLifeState,
        &NeedState,
        &ScheduleState,
        &NpcPlannedActionQueue,
        &NpcActiveOfflineAction,
        &ReservationState,
        &mut NpcRuntimeBridgeState,
        &mut BackgroundLifeState,
        Option<&RuntimeActorLink>,
    )>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        return;
    }
    let (Some(definitions), Some(settlements)) = (definitions, settlements) else {
        return;
    };

    let snapshot = runtime_state.runtime.snapshot();
    let active_map_id = snapshot.grid.map_id.clone();
    let mut runtime_actors_by_definition = snapshot
        .actors
        .iter()
        .filter_map(|actor| {
            actor
                .definition_id
                .as_ref()
                .map(|definition_id| (definition_id.as_str().to_string(), actor.actor_id))
        })
        .collect::<std::collections::HashMap<_, _>>();

    for (
        entity,
        definition_id,
        display_name,
        mut grid_position,
        mut life,
        need,
        schedule,
        current_plan,
        current_action,
        reservation_state,
        mut runtime_bridge,
        mut background_state,
        runtime_link,
    ) in &mut query
    {
        let Some(settlement) = settlements.0.get(&SettlementId(life.settlement_id.clone())) else {
            continue;
        };
        let should_be_online = active_map_id
            .as_ref()
            .map(|map_id| settlement.map_id == *map_id)
            .unwrap_or(false);
        let runtime_actor_exists = runtime_link
            .map(|link| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == link.actor_id)
            })
            .unwrap_or(false);

        if should_be_online {
            life.online = true;
            runtime_bridge.execution_mode = game_core::NpcExecutionMode::Online;
            let actor_id = if let Some(link) = runtime_link.filter(|_| runtime_actor_exists) {
                link.actor_id
            } else if let Some(actor_id) = runtime_actors_by_definition
                .get(definition_id.0.as_str())
                .copied()
            {
                commands
                    .entity(entity)
                    .insert(RuntimeActorLink { actor_id });
                actor_id
            } else {
                let Some(definition) = definitions.0.get(&definition_id.0) else {
                    continue;
                };
                let desired_spawn_grid = background_state
                    .0
                    .as_ref()
                    .and_then(|background| {
                        background
                            .current_anchor
                            .as_deref()
                            .and_then(|anchor| resolve_anchor_grid(settlement, anchor))
                            .or(Some(background.grid_position))
                    })
                    .unwrap_or(grid_position.0);
                let spawn_grid =
                    resolve_reachable_runtime_grid(&snapshot, desired_spawn_grid, None)
                        .unwrap_or(desired_spawn_grid);
                let actor_id = register_runtime_actor_from_definition(
                    &mut runtime_state.runtime,
                    definition,
                    spawn_grid,
                );
                runtime_actors_by_definition.insert(definition_id.0.as_str().to_string(), actor_id);
                commands
                    .entity(entity)
                    .insert(RuntimeActorLink { actor_id });
                if let Some(background) = background_state.0.as_ref() {
                    runtime_state
                        .runtime
                        .import_actor_background_state(actor_id, background);
                }
                actor_id
            };

            if let Some(runtime_grid) = runtime_state.runtime.get_actor_grid_position(actor_id) {
                grid_position.0 = runtime_grid;
            }
            let actor_in_combat = snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == actor_id)
                .map(|actor| actor.in_combat)
                .unwrap_or(false);
            if actor_in_combat {
                runtime_bridge.ai_mode = NpcRuntimeAiMode::Combat;
            } else if runtime_bridge.ai_mode != NpcRuntimeAiMode::Combat {
                runtime_bridge.ai_mode = NpcRuntimeAiMode::Life;
                runtime_bridge.combat_target_actor_id = None;
                runtime_bridge.runtime_goal_grid = None;
            }
            background_state.0 = None;
        } else {
            life.online = false;
            runtime_bridge.execution_mode = game_core::NpcExecutionMode::Background;
            runtime_bridge.ai_mode = NpcRuntimeAiMode::Life;
            runtime_bridge.combat_alert_active = false;
            runtime_bridge.combat_replan_required = false;
            runtime_bridge.combat_threat_actor_id = None;
            runtime_bridge.combat_target_actor_id = None;
            runtime_bridge.last_combat_target_actor_id = None;
            runtime_bridge.last_combat_intent = None;
            runtime_bridge.last_combat_outcome = None;
            runtime_bridge.runtime_goal_grid = None;
            runtime_bridge.actor_hp_ratio = None;
            runtime_bridge.attack_ap_cost = None;
            runtime_bridge.target_hp_ratio = None;
            runtime_bridge.approach_distance_steps = None;
            runtime_bridge.last_damage_taken = None;
            runtime_bridge.last_damage_dealt = None;
            runtime_bridge.last_failure_reason = None;

            if let Some(link) = runtime_link {
                let mut exported = runtime_state
                    .runtime
                    .export_actor_background_state(link.actor_id)
                    .unwrap_or_else(|| {
                        build_background_state(
                            definition_id.0.as_str(),
                            display_name.0.as_str(),
                            settlement.map_id.clone(),
                            grid_position.0,
                            &life,
                            need,
                            schedule,
                            current_plan,
                            current_action,
                            reservation_state,
                            &runtime_bridge,
                        )
                    });
                exported.definition_id = Some(definition_id.0.as_str().to_string());
                exported.display_name = display_name.0.clone();
                exported.map_id = Some(settlement.map_id.clone());
                exported.grid_position = grid_position.0;
                exported.current_anchor = life.current_anchor.clone();
                exported.current_plan = current_plan.steps.clone();
                exported.plan_next_index = current_plan.next_index;
                exported.current_action = current_action.0.as_ref().map(|action| {
                    NpcRuntimeActionState::from_offline_action(
                        action,
                        reservation_state.active.clone(),
                        runtime_bridge.last_failure_reason.clone(),
                        runtime_bridge.runtime_goal_grid,
                    )
                });
                exported.held_reservations = reservation_state.active.clone();
                exported.hunger = quantize_need(need.hunger);
                exported.energy = quantize_need(need.energy);
                exported.morale = quantize_need(need.morale);
                exported.on_shift = schedule.on_shift;
                exported.meal_window_open = schedule.meal_window_open;
                exported.quiet_hours = schedule.quiet_hours;
                background_state.0 = Some(exported);

                for reservation in &reservation_state.active {
                    reservations.release(reservation, entity);
                }
                runtime_state
                    .runtime
                    .clear_actor_autonomous_movement_goal(link.actor_id);
                runtime_state
                    .runtime
                    .clear_actor_runtime_action_state(link.actor_id);
                runtime_state.runtime.unregister_actor(link.actor_id);
                commands.entity(entity).remove::<RuntimeActorLink>();
            } else if background_state.0.is_none() {
                background_state.0 = Some(build_background_state(
                    definition_id.0.as_str(),
                    display_name.0.as_str(),
                    settlement.map_id.clone(),
                    grid_position.0,
                    &life,
                    need,
                    schedule,
                    current_plan,
                    current_action,
                    reservation_state,
                    &runtime_bridge,
                ));
            }
        }
    }
}
