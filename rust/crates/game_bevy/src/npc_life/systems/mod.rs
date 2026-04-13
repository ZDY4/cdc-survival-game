mod combat_bridge;
mod debug_snapshot;
mod init;
mod offline_execution;
mod planning;

use bevy_app::{App, Update};
use bevy_ecs::schedule::IntoScheduleConfigs;

pub(super) fn configure(app: &mut App) {
    app.configure_sets(Update, super::NpcLifeUpdateSet::RuntimeState);
    app.add_systems(
        Update,
        (
            init::initialize_npc_life_entities,
            init::sync_reservation_catalog_system,
            planning::update_schedule_state_system,
            planning::update_need_state_system,
            planning::plan_npc_life_system,
            offline_execution::execute_offline_actions_system,
            combat_bridge::refresh_npc_runtime_bridge_state_system,
            debug_snapshot::refresh_debug_snapshot_system,
            planning::advance_sim_clock_system,
        )
            .chain()
            .in_set(super::NpcLifeUpdateSet::RuntimeState),
    );
}

pub(super) fn initialize_resources(app: &mut App) {
    init::initialize_resources(app);
}
