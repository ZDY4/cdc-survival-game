use std::path::Path;

use thiserror::Error;

use crate::{
    build_runtime_from_seed, default_debug_seed, load_character_definitions, load_map_definitions,
    load_overworld_definitions, load_runtime_startup_config, resolve_startup_map_id,
    CharacterDefinitions, CharacterLoadError, MapDefinitions, MapLoadError, OverworldDefinitions,
    OverworldLoadError, RuntimeBuildError, RuntimeScenarioSeed, RuntimeStartupConfig,
    RuntimeStartupConfigError,
};
use game_core::SimulationRuntime;

#[derive(Debug, Clone)]
pub struct RuntimeBootstrapBundle {
    pub character_definitions: CharacterDefinitions,
    pub map_definitions: MapDefinitions,
    pub overworld_definitions: OverworldDefinitions,
    pub runtime_startup_config: RuntimeStartupConfig,
}

#[derive(Debug, Error)]
pub enum RuntimeBootstrapError {
    #[error(transparent)]
    CharacterDefinitions(#[from] CharacterLoadError),
    #[error(transparent)]
    MapDefinitions(#[from] MapLoadError),
    #[error(transparent)]
    OverworldDefinitions(#[from] OverworldLoadError),
    #[error(transparent)]
    RuntimeStartupConfig(#[from] RuntimeStartupConfigError),
    #[error(transparent)]
    RuntimeBuild(#[from] RuntimeBuildError),
}

pub fn load_runtime_bootstrap(
    character_path: impl AsRef<Path>,
    map_path: impl AsRef<Path>,
    overworld_path: impl AsRef<Path>,
    runtime_startup_config_path: impl AsRef<Path>,
) -> Result<RuntimeBootstrapBundle, RuntimeBootstrapError> {
    Ok(RuntimeBootstrapBundle {
        character_definitions: load_character_definitions(character_path)?,
        map_definitions: load_map_definitions(map_path)?,
        overworld_definitions: load_overworld_definitions(overworld_path)?,
        runtime_startup_config: load_runtime_startup_config(runtime_startup_config_path)?,
    })
}

pub fn build_default_startup_seed(
    maps: &game_data::MapLibrary,
    startup_map: Option<game_data::MapId>,
) -> RuntimeScenarioSeed {
    let mut seed = default_debug_seed();
    let resolved_map_id = resolve_startup_map_id(maps, startup_map);
    seed.map_id = resolved_map_id.clone();
    seed.start_map_id = resolved_map_id;
    seed
}

pub fn build_runtime_from_default_startup_seed(
    bootstrap: &RuntimeBootstrapBundle,
) -> Result<SimulationRuntime, RuntimeBootstrapError> {
    let seed = build_default_startup_seed(
        &bootstrap.map_definitions.0,
        bootstrap.runtime_startup_config.startup_map.clone(),
    );
    Ok(build_runtime_from_seed(
        &bootstrap.character_definitions.0,
        &bootstrap.map_definitions.0,
        &bootstrap.overworld_definitions.0,
        &seed,
    )?)
}
