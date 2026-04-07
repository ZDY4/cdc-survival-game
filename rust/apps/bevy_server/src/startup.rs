use bevy_ecs::prelude::*;
use bevy_ecs::system::SystemParam;

use crate::config::{
    EconomySmokeReport, ServerConfig, ServerSimulationRuntime, ServerStartupState,
};
use game_bevy::{
    advance_map_ai_spawn_runtime, apply_dialogue_libraries, apply_gameplay_libraries,
    build_default_startup_seed, build_runtime_from_default_startup_seed, CharacterDefinitions,
    DialogueDefinitions, DialogueRuleDefinitions, EffectDefinitions, ItemDefinitions,
    MapAiSpawnRuntimeState, MapDefinitions, OverworldDefinitions, QuestDefinitions,
    RecipeDefinitions, RuntimeBootstrapBundle, RuntimeContentLoadState, RuntimeStartupConfig,
    ShopDefinitions, SkillDefinitions, SkillTreeDefinitions, SpawnCharacterRequest,
};
use game_core::SimulationRuntime;
use game_data::{CharacterId, GridCoord};
use tracing::{error, info};

#[derive(SystemParam)]
pub struct StartupContent<'w, 's> {
    definitions: Option<Res<'w, CharacterDefinitions>>,
    effects: Option<Res<'w, EffectDefinitions>>,
    items: Option<Res<'w, ItemDefinitions>>,
    maps: Option<Res<'w, MapDefinitions>>,
    overworld: Option<Res<'w, OverworldDefinitions>>,
    skills: Option<Res<'w, SkillDefinitions>>,
    skill_trees: Option<Res<'w, SkillTreeDefinitions>>,
    recipes: Option<Res<'w, RecipeDefinitions>>,
    quests: Option<Res<'w, QuestDefinitions>>,
    shops: Option<Res<'w, ShopDefinitions>>,
    dialogues: Option<Res<'w, DialogueDefinitions>>,
    dialogue_rules: Option<Res<'w, DialogueRuleDefinitions>>,
    startup_config: Option<Res<'w, RuntimeStartupConfig>>,
    _marker: std::marker::PhantomData<&'s ()>,
}

