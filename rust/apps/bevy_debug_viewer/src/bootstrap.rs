use std::path::PathBuf;

use game_bevy::{
    build_runtime_from_default_startup_seed, load_runtime_bootstrap, CharacterDefinitionPath,
    MapDefinitionPath, OverworldDefinitionPath, RuntimeBootstrapError, RuntimeStartupConfigPath,
};
use game_core::SimulationRuntime;
use game_data::{load_dialogue_library, load_dialogue_rule_library};

pub(crate) struct ViewerBootstrap {
    pub runtime: SimulationRuntime,
    pub asset_dir: PathBuf,
}

pub(crate) fn load_viewer_bootstrap() -> Result<ViewerBootstrap, RuntimeBootstrapError> {
    let bootstrap = load_runtime_bootstrap(
        &CharacterDefinitionPath::default().0,
        &MapDefinitionPath::default().0,
        &OverworldDefinitionPath::default().0,
        &RuntimeStartupConfigPath::default().0,
    )?;
    let mut runtime = build_runtime_from_default_startup_seed(&bootstrap)?;
    let data_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data");
    let dialogue_library = load_dialogue_library(data_root.join("dialogues"))
        .unwrap_or_else(|error| panic!("failed to load viewer dialogue library: {error}"));
    let dialogue_rule_library = load_dialogue_rule_library(data_root.join("dialogue_rules"), None)
        .unwrap_or_else(|error| panic!("failed to load viewer dialogue rule library: {error}"));
    runtime.set_dialogue_library(dialogue_library);
    runtime.set_dialogue_rule_library(dialogue_rule_library);
    let asset_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
    Ok(ViewerBootstrap { runtime, asset_dir })
}
