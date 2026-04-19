use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::EguiPrimaryContextPass;
use game_bevy::rust_asset_dir;
use game_editor::{
    configure_editor_app_shell, configure_game_ui_fonts_system, preview_camera_input_system,
    preview_camera_sync_system, setup_preview_stage, write_editor_session, EditorAppShellConfig,
    EditorKind, GameUiFontsState, PreviewCameraController, PreviewStageConfig,
    WindowSizePersistenceConfig,
};

use crate::commands::{handle_item_editor_commands, ItemEditorCommand};
use crate::data::{load_editor_resources, poll_external_selection_system};
use crate::preview::{
    default_preview_orbit, frame_loaded_scene_system, refresh_preview_load_status_system,
    sync_preview_request_from_selection, sync_preview_scene_system, PreviewCamera, PreviewState,
    CAMERA_RADIUS_MAX, CAMERA_RADIUS_MIN, PREVIEW_BG,
};
use crate::state::ExternalItemSelectionState;
use crate::ui::editor_ui_system;

pub(crate) fn run(initial_selection: Option<u32>) {
    let (editor_state, catalogs) = match load_editor_resources(initial_selection) {
        Ok(value) => value,
        Err(error) => {
            eprintln!("item editor failed to load: {error}");
            return;
        }
    };
    let repo_root = editor_state.repo_root.clone();
    if let Err(error) = write_editor_session(&repo_root, EditorKind::Item, std::process::id()) {
        warn!("item editor failed to create initial handoff session: {error}");
    }

    let mut app = App::new();
    configure_editor_app_shell(
        &mut app,
        &EditorAppShellConfig::new(
            "bevy_item_editor",
            "CDC Item Editor",
            rust_asset_dir(),
            WindowSizePersistenceConfig::new("bevy_item_editor", 1680.0, 980.0, 1280.0, 720.0),
        ),
    );

    app.add_message::<ItemEditorCommand>()
        .insert_resource(ClearColor(PREVIEW_BG))
        .insert_resource(editor_state)
        .insert_resource(catalogs)
        .insert_resource(ExternalItemSelectionState::new(repo_root))
        .insert_resource(PreviewState::default())
        .insert_resource(GameUiFontsState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(
            EguiPrimaryContextPass,
            (configure_game_ui_fonts_system, editor_ui_system).chain(),
        )
        .add_systems(
            Update,
            (
                handle_item_editor_commands,
                (
                    sync_preview_request_from_selection,
                    sync_preview_scene_system,
                    refresh_preview_load_status_system,
                    frame_loaded_scene_system,
                    preview_camera_input_system,
                    preview_camera_sync_system,
                )
                    .chain(),
            ),
        )
        .add_systems(Update, poll_external_selection_system)
        .run();
}

fn setup_editor(
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
                orbit: default_preview_orbit(),
                focus_anchor: default_preview_orbit().focus,
                viewport_rect: None,
                rotate_drag_active: false,
                pan_drag_active: false,
                block_pointer_input: false,
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
            floor_size: Vec2::new(8.0, 8.0),
            floor_color: Color::srgb(0.22, 0.235, 0.26),
            spawn_scene_host: true,
        },
    );
    commands.entity(stage.preview_camera).insert(PreviewCamera);
    preview_state.host_entity = stage.scene_host;
}
