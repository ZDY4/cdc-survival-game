use bevy::prelude::*;
use game_bevy::{
    register_runtime_actor_from_definition, BackgroundLifeState, CharacterDefinitionId,
    CharacterDefinitions, CurrentAction, CurrentPlan, DisplayName, GridPosition, NeedState,
    NpcLifeState, ReservationState, RuntimeActorLink, RuntimeExecutionState, ScheduleState,
    SettlementDefinitions, SmartObjectReservations,
};
use game_core::{NpcBackgroundState, NpcRuntimeActionState};
use game_data::{GridCoord, MapId, SettlementId};

use crate::state::{ViewerRuntimeState, ViewerSceneKind};

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
        &CurrentPlan,
        &CurrentAction,
        &ReservationState,
        &mut RuntimeExecutionState,
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
        mut runtime_execution,
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
            runtime_execution.mode = game_core::NpcExecutionMode::Online;
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
            runtime_execution.last_failure_reason = None;
            background_state.0 = None;
        } else {
            life.online = false;
            runtime_execution.mode = game_core::NpcExecutionMode::Background;
            runtime_execution.runtime_goal_grid = None;

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
                            &runtime_execution,
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
                        runtime_execution.last_failure_reason.clone(),
                        runtime_execution.runtime_goal_grid,
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
                    &runtime_execution,
                ));
            }
        }
    }
}

pub(super) fn resolve_anchor_grid(
    settlement: &game_data::SettlementDefinition,
    anchor_id: &str,
) -> Option<GridCoord> {
    settlement
        .anchors
        .iter()
        .find(|anchor| anchor.id == anchor_id)
        .map(|anchor| anchor.grid)
}

pub(super) fn resolve_reachable_runtime_grid(
    snapshot: &game_core::SimulationSnapshot,
    desired_grid: GridCoord,
    actor_id: Option<game_data::ActorId>,
) -> Option<GridCoord> {
    if is_runtime_grid_walkable(snapshot, desired_grid, actor_id) {
        return Some(desired_grid);
    }

    let max_radius = snapshot
        .grid
        .map_width
        .zip(snapshot.grid.map_height)
        .map(|(width, height)| width.max(height) as i32)
        .unwrap_or(8)
        .max(1);

    for radius in 1..=max_radius {
        for candidate in collect_ring_cells(desired_grid, radius) {
            if is_runtime_grid_walkable(snapshot, candidate, actor_id) {
                return Some(candidate);
            }
        }
    }

    None
}

fn is_runtime_grid_walkable(
    snapshot: &game_core::SimulationSnapshot,
    grid: GridCoord,
    actor_id: Option<game_data::ActorId>,
) -> bool {
    if grid.x < 0 || grid.z < 0 {
        return false;
    }

    if let Some(width) = snapshot.grid.map_width {
        if grid.x as u32 >= width {
            return false;
        }
    }
    if let Some(height) = snapshot.grid.map_height {
        if grid.z as u32 >= height {
            return false;
        }
    }
    if !snapshot.grid.levels.is_empty() && !snapshot.grid.levels.contains(&grid.y) {
        return false;
    }
    if snapshot.grid.map_blocked_cells.contains(&grid) {
        return false;
    }
    if snapshot.grid.runtime_blocked_cells.contains(&grid) {
        return actor_id
            .and_then(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .find(|actor| actor.actor_id == actor_id)
                    .map(|actor| actor.grid_position == grid)
            })
            .unwrap_or(false);
    }

    true
}

fn collect_ring_cells(center: GridCoord, radius: i32) -> Vec<GridCoord> {
    let mut cells = Vec::new();
    for dx in -radius..=radius {
        for dz in -radius..=radius {
            if dx.abs().max(dz.abs()) != radius {
                continue;
            }
            cells.push(GridCoord::new(center.x + dx, center.y, center.z + dz));
        }
    }
    cells
}

fn quantize_need(value: f32) -> u8 {
    value.round().clamp(0.0, 100.0) as u8
}

fn build_background_state(
    definition_id: &str,
    display_name: &str,
    map_id: MapId,
    grid_position: GridCoord,
    life: &NpcLifeState,
    need: &NeedState,
    schedule: &ScheduleState,
    current_plan: &CurrentPlan,
    current_action: &CurrentAction,
    reservation_state: &ReservationState,
    runtime_execution: &RuntimeExecutionState,
) -> NpcBackgroundState {
    NpcBackgroundState {
        definition_id: Some(definition_id.to_string()),
        display_name: display_name.to_string(),
        map_id: Some(map_id),
        grid_position,
        current_anchor: life.current_anchor.clone(),
        current_plan: current_plan.steps.clone(),
        plan_next_index: current_plan.next_index,
        current_action: current_action.0.as_ref().map(|action| {
            NpcRuntimeActionState::from_offline_action(
                action,
                reservation_state.active.clone(),
                runtime_execution.last_failure_reason.clone(),
                runtime_execution.runtime_goal_grid,
            )
        }),
        held_reservations: reservation_state.active.clone(),
        hunger: quantize_need(need.hunger),
        energy: quantize_need(need.energy),
        morale: quantize_need(need.morale),
        on_shift: schedule.on_shift,
        meal_window_open: schedule.meal_window_open,
        quiet_hours: schedule.quiet_hours,
        world_alert_active: false,
    }
}
