use bevy::asset::AssetPlugin;
use bevy::camera::{CameraOutputMode, ClearColorConfig};
use bevy::log::{info, warn, LogPlugin};
use bevy::prelude::*;
use bevy::render::render_resource::BlendState;
use bevy::window::WindowPlugin;
use bevy_egui::{EguiGlobalSettings, EguiPlugin, EguiPrimaryContextPass, PrimaryEguiContext};
use game_bevy::{init_runtime_logging, rust_asset_dir, RuntimeLogSettings};
use game_editor::{
    build_persisted_primary_window,
    preview_camera_input_system as shared_preview_camera_input_system,
    preview_camera_sync_system as shared_preview_camera_sync_system, PreviewCameraController,
    WindowSizePersistenceConfig, WindowSizePersistencePlugin,
};

use crate::data::{load_editor_resources, poll_external_selection_system};
use crate::preview::{
    default_preview_orbit, frame_loaded_scene_system, refresh_preview_load_status_system,
    setup_preview_scene, sync_preview_request_from_selection, sync_preview_scene_system,
    PreviewCamera, PreviewState, CAMERA_RADIUS_MAX, CAMERA_RADIUS_MIN, PREVIEW_BG,
};
use crate::state::{
    EditorEguiFontState, ExternalItemSelectionState, ItemAiState, ItemAiWorkerState,
};
use crate::ui::{configure_egui_fonts_system, editor_ui_system, poll_ai_worker_system};

pub(crate) fn run(initial_selection: Option<u32>) {
    let window_config =
        WindowSizePersistenceConfig::new("bevy_item_editor", 1680.0, 980.0, 1280.0, 720.0);
    let log_settings = RuntimeLogSettings::new("bevy_item_editor").with_single_run_file();
    if let Err(error) = init_runtime_logging(&log_settings) {
        eprintln!("failed to initialize bevy_item_editor logging: {error}");
    } else {
        info!("bevy_item_editor logger initialized");
    }

    let (editor_state, catalogs) = load_editor_resources(initial_selection)
        .unwrap_or_else(|error| panic!("item editor failed to load: {error}"));
    let repo_root = editor_state.repo_root.clone();
    if let Err(error) = game_editor::write_item_editor_session(&repo_root, std::process::id()) {
        warn!("item editor failed to create initial handoff session: {error}");
    }

    App::new()
        .add_plugins(
            DefaultPlugins
                .build()
                .disable::<LogPlugin>()
                .set(WindowPlugin {
                    primary_window: Some(build_persisted_primary_window(
                        window_config.clone(),
                        "CDC Item Editor",
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
        .insert_resource(ClearColor(PREVIEW_BG))
        .insert_resource(editor_state)
        .insert_resource(catalogs)
        .insert_resource(ExternalItemSelectionState::new(repo_root))
        .insert_resource(PreviewState::default())
        .insert_resource(EditorEguiFontState::default())
        .insert_resource(ItemAiState::load("bevy_item_editor"))
        .insert_resource(ItemAiWorkerState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(
            EguiPrimaryContextPass,
            (configure_egui_fonts_system, editor_ui_system).chain(),
        )
        .add_systems(
            Update,
            (
                sync_preview_request_from_selection,
                sync_preview_scene_system,
                refresh_preview_load_status_system,
                frame_loaded_scene_system,
                shared_preview_camera_input_system,
                shared_preview_camera_sync_system,
            )
                .chain(),
        )
        .add_systems(
            Update,
            (poll_external_selection_system, poll_ai_worker_system),
        )
        .run();
}

fn setup_editor(
    mut commands: Commands,
    mut egui_global_settings: ResMut<EguiGlobalSettings>,
    mut preview_state: ResMut<PreviewState>,
) {
    egui_global_settings.auto_create_primary_context = false;

    preview_state.host_entity = Some(setup_preview_scene(&mut commands));

    commands.spawn((
        Camera3d::default(),
        Camera {
            order: 0,
            clear_color: ClearColorConfig::Custom(PREVIEW_BG),
            ..default()
        },
        Projection::Perspective(PerspectiveProjection {
            fov: std::f32::consts::FRAC_PI_4,
            near: 0.01,
            far: 200.0,
            ..default()
        }),
        Transform::from_xyz(2.8, 1.8, 4.0).looking_at(Vec3::new(0.0, 0.7, 0.0), Vec3::Y),
        PreviewCameraController {
            orbit: default_preview_orbit(),
            focus_anchor: default_preview_orbit().focus,
            viewport_rect: None,
            rotate_drag_active: false,
            pan_drag_active: false,
            allow_rotate: true,
            allow_pan: true,
            allow_zoom: true,
            pitch_min: -1.2,
            pitch_max: 0.72,
            radius_min: CAMERA_RADIUS_MIN,
            radius_max: CAMERA_RADIUS_MAX,
            rotate_speed_x: 0.012,
            rotate_speed_y: 0.008,
            zoom_speed: 0.24,
            pan_speed: 1.0,
            pan_max_focus_offset: 2.8,
        },
        PreviewCamera,
    ));
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
