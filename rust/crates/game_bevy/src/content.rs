use std::fmt::Display;
use std::fs;
use std::path::{Path, PathBuf};

use bevy_app::{App, Plugin, Startup};
use bevy_ecs::prelude::*;
use bevy_ecs::schedule::{IntoScheduleConfigs, SystemSet};
use game_core::{HeadlessEconomyRuntime, SimulationRuntime};
use game_data::{
    load_ai_module_library, load_character_library, load_dialogue_library,
    load_dialogue_rule_library, load_effect_library, load_item_library, load_map_library,
    load_overworld_library, load_quest_library, load_recipe_library, load_settlement_library,
    load_shop_library, load_skill_library, load_skill_tree_library, load_world_tile_library,
    validate_outdoor_transition_trigger_layout, AiModuleLibrary, AiModuleLoadError,
    CharacterLibrary, CharacterLoadError, DialogueLibrary, DialogueLoadError, DialogueRuleLibrary,
    DialogueRuleLoadError, EffectLibrary, EffectLoadError, ItemLibrary, ItemLoadError, MapId,
    MapLibrary, MapLoadError, OutdoorTransitionTriggerLayoutValidationError, OverworldLibrary,
    OverworldLoadError, QuestLibrary, QuestLoadError, RecipeLibrary, RecipeLoadError,
    SettlementLibrary, SettlementLoadError, ShopLibrary, ShopLoadError, SkillLibrary,
    SkillLoadError, SkillTreeLibrary, SkillTreeLoadError, WorldTileLibrary, WorldTileLoadError,
};
use thiserror::Error;

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
pub struct WorldTileDefinitionPath(pub PathBuf);

impl Default for WorldTileDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/world_tiles"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct WorldTileDefinitions(pub WorldTileLibrary);

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
pub struct AiDefinitionPath(pub PathBuf);

impl Default for AiDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/ai"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct AiDefinitions(pub AiModuleLibrary);

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

#[derive(Resource, Debug, Clone)]
pub struct DialogueDefinitionPath(pub PathBuf);

impl Default for DialogueDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/dialogues"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct DialogueDefinitions(pub DialogueLibrary);

#[derive(Resource, Debug, Clone)]
pub struct DialogueRuleDefinitionPath(pub PathBuf);

