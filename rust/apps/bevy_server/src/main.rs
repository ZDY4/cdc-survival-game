use bevy_app::prelude::*;
use bevy_app::{AppExit, ScheduleRunnerPlugin, TaskPoolPlugin};
use bevy_ecs::prelude::*;
use std::time::Duration;

use game_bevy::{
    build_runtime_from_seed, default_debug_seed, load_character_definitions_on_startup,
    load_effect_definitions_on_startup, load_item_definitions_on_startup,
    load_map_definitions_on_startup, load_quest_definitions_on_startup,
    load_recipe_definitions_on_startup, load_runtime_startup_config_on_startup,
    load_settlement_definitions_on_startup, load_shop_definitions_on_startup,
    load_skill_definitions_on_startup, load_skill_tree_definitions_on_startup,
    resolve_startup_map_id,
    spawn_characters_from_definition, AiCombatProfile, BehaviorProfile, CampId,
    CharacterArchetypeComponent, CharacterDefinitionId, CharacterDefinitionPath,
    CharacterDefinitions, CharacterSpawnRejected, DisplayName, Disposition, EffectDefinitionPath,
    EffectDefinitions, GridPosition, ItemDefinitionPath, ItemDefinitions, Level, LootTable,
    MapDefinitionPath, MapDefinitions, NpcLifePlugin, QuestDefinitionPath, QuestDefinitions,
    RecipeDefinitionPath, RecipeDefinitions, RuntimeStartupConfig, RuntimeStartupConfigPath,
    SettlementDebugSnapshot, SettlementDefinitionPath, SettlementSimulationPlugin,
    ShopDefinitionPath, ShopDefinitions, SimClock, SkillDefinitionPath, SkillDefinitions,
    SkillTreeDefinitionPath, SkillTreeDefinitions, SpawnCharacterRequest, XpReward,
};
use game_core::{GameCorePlugin, HeadlessEconomyRuntime, SimulationRuntime};
use game_data::{CharacterId, GameDataPlugin, GridCoord};
use game_protocol::GameProtocolPlugin;

