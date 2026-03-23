use bevy_app::prelude::*;
use bevy_app::{AppExit, ScheduleRunnerPlugin, TaskPoolPlugin};
use bevy_ecs::prelude::*;
use std::time::Duration;

use game_bevy::{
    build_runtime_from_seed, default_debug_seed, load_character_definitions_on_startup,
    load_map_definitions_on_startup, load_runtime_startup_config_on_startup,
    load_settlement_definitions_on_startup, resolve_startup_map_id,
    spawn_characters_from_definition, AiCombatProfile, BehaviorProfile, CampId,
    CharacterArchetypeComponent, CharacterDefinitionId, CharacterDefinitionPath,
    CharacterDefinitions, CharacterSpawnRejected, DisplayName, Disposition, GridPosition, Level,
    LootTable, MapDefinitionPath, MapDefinitions, NpcLifePlugin, RuntimeStartupConfig,
    RuntimeStartupConfigPath, SettlementDefinitionPath, SettlementSimulationPlugin,
    SpawnCharacterRequest, XpReward,
};
use game_core::{GameCorePlugin, SimulationRuntime};
use game_data::GameDataPlugin;
use game_protocol::GameProtocolPlugin;

fn main() {
    App::new()
        .insert_resource(ServerConfig::default())
        .insert_resource(CharacterDefinitionPath::default())
        .insert_resource(MapDefinitionPath::default())
        .insert_resource(SettlementDefinitionPath::default())
        .insert_resource(RuntimeStartupConfigPath::default())
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
        .add_systems(
            Startup,
            (
                load_character_definitions_on_startup,
                load_map_definitions_on_startup,
                load_settlement_definitions_on_startup,
                load_runtime_startup_config_on_startup,
                startup_demo,
            )
                .chain(),
        )
        .add_systems(
            Update,
            (
                spawn_characters_from_definition,
                report_spawned_characters_and_exit,
            )
                .chain(),
        )
        .run();
}

#[derive(Resource, Debug, Clone)]
struct ServerConfig {
    tick_rate_hz: u16,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self { tick_rate_hz: 60 }
    }
}

#[derive(Resource, Debug)]
struct ServerSimulationRuntime(pub SimulationRuntime);

fn startup_demo(
    mut commands: Commands,
    config: Res<ServerConfig>,
    definitions: Res<CharacterDefinitions>,
    maps: Res<MapDefinitions>,
    startup_config: Res<RuntimeStartupConfig>,
    mut requests: MessageWriter<SpawnCharacterRequest>,
) {
    let mut seed = default_debug_seed();
    seed.map_id = resolve_startup_map_id(&maps.0, startup_config.startup_map.clone());

    println!(
        "bevy_server booted with headless loop at {} Hz",
        config.tick_rate_hz
    );
    println!(
        "loaded {} character definitions from Rust game_data authority",
        definitions.0.len()
    );
    println!(
        "loaded {} map definitions from Rust game_data authority",
        maps.0.len()
    );
    match seed.map_id.as_ref() {
        Some(map_id) => {
            if maps.0.get(map_id).is_none() {
                panic!(
                    "configured startup_map {} was not found in loaded map definitions",
                    map_id
                );
            }
            println!(
                "selected startup_map={} from shared bevy runtime config",
                map_id
            );
        }
        None => {
            println!("selected startup_map=<none>; no map definitions available");
        }
    }

    let runtime = build_runtime_from_seed(&definitions.0, &maps.0, &seed).unwrap_or_else(|error| {
        panic!("failed to build bevy_server runtime from startup seed: {error}")
    });
    let snapshot = runtime.snapshot();
    println!(
        "initialized simulation runtime map_id={} size={}x{} levels={:?}",
        snapshot
            .grid
            .map_id
            .as_ref()
            .map(|map_id| map_id.as_str())
            .unwrap_or("none"),
        snapshot.grid.map_width.unwrap_or(0),
        snapshot.grid.map_height.unwrap_or(0),
        snapshot.grid.levels,
    );
    commands.insert_resource(ServerSimulationRuntime(runtime));

    for entry in seed.characters {
        requests.write(SpawnCharacterRequest {
            definition_id: entry.definition_id,
            grid_position: entry.grid_position,
        });
    }
}

