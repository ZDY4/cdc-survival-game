use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use bevy_ecs::prelude::*;
use game_core::simulation::Simulation;
use game_core::{
    FollowGridGoalAiController, HeadlessEconomyRuntime, NoopAiController, RegisterActor,
    SimulationRuntime,
};
use game_data::{
    load_character_library, load_effect_library, load_item_library, load_map_library,
    load_overworld_library, load_quest_library, load_recipe_library, load_settlement_library,
    load_shop_library, load_skill_library, load_skill_tree_library, ActorId, ActorKind,
    ActorSide, CharacterAiProfile, CharacterArchetype, CharacterDefinition,
    CharacterDisposition, CharacterId, CharacterLibrary, CharacterLoadError,
    CharacterLootEntry, CharacterPlaceholderColors, CharacterResourcePool, EffectLibrary,
    EffectLoadError, GridCoord, ItemLibrary, ItemLoadError, MapId,
    MapLibrary, MapLoadError, OverworldLibrary, OverworldLoadError, QuestLibrary,
    QuestLoadError, RecipeLibrary, RecipeLoadError, SettlementLibrary, SettlementLoadError,
    ShopLibrary, ShopLoadError, SkillLibrary, SkillLoadError, SkillTreeLibrary,
    SkillTreeLoadError, WorldMode,
};
use npc_life::LifeProfileComponent;
use thiserror::Error;

pub mod bootstrap;
pub mod npc_life;
pub mod reservations;

pub use bootstrap::{
    build_default_startup_seed, build_runtime_from_default_startup_seed, load_runtime_bootstrap,
    RuntimeBootstrapBundle, RuntimeBootstrapError,
};
pub use npc_life::{
    BackgroundLifeState, CurrentAction, CurrentGoal, CurrentPlan,
    LifeProfileComponent as CharacterLifeProfileComponent, NeedState, NpcLifePlugin,
    NpcLifeState, ReservationState, RuntimeActorLink, RuntimeExecutionState, ScheduleState,
    SettlementContext, SettlementDebugEntry, SettlementDebugSnapshot,
    SettlementSimulationPlugin, SimClock, WorldAlertState,
};
pub use reservations::SmartObjectReservations;

#[derive(Resource, Debug, Clone)]
pub struct CharacterDefinitionPath(pub PathBuf);

impl Default for CharacterDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/characters"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct CharacterDefinitions(pub CharacterLibrary);

#[derive(Resource, Debug, Clone)]
pub struct MapDefinitionPath(pub PathBuf);

impl Default for MapDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/maps"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct MapDefinitions(pub MapLibrary);

#[derive(Resource, Debug, Clone)]
pub struct OverworldDefinitionPath(pub PathBuf);

impl Default for OverworldDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/overworld"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct OverworldDefinitions(pub OverworldLibrary);

#[derive(Resource, Debug, Clone)]
pub struct SettlementDefinitionPath(pub PathBuf);

impl Default for SettlementDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/settlements"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct SettlementDefinitions(pub SettlementLibrary);

#[derive(Resource, Debug, Clone)]
pub struct EffectDefinitionPath(pub PathBuf);

impl Default for EffectDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/json/effects"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct EffectDefinitions(pub EffectLibrary);

#[derive(Resource, Debug, Clone)]
pub struct ItemDefinitionPath(pub PathBuf);

impl Default for ItemDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/items"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct ItemDefinitions(pub ItemLibrary);

#[derive(Resource, Debug, Clone)]
pub struct SkillDefinitionPath(pub PathBuf);

impl Default for SkillDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/skills"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct SkillDefinitions(pub SkillLibrary);

#[derive(Resource, Debug, Clone)]
pub struct SkillTreeDefinitionPath(pub PathBuf);

impl Default for SkillTreeDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/skill_trees"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct SkillTreeDefinitions(pub SkillTreeLibrary);

#[derive(Resource, Debug, Clone)]
pub struct RecipeDefinitionPath(pub PathBuf);

impl Default for RecipeDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/recipes"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct RecipeDefinitions(pub RecipeLibrary);

#[derive(Resource, Debug, Clone)]
pub struct QuestDefinitionPath(pub PathBuf);

impl Default for QuestDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/quests"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct QuestDefinitions(pub QuestLibrary);

#[derive(Resource, Debug, Clone)]
pub struct ShopDefinitionPath(pub PathBuf);

impl Default for ShopDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/shops"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct ShopDefinitions(pub ShopLibrary);

#[derive(Resource, Debug, Clone, Default)]
pub struct ServerEconomyState(pub HeadlessEconomyRuntime);

#[derive(Resource, Debug, Clone)]
pub struct RuntimeStartupConfigPath(pub PathBuf);

