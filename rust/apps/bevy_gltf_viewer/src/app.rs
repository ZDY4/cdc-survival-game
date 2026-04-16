use bevy::prelude::*;
use bevy_egui::EguiPrimaryContextPass;
use game_bevy::rust_asset_dir;
use game_editor::{
    configure_editor_app_shell, configure_game_ui_fonts_system, preview_camera_input_system,
    preview_camera_sync_system, setup_preview_stage, EditorAppShellConfig, GameUiFontsState,
    PreviewCameraController, PreviewStageConfig, WindowSizePersistenceConfig,
};

use crate::catalog::{handle_catalog_loading_task, spawn_catalog_scan_task};
use crate::commands::{handle_viewer_commands, GltfViewerCommand};
use crate::preview::{
    default_viewer_orbit, frame_loaded_scene_system, refresh_preview_load_status_system,
    sync_preview_ground_visibility_system, sync_preview_scene_system,
};
use crate::state::{
    PreviewCamera, PreviewState, ViewerAppState, ViewerAssetRoot, ViewerUiState, ViewerUiStyleState,
};
use crate::ui::{configure_viewer_ui_style_system, loading_ui_system, viewer_ui_system};

const PREVIEW_BG: Color = Color::srgb(0.095, 0.105, 0.125);

pub(crate) fn run() {
    let asset_dir = rust_asset_dir();
    let shell_config = EditorAppShellConfig::new(
        "bevy_gltf_viewer",
        "CDC glTF Viewer",
        asset_dir.clone(),
        WindowSizePersistenceConfig::new("bevy_gltf_viewer", 1600.0, 920.0, 1280.0, 720.0),
    );

    let mut app = App::new();
    configure_editor_app_shell(&mut app, &shell_config);

    app.init_state::<ViewerAppState>()
        .add_message::<GltfViewerCommand>()
        .insert_resource(ClearColor(PREVIEW_BG))
        .insert_resource(ViewerAssetRoot(asset_dir))
        .insert_resource(ViewerUiState::default())
        .insert_resource(PreviewState::default())
        .insert_resource(GameUiFontsState::default())
        .insert_resource(ViewerUiStyleState::default())
        .add_systems(Startup, (setup_viewer_stage, spawn_catalog_scan_task))
        .add_systems(
            EguiPrimaryContextPass,
            (
                configure_game_ui_fonts_system,
                configure_viewer_ui_style_system,
                loading_ui_system.run_if(in_state(ViewerAppState::Loading)),
                viewer_ui_system.run_if(in_state(ViewerAppState::Ready)),
            )
                .chain(),
        )
        .add_systems(
            Update,
            (
                handle_catalog_loading_task.run_if(in_state(ViewerAppState::Loading)),
                handle_viewer_commands,
                (
                    preview_camera_input_system,
                    sync_preview_scene_system,
                    refresh_preview_load_status_system,
                    frame_loaded_scene_system,
                    sync_preview_ground_visibility_system,
                    preview_camera_sync_system,
                )
                    .chain()
                    .run_if(in_state(ViewerAppState::Ready)),
            ),
        )
        .run();
}

fn setup_viewer_stage(
    mut commands: Commands,
    mut egui_global_settings: ResMut<bevy_egui::EguiGlobalSettings>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut preview_state: ResMut<PreviewState>,
) {
    let stage = setup_preview_stage(
        &mut commands,
        &mut egui_global_settings,
        &mut meshes,
        &mut materials,
        &PreviewStageConfig {
            clear_color: PREVIEW_BG,
            projection: Projection::Perspective(PerspectiveProjection {
                fov: std::f32::consts::FRAC_PI_4,
                near: 0.01,
                far: 200.0,
                ..default()
            }),
            camera_transform: Transform::from_xyz(2.8, 1.8, 4.0)
                .looking_at(Vec3::new(0.0, 0.7, 0.0), Vec3::Y),
            controller: PreviewCameraController {
                orbit: default_viewer_orbit(),
                focus_anchor: default_viewer_orbit().focus,
                viewport_rect: None,
                rotate_drag_active: false,
                pan_drag_active: false,
                block_pointer_input: false,
                allow_rotate: true,
                allow_pan: true,
                allow_zoom: true,
                pitch_min: -1.2,
                pitch_max: 0.72,
                radius_min: 0.8,
                radius_max: 18.0,
                rotate_speed_x: 0.012,
                rotate_speed_y: 0.008,
                zoom_speed: 0.24,
                pan_speed: 1.0,
                pan_max_focus_offset: 2.8,
            },
            floor_size: Vec2::new(8.0, 8.0),
            floor_color: Color::srgb(0.22, 0.235, 0.26),
            spawn_scene_host: true,
        },
    );
    commands.entity(stage.preview_camera).insert(PreviewCamera);
    preview_state.host_entity = stage.scene_host;
}