impl Default for DialogueRuleDefinitionPath {
    fn default() -> Self {
        Self(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/dialogue_rules"))
    }
}

#[derive(Resource, Debug, Clone)]
pub struct DialogueRuleDefinitions(pub DialogueRuleLibrary);

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

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum RuntimeBuildError {
    #[error("unknown character definition: {definition_id}")]
    UnknownCharacterDefinition {
        definition_id: game_data::CharacterId,
    },
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RuntimeContentLoadStatus {
    #[default]
    Loading,
    Ready,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeContentLoadFailure {
    pub stage: &'static str,
    pub message: String,
}

#[derive(Resource, Debug, Clone, Default)]
pub struct RuntimeContentLoadState {
    pub status: RuntimeContentLoadStatus,
    pub failures: Vec<RuntimeContentLoadFailure>,
}

impl RuntimeContentLoadState {
    pub fn record_failure(&mut self, stage: &'static str, message: impl Into<String>) {
        self.failures.push(RuntimeContentLoadFailure {
            stage,
            message: message.into(),
        });
        self.status = RuntimeContentLoadStatus::Failed;
    }

    pub fn is_ready(&self) -> bool {
        self.status == RuntimeContentLoadStatus::Ready
    }
}

#[derive(SystemSet, Debug, Hash, PartialEq, Eq, Clone)]
pub enum RuntimeContentStartupSet {
    LoadResources,
    Finalize,
}

#[derive(Debug, Default)]
pub struct RuntimeContentPlugin;

impl Plugin for RuntimeContentPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<CharacterDefinitionPath>()
            .init_resource::<MapDefinitionPath>()
            .init_resource::<OverworldDefinitionPath>()
            .init_resource::<WorldTileDefinitionPath>()
            .init_resource::<SettlementDefinitionPath>()
            .init_resource::<AiDefinitionPath>()
            .init_resource::<EffectDefinitionPath>()
            .init_resource::<ItemDefinitionPath>()
            .init_resource::<SkillDefinitionPath>()
            .init_resource::<SkillTreeDefinitionPath>()
            .init_resource::<RecipeDefinitionPath>()
            .init_resource::<QuestDefinitionPath>()
            .init_resource::<ShopDefinitionPath>()
            .init_resource::<DialogueDefinitionPath>()
            .init_resource::<DialogueRuleDefinitionPath>()
            .init_resource::<RuntimeStartupConfigPath>()
            .init_resource::<RuntimeContentLoadState>()
            .configure_sets(
                Startup,
                (
                    RuntimeContentStartupSet::LoadResources,
                    RuntimeContentStartupSet::Finalize,
                )
                    .chain(),
            )
            .add_systems(
                Startup,
                (
                    load_character_definitions_on_startup,
                    load_ai_definitions_on_startup,
                    load_effect_definitions_on_startup,
                    load_item_definitions_on_startup,
                    load_map_definitions_on_startup,
                    load_overworld_definitions_on_startup,
                    load_world_tile_definitions_on_startup,
                    load_settlement_definitions_on_startup,
                    load_skill_definitions_on_startup,
                    load_skill_tree_definitions_on_startup,
                    load_recipe_definitions_on_startup,
                    load_quest_definitions_on_startup,
                    load_shop_definitions_on_startup,
                    load_dialogue_definitions_on_startup,
                    load_dialogue_rule_definitions_on_startup,
                    load_runtime_startup_config_on_startup,
                )
                    .chain()
                    .in_set(RuntimeContentStartupSet::LoadResources),
            )
            .add_systems(
                Startup,
                (
                    validate_outdoor_transition_trigger_layout_on_startup,
                    finalize_runtime_content_load_state,
                )
                    .chain()
                    .in_set(RuntimeContentStartupSet::Finalize),
            );
    }
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

pub fn load_ai_definitions(path: impl AsRef<Path>) -> Result<AiDefinitions, AiModuleLoadError> {
    Ok(AiDefinitions(load_ai_module_library(path)?))
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

pub fn load_world_tile_definitions(
    path: impl AsRef<Path>,
) -> Result<WorldTileDefinitions, WorldTileLoadError> {
    Ok(WorldTileDefinitions(load_world_tile_library(path)?))
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

pub fn load_dialogue_definitions(
    path: impl AsRef<Path>,
) -> Result<DialogueDefinitions, DialogueLoadError> {
    Ok(DialogueDefinitions(load_dialogue_library(path)?))
}

pub fn load_dialogue_rule_definitions(
    path: impl AsRef<Path>,
) -> Result<DialogueRuleDefinitions, DialogueRuleLoadError> {
    Ok(DialogueRuleDefinitions(load_dialogue_rule_library(
        path, None,
    )?))
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

pub fn validate_runtime_outdoor_transition_layout(
    maps: &MapDefinitions,
    overworld: &OverworldDefinitions,
) -> Result<(), OutdoorTransitionTriggerLayoutValidationError> {
    validate_outdoor_transition_trigger_layout(&maps.0, &overworld.0)
}

pub fn apply_gameplay_libraries(
    runtime: &mut SimulationRuntime,
    items: &ItemDefinitions,
    skills: &SkillDefinitions,
    recipes: &RecipeDefinitions,
    quests: &QuestDefinitions,
    shops: &ShopDefinitions,
    overworld: &OverworldDefinitions,
) {
    runtime.set_item_library(items.0.clone());
    runtime.set_skill_library(skills.0.clone());
    runtime.set_recipe_library(recipes.0.clone());
    runtime.set_quest_library(quests.0.clone());
    runtime.set_shop_library(shops.0.clone());
    runtime.set_overworld_library(overworld.0.clone());
}

pub fn apply_dialogue_libraries(
    runtime: &mut SimulationRuntime,
    dialogues: &DialogueDefinitions,
    dialogue_rules: &DialogueRuleDefinitions,
) {
    runtime.set_dialogue_library(dialogues.0.clone());
    runtime.set_dialogue_rule_library(dialogue_rules.0.clone());
}

pub fn load_character_definitions_on_startup(
    mut commands: Commands,
    path: Res<CharacterDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "character_definitions",
        load_character_definitions(&path.0),
        &path.0,
    );
}

pub fn load_map_definitions_on_startup(
    mut commands: Commands,
    path: Res<MapDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "map_definitions",
        load_map_definitions(&path.0),
        &path.0,
    );
}

pub fn load_overworld_definitions_on_startup(
    mut commands: Commands,
    path: Res<OverworldDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "overworld_definitions",
        load_overworld_definitions(&path.0),
        &path.0,
    );
}

pub fn load_world_tile_definitions_on_startup(
    mut commands: Commands,
    path: Res<WorldTileDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "world_tile_definitions",
        load_world_tile_definitions(&path.0),
        &path.0,
    );
}

pub fn load_settlement_definitions_on_startup(
    mut commands: Commands,
    path: Res<SettlementDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "settlement_definitions",
        load_settlement_definitions(&path.0),
        &path.0,
    );
}

