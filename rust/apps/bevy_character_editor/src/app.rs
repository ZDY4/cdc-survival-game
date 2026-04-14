//! Bevy App 装配层。
//! 负责窗口、插件、启动系统、加载态切换和预览场景基础搭建。

use bevy::asset::AssetPlugin;
use bevy::camera::{visibility::RenderLayers, CameraOutputMode, ClearColorConfig};
use bevy::log::{info, LogPlugin};
use bevy::prelude::*;
use bevy::render::render_resource::BlendState;
use bevy::tasks::{block_on, poll_once, AsyncComputeTaskPool, Task};
use bevy::window::WindowPlugin;
use bevy_egui::{EguiGlobalSettings, EguiPlugin, EguiPrimaryContextPass, PrimaryEguiContext};
use game_bevy::{init_runtime_logging, rust_asset_dir, RuntimeLogSettings};
use game_editor::{
    build_persisted_primary_window,
    preview_camera_input_system as shared_preview_camera_input_system,
    preview_camera_sync_system as shared_preview_camera_sync_system, spawn_preview_floor,
    spawn_preview_light_rig, PreviewCameraController, PreviewOrbitCamera,
    WindowSizePersistenceConfig, WindowSizePersistencePlugin,
};

use crate::data::load_editor_data;
use crate::preview::{
    sync_preview_scene_system, PreviewCamera, CAMERA_RADIUS_MAX, CAMERA_RADIUS_MIN, PREVIEW_BG,
};
use crate::state::{EditorData, EditorEguiFontState, EditorUiState, PreviewState};
use crate::ui::{configure_egui_fonts_system, editor_ui_system, loading_ui_system};

#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
enum AppState {
    #[default]
    Loading,
    Ready,
}

#[derive(Component)]
struct LoadingTask(Task<EditorData>);

pub(crate) fn run() {
    let window_config =
        WindowSizePersistenceConfig::new("bevy_character_editor", 1720.0, 980.0, 1280.0, 720.0);
    let log_settings = RuntimeLogSettings::new("bevy_character_editor").with_single_run_file();
    if let Err(error) = init_runtime_logging(&log_settings) {
        eprintln!("failed to initialize bevy_character_editor logging: {error}");
    } else {
        info!("bevy_character_editor logger initialized");
    }
    App::new()
        .add_plugins(
            DefaultPlugins
                .build()
                .disable::<LogPlugin>()
                .set(WindowPlugin {
                    primary_window: Some(build_persisted_primary_window(
                        window_config.clone(),
                        "CDC Character Editor",
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
        .init_state::<AppState>()
        .insert_resource(ClearColor(PREVIEW_BG))
        .insert_resource(EditorUiState::default())
        .insert_resource(PreviewState::default())
        .insert_resource(EditorEguiFontState::default())
        .add_systems(Startup, (setup_editor, load_editor_data_async))
        .add_systems(
            EguiPrimaryContextPass,
            (
                configure_egui_fonts_system,
                loading_ui_system.run_if(in_state(AppState::Loading)),
                editor_ui_system.run_if(in_state(AppState::Ready)),
            )
                .chain(),
        )
        .add_systems(
            Update,
            (
                handle_loading_task.run_if(in_state(AppState::Loading)),
                (
                    sync_preview_scene_system,
                    shared_preview_camera_input_system,
                    shared_preview_camera_sync_system,
                )
                    .chain()
                    .run_if(in_state(AppState::Ready)),
            ),
        )
        .run();
}

// 异步加载编辑器数据，避免阻塞启动帧。
fn load_editor_data_async(mut commands: Commands) {
    let task = AsyncComputeTaskPool::get().spawn(async move { load_editor_data() });
    commands.spawn((LoadingTask(task),));
}

// 轮询加载任务，完成后切换到可交互状态。
fn handle_loading_task(
    mut commands: Commands,
    mut query: Query<(Entity, &mut LoadingTask)>,
    mut next_state: ResMut<NextState<AppState>>,
) {
    for (entity, mut task) in &mut query {
        if let Some(data) = block_on(poll_once(&mut task.0)) {
            info!(
                "character editor loading completed: characters={}, warnings={}",
                data.character_summaries.len(),
                data.warnings.len()
            );
            commands.insert_resource(data);
            commands.entity(entity).despawn();
            next_state.set(AppState::Ready);
        }
    }
}

// 初始化预览相机、光照、地板和 Egui 主上下文相机。
fn setup_editor(
    mut commands: Commands,
    mut egui_global_settings: ResMut<EguiGlobalSettings>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    egui_global_settings.auto_create_primary_context = false;

    spawn_preview_light_rig(&mut commands);
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
            far: 100.0,
            ..default()
        }),
        Transform::from_xyz(2.2, 1.6, 3.0).looking_at(Vec3::new(0.0, 0.95, 0.0), Vec3::Y),
        PreviewCameraController {
            orbit: PreviewOrbitCamera::default(),
            focus_anchor: PreviewOrbitCamera::default().focus,
            viewport_rect: None,
            rotate_drag_active: false,
            pan_drag_active: false,
            pitch_min: -1.1,
            pitch_max: 0.65,
            radius_min: CAMERA_RADIUS_MIN,
            radius_max: CAMERA_RADIUS_MAX,
            rotate_speed_x: 0.012,
            rotate_speed_y: 0.008,
            zoom_speed: 0.16,
            pan_speed: 1.0,
            pan_max_focus_offset: 1.35,
        },
        PreviewCamera,
    ));
    commands.spawn((
        PrimaryEguiContext,
        Camera2d,
        RenderLayers::none(),
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
    spawn_preview_floor(
        &mut commands,
        &mut meshes,
        &mut materials,
        Vec2::new(5.0, 5.0),
        Color::srgb(0.22, 0.235, 0.26),
    );
}
