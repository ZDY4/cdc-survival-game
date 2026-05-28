//! 在线 NPC 背景态组装模块。
//! 负责构造共享 background state 导出数据，不负责实体在线/离线切换。

use game_bevy::{
    NeedState, NpcActiveOfflineAction, NpcLifeState, NpcPlannedActionQueue, NpcRuntimeBridgeState,
    ReservationState, ScheduleState,
};
use game_core::{NpcBackgroundState, NpcRuntimeActionState};
use game_data::{GridCoord, MapId};

pub(crate) fn quantize_need(value: f32) -> u8 {
    value.round().clamp(0.0, 100.0) as u8
}

pub(crate) fn build_background_state(
    definition_id: &str,
    display_name: &str,
    map_id: MapId,
    grid_position: GridCoord,
    life: &NpcLifeState,
    need: &NeedState,
    schedule: &ScheduleState,
    current_plan: &NpcPlannedActionQueue,
    current_action: &NpcActiveOfflineAction,
    reservation_state: &ReservationState,
    runtime_bridge: &NpcRuntimeBridgeState,
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
                runtime_bridge.last_failure_reason.clone(),
                runtime_bridge.runtime_goal_grid,
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
