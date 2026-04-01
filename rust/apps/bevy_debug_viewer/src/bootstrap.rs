use std::path::PathBuf;

use game_bevy::{
    apply_dialogue_libraries, build_runtime_from_default_startup_seed, load_dialogue_definitions,
    load_dialogue_rule_definitions, load_runtime_bootstrap, CharacterDefinitionPath,
    DialogueDefinitionPath, DialogueRuleDefinitionPath, MapDefinitionPath, OverworldDefinitionPath,
    RuntimeBootstrapError, RuntimeStartupConfigPath,
};
use game_core::SimulationRuntime;

pub(crate) struct ViewerBootstrap {
    pub runtime: SimulationRuntime,
    pub asset_dir: PathBuf,
}

pub(crate) fn load_viewer_bootstrap() -> Result<ViewerBootstrap, RuntimeBootstrapError> {
    let mut runtime = build_viewer_main_menu_runtime();
    configure_viewer_runtime(&mut runtime)?;
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
    configure_viewer_runtime(&mut runtime)?;
    let asset_dir = viewer_asset_dir();
    Ok(ViewerBootstrap { runtime, asset_dir })
}

fn build_viewer_main_menu_runtime() -> SimulationRuntime {
    SimulationRuntime::new()
}

fn configure_viewer_runtime(runtime: &mut SimulationRuntime) -> Result<(), RuntimeBootstrapError> {
    let dialogues = load_dialogue_definitions(&DialogueDefinitionPath::default().0)?;
    let dialogue_rules = load_dialogue_rule_definitions(&DialogueRuleDefinitionPath::default().0)?;
    apply_dialogue_libraries(runtime, &dialogues, &dialogue_rules);
    Ok(())
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
