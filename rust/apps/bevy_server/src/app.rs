use std::time::Duration;

use bevy_app::prelude::*;
use bevy_app::{ScheduleRunnerPlugin, TaskPoolPlugin};
use bevy_ecs::schedule::IntoScheduleConfigs;

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
    load_character_definitions_on_startup, load_effect_definitions_on_startup,
    load_item_definitions_on_startup, load_map_definitions_on_startup,
    load_overworld_definitions_on_startup, load_quest_definitions_on_startup,
    load_recipe_definitions_on_startup, load_runtime_startup_config_on_startup,
    load_settlement_definitions_on_startup, load_shop_definitions_on_startup,
    load_skill_definitions_on_startup, load_skill_tree_definitions_on_startup,
    spawn_characters_from_definition, CharacterDefinitionPath, CharacterSpawnRejected,
    EffectDefinitionPath, ItemDefinitionPath, MapAiSpawnRuntimeState, MapDefinitionPath,
    NpcLifePlugin, OverworldDefinitionPath, QuestDefinitionPath, RecipeDefinitionPath,
    RuntimeStartupConfigPath, SettlementDefinitionPath, SettlementSimulationPlugin,
    ShopDefinitionPath, SkillDefinitionPath, SkillTreeDefinitionPath, SpawnCharacterRequest,
};
use game_core::GameCorePlugin;
use game_data::GameDataPlugin;
use game_protocol::GameProtocolPlugin;

pub fn run() {
    App::new().add_plugins(ServerAppPlugin).run();
}

struct ServerAppPlugin;

impl Plugin for ServerAppPlugin {
    fn build(&self, app: &mut App) {
        app.insert_resource(crate::config::ServerConfig::default())
            .insert_resource(CharacterDefinitionPath::default())
            .insert_resource(EffectDefinitionPath::default())
            .insert_resource(ItemDefinitionPath::default())
            .insert_resource(MapDefinitionPath::default())
            .insert_resource(OverworldDefinitionPath::default())
            .insert_resource(SettlementDefinitionPath::default())
            .insert_resource(SkillDefinitionPath::default())
            .insert_resource(SkillTreeDefinitionPath::default())
            .insert_resource(RecipeDefinitionPath::default())
            .insert_resource(QuestDefinitionPath::default())
            .insert_resource(ShopDefinitionPath::default())
            .insert_resource(RuntimeStartupConfigPath::default())
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
                GameDataPlugin,
                GameProtocolPlugin,
                GameCorePlugin,
                SettlementSimulationPlugin,
                NpcLifePlugin,
            ))
            .add_message::<SpawnCharacterRequest>()
            .add_message::<CharacterSpawnRejected>()
            .add_message::<ServerProtocolRequest>()
            .add_message::<ServerProtocolResponse>()
            .add_systems(
                Startup,
                (
                    load_character_definitions_on_startup,
                    load_effect_definitions_on_startup,
                    load_item_definitions_on_startup,
                    load_map_definitions_on_startup,
                    load_overworld_definitions_on_startup,
                    load_settlement_definitions_on_startup,
                    load_skill_definitions_on_startup,
                    load_skill_tree_definitions_on_startup,
                    load_recipe_definitions_on_startup,
                    load_quest_definitions_on_startup,
                    load_shop_definitions_on_startup,
                    load_runtime_startup_config_on_startup,
                    startup_demo,
                )
                    .chain(),
            )
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