impl Default for RuntimeStartupConfigPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../config/bevy_runtime.ini"))
    }
}

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub struct RuntimeStartupConfig {
    pub startup_map: Option<MapId>,
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub struct SpawnCharacterRequest {
    pub definition_id: CharacterId,
    pub grid_position: GridCoord,
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub struct CharacterSpawnRejected {
    pub definition_id: CharacterId,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeSpawnEntry {
    pub definition_id: CharacterId,
    pub grid_position: GridCoord,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RuntimeScenarioSeed {
    pub map_id: Option<MapId>,
    pub start_world_mode: Option<WorldMode>,
    pub start_location_id: Option<String>,
    pub start_map_id: Option<MapId>,
    pub start_entry_point_id: Option<String>,
    pub unlocked_locations: Vec<String>,
    pub static_obstacles: Vec<GridCoord>,
    pub characters: Vec<RuntimeSpawnEntry>,
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum RuntimeBuildError {
    #[error("unknown character definition: {definition_id}")]
    UnknownCharacterDefinition { definition_id: CharacterId },
    #[error("unknown map definition: {map_id}")]
    UnknownMapDefinition { map_id: MapId },
    #[error("invalid overworld seed: {message}")]
    InvalidOverworldSeed { message: String },
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum RuntimeStartupConfigError {
    #[error("failed to read runtime startup config {path}: {message}")]
    ReadFile { path: PathBuf, message: String },
    #[error("invalid config line {line_number}: {line}")]
    InvalidLine { line_number: usize, line: String },
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct CharacterDefinitionId(pub CharacterId);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct CharacterArchetypeComponent(pub CharacterArchetype);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct Disposition(pub CharacterDisposition);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct CampId(pub String);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct DisplayName(pub String);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct Description(pub String);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct Level(pub u32);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct BehaviorProfile(pub String);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct AiCombatProfile(pub CharacterAiProfile);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct XpReward(pub i32);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct LootTable(pub Vec<CharacterLootEntry>);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct PortraitPath(pub String);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct AvatarPath(pub String);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct ModelPath(pub String);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct PlaceholderColors(pub CharacterPlaceholderColors);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct BaseAttributeSet(pub BTreeMap<String, f32>);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct CombatAttributeSet(pub BTreeMap<String, f32>);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct ResourcePools(pub BTreeMap<String, CharacterResourcePool>);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct GridPosition(pub GridCoord);

#[derive(Bundle, Debug, Clone, PartialEq)]
struct SpawnedCharacterBundle {
    definition_id: CharacterDefinitionId,
    archetype: CharacterArchetypeComponent,
    disposition: Disposition,
    camp_id: CampId,
    display_name: DisplayName,
    description: Description,
    level: Level,
    behavior: BehaviorProfile,
    ai: AiCombatProfile,
    xp_reward: XpReward,
    loot: LootTable,
    portrait: PortraitPath,
    avatar: AvatarPath,
    model: ModelPath,
    placeholder_colors: PlaceholderColors,
    base_attributes: BaseAttributeSet,
    combat_attributes: CombatAttributeSet,
    resources: ResourcePools,
    grid_position: GridPosition,
}

pub fn load_character_definitions(
    path: impl AsRef<Path>,
) -> Result<CharacterDefinitions, CharacterLoadError> {
    Ok(CharacterDefinitions(load_character_library(path)?))
}

pub fn load_effect_definitions(
    path: impl AsRef<Path>,
) -> Result<EffectDefinitions, EffectLoadError> {
    Ok(EffectDefinitions(load_effect_library(path)?))
}

pub fn load_item_definitions(
    path: impl AsRef<Path>,
    effects: Option<&EffectLibrary>,
) -> Result<ItemDefinitions, ItemLoadError> {
    Ok(ItemDefinitions(load_item_library(path, effects)?))
}

pub fn load_map_definitions(path: impl AsRef<Path>) -> Result<MapDefinitions, MapLoadError> {
    Ok(MapDefinitions(load_map_library(path)?))
}

pub fn load_overworld_definitions(
    path: impl AsRef<Path>,
) -> Result<OverworldDefinitions, OverworldLoadError> {
    Ok(OverworldDefinitions(load_overworld_library(path)?))
}

pub fn load_settlement_definitions(
    path: impl AsRef<Path>,
) -> Result<SettlementDefinitions, SettlementLoadError> {
    Ok(SettlementDefinitions(load_settlement_library(path)?))
}

pub fn load_skill_definitions(path: impl AsRef<Path>) -> Result<SkillDefinitions, SkillLoadError> {
    Ok(SkillDefinitions(load_skill_library(path, None)?))
}

pub fn load_skill_tree_definitions(
    path: impl AsRef<Path>,
) -> Result<SkillTreeDefinitions, SkillTreeLoadError> {
    Ok(SkillTreeDefinitions(load_skill_tree_library(path, None)?))
}

pub fn load_recipe_definitions(
    path: impl AsRef<Path>,
) -> Result<RecipeDefinitions, RecipeLoadError> {
    Ok(RecipeDefinitions(load_recipe_library(path, None)?))
}

pub fn load_quest_definitions(path: impl AsRef<Path>) -> Result<QuestDefinitions, QuestLoadError> {
    Ok(QuestDefinitions(load_quest_library(path, None)?))
}

pub fn load_shop_definitions(path: impl AsRef<Path>) -> Result<ShopDefinitions, ShopLoadError> {
    Ok(ShopDefinitions(load_shop_library(path, None)?))
}

pub fn load_character_definitions_on_startup(
    mut commands: Commands,
    path: Res<CharacterDefinitionPath>,
) {
    let definitions = load_character_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load character definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_map_definitions_on_startup(mut commands: Commands, path: Res<MapDefinitionPath>) {
    let definitions = load_map_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load map definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_overworld_definitions_on_startup(
    mut commands: Commands,
    path: Res<OverworldDefinitionPath>,
) {
    let definitions = load_overworld_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load overworld definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_settlement_definitions_on_startup(
    mut commands: Commands,
    path: Res<SettlementDefinitionPath>,
) {
    let definitions = load_settlement_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load settlement definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_effect_definitions_on_startup(mut commands: Commands, path: Res<EffectDefinitionPath>) {
    let definitions = load_effect_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load effect definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_item_definitions_on_startup(
    mut commands: Commands,
    path: Res<ItemDefinitionPath>,
    effects: Option<Res<EffectDefinitions>>,
) {
    let effect_library = effects.as_ref().map(|definitions| &definitions.0);
    let definitions = load_item_definitions(&path.0, effect_library).unwrap_or_else(|error| {
        panic!(
            "failed to load item definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_skill_definitions_on_startup(mut commands: Commands, path: Res<SkillDefinitionPath>) {
    let definitions = load_skill_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load skill definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_skill_tree_definitions_on_startup(
    mut commands: Commands,
    path: Res<SkillTreeDefinitionPath>,
) {
    let definitions = load_skill_tree_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load skill tree definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_recipe_definitions_on_startup(mut commands: Commands, path: Res<RecipeDefinitionPath>) {
    let definitions = load_recipe_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load recipe definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_quest_definitions_on_startup(mut commands: Commands, path: Res<QuestDefinitionPath>) {
    let definitions = load_quest_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load quest definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn load_shop_definitions_on_startup(mut commands: Commands, path: Res<ShopDefinitionPath>) {
    let definitions = load_shop_definitions(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load shop definitions from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(definitions);
}

pub fn parse_runtime_startup_config(
    source: &str,
) -> Result<RuntimeStartupConfig, RuntimeStartupConfigError> {
    let mut config = RuntimeStartupConfig::default();
    let mut current_section = String::new();

    for (line_index, raw_line) in source.lines().enumerate() {
        let line_number = line_index + 1;
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with(';') || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            current_section = line[1..line.len() - 1].trim().to_ascii_lowercase();
            continue;
        }

        let Some((key, value)) = line.split_once('=') else {
            return Err(RuntimeStartupConfigError::InvalidLine {
                line_number,
                line: line.to_string(),
            });
        };
        if current_section != "startup" {
            continue;
        }

        if key.trim().eq_ignore_ascii_case("startup_map") {
            let value = value.trim().trim_matches('"').trim();
            config.startup_map = if value.is_empty() {
                None
            } else {
                Some(MapId(value.to_string()))
            };
        }
    }

    Ok(config)
}

pub fn load_runtime_startup_config(
    path: impl AsRef<Path>,
) -> Result<RuntimeStartupConfig, RuntimeStartupConfigError> {
    let path = path.as_ref();
    if !path.exists() {
        return Ok(RuntimeStartupConfig::default());
    }

    let raw = fs::read_to_string(path).map_err(|error| RuntimeStartupConfigError::ReadFile {
        path: path.to_path_buf(),
        message: error.to_string(),
    })?;
    parse_runtime_startup_config(&raw)
}

pub fn load_runtime_startup_config_on_startup(
    mut commands: Commands,
    path: Res<RuntimeStartupConfigPath>,
) {
    let config = load_runtime_startup_config(&path.0).unwrap_or_else(|error| {
        panic!(
            "failed to load runtime startup config from {}: {error}",
            path.0.display()
        )
    });
    commands.insert_resource(config);
}

pub fn resolve_startup_map_id(
    maps: &MapLibrary,
    configured_map_id: Option<MapId>,
) -> Option<MapId> {
    if let Some(map_id) = configured_map_id {
        return Some(map_id);
    }

    maps.iter().next().map(|(map_id, _)| map_id.clone())
}

pub fn spawn_characters_from_definition(
    mut commands: Commands,
    definitions: Option<Res<CharacterDefinitions>>,
    mut requests: MessageReader<SpawnCharacterRequest>,
    mut rejections: MessageWriter<CharacterSpawnRejected>,
) {
    let Some(definitions) = definitions else {
        for request in requests.read() {
            rejections.write(CharacterSpawnRejected {
                definition_id: request.definition_id.clone(),
                reason: "character_definitions_missing".to_string(),
            });
        }
        return;
    };

    for request in requests.read() {
        let Some(definition) = definitions.0.get(&request.definition_id) else {
            rejections.write(CharacterSpawnRejected {
                definition_id: request.definition_id.clone(),
                reason: format!("unknown_character_definition: {}", request.definition_id),
            });
            continue;
        };

        spawn_character_entity(&mut commands, definition, request.grid_position);
    }
}

pub fn build_simulation_from_seed(
    definitions: &CharacterLibrary,
    maps: &MapLibrary,
    overworld: &OverworldLibrary,
    seed: &RuntimeScenarioSeed,
) -> Result<Simulation, RuntimeBuildError> {
    let mut simulation = Simulation::new();
    simulation.set_map_library(maps.clone());
    simulation.set_overworld_library(overworld.clone());

    let requested_world_mode = seed.start_world_mode.unwrap_or({
        if seed.start_location_id.is_some() || seed.start_map_id.is_some() || seed.map_id.is_some()
        {
            WorldMode::Outdoor
        } else {
            WorldMode::Unknown
        }
    });
    let requested_map_id = seed.start_map_id.as_ref().or(seed.map_id.as_ref());

    if !matches!(requested_world_mode, WorldMode::Overworld | WorldMode::Traveling) {
        if let Some(map_id) = requested_map_id {
            let map = maps
                .get(map_id)
                .ok_or_else(|| RuntimeBuildError::UnknownMapDefinition {
                    map_id: map_id.clone(),
                })?;
            simulation.grid_world_mut().load_map(map);
        }
    }

    let mut player_actor_id = None;
    for obstacle in &seed.static_obstacles {
        simulation
            .grid_world_mut()
            .register_static_obstacle(*obstacle);
    }
    for entry in &seed.characters {
        let definition = definitions.get(&entry.definition_id).ok_or_else(|| {
            RuntimeBuildError::UnknownCharacterDefinition {
                definition_id: entry.definition_id.clone(),
            }
        })?;
        let actor_id = simulation.register_actor(register_actor_from_definition(
            definition,
            entry.grid_position,
        ));
        if player_actor_id.is_none() && definition.archetype == CharacterArchetype::Player {
            player_actor_id = Some(actor_id);
        }
        simulation.seed_actor_progression(
            actor_id,
            definition.progression.level as i32,
            definition.combat.xp_reward,
        );
        simulation.seed_actor_combat_profile(
            actor_id,
            definition
                .attributes
                .sets
                .get("combat")
                .cloned()
                .unwrap_or_default(),
            definition.attributes.resources.clone(),
        );
        simulation.seed_actor_loot_table(actor_id, definition.combat.loot.clone());
    }

    for location_id in &seed.unlocked_locations {
        match simulation.apply_command(game_core::SimulationCommand::UnlockLocation {
            location_id: location_id.clone(),
        }) {
            game_core::SimulationCommandResult::OverworldState(Ok(_))
            | game_core::SimulationCommandResult::None => {}
            game_core::SimulationCommandResult::OverworldState(Err(message)) => {
                return Err(RuntimeBuildError::InvalidOverworldSeed { message });
            }
            other => {
                return Err(RuntimeBuildError::InvalidOverworldSeed {
                    message: format!("unexpected unlock command result: {other:?}"),
                });
            }
        }
    }

    if matches!(requested_world_mode, WorldMode::Overworld | WorldMode::Traveling) {
        simulation
            .seed_overworld_state(
                requested_world_mode,
                seed.start_location_id.clone(),
                seed.start_entry_point_id.clone(),
                Vec::<String>::new(),
            )
            .map_err(|message| RuntimeBuildError::InvalidOverworldSeed { message })?;
    } else if let Some(location_id) = seed.start_location_id.as_ref() {
        let Some(player_actor_id) = player_actor_id else {
            return Err(RuntimeBuildError::InvalidOverworldSeed {
                message: "missing_player_actor_for_location_start".to_string(),
            });
        };
        match simulation.apply_command(game_core::SimulationCommand::EnterLocation {
            actor_id: player_actor_id,
            location_id: location_id.clone(),
            entry_point_id: seed.start_entry_point_id.clone(),
        }) {
            game_core::SimulationCommandResult::LocationTransition(Ok(_)) => {}
            game_core::SimulationCommandResult::LocationTransition(Err(message)) => {
                return Err(RuntimeBuildError::InvalidOverworldSeed { message });
            }
            other => {
                return Err(RuntimeBuildError::InvalidOverworldSeed {
                    message: format!("unexpected enter location result: {other:?}"),
                });
            }
        }
    }

    Ok(simulation)
}

pub fn build_runtime_from_seed(
    definitions: &CharacterLibrary,
    maps: &MapLibrary,
    overworld: &OverworldLibrary,
    seed: &RuntimeScenarioSeed,
) -> Result<SimulationRuntime, RuntimeBuildError> {
    Ok(SimulationRuntime::from_simulation(
        build_simulation_from_seed(definitions, maps, overworld, seed)?,
    ))
}

pub fn register_runtime_actor_from_definition(
    runtime: &mut SimulationRuntime,
    definition: &CharacterDefinition,
    grid_position: GridCoord,
) -> ActorId {
    let actor_id = runtime.register_actor(register_actor_from_definition(definition, grid_position));
    runtime.seed_actor_progression(
        actor_id,
        definition.progression.level as i32,
        definition.combat.xp_reward,
    );
    runtime.seed_actor_combat_profile(
        actor_id,
        definition
            .attributes
            .sets
            .get("combat")
            .cloned()
            .unwrap_or_default(),
        definition.attributes.resources.clone(),
    );
    runtime.seed_actor_loot_table(actor_id, definition.combat.loot.clone());
    actor_id
}

pub fn default_debug_seed() -> RuntimeScenarioSeed {
    RuntimeScenarioSeed {
        map_id: Some(MapId("survivor_outpost_01_grid".to_string())),
        start_world_mode: Some(WorldMode::Outdoor),
        start_location_id: Some("survivor_outpost_01".to_string()),
        start_map_id: Some(MapId("survivor_outpost_01_grid".to_string())),
        start_entry_point_id: Some("default_entry".to_string()),
        unlocked_locations: vec![
            "survivor_outpost_01".to_string(),
            "street_a".to_string(),
            "street_b".to_string(),
            "survivor_outpost_01_perimeter".to_string(),
            "survivor_outpost_01_interior".to_string(),
        ],
        static_obstacles: Vec::new(),
        characters: vec![
            RuntimeSpawnEntry {
                definition_id: CharacterId("player".to_string()),
                grid_position: GridCoord::new(0, 0, 0),
            },
            RuntimeSpawnEntry {
                definition_id: CharacterId("trader_lao_wang".to_string()),
                grid_position: GridCoord::new(1, 0, 0),
            },
            RuntimeSpawnEntry {
                definition_id: CharacterId("zombie_walker".to_string()),
                grid_position: GridCoord::new(4, 0, 0),
            },
        ],
    }
}

fn spawn_character_entity(
    commands: &mut Commands,
    definition: &CharacterDefinition,
    grid_position: GridCoord,
) -> Entity {
    let base_attributes = definition
        .attributes
        .sets
        .get("base")
        .cloned()
        .unwrap_or_default();
    let combat_attributes = definition
        .attributes
        .sets
        .get("combat")
        .cloned()
        .unwrap_or_default();

    let entity = commands
        .spawn(SpawnedCharacterBundle {
            definition_id: CharacterDefinitionId(definition.id.clone()),
            archetype: CharacterArchetypeComponent(definition.archetype),
            disposition: Disposition(definition.faction.disposition),
            camp_id: CampId(definition.faction.camp_id.clone()),
            display_name: DisplayName(definition.identity.display_name.clone()),
            description: Description(definition.identity.description.clone()),
            level: Level(definition.progression.level),
            behavior: BehaviorProfile(definition.combat.behavior.clone()),
            ai: AiCombatProfile(definition.ai.clone()),
            xp_reward: XpReward(definition.combat.xp_reward),
            loot: LootTable(definition.combat.loot.clone()),
            portrait: PortraitPath(definition.presentation.portrait_path.clone()),
            avatar: AvatarPath(definition.presentation.avatar_path.clone()),
            model: ModelPath(definition.presentation.model_path.clone()),
            placeholder_colors: PlaceholderColors(
                definition.presentation.placeholder_colors.clone(),
            ),
            base_attributes: BaseAttributeSet(base_attributes),
            combat_attributes: CombatAttributeSet(combat_attributes),
            resources: ResourcePools(definition.attributes.resources.clone()),
            grid_position: GridPosition(grid_position),
        })
        .id();

    if let Some(life) = definition.life.clone() {
        commands.entity(entity).insert(LifeProfileComponent(life));
    }

    entity
}

fn register_actor_from_definition(
    definition: &CharacterDefinition,
    grid_position: GridCoord,
) -> RegisterActor {
    let ai_controller = if definition.life.is_some() {
        Some(Box::new(FollowGridGoalAiController) as Box<_>)
    } else {
        Some(Box::new(NoopAiController) as Box<_>)
    };

    RegisterActor {
        definition_id: Some(definition.id.clone()),
        display_name: definition.identity.display_name.clone(),
        kind: actor_kind_from_archetype(definition.archetype),
        side: actor_side_from_disposition(definition.faction.disposition),
        group_id: actor_group_id(definition),
        grid_position,
        interaction: definition.interaction.clone(),
        attack_range: definition.ai.attack_range,
        ai_controller,
    }
}

fn actor_kind_from_archetype(archetype: CharacterArchetype) -> ActorKind {
    match archetype {
        CharacterArchetype::Player => ActorKind::Player,
        CharacterArchetype::Npc => ActorKind::Npc,
        CharacterArchetype::Enemy => ActorKind::Enemy,
    }
}

fn actor_side_from_disposition(disposition: CharacterDisposition) -> ActorSide {
    match disposition {
        CharacterDisposition::Player => ActorSide::Player,
        CharacterDisposition::Friendly => ActorSide::Friendly,
        CharacterDisposition::Hostile => ActorSide::Hostile,
        CharacterDisposition::Neutral => ActorSide::Neutral,
    }
}

fn actor_group_id(definition: &CharacterDefinition) -> String {
    if definition.archetype == CharacterArchetype::Player {
        "player".to_string()
    } else {
        definition.faction.camp_id.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::{
        build_runtime_from_seed, default_debug_seed, load_runtime_startup_config,
        parse_runtime_startup_config, resolve_startup_map_id, spawn_characters_from_definition,
        AiCombatProfile, AvatarPath, BaseAttributeSet, BehaviorProfile, CampId,
        CharacterArchetypeComponent, CharacterDefinitionId, CharacterDefinitionPath,
        CharacterDefinitions, CharacterSpawnRejected, CombatAttributeSet, Description, DisplayName,
        Disposition, GridPosition, Level, LootTable, MapDefinitionPath, ModelPath,
        PlaceholderColors, PortraitPath, ResourcePools, RuntimeBuildError, RuntimeScenarioSeed,
        RuntimeSpawnEntry, RuntimeStartupConfig, SpawnCharacterRequest, XpReward,
    };
    use bevy_app::{App, Update};
    use bevy_ecs::message::{MessageReader, Messages};
    use bevy_ecs::prelude::*;
    use game_data::{
        CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate, CharacterCombatProfile,
        CharacterDefinition, CharacterDisposition, CharacterFaction, CharacterId,
        CharacterIdentity, CharacterLibrary, CharacterLootEntry, CharacterPlaceholderColors,
        CharacterPresentation, CharacterProgression, CharacterResourcePool, GridCoord,
        MapBuildingProps, MapCellDefinition, MapDefinition, MapEntryPointDefinition, MapId,
        MapLevelDefinition, MapLibrary, MapObjectDefinition, MapObjectFootprint, MapObjectKind,
        MapObjectProps, MapRotation, MapSize, OverworldCellDefinition, OverworldDefinition,
        OverworldEdgeDefinition, OverworldId, OverworldLibrary, OverworldLocationDefinition,
        OverworldLocationId, OverworldLocationKind, OverworldTravelRuleSet,
    };
    use std::collections::BTreeMap;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[derive(Resource, Debug, Default)]
    struct CapturedRejections(Vec<CharacterSpawnRejected>);

    #[test]
    fn runtime_seed_maps_character_metadata_to_core_runtime() {
        let library = sample_library();
        let maps = sample_map_library();
        let seed = RuntimeScenarioSeed {
            map_id: Some(MapId("survivor_outpost_01_grid".into())),
            static_obstacles: vec![GridCoord::new(2, 0, 1)],
            characters: vec![
                RuntimeSpawnEntry {
                    definition_id: CharacterId("player".into()),
                    grid_position: GridCoord::new(0, 0, 0),
                },
                RuntimeSpawnEntry {
                    definition_id: CharacterId("trader_lao_wang".into()),
                    grid_position: GridCoord::new(1, 0, 0),
                },
                RuntimeSpawnEntry {
                    definition_id: CharacterId("zombie_walker".into()),
                    grid_position: GridCoord::new(4, 0, 0),
                },
            ],
            ..RuntimeScenarioSeed::default()
        };

        let runtime = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect("runtime should build");
        let snapshot = runtime.snapshot();

        let player = snapshot
            .actors
            .iter()
            .find(|actor| actor.definition_id.as_ref().map(CharacterId::as_str) == Some("player"))
            .expect("player actor should exist");
        assert_eq!(player.kind, game_data::ActorKind::Player);
        assert_eq!(player.side, game_data::ActorSide::Player);
        assert_eq!(player.group_id, "player");
        assert_eq!(player.display_name, "Rust Player");

        let npc = snapshot
            .actors
            .iter()
            .find(|actor| {
                actor.definition_id.as_ref().map(CharacterId::as_str) == Some("trader_lao_wang")
            })
            .expect("npc actor should exist");
        assert_eq!(npc.kind, game_data::ActorKind::Npc);
        assert_eq!(npc.side, game_data::ActorSide::Friendly);
        assert_eq!(npc.group_id, "survivor");

        let enemy = snapshot
            .actors
            .iter()
            .find(|actor| {
                actor.definition_id.as_ref().map(CharacterId::as_str) == Some("zombie_walker")
            })
            .expect("enemy actor should exist");
        assert_eq!(enemy.kind, game_data::ActorKind::Enemy);
        assert_eq!(enemy.side, game_data::ActorSide::Hostile);
        assert_eq!(enemy.group_id, "infected");
        assert_eq!(
            snapshot.grid.map_id.as_ref().map(MapId::as_str),
            Some("survivor_outpost_01_grid")
        );
        assert_eq!(snapshot.grid.map_width, Some(12));
        assert_eq!(snapshot.grid.levels, vec![0, 1]);
        assert!(snapshot
            .grid
            .static_obstacles
            .contains(&GridCoord::new(2, 0, 1)));
    }

    #[test]
    fn unknown_definition_in_runtime_seed_returns_explicit_error() {
        let library = sample_library();
        let maps = sample_map_library();
        let seed = RuntimeScenarioSeed {
            map_id: None,
            static_obstacles: Vec::new(),
            characters: vec![RuntimeSpawnEntry {
                definition_id: CharacterId("missing".into()),
                grid_position: GridCoord::new(0, 0, 0),
            }],
            ..RuntimeScenarioSeed::default()
        };

        let error = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect_err("missing definitions should fail");
        assert_eq!(
            error,
            RuntimeBuildError::UnknownCharacterDefinition {
                definition_id: CharacterId("missing".into()),
            }
        );
    }

    #[test]
    fn unknown_map_in_runtime_seed_returns_explicit_error() {
        let library = sample_library();
        let maps = MapLibrary::default();
        let seed = RuntimeScenarioSeed {
            map_id: Some(MapId("missing_map".into())),
            static_obstacles: Vec::new(),
            characters: Vec::new(),
            ..RuntimeScenarioSeed::default()
        };

        let error = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect_err("missing map should fail");
        assert_eq!(
            error,
            RuntimeBuildError::UnknownMapDefinition {
                map_id: MapId("missing_map".into()),
            }
        );
    }

    #[test]
    fn spawn_request_creates_expected_character_components() {
        let mut app = App::new();
        app.add_message::<SpawnCharacterRequest>();
        app.add_message::<CharacterSpawnRejected>();
        app.insert_resource(CharacterDefinitions(sample_library()));
        app.add_systems(Update, spawn_characters_from_definition);

        app.world_mut()
            .resource_mut::<Messages<SpawnCharacterRequest>>()
            .write(SpawnCharacterRequest {
                definition_id: CharacterId("trader_lao_wang".to_string()),
                grid_position: GridCoord::new(3, 0, 2),
            });

        app.update();

        let entity = {
            let mut query = app.world_mut().query::<(Entity, &CharacterDefinitionId)>();
            query
                .iter(app.world())
                .find(|(_, id)| id.0.as_str() == "trader_lao_wang")
                .map(|(entity, _)| entity)
                .expect("spawned entity should exist")
        };
        let entity_ref = app.world().entity(entity);

        assert!(entity_ref.contains::<CharacterArchetypeComponent>());
        assert!(entity_ref.contains::<Disposition>());
        assert!(entity_ref.contains::<CampId>());
        assert!(entity_ref.contains::<DisplayName>());
        assert!(entity_ref.contains::<Description>());
        assert!(entity_ref.contains::<Level>());
        assert!(entity_ref.contains::<BehaviorProfile>());
        assert!(entity_ref.contains::<AiCombatProfile>());
        assert!(entity_ref.contains::<XpReward>());
        assert!(entity_ref.contains::<LootTable>());
        assert!(entity_ref.contains::<PortraitPath>());
        assert!(entity_ref.contains::<AvatarPath>());
        assert!(entity_ref.contains::<ModelPath>());
        assert!(entity_ref.contains::<PlaceholderColors>());
        assert!(entity_ref.contains::<BaseAttributeSet>());
        assert!(entity_ref.contains::<CombatAttributeSet>());
        assert!(entity_ref.contains::<ResourcePools>());
        assert!(entity_ref.contains::<GridPosition>());
    }

    #[test]
    fn unknown_definition_request_emits_rejection() {
        let mut app = App::new();
        app.add_message::<SpawnCharacterRequest>();
        app.add_message::<CharacterSpawnRejected>();
        app.insert_resource(CharacterDefinitions(sample_library()));
        app.insert_resource(CapturedRejections::default());
        app.add_systems(
            Update,
            (spawn_characters_from_definition, capture_rejections).chain(),
        );

        app.world_mut()
            .resource_mut::<Messages<SpawnCharacterRequest>>()
            .write(SpawnCharacterRequest {
                definition_id: CharacterId("missing".to_string()),
                grid_position: GridCoord::new(0, 0, 0),
            });

        app.update();

        let captured = app.world().resource::<CapturedRejections>();
        assert_eq!(captured.0.len(), 1);
        assert_eq!(captured.0[0].definition_id.as_str(), "missing");
        assert!(captured.0[0]
            .reason
            .contains("unknown_character_definition"));
    }

    #[test]
    fn default_debug_seed_uses_known_character_ids() {
        let ids: Vec<String> = default_debug_seed()
            .characters
            .into_iter()
            .map(|entry| entry.definition_id.0)
            .collect();

        assert_eq!(
            ids,
            vec![
                "player".to_string(),
                "trader_lao_wang".to_string(),
                "zombie_walker".to_string(),
            ]
        );
        assert_eq!(
            default_debug_seed().map_id.as_ref().map(MapId::as_str),
            Some("survivor_outpost_01_grid")
        );
        assert_eq!(
            default_debug_seed().start_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
    }

    #[test]
    fn default_character_definition_path_targets_repo_data_directory() {
        let path = CharacterDefinitionPath::default();
        assert!(path.0.ends_with("data/characters"));
    }

    #[test]
    fn default_map_definition_path_targets_repo_data_directory() {
        let path = MapDefinitionPath::default();
        assert!(path.0.ends_with("data/maps"));
    }

    #[test]
    fn startup_config_reads_startup_section_map_id() {
        let config = parse_runtime_startup_config(
            r#"
[Startup]
startup_map = "survivor_outpost_01_grid"
"#,
        )
        .expect("runtime startup config should parse");

        assert_eq!(
            config,
            RuntimeStartupConfig {
                startup_map: Some(MapId("survivor_outpost_01_grid".into())),
            }
        );
    }

    #[test]
    fn startup_config_allows_blank_startup_map() {
        let config = parse_runtime_startup_config(
            r#"
[Startup]
startup_map =
"#,
        )
        .expect("blank startup_map should parse");

        assert_eq!(config, RuntimeStartupConfig { startup_map: None });
    }

    #[test]
    fn startup_map_resolution_prefers_configured_map() {
        let maps = sample_map_library();

        let resolved =
            resolve_startup_map_id(&maps, Some(MapId("survivor_outpost_01_grid".into())));

        assert_eq!(resolved, Some(MapId("survivor_outpost_01_grid".into())));
    }

    #[test]
    fn startup_map_resolution_falls_back_to_first_available_map() {
        let maps = sample_map_library();

        let resolved = resolve_startup_map_id(&maps, None);

        assert_eq!(resolved, Some(MapId("survivor_outpost_01_grid".into())));
    }

    #[test]
    fn loading_missing_startup_config_returns_default() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be available")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("missing_runtime_startup_{suffix}.ini"));

        let config = load_runtime_startup_config(&path).expect("missing file should be allowed");

        assert_eq!(config, RuntimeStartupConfig::default());
    }

    fn capture_rejections(
        mut rejections: MessageReader<CharacterSpawnRejected>,
        mut captured: ResMut<CapturedRejections>,
    ) {
        captured.0.extend(rejections.read().cloned());
    }

    fn sample_library() -> CharacterLibrary {
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
            locations: vec![
                OverworldLocationDefinition {
                    id: OverworldLocationId("survivor_outpost_01".into()),
                    name: "Survivor Outpost 01".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("survivor_outpost_01_grid".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(0, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                },
                OverworldLocationDefinition {
                    id: OverworldLocationId("street_a".into()),
                    name: "Street A".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("survivor_outpost_01_grid".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(-1, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                },
            ],
            edges: vec![OverworldEdgeDefinition {
                from: OverworldLocationId("survivor_outpost_01".into()),
                to: OverworldLocationId("street_a".into()),
                bidirectional: true,
                travel_minutes: 30,
                food_cost: 1,
                stamina_cost: 1,
                risk_level: 0.0,
                route_cells: Vec::new(),
                extra: BTreeMap::new(),
            }],
            walkable_cells: vec![
                OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(-1, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
            ],
            travel_rules: OverworldTravelRuleSet::default(),
        };

        let mut definitions = BTreeMap::new();
        definitions.insert(definition.id.clone(), definition);
        OverworldLibrary::from(definitions)
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
}
