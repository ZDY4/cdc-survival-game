use bevy::asset::AssetPlugin;
use bevy::diagnostic::FrameTimeDiagnosticsPlugin;
use bevy::log::{info, LogPlugin};
use bevy::prelude::*;
use bevy::window::WindowPlugin;
use bevy_egui::{EguiPlugin, EguiPrimaryContextPass};
use game_bevy::{
    init_runtime_logging, rust_asset_dir,
    world_render::{
        WorldRenderConfig, WorldRenderPalette, WorldRenderPlugin, WorldRenderStyleProfile,
    },
    RuntimeLogSettings,
};
use game_editor::{
    build_persisted_primary_window, WindowSizePersistenceConfig, WindowSizePersistencePlugin,
};

use crate::camera::{apply_camera_transform_system, camera_input_system};
use crate::scene::{
    draw_hovered_grid_outline_system, rebuild_scene_system, setup_editor, update_hover_info_system,
};
use crate::state::{
    load_editor_state, load_editor_world_tiles, EditorEguiFontState, EditorUiState, MapAiState,
    MapAiWorkerState, MiddleClickState, OrbitCameraState,
};
use crate::ui::{configure_editor_egui_fonts_system, editor_ui_system, poll_ai_worker_system};

pub(crate) fn run() {
    let render_palette = WorldRenderPalette::default();
    let render_style = WorldRenderStyleProfile::default();
    let render_config = WorldRenderConfig::default();
    let asset_dir = rust_asset_dir();
    let window_config =
        WindowSizePersistenceConfig::new("bevy_map_editor", 1680.0, 980.0, 1280.0, 720.0);
    let log_settings = RuntimeLogSettings::new("bevy_map_editor").with_single_run_file();
    if let Err(error) = init_runtime_logging(&log_settings) {
        eprintln!("failed to initialize bevy_map_editor logging: {error}");
    } else {
        info!("bevy_map_editor logger initialized");
    }

    App::new()
        .add_plugins(
            DefaultPlugins
                .build()
                .disable::<LogPlugin>()
                .set(WindowPlugin {
                    primary_window: Some(build_persisted_primary_window(
                        window_config.clone(),
                        "CDC Map Editor",
                    )),
                    ..default()
                })
                .set(AssetPlugin {
                    file_path: asset_dir.display().to_string(),
                    ..default()
                }),
        )
        .add_plugins(WorldRenderPlugin)
        .add_plugins(FrameTimeDiagnosticsPlugin::default())
        .add_plugins(EguiPlugin::default())
        .add_plugins(WindowSizePersistencePlugin::new(window_config))
        .insert_resource(ClearColor(render_palette.clear_color))
        .insert_resource(render_palette)
        .insert_resource(render_style)
        .insert_resource(render_config)
        .insert_resource(load_editor_state())
        .insert_resource(load_editor_world_tiles())
        .insert_resource(MapAiState::load("bevy_map_editor"))
        .insert_resource(EditorUiState::default())
        .insert_resource(EditorEguiFontState::default())
        .insert_resource(OrbitCameraState::default())
        .insert_resource(MiddleClickState::default())
        .insert_resource(MapAiWorkerState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(
            EguiPrimaryContextPass,
            (configure_editor_egui_fonts_system, editor_ui_system).chain(),
        )
        .add_systems(
            Update,
            (
                rebuild_scene_system,
                camera_input_system,
                apply_camera_transform_system,
                update_hover_info_system,
                draw_hovered_grid_outline_system,
            )
                .chain(),
        )
        .add_systems(Update, poll_ai_worker_system)
        .run();
}