fn report_spawned_characters_and_exit(
    spawned_characters: Query<(
        Entity,
        &CharacterDefinitionId,
        &CharacterArchetypeComponent,
        &Disposition,
        &CampId,
        &DisplayName,
        &Level,
        &BehaviorProfile,
        &AiCombatProfile,
        &XpReward,
        &LootTable,
        &GridPosition,
    )>,
    mut rejections: MessageReader<CharacterSpawnRejected>,
    mut already_reported: Local<bool>,
    mut app_exit: MessageWriter<AppExit>,
) {
    if *already_reported {
        return;
    }

    let mut spawned_count = 0usize;
    for (
        entity,
        definition_id,
        archetype,
        disposition,
        camp_id,
        display_name,
        level,
        behavior,
        ai,
        xp_reward,
        loot,
        grid_position,
    ) in &spawned_characters
    {
        spawned_count += 1;
        println!(
            "spawned entity={entity:?} id={} archetype={:?} disposition={:?} camp={} name={} level={} grid=({}, {}, {}) behavior={} xp={} loot={} ai_attack_range={}",
            definition_id.0,
            archetype.0,
            disposition.0,
            camp_id.0,
            display_name.0,
            level.0,
            grid_position.0.x,
            grid_position.0.y,
            grid_position.0.z,
            behavior.0,
            xp_reward.0,
            loot.0.len(),
            ai.0.attack_range,
        );
    }

    for rejection in rejections.read() {
        println!(
            "character spawn rejected: definition_id={} reason={}",
            rejection.definition_id, rejection.reason
        );
    }

    if spawned_count > 0 {
        *already_reported = true;
        app_exit.write(AppExit::Success);
    }
}

#[cfg(test)]
mod tests {
    use super::{startup_demo, ServerConfig, ServerSimulationRuntime};
    use bevy_app::{App, Startup};
    use bevy_ecs::message::MessageReader;
    use bevy_ecs::prelude::*;
    use game_bevy::{
        default_debug_seed, CharacterDefinitions, MapDefinitions, RuntimeStartupConfig,
        SpawnCharacterRequest,
    };
    use game_data::{
        CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate, CharacterCombatProfile,
        CharacterDefinition, CharacterDisposition, CharacterFaction, CharacterId,
        CharacterIdentity, CharacterLibrary, CharacterLootEntry, CharacterPlaceholderColors,
        CharacterPresentation, CharacterProgression, CharacterResourcePool, GridCoord,
        MapBuildingProps, MapCellDefinition, MapDefinition, MapId, MapLevelDefinition, MapLibrary,
        MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps, MapRotation,
        MapSize,
    };
    use std::collections::BTreeMap;

    #[derive(Resource, Debug, Default)]
    struct CapturedRequests(Vec<SpawnCharacterRequest>);

    #[test]
    fn startup_demo_queues_shared_default_seed_requests() {
        let mut app = App::new();
        app.insert_resource(ServerConfig::default());
        app.insert_resource(CharacterDefinitions(sample_character_library()));
        app.insert_resource(MapDefinitions(sample_map_library()));
        app.insert_resource(RuntimeStartupConfig { startup_map: None });
        app.insert_resource(CapturedRequests::default());
        app.add_message::<SpawnCharacterRequest>();
        app.add_systems(Startup, (startup_demo, capture_requests).chain());

        app.update();

        let captured = app.world().resource::<CapturedRequests>();
        let ids: Vec<&str> = captured
            .0
            .iter()
            .map(|request| request.definition_id.as_str())
            .collect();
        let seed = default_debug_seed();
        let expected: Vec<&str> = seed
            .characters
            .iter()
            .map(|entry| entry.definition_id.as_str())
            .collect();

        assert_eq!(ids, expected);
    }

    #[test]
    fn startup_demo_builds_runtime_with_configured_startup_map() {
        let mut app = App::new();
        app.insert_resource(ServerConfig::default());
        app.insert_resource(CharacterDefinitions(sample_character_library()));
        app.insert_resource(MapDefinitions(sample_map_library()));
        app.insert_resource(RuntimeStartupConfig {
            startup_map: Some(MapId("safehouse_grid".into())),
        });
        app.add_message::<SpawnCharacterRequest>();
        app.add_systems(Startup, startup_demo);

        app.update();

        let runtime = app.world().resource::<ServerSimulationRuntime>();
        let snapshot = runtime.0.snapshot();

        assert_eq!(
            snapshot.grid.map_id.as_ref().map(MapId::as_str),
            Some("safehouse_grid")
        );
        assert_eq!(snapshot.grid.map_width, Some(12));
        assert_eq!(snapshot.grid.map_height, Some(12));
    }