fn main() {
    App::new()
        .insert_resource(ServerConfig::default())
        .insert_resource(CharacterDefinitionPath::default())
        .insert_resource(EffectDefinitionPath::default())
        .insert_resource(ItemDefinitionPath::default())
        .insert_resource(MapDefinitionPath::default())
        .insert_resource(SettlementDefinitionPath::default())
        .insert_resource(SkillDefinitionPath::default())
        .insert_resource(SkillTreeDefinitionPath::default())
        .insert_resource(RecipeDefinitionPath::default())
        .insert_resource(QuestDefinitionPath::default())
        .insert_resource(ShopDefinitionPath::default())
        .insert_resource(RuntimeStartupConfigPath::default())
        .insert_resource(NpcDebugReportState::default())
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
                load_effect_definitions_on_startup,
                load_item_definitions_on_startup,
                load_map_definitions_on_startup,
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
                spawn_characters_from_definition,
                report_npc_life_debug_snapshot,
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

#[derive(Resource, Debug, Clone, Default)]
struct NpcDebugReportState {
    ticks: u32,
    printed_frames: u32,
}

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
struct EconomySmokeReport {
    learned_skill_id: Option<String>,
    crafted_recipe_id: Option<String>,
    crafted_output_item_id: Option<u32>,
    bought_item_id: Option<u32>,
    sold_item_id: Option<u32>,
}

fn startup_demo(
    mut commands: Commands,
    config: Res<ServerConfig>,
    definitions: Res<CharacterDefinitions>,
    effects: Res<EffectDefinitions>,
    items: Res<ItemDefinitions>,
    maps: Res<MapDefinitions>,
    skills: Res<SkillDefinitions>,
    skill_trees: Res<SkillTreeDefinitions>,
    recipes: Res<RecipeDefinitions>,
    quests: Res<QuestDefinitions>,
    shops: Res<ShopDefinitions>,
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
        "loaded {} effect definitions from Rust game_data authority",
        effects.0.len()
    );
    println!(
        "loaded {} item definitions from Rust game_data authority",
        items.0.len()
    );
    println!(
        "loaded {} character definitions from Rust game_data authority",
        definitions.0.len()
    );
    println!(
        "loaded {} map definitions from Rust game_data authority",
        maps.0.len()
    );
    println!(
        "loaded {} skill definitions from Rust game_data authority",
        skills.0.len()
    );
    println!(
        "loaded {} skill tree definitions from Rust game_data authority",
        skill_trees.0.len()
    );
    println!(
        "loaded {} recipe definitions from Rust game_data authority",
        recipes.0.len()
    );
    println!(
        "loaded {} quest definitions from Rust game_data authority",
        quests.0.len()
    );
    println!(
        "loaded {} shop definitions from Rust game_data authority",
        shops.0.len()
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

    let mut runtime = build_runtime_from_seed(&definitions.0, &maps.0, &seed)
        .unwrap_or_else(|error| {
            panic!("failed to build bevy_server runtime from startup seed: {error}")
        });
    runtime.set_item_library(items.0.clone());
    runtime.set_skill_library(skills.0.clone());
    runtime.set_recipe_library(recipes.0.clone());
    runtime.set_quest_library(quests.0.clone());
    runtime.set_shop_library(shops.0.clone());
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
    let smoke_report = run_economy_smoke_demo(
        runtime.economy_mut(),
        &snapshot,
        &items.0,
        &skills.0,
        &recipes.0,
        &shops.0,
    );
    println!(
        "initialized headless economy actors={} shops={} default_recipe_domains_ready=true",
        runtime.economy().actor_count(),
        runtime.economy().shop_count(),
    );
    println!(
        "economy_smoke learned_skill={:?} crafted_recipe={:?} crafted_output={:?} bought_item={:?} sold_item={:?}",
        smoke_report.learned_skill_id,
        smoke_report.crafted_recipe_id,
        smoke_report.crafted_output_item_id,
        smoke_report.bought_item_id,
        smoke_report.sold_item_id,
    );
    commands.insert_resource(ServerSimulationRuntime(runtime));
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
        println!("queued {next_spawn_index} life-enabled npc spawns for AI debug visibility");
    }
    println!("startup queued total spawn requests={total_requests}");
}

fn run_economy_smoke_demo(
    economy: &mut HeadlessEconomyRuntime,
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
            economy.set_actor_attribute(player_actor_id, attribute.clone(), *required);
        }
        if economy.add_skill_points(player_actor_id, 1).is_ok()
            && economy
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
            let actor = economy.ensure_actor(player_actor_id);
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
            let _ = economy.add_item(player_actor_id, material.item_id, material.count, items);
        }
        for tool_id in definition.required_tools.iter() {
            if let Ok(tool_item_id) = tool_id.parse::<u32>() {
                let _ = economy.add_item(player_actor_id, tool_item_id, 1, items);
            } else {
                let _ = economy.grant_tool_tag(player_actor_id, tool_id.clone());
            }
        }
        if definition.required_station.trim() != "none"
            && !definition.required_station.trim().is_empty()
        {
            let _ = economy.grant_station_tag(player_actor_id, definition.required_station.clone());
        }

        if economy
            .check_recipe(player_actor_id, recipe_id, recipes)
            .map(|check| check.can_craft())
            .unwrap_or(false)
        {
            if let Ok(outcome) = economy.craft_recipe(player_actor_id, recipe_id, recipes, items) {
                report.crafted_recipe_id = Some(outcome.recipe_id);
                report.crafted_output_item_id = Some(outcome.output_item_id);
            }
        }
    }

    if let Some((shop_id, definition)) = shops.iter().next() {
        if let Some(first_entry) = definition.inventory.first() {
            let _ = economy.grant_money(player_actor_id, 5_000);
            if economy
                .buy_item_from_shop(player_actor_id, shop_id, first_entry.item_id, 1, items)
                .is_ok()
            {
                report.bought_item_id = Some(first_entry.item_id);
            }
            if economy
                .sell_item_to_shop(player_actor_id, shop_id, first_entry.item_id, 1, items)
                .is_ok()
            {
                report.sold_item_id = Some(first_entry.item_id);
            }
        }
    }

    report
}

