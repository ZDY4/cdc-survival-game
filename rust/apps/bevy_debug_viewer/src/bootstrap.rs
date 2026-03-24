use std::path::PathBuf;

use game_bevy::{
    build_runtime_from_default_startup_seed, load_runtime_bootstrap, CharacterDefinitionPath,
    MapDefinitionPath, RuntimeBootstrapError, RuntimeStartupConfigPath,
};
use game_core::SimulationRuntime;

pub(crate) struct ViewerBootstrap {
    pub runtime: SimulationRuntime,
    pub asset_dir: PathBuf,
}

pub(crate) fn load_viewer_bootstrap() -> Result<ViewerBootstrap, RuntimeBootstrapError> {
    let bootstrap = load_runtime_bootstrap(
        &CharacterDefinitionPath::default().0,
        &MapDefinitionPath::default().0,
        &RuntimeStartupConfigPath::default().0,
    )?;
    let runtime = build_runtime_from_default_startup_seed(&bootstrap)?;
    let asset_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
    Ok(ViewerBootstrap { runtime, asset_dir })
}
