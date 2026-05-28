//! NPC life 系统装配模块。
//! 负责注册 life 域系统顺序，不负责承载具体业务数据定义。

mod background_execution;
mod combat_state_sync;
mod debug_snapshot_sync;
mod entity_init;
mod life_planning;

use bevy_app::{App, Update};
use bevy_ecs::schedule::IntoScheduleConfigs;

use super::plugin::NpcLifeUpdateSet;

pub(super) fn configure(app: &mut App) {
    app.configure_sets(Update, NpcLifeUpdateSet::RuntimeState);
    app.add_systems(
        Update,
        (
            entity_init::initialize_npc_life_entities,
            entity_init::sync_reservation_catalog_system,
            life_planning::update_schedule_state_system,
            life_planning::update_need_state_system,
            life_planning::plan_npc_life_system,
            background_execution::execute_offline_actions_system,
            combat_state_sync::refresh_npc_runtime_bridge_state_system,
            debug_snapshot_sync::refresh_debug_snapshot_system,
            life_planning::advance_sim_clock_system,
        )
            .chain()
            .in_set(NpcLifeUpdateSet::RuntimeState),
    );
}

pub(super) fn initialize_resources(app: &mut App) {
    entity_init::initialize_resources(app);
}