pub fn load_effect_definitions_on_startup(
    mut commands: Commands,
    path: Res<EffectDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "effect_definitions",
        load_effect_definitions(&path.0),
        &path.0,
    );
}

pub fn load_ai_definitions_on_startup(
    mut commands: Commands,
    path: Res<AiDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "ai_definitions",
        load_ai_definitions(&path.0),
        &path.0,
    );
}

pub fn load_item_definitions_on_startup(
    mut commands: Commands,
    path: Res<ItemDefinitionPath>,
    effects: Option<Res<EffectDefinitions>>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    let effect_library = effects.as_ref().map(|definitions| &definitions.0);
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "item_definitions",
        load_item_definitions(&path.0, effect_library),
        &path.0,
    );
}

pub fn load_skill_definitions_on_startup(
    mut commands: Commands,
    path: Res<SkillDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "skill_definitions",
        load_skill_definitions(&path.0),
        &path.0,
    );
}

pub fn load_skill_tree_definitions_on_startup(
    mut commands: Commands,
    path: Res<SkillTreeDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "skill_tree_definitions",
        load_skill_tree_definitions(&path.0),
        &path.0,
    );
}

pub fn load_recipe_definitions_on_startup(
    mut commands: Commands,
    path: Res<RecipeDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "recipe_definitions",
        load_recipe_definitions(&path.0),
        &path.0,
    );
}

pub fn load_quest_definitions_on_startup(
    mut commands: Commands,
    path: Res<QuestDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "quest_definitions",
        load_quest_definitions(&path.0),
        &path.0,
    );
}

pub fn load_shop_definitions_on_startup(
    mut commands: Commands,
    path: Res<ShopDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "shop_definitions",
        load_shop_definitions(&path.0),
        &path.0,
    );
}

pub fn load_dialogue_definitions_on_startup(
    mut commands: Commands,
    path: Res<DialogueDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "dialogue_definitions",
        load_dialogue_definitions(&path.0),
        &path.0,
    );
}

pub fn load_dialogue_rule_definitions_on_startup(
    mut commands: Commands,
    path: Res<DialogueRuleDefinitionPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "dialogue_rule_definitions",
        load_dialogue_rule_definitions(&path.0),
        &path.0,
    );
}

pub fn load_runtime_startup_config_on_startup(
    mut commands: Commands,
    path: Res<RuntimeStartupConfigPath>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    insert_loaded_resource(
        &mut commands,
        &mut state,
        "runtime_startup_config",
        load_runtime_startup_config(&path.0),
        &path.0,
    );
}

fn finalize_runtime_content_load_state(mut state: ResMut<RuntimeContentLoadState>) {
    if state.failures.is_empty() {
        state.status = RuntimeContentLoadStatus::Ready;
    } else {
        state.status = RuntimeContentLoadStatus::Failed;
    }
}

fn validate_outdoor_transition_trigger_layout_on_startup(
    maps: Option<Res<MapDefinitions>>,
    overworld: Option<Res<OverworldDefinitions>>,
    mut state: ResMut<RuntimeContentLoadState>,
) {
    let (Some(maps), Some(overworld)) = (maps, overworld) else {
        return;
    };
    if let Err(error) = validate_runtime_outdoor_transition_layout(&maps, &overworld) {
        state.record_failure("outdoor_transition_trigger_layout", error.to_string());
    }
}

fn insert_loaded_resource<T, E>(
    commands: &mut Commands,
    state: &mut RuntimeContentLoadState,
    stage: &'static str,
    result: Result<T, E>,
    path: &Path,
) where
    T: Resource,
    E: Display,
{
    match result {
        Ok(resource) => {
            commands.insert_resource(resource);
        }
        Err(error) => {
            state.record_failure(stage, format!("{}: {error}", path.display()));
        }
    }
}