fn report_npc_life_debug_snapshot(
    mut debug_state: ResMut<NpcDebugReportState>,
    clock: Res<SimClock>,
    snapshot: Res<SettlementDebugSnapshot>,
) {
    debug_state.ticks += 1;
    if snapshot.entries.is_empty() {
        return;
    }
    if debug_state.printed_frames > 0 && debug_state.ticks % 10 != 0 {
        return;
    }
    debug_state.printed_frames += 1;

    println!(
        "npc_debug_snapshot day={:?} minute={} entries={}",
        clock.day,
        clock.minute_of_day,
        snapshot.entries.len(),
    );
    for entry in snapshot.entries.iter().take(6) {
        let top_scores = entry
            .goal_scores
            .iter()
            .take(3)
            .map(|score| format!("{:?}:{}", score.goal, score.score))
            .collect::<Vec<_>>()
            .join(",");
        let top_facts = entry
            .facts
            .iter()
            .take(5)
            .map(|fact| format!("{fact:?}"))
            .collect::<Vec<_>>()
            .join(",");
        let pending = entry
            .pending_plan
            .iter()
            .map(|step| format!("{:?}@{:?}", step.action, step.target_anchor))
            .collect::<Vec<_>>()
            .join(" -> ");
        println!(
            "npc entity={:?} role={:?} goal={:?} action={:?}/{:?} anchor={:?} needs(h/e/m)={}/{}/{} on_shift={} replan={} top_scores=[{}] facts=[{}] pending=[{}] summary={}",
            entry.entity,
            entry.role,
            entry.goal,
            entry.action,
            entry.action_phase,
            entry.current_anchor,
            entry.need_hunger,
            entry.need_energy,
            entry.need_morale,
            entry.on_shift,
            entry.replan_required,
            top_scores,
            top_facts,
            pending,
            entry.decision_summary,
        );
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
    debug_state: Res<NpcDebugReportState>,
    snapshot: Res<SettlementDebugSnapshot>,
    mut already_reported: Local<bool>,
    mut app_exit: MessageWriter<AppExit>,
) {
    if !*already_reported {
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
        }
        return;
    }

    for rejection in rejections.read() {
        println!(
            "character spawn rejected: definition_id={} reason={}",
            rejection.definition_id, rejection.reason
        );
    }

    let enough_debug_cycles = debug_state.printed_frames >= 2;
    let has_npc_debug_entries = !snapshot.entries.is_empty();
    let timeout_reached = debug_state.ticks >= 600;
    if (enough_debug_cycles && has_npc_debug_entries) || timeout_reached {
        if timeout_reached && !has_npc_debug_entries {
            println!("npc_debug_snapshot timeout reached without npc entries; shutting down");
        }
        app_exit.write(AppExit::Success);
    }
}

#[cfg(test)]
mod tests {
    use super::{startup_demo, EconomySmokeReport, ServerConfig, ServerSimulationRuntime};
    use bevy_app::{App, Startup};
    use bevy_ecs::message::MessageReader;
    use bevy_ecs::prelude::*;
    use game_bevy::{
        default_debug_seed, CharacterDefinitions, EffectDefinitions, ItemDefinitions,
        MapDefinitions, QuestDefinitions, RecipeDefinitions, RuntimeStartupConfig,
        ShopDefinitions, SkillDefinitions, SkillTreeDefinitions, SpawnCharacterRequest,
    };
    use game_data::{
        CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate, CharacterCombatProfile,
        CharacterDefinition, CharacterDisposition, CharacterFaction, CharacterId,
        CharacterIdentity, CharacterLibrary, CharacterLifeProfile, CharacterLootEntry,
        CharacterPlaceholderColors, CharacterPresentation, CharacterProgression,
        CharacterResourcePool, EffectLibrary, GridCoord, ItemLibrary, MapBuildingProps,
        MapCellDefinition, MapDefinition, MapId, MapLevelDefinition, MapLibrary,
        MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps, MapRotation,
        MapSize, NeedProfile, NpcRole, QuestLibrary, RecipeLibrary, ScheduleBlock, ScheduleDay,
        ShopLibrary, SkillLibrary, SkillTreeLibrary,
    };
    use std::collections::BTreeMap;

