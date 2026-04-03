use std::time::Duration;

use bevy_app::prelude::*;
use bevy_app::{ScheduleRunnerPlugin, TaskPoolPlugin};
use bevy_ecs::schedule::IntoScheduleConfigs;
use tracing::info;

use crate::config::{NpcDebugReportState, ServerVisionConfig};
use crate::progression::advance_runtime_progression;
use crate::protocol::{
    dispatch_protocol_requests, drain_protocol_responses, emit_runtime_protocol_events,
    RuntimeProtocolPushState, RuntimeProtocolSequence, RuntimeSnapshotStore, ServerProtocolRequest,
    ServerProtocolResponse,
};
use crate::reporting::{report_npc_life_debug_snapshot, report_spawned_characters_and_exit};
use crate::startup::{advance_map_ai_spawns, startup_demo};
use crate::vision::{refresh_runtime_vision, ServerVisionTrackerState};
use game_bevy::{
    init_runtime_logging, spawn_characters_from_definition, CharacterSpawnRejected,
    MapAiSpawnRuntimeState, NpcLifePlugin, RuntimeContentPlugin, RuntimeLogSettings,
    SettlementSimulationPlugin, SpawnCharacterRequest,
};

pub fn run() {
    let log_settings = RuntimeLogSettings::new("bevy_server");
    if let Err(error) = init_runtime_logging(&log_settings) {
        eprintln!("failed to initialize bevy_server logging: {error}");
    }
    info!("bevy_server logger initialized");
    let mut app = App::new();
    app.add_plugins(ServerAppPlugin);
    app.run();
}

struct ServerAppPlugin;

impl Plugin for ServerAppPlugin {
    fn build(&self, app: &mut App) {
        app.insert_resource(crate::config::ServerConfig::default())
            .insert_resource(crate::config::ServerStartupState::default())
            .insert_resource(NpcDebugReportState::default())
            .insert_resource(ServerVisionConfig::default())
            .insert_resource(ServerVisionTrackerState::default())
            .insert_resource(MapAiSpawnRuntimeState::default())
            .insert_resource(RuntimeSnapshotStore::default())
            .insert_resource(RuntimeProtocolPushState::default())
            .insert_resource(RuntimeProtocolSequence::default())
            .add_plugins(TaskPoolPlugin::default())
            .add_plugins(ScheduleRunnerPlugin::run_loop(Duration::from_millis(16)))
            .add_plugins((
                RuntimeContentPlugin,
                SettlementSimulationPlugin,
                NpcLifePlugin,
            ))
            .add_message::<SpawnCharacterRequest>()
            .add_message::<CharacterSpawnRejected>()
            .add_message::<ServerProtocolRequest>()
            .add_message::<ServerProtocolResponse>()
            .add_systems(PostStartup, startup_demo)
            .add_systems(
                Update,
                (
                    dispatch_protocol_requests,
                    advance_runtime_progression,
                    refresh_runtime_vision,
                    emit_runtime_protocol_events,
                    drain_protocol_responses,
                    spawn_characters_from_definition,
                    advance_map_ai_spawns,
                    report_npc_life_debug_snapshot,
                    report_spawned_characters_and_exit,
                )
                    .chain(),
            );
    }
}
