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
    let mut runtime = build_viewer_main_menu_runtime();
    configure_viewer_runtime(&mut runtime);
    let asset_dir = viewer_asset_dir();
    Ok(ViewerBootstrap { runtime, asset_dir })
}

pub(crate) fn load_viewer_gameplay_bootstrap() -> Result<ViewerBootstrap, RuntimeBootstrapError> {
    let bootstrap = load_runtime_bootstrap(
        &CharacterDefinitionPath::default().0,
        &MapDefinitionPath::default().0,
        &OverworldDefinitionPath::default().0,
        &RuntimeStartupConfigPath::default().0,
    )?;
    let mut runtime = build_runtime_from_default_startup_seed(&bootstrap)?;
    configure_viewer_runtime(&mut runtime);
    let asset_dir = viewer_asset_dir();
    Ok(ViewerBootstrap { runtime, asset_dir })
}

fn build_viewer_main_menu_runtime() -> SimulationRuntime {
    SimulationRuntime::new()
}

fn configure_viewer_runtime(runtime: &mut SimulationRuntime) {
    let data_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data");
    let dialogue_library = load_dialogue_library(data_root.join("dialogues"))
        .unwrap_or_else(|error| panic!("failed to load viewer dialogue library: {error}"));
    let dialogue_rule_library = load_dialogue_rule_library(data_root.join("dialogue_rules"), None)
        .unwrap_or_else(|error| panic!("failed to load viewer dialogue rule library: {error}"));
    runtime.set_dialogue_library(dialogue_library);
    runtime.set_dialogue_rule_library(dialogue_rule_library);
}

fn viewer_asset_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets")
}

#[cfg(test)]
mod tests {
    use super::build_viewer_main_menu_runtime;

    #[test]
    fn viewer_main_menu_runtime_starts_empty_without_map_or_actors() {
        let runtime = build_viewer_main_menu_runtime();
        let snapshot = runtime.snapshot();

        assert!(snapshot.grid.map_id.is_none());
        assert!(snapshot.actors.is_empty());
        assert!(snapshot
            .interaction_context
            .active_outdoor_location_id
            .is_none());
    }
}