    fn capture_requests(
        mut reader: MessageReader<SpawnCharacterRequest>,
        mut captured: ResMut<CapturedRequests>,
    ) {
        captured.0.extend(reader.read().cloned());
    }

    fn sample_character_library() -> CharacterLibrary {
        let definitions = vec![
            sample_definition(
                "player",
                CharacterArchetype::Player,
                CharacterDisposition::Player,
                "survivor",
                "Rust Player",
            ),
            sample_definition(
                "trader_lao_wang",
                CharacterArchetype::Npc,
                CharacterDisposition::Friendly,
                "survivor",
                "废土商人·老王",
            ),
            sample_definition(
                "zombie_walker",
                CharacterArchetype::Enemy,
                CharacterDisposition::Hostile,
                "infected",
                "行尸",
            ),
        ];

        let mut map = BTreeMap::new();
        for definition in definitions {
            map.insert(definition.id.clone(), definition);
        }
        CharacterLibrary::from(map)
    }

    fn sample_map_library() -> MapLibrary {
        let definition = MapDefinition {
            id: MapId("safehouse_grid".into()),
            name: "Safehouse".into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![
                MapLevelDefinition {
                    y: 0,
                    cells: vec![MapCellDefinition {
                        x: 2,
                        z: 1,
                        blocks_movement: true,
                        blocks_sight: true,
                        terrain: "pillar".into(),
                        extra: BTreeMap::new(),
                    }],
                },
                MapLevelDefinition {
                    y: 1,
                    cells: Vec::new(),
                },
            ],
            objects: vec![MapObjectDefinition {
                object_id: "house".into(),
                kind: MapObjectKind::Building,
                anchor: GridCoord::new(7, 0, 4),
                footprint: MapObjectFootprint {
                    width: 2,
                    height: 2,
                },
                rotation: MapRotation::North,
                blocks_movement: true,
                blocks_sight: true,
                props: MapObjectProps {
                    building: Some(MapBuildingProps {
                        prefab_id: "safehouse_house".into(),
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        };

        let mut maps = BTreeMap::new();
        maps.insert(definition.id.clone(), definition);
        MapLibrary::from(maps)
    }

    fn sample_definition(
        id: &str,
        archetype: CharacterArchetype,
        disposition: CharacterDisposition,
        camp_id: &str,
        display_name: &str,
    ) -> CharacterDefinition {
        CharacterDefinition {
            id: CharacterId(id.to_string()),
            archetype,
            identity: CharacterIdentity {
                display_name: display_name.to_string(),
                description: "sample".to_string(),
            },
            faction: CharacterFaction {
                camp_id: camp_id.to_string(),
                disposition,
            },
            presentation: CharacterPresentation {
                portrait_path: String::new(),
                avatar_path: String::new(),
                model_path: String::new(),
                placeholder_colors: CharacterPlaceholderColors {
                    head: "#eecba0".to_string(),
                    body: "#6a9add".to_string(),
                    legs: "#3c5c90".to_string(),
                },
            },
            progression: CharacterProgression { level: 5 },
            combat: CharacterCombatProfile {
                behavior: "neutral".to_string(),
                xp_reward: 25,
                loot: vec![CharacterLootEntry {
                    item_id: 1010,
                    chance: 0.2,
                    min: 1,
                    max: 2,
                }],
            },
            ai: CharacterAiProfile {
                aggro_range: 0.0,
                attack_range: 1.2,
                wander_radius: 3.0,
                leash_distance: 5.0,
                decision_interval: 1.2,
                attack_cooldown: 999.0,
            },
            attributes: CharacterAttributeTemplate {
                sets: BTreeMap::from([
                    (
                        "base".to_string(),
                        BTreeMap::from([("strength".to_string(), 5.0)]),
                    ),
                    (
                        "combat".to_string(),
                        BTreeMap::from([("max_hp".to_string(), 60.0)]),
                    ),
                ]),
                resources: BTreeMap::from([(
                    "hp".to_string(),
                    CharacterResourcePool { current: 60.0 },
                )]),
            },
            life: None,
        }
    }
}