pub fn startup_demo(
    mut commands: Commands,
    config: Res<ServerConfig>,
    content_state: Res<RuntimeContentLoadState>,
    content: StartupContent,
    mut requests: MessageWriter<SpawnCharacterRequest>,
) {
    if !content_state.is_ready() {
        let error = format!(
            "runtime content failed to load: {:?}",
            content_state.failures
        );
        error!("{error}");
        commands.insert_resource(ServerSimulationRuntime(SimulationRuntime::new()));
        commands.insert_resource(ServerStartupState::Failed { error });
        return;
    }

    let (
        Some(definitions),
        Some(effects),
        Some(items),
        Some(maps),
        Some(overworld),
        Some(skills),
        Some(skill_trees),
        Some(recipes),
        Some(quests),
        Some(shops),
        Some(dialogues),
        Some(dialogue_rules),
        Some(startup_config),
    ) = (
        content.definitions,
        content.effects,
        content.items,
        content.maps,
        content.overworld,
        content.skills,
        content.skill_trees,
        content.recipes,
        content.quests,
        content.shops,
        content.dialogues,
        content.dialogue_rules,
        content.startup_config,
    )
    else {
        let error = "runtime content resources are incomplete after shared startup".to_string();
        error!("{error}");
        commands.insert_resource(ServerSimulationRuntime(SimulationRuntime::new()));
        commands.insert_resource(ServerStartupState::Failed { error });
        return;
    };

    let bootstrap_bundle = RuntimeBootstrapBundle {
        character_definitions: definitions.as_ref().clone(),
        map_definitions: maps.as_ref().clone(),
        overworld_definitions: overworld.as_ref().clone(),
        runtime_startup_config: startup_config.as_ref().clone(),
    };
    let seed = build_default_startup_seed(
        &bootstrap_bundle.map_definitions.0,
        &bootstrap_bundle.overworld_definitions.0,
        bootstrap_bundle.runtime_startup_config.startup_map.clone(),
    );

    info!(
        "bevy_server booted with headless loop at {} Hz",
        config.tick_rate_hz
    );
    info!(
        "loaded {} effect definitions from Rust game_data authority",
        effects.0.len()
    );
    info!(
        "loaded {} item definitions from Rust game_data authority",
        items.0.len()
    );
    info!(
        "loaded {} character definitions from Rust game_data authority",
        definitions.0.len()
    );
    info!(
        "loaded {} map definitions from Rust game_data authority",
        maps.0.len()
    );
    info!(
        "loaded {} overworld definitions from Rust game_data authority",
        overworld.0.len()
    );
    info!(
        "loaded {} skill definitions from Rust game_data authority",
        skills.0.len()
    );
    info!(
        "loaded {} skill tree definitions from Rust game_data authority",
        skill_trees.0.len()
    );
    info!(
        "loaded {} recipe definitions from Rust game_data authority",
        recipes.0.len()
    );
    info!(
        "loaded {} quest definitions from Rust game_data authority",
        quests.0.len()
    );
    info!(
        "loaded {} shop definitions from Rust game_data authority",
        shops.0.len()
    );
    match seed.map_id.as_ref() {
        Some(map_id) => {
            if maps.0.get(map_id).is_none() {
                let error = format!(
                    "configured startup_map {} was not found in loaded map definitions",
                    map_id
                );
                error!("{error}");
                commands.insert_resource(ServerSimulationRuntime(SimulationRuntime::new()));
                commands.insert_resource(ServerStartupState::Failed { error });
                return;
            }
            info!(
                "selected startup_map={} from shared bevy runtime config",
                map_id
            );
        }
        None => {
            info!("selected startup_map=<none>; no map definitions available");
        }
    }

    let mut runtime = match build_runtime_from_default_startup_seed(&bootstrap_bundle) {
        Ok(runtime) => runtime,
        Err(error) => {
            let error = format!("failed to build bevy_server runtime from startup seed: {error}");
            error!("{error}");
            commands.insert_resource(ServerSimulationRuntime(SimulationRuntime::new()));
            commands.insert_resource(ServerStartupState::Failed { error });
            return;
        }
    };
    runtime.set_map_library(maps.0.clone());
    runtime.set_overworld_library(overworld.0.clone());
    apply_gameplay_libraries(
        &mut runtime,
        &items,
        &skills,
        &recipes,
        &quests,
        &shops,
        &overworld,
    );
    apply_dialogue_libraries(&mut runtime, &dialogues, &dialogue_rules);
    let snapshot = runtime.snapshot();
    info!(
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
    let smoke_report = run_economy_smoke_demo(
        &mut runtime,
        &snapshot,
        &items.0,
        &skills.0,
        &recipes.0,
        &shops.0,
    );
    info!(
        "initialized headless economy actors={} shops={} default_recipe_domains_ready=true",
        runtime.economy().actor_count(),
        runtime.economy().shop_count(),
    );
    info!(
        "economy_smoke learned_skill={:?} crafted_recipe={:?} crafted_output={:?} bought_item={:?} sold_item={:?}",
        smoke_report.learned_skill_id,
        smoke_report.crafted_recipe_id,
        smoke_report.crafted_output_item_id,
        smoke_report.bought_item_id,
        smoke_report.sold_item_id,
    );
    commands.insert_resource(ServerSimulationRuntime(runtime));
    commands.insert_resource(ServerStartupState::Ready);
    commands.insert_resource(smoke_report);

    let mut total_requests = 0usize;
    for entry in &seed.characters {
        requests.write(SpawnCharacterRequest {
            definition_id: entry.definition_id.clone(),
            grid_position: entry.grid_position,
        });
        total_requests += 1;
    }

    // Queue life-enabled NPCs so the server can emit runtime AI debug snapshots on startup.
    let mut next_spawn_index: i32 = 0;
    for (definition_id, definition) in definitions.0.iter() {
        if definition.life.is_none() {
            continue;
        }
        if seed
            .characters
            .iter()
            .any(|entry| entry.definition_id == *definition_id)
        {
            continue;
        }
        requests.write(SpawnCharacterRequest {
            definition_id: definition_id.clone(),
            grid_position: GridCoord::new(8 + next_spawn_index, 0, 8),
        });
        next_spawn_index += 1;
        total_requests += 1;
    }

    if next_spawn_index > 0 {
        info!("queued {next_spawn_index} life-enabled npc spawns for AI debug visibility");
    }
    info!("startup queued total spawn requests={total_requests}");
}

pub fn advance_map_ai_spawns(
    config: Res<ServerConfig>,
    definitions: Res<CharacterDefinitions>,
    maps: Res<MapDefinitions>,
    mut spawn_state: ResMut<MapAiSpawnRuntimeState>,
    mut runtime: ResMut<ServerSimulationRuntime>,
) {
    let delta_seconds = 1.0 / f32::from(config.tick_rate_hz.max(1));
    advance_map_ai_spawn_runtime(
        &mut spawn_state,
        &mut runtime.0,
        &definitions.0,
        &maps.0,
        delta_seconds,
    );
}

pub fn run_economy_smoke_demo(
    runtime: &mut SimulationRuntime,
    snapshot: &game_core::SimulationSnapshot,
    items: &game_data::ItemLibrary,
    skills: &game_data::SkillLibrary,
    recipes: &game_data::RecipeLibrary,
    shops: &game_data::ShopLibrary,
) -> EconomySmokeReport {
    let Some(player_actor_id) = snapshot
        .actors
        .iter()
        .find(|actor| {
            actor.definition_id.as_ref().map(CharacterId::as_str) == Some("player")
                || actor.side == game_data::ActorSide::Player
        })
        .map(|actor| actor.actor_id)
    else {
        return EconomySmokeReport::default();
    };

    let mut report = EconomySmokeReport::default();

    if let Some((skill_id, definition)) = skills
        .iter()
        .find(|(_, definition)| definition.prerequisites.is_empty())
    {
        for (attribute, required) in &definition.attribute_requirements {
            runtime.economy_mut().set_actor_attribute(
                player_actor_id,
                attribute.clone(),
                *required,
            );
        }
        if runtime
            .economy_mut()
            .add_skill_points(player_actor_id, 1)
            .is_ok()
            && runtime
                .learn_skill(player_actor_id, skill_id, skills)
                .is_ok()
        {
            report.learned_skill_id = Some(skill_id.clone());
        }
    }

    if let Some((recipe_id, definition)) =
        recipes.iter().find(|(_, definition)| !definition.is_repair)
    {
        {
            let actor = runtime.economy_mut().ensure_actor(player_actor_id);
            if !definition.is_default_unlocked {
                actor.unlocked_recipes.insert(recipe_id.clone());
            }
            for condition in &definition.unlock_conditions {
                if condition.condition_type == "recipe" && !condition.id.trim().is_empty() {
                    actor.unlocked_recipes.insert(condition.id.clone());
                }
            }
            for (skill_id, required_level) in &definition.skill_requirements {
                actor
                    .learned_skills
                    .insert(skill_id.clone(), *required_level);
            }
        }

        for material in &definition.materials {
            let _ = runtime.economy_mut().add_item(
                player_actor_id,
                material.item_id,
                material.count,
                items,
            );
        }
        for tool_id in &definition.required_tools {
            if let Ok(tool_item_id) = tool_id.parse::<u32>() {
                let _ = runtime
                    .economy_mut()
                    .add_item(player_actor_id, tool_item_id, 1, items);
            } else {
                let _ = runtime
                    .economy_mut()
                    .grant_tool_tag(player_actor_id, tool_id.clone());
            }
        }
        if definition.required_station.trim() != "none"
            && !definition.required_station.trim().is_empty()
        {
            let _ = runtime
                .economy_mut()
                .grant_station_tag(player_actor_id, definition.required_station.clone());
        }

        if runtime
            .economy()
            .check_recipe(player_actor_id, recipe_id, recipes)
            .map(|check| check.can_craft())
            .unwrap_or(false)
        {
            if let Ok(outcome) = runtime.craft_recipe(player_actor_id, recipe_id, recipes, items) {
                report.crafted_recipe_id = Some(outcome.recipe_id);
                report.crafted_output_item_id = Some(outcome.output_item_id);
            }
        }
    }

    if let Some((shop_id, definition)) = shops.iter().next() {
        if let Some(first_entry) = definition.inventory.first() {
            let _ = runtime.economy_mut().grant_money(player_actor_id, 5_000);
            if runtime
                .buy_item_from_shop(player_actor_id, shop_id, first_entry.item_id, 1, items)
                .is_ok()
            {
                report.bought_item_id = Some(first_entry.item_id);
            }
            if runtime
                .sell_item_to_shop(player_actor_id, shop_id, first_entry.item_id, 1, items)
                .is_ok()
            {
                report.sold_item_id = Some(first_entry.item_id);
            }
        }
    }

    report
}

#[cfg(test)]
mod tests {
    use super::{startup_demo, EconomySmokeReport, ServerConfig, ServerSimulationRuntime};
    use bevy_app::{App, Startup};
    use bevy_ecs::message::MessageReader;
    use bevy_ecs::prelude::*;
    use game_bevy::{
        default_debug_seed, CharacterDefinitions, DialogueDefinitions, DialogueRuleDefinitions,
        EffectDefinitions, ItemDefinitions, MapDefinitions, OverworldDefinitions, QuestDefinitions,
        RecipeDefinitions, RuntimeContentLoadState, RuntimeContentLoadStatus, RuntimeStartupConfig,
        ShopDefinitions, SkillDefinitions, SkillTreeDefinitions, SpawnCharacterRequest,
    };
    use game_data::{
        CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate, CharacterCombatProfile,
        CharacterDefinition, CharacterDisposition, CharacterFaction, CharacterId,
        CharacterIdentity, CharacterLibrary, CharacterLifeProfile, CharacterLootEntry,
        CharacterPlaceholderColors, CharacterPresentation, CharacterProgression,
        CharacterResourcePool, DialogueLibrary, DialogueRuleLibrary, EffectLibrary, GridCoord,
        ItemLibrary, MapBuildingProps, MapCellDefinition, MapDefinition, MapEntryPointDefinition,
        MapId, MapLevelDefinition, MapLibrary, MapObjectDefinition, MapObjectFootprint,
        MapObjectKind, MapObjectProps, MapRotation, MapSize, NeedProfile, NpcRole,
        OverworldCellDefinition, OverworldDefinition, OverworldId, OverworldLibrary,
        OverworldLocationDefinition, OverworldLocationId, OverworldLocationKind,
        OverworldTravelRuleSet, QuestLibrary, RecipeLibrary, ScheduleBlock, ScheduleDay,
        ShopLibrary, SkillLibrary, SkillTreeLibrary,
    };
    use std::collections::BTreeMap;

    #[derive(Resource, Debug, Default)]
    struct CapturedRequests(Vec<SpawnCharacterRequest>);

    fn insert_startup_resources(app: &mut App, characters: CharacterDefinitions) {
        app.insert_resource(ServerConfig::default());
        app.insert_resource(RuntimeContentLoadState {
            status: RuntimeContentLoadStatus::Ready,
            failures: Vec::new(),
        });
        app.insert_resource(characters);
        app.insert_resource(EffectDefinitions(EffectLibrary::default()));
        app.insert_resource(ItemDefinitions(ItemLibrary::default()));
        app.insert_resource(MapDefinitions(sample_map_library()));
        app.insert_resource(OverworldDefinitions(sample_overworld_library()));
        app.insert_resource(SkillDefinitions(SkillLibrary::default()));
        app.insert_resource(SkillTreeDefinitions(SkillTreeLibrary::default()));
        app.insert_resource(RecipeDefinitions(RecipeLibrary::default()));
        app.insert_resource(QuestDefinitions(QuestLibrary::default()));
        app.insert_resource(ShopDefinitions(ShopLibrary::default()));
        app.insert_resource(DialogueDefinitions(DialogueLibrary::default()));
        app.insert_resource(DialogueRuleDefinitions(DialogueRuleLibrary::default()));
    }

    #[test]
    fn startup_demo_queues_shared_default_seed_requests() {
        let mut app = App::new();
        insert_startup_resources(&mut app, CharacterDefinitions(sample_character_library()));
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
        insert_startup_resources(&mut app, CharacterDefinitions(sample_character_library()));
        app.insert_resource(RuntimeStartupConfig {
            startup_map: Some(MapId("survivor_outpost_01_grid".into())),
        });
        app.add_message::<SpawnCharacterRequest>();
        app.add_systems(Startup, startup_demo);

        app.update();

        let runtime = app.world().resource::<ServerSimulationRuntime>();
        let snapshot = runtime.0.snapshot();

        assert_eq!(
            snapshot.grid.map_id.as_ref().map(MapId::as_str),
            Some("survivor_outpost_01_grid")
        );
        assert_eq!(snapshot.grid.map_width, Some(12));
        assert_eq!(snapshot.grid.map_height, Some(12));
    }

    #[test]
    fn startup_demo_adds_life_enabled_npcs_for_debug_visibility() {
        let mut app = App::new();
        insert_startup_resources(
            &mut app,
            CharacterDefinitions(sample_character_library_with_life()),
        );
        app.insert_resource(RuntimeStartupConfig { startup_map: None });
        app.insert_resource(CapturedRequests::default());
        app.add_message::<SpawnCharacterRequest>();
        app.add_systems(Startup, (startup_demo, capture_requests).chain());

        app.update();

        let captured = app.world().resource::<CapturedRequests>();
        let contains_guard = captured
            .0
            .iter()
            .any(|request| request.definition_id.as_str() == "survivor_outpost_01_guard_liu");
        assert!(
            contains_guard,
            "life-enabled npc should be queued for debug"
        );
    }

    #[test]
    fn startup_demo_inserts_default_economy_smoke_report() {
        let mut app = App::new();
        insert_startup_resources(&mut app, CharacterDefinitions(sample_character_library()));
        app.insert_resource(RuntimeStartupConfig { startup_map: None });
        app.add_message::<SpawnCharacterRequest>();
        app.add_systems(Startup, startup_demo);

        app.update();

        let report = app.world().resource::<EconomySmokeReport>();
        assert_eq!(report, &EconomySmokeReport::default());
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

    fn sample_character_library_with_life() -> CharacterLibrary {
        let mut map = BTreeMap::new();
        for definition in [
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
            sample_definition_with_life(
                "survivor_outpost_01_guard_liu",
                CharacterArchetype::Npc,
                CharacterDisposition::Friendly,
                "survivor",
                "据点卫兵·刘山",
            ),
        ] {
            map.insert(definition.id.clone(), definition);
        }
        CharacterLibrary::from(map)
    }

    fn sample_map_library() -> MapLibrary {
        let definition = MapDefinition {
            id: MapId("survivor_outpost_01_grid".into()),
            name: "Survivor Outpost 01".into(),
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
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
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
                        prefab_id: "survivor_outpost_01_dormitory".into(),
                        layout: None,
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

    fn sample_overworld_library() -> OverworldLibrary {
        let definition = OverworldDefinition {
            id: OverworldId("main_overworld".into()),
            size: MapSize {
                width: 3,
                height: 2,
            },
            locations: vec![
                sample_overworld_location("survivor_outpost_01", "survivor_outpost_01_grid", 1, 0),
                sample_overworld_location(
                    "survivor_outpost_01_perimeter",
                    "survivor_outpost_01_grid",
                    1,
                    1,
                ),
                sample_overworld_location("street_a", "survivor_outpost_01_grid", 0, 0),
                sample_overworld_location("street_b", "survivor_outpost_01_grid", 2, 0),
                OverworldLocationDefinition {
                    id: OverworldLocationId("survivor_outpost_01_interior".into()),
                    name: "Survivor Outpost 01 Interior".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Interior,
                    map_id: MapId("survivor_outpost_01_interior_grid".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: Some(OverworldLocationId(
                        "survivor_outpost_01".into(),
                    )),
                    return_entry_point_id: Some("default_entry".into()),
                    default_unlocked: true,
                    visible: false,
                    overworld_cell: GridCoord::new(1, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                },
            ],
            cells: vec![
                OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: "road".into(),
                    blocked: false,
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(1, 0, 0),
                    terrain: "road".into(),
                    blocked: false,
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(2, 0, 0),
                    terrain: "road".into(),
                    blocked: false,
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 1),
                    terrain: "road".into(),
                    blocked: false,
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(1, 0, 1),
                    terrain: "wilderness".into(),
                    blocked: false,
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(2, 0, 1),
                    terrain: "wilderness".into(),
                    blocked: false,
                    extra: BTreeMap::new(),
                },
            ],
            travel_rules: OverworldTravelRuleSet::default(),
        };

        let mut definitions = BTreeMap::new();
        definitions.insert(definition.id.clone(), definition);
        OverworldLibrary::from(definitions)
    }

    fn sample_overworld_location(
        id: &str,
        map_id: &str,
        x: i32,
        z: i32,
    ) -> OverworldLocationDefinition {
        OverworldLocationDefinition {
            id: OverworldLocationId(id.into()),
            name: id.into(),
            description: String::new(),
            kind: OverworldLocationKind::Outdoor,
            map_id: MapId(map_id.into()),
            entry_point_id: "default_entry".into(),
            parent_outdoor_location_id: None,
            return_entry_point_id: None,
            default_unlocked: true,
            visible: true,
            overworld_cell: GridCoord::new(x + 1, 0, z),
            danger_level: 0,
            icon: String::new(),
            extra: BTreeMap::new(),
        }
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
            interaction: None,
            life: None,
        }
    }

    fn sample_definition_with_life(
        id: &str,
        archetype: CharacterArchetype,
        disposition: CharacterDisposition,
        camp_id: &str,
        display_name: &str,
    ) -> CharacterDefinition {
        CharacterDefinition {
            life: Some(CharacterLifeProfile {
                settlement_id: "survivor_outpost_01_settlement".to_string(),
                role: NpcRole::Guard,
                ai_behavior_profile_id: "guard_settlement".to_string(),
                home_anchor: "guard_home_01".to_string(),
                duty_route_id: "guard_patrol_north".to_string(),
                schedule: vec![ScheduleBlock {
                    day: ScheduleDay::Monday,
                    start_minute: 8 * 60,
                    end_minute: 16 * 60,
                    label: "白班执勤".to_string(),
                    tags: vec!["shift".to_string(), "guard".to_string()],
                }],
                smart_object_access: vec!["guard_post".to_string(), "bed".to_string()],
                need_profile: NeedProfile {
                    hunger_decay_per_hour: 4.0,
                    energy_decay_per_hour: 3.0,
                    morale_decay_per_hour: 1.5,
                    safety_bias: 0.7,
                },
            }),
            ..sample_definition(id, archetype, disposition, camp_id, display_name)
        }
    }
}
