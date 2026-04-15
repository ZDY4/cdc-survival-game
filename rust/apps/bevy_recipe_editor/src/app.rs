use bevy::asset::AssetPlugin;
use bevy::camera::{CameraOutputMode, ClearColorConfig};
use bevy::log::{info, LogPlugin};
use bevy::prelude::*;
use bevy::render::render_resource::BlendState;
use bevy::window::WindowPlugin;
use bevy_egui::{EguiGlobalSettings, EguiPlugin, EguiPrimaryContextPass, PrimaryEguiContext};
use game_bevy::{init_runtime_logging, rust_asset_dir, RuntimeLogSettings};
use game_editor::{
    build_persisted_primary_window, WindowSizePersistenceConfig, WindowSizePersistencePlugin,
};

use crate::data::load_editor_resources;
use crate::state::{EditorEguiFontState, RecipeAiState, RecipeAiWorkerState};
use crate::ui::{configure_egui_fonts_system, editor_ui_system, poll_ai_worker_system};

pub(crate) fn run() {
    let window_config =
        WindowSizePersistenceConfig::new("bevy_recipe_editor", 1680.0, 980.0, 1280.0, 720.0);
    let log_settings = RuntimeLogSettings::new("bevy_recipe_editor").with_single_run_file();
    if let Err(error) = init_runtime_logging(&log_settings) {
        eprintln!("failed to initialize bevy_recipe_editor logging: {error}");
    } else {
        info!("bevy_recipe_editor logger initialized");
    }

    let (editor_state, catalogs) = load_editor_resources()
        .unwrap_or_else(|error| panic!("recipe editor failed to load: {error}"));

    App::new()
        .add_plugins(
            DefaultPlugins
                .build()
                .disable::<LogPlugin>()
                .set(WindowPlugin {
                    primary_window: Some(build_persisted_primary_window(
                        window_config.clone(),
                        "CDC Recipe Editor",
                    )),
                    ..default()
                })
                .set(AssetPlugin {
                    file_path: rust_asset_dir().display().to_string(),
                    ..default()
                }),
        )
        .add_plugins(EguiPlugin::default())
        .add_plugins(WindowSizePersistencePlugin::new(window_config))
        .insert_resource(editor_state)
        .insert_resource(catalogs)
        .insert_resource(EditorEguiFontState::default())
        .insert_resource(RecipeAiState::load("bevy_recipe_editor"))
        .insert_resource(RecipeAiWorkerState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(
            EguiPrimaryContextPass,
            (configure_egui_fonts_system, editor_ui_system).chain(),
        )
        .add_systems(Update, poll_ai_worker_system)
        .run();
}

fn setup_editor(mut commands: Commands, mut egui_global_settings: ResMut<EguiGlobalSettings>) {
    egui_global_settings.auto_create_primary_context = false;

    commands.spawn((
        PrimaryEguiContext,
        Camera2d,
        Camera {
            order: 1,
            output_mode: CameraOutputMode::Write {
                blend_state: Some(BlendState::ALPHA_BLENDING),
                clear_color: ClearColorConfig::None,
            },
            clear_color: ClearColorConfig::Custom(Color::NONE),
            ..default()
        },
    ));
}