    #[derive(Resource, Debug, Default)]
    struct CapturedRequests(Vec<SpawnCharacterRequest>);

    #[test]
    fn startup_demo_queues_shared_default_seed_requests() {
        let mut app = App::new();
        app.insert_resource(ServerConfig::default());
        app.insert_resource(CharacterDefinitions(sample_character_library()));
        app.insert_resource(EffectDefinitions(EffectLibrary::default()));
        app.insert_resource(ItemDefinitions(ItemLibrary::default()));
        app.insert_resource(MapDefinitions(sample_map_library()));
        app.insert_resource(SkillDefinitions(SkillLibrary::default()));
        app.insert_resource(SkillTreeDefinitions(SkillTreeLibrary::default()));
        app.insert_resource(RecipeDefinitions(RecipeLibrary::default()));
        app.insert_resource(QuestDefinitions(QuestLibrary::default()));
        app.insert_resource(ShopDefinitions(ShopLibrary::default()));
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
        app.insert_resource(EffectDefinitions(EffectLibrary::default()));
        app.insert_resource(ItemDefinitions(ItemLibrary::default()));
        app.insert_resource(MapDefinitions(sample_map_library()));
        app.insert_resource(SkillDefinitions(SkillLibrary::default()));
        app.insert_resource(SkillTreeDefinitions(SkillTreeLibrary::default()));
        app.insert_resource(RecipeDefinitions(RecipeLibrary::default()));
        app.insert_resource(QuestDefinitions(QuestLibrary::default()));
        app.insert_resource(ShopDefinitions(ShopLibrary::default()));
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

    #[test]
    fn startup_demo_adds_life_enabled_npcs_for_debug_visibility() {
        let mut app = App::new();
        app.insert_resource(ServerConfig::default());
        app.insert_resource(CharacterDefinitions(sample_character_library_with_life()));
        app.insert_resource(EffectDefinitions(EffectLibrary::default()));
        app.insert_resource(ItemDefinitions(ItemLibrary::default()));
        app.insert_resource(MapDefinitions(sample_map_library()));
        app.insert_resource(SkillDefinitions(SkillLibrary::default()));
        app.insert_resource(SkillTreeDefinitions(SkillTreeLibrary::default()));
        app.insert_resource(RecipeDefinitions(RecipeLibrary::default()));
        app.insert_resource(QuestDefinitions(QuestLibrary::default()));
        app.insert_resource(ShopDefinitions(ShopLibrary::default()));
        app.insert_resource(RuntimeStartupConfig { startup_map: None });
        app.insert_resource(CapturedRequests::default());
        app.add_message::<SpawnCharacterRequest>();
        app.add_systems(Startup, (startup_demo, capture_requests).chain());

        app.update();

        let captured = app.world().resource::<CapturedRequests>();
        let contains_guard = captured
            .0
            .iter()
            .any(|request| request.definition_id.as_str() == "safehouse_guard_liu");
        assert!(
            contains_guard,
            "life-enabled npc should be queued for debug"
        );
    }

    #[test]
    fn startup_demo_inserts_default_economy_smoke_report() {
        let mut app = App::new();
        app.insert_resource(ServerConfig::default());
        app.insert_resource(CharacterDefinitions(sample_character_library()));
        app.insert_resource(EffectDefinitions(EffectLibrary::default()));
        app.insert_resource(ItemDefinitions(ItemLibrary::default()));
        app.insert_resource(MapDefinitions(sample_map_library()));
        app.insert_resource(SkillDefinitions(SkillLibrary::default()));
        app.insert_resource(SkillTreeDefinitions(SkillTreeLibrary::default()));
        app.insert_resource(RecipeDefinitions(RecipeLibrary::default()));
        app.insert_resource(QuestDefinitions(QuestLibrary::default()));
        app.insert_resource(ShopDefinitions(ShopLibrary::default()));
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
                "safehouse_guard_liu",
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
                settlement_id: "safehouse_survivor_outpost".to_string(),
                role: NpcRole::Guard,
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
