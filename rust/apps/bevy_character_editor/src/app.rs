//! Bevy App 装配层。
//! 负责窗口、插件、启动系统、加载态切换和预览场景基础搭建。

use bevy::camera::visibility::RenderLayers;
use bevy::prelude::*;
use bevy::tasks::{block_on, poll_once, AsyncComputeTaskPool, Task};
use bevy_egui::EguiPrimaryContextPass;
use game_bevy::rust_asset_dir;
use game_editor::{
    configure_editor_app_shell, configure_game_ui_fonts_system,
    preview_camera_input_system as shared_preview_camera_input_system,
    preview_camera_sync_system as shared_preview_camera_sync_system, setup_preview_stage,
    EditorAppShellConfig, GameUiFontsState, PreviewCameraController,
    PreviewStageConfig, WindowSizePersistenceConfig,
};

use crate::camera_mode::{PreviewCameraModeState, FREE_PREVIEW_FOV};
use crate::commands::{
    ensure_selected_character_system, handle_character_editor_commands, CharacterEditorCommand,
};
use crate::data::load_editor_data;
use crate::preview::{
    sync_preview_scene_system, PreviewCamera, CAMERA_RADIUS_MAX, CAMERA_RADIUS_MIN, PREVIEW_BG,
};
use crate::state::{CharacterUiStyleState, EditorData, EditorUiState, PreviewState};
use crate::ui::{configure_character_ui_style_system, editor_ui_system, loading_ui_system};

#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
enum AppState {
    #[default]
    Loading,
    Ready,
}

#[derive(Component)]
struct LoadingTask(Task<EditorData>);

pub(crate) fn run() {
    let mut app = App::new();
    configure_editor_app_shell(
        &mut app,
        &EditorAppShellConfig::new(
            "bevy_character_editor",
            "CDC Character Editor",
            rust_asset_dir(),
            WindowSizePersistenceConfig::new("bevy_character_editor", 1720.0, 980.0, 1280.0, 720.0),
        ),
    );
    app.init_state::<AppState>()
        .add_message::<CharacterEditorCommand>()
        .insert_resource(ClearColor(PREVIEW_BG))
        .insert_resource(EditorUiState::default())
        .insert_resource(PreviewState::default())
        .insert_resource(PreviewCameraModeState::default())
        .insert_resource(GameUiFontsState::default())
        .insert_resource(CharacterUiStyleState::default())
        .add_systems(Startup, (setup_editor, load_editor_data_async))
        .add_systems(
            EguiPrimaryContextPass,
            (
                configure_game_ui_fonts_system,
                configure_character_ui_style_system,
                loading_ui_system.run_if(in_state(AppState::Loading)),
                editor_ui_system.run_if(in_state(AppState::Ready)),
            )
                .chain(),
        )
        .add_systems(
            Update,
            (
                handle_loading_task.run_if(in_state(AppState::Loading)),
                ensure_selected_character_system.run_if(in_state(AppState::Ready)),
                handle_character_editor_commands.run_if(in_state(AppState::Ready)),
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
    mut egui_global_settings: ResMut<bevy_egui::EguiGlobalSettings>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let stage = setup_preview_stage(
        &mut commands,
        &mut egui_global_settings,
        &mut meshes,
        &mut materials,
        &PreviewStageConfig {
            clear_color: PREVIEW_BG,
            projection: Projection::Perspective(PerspectiveProjection {
                fov: FREE_PREVIEW_FOV,
                near: 0.01,
                far: 100.0,
                ..default()
            }),
            camera_transform: Transform::from_xyz(2.2, 1.6, 3.0)
                .looking_at(Vec3::new(0.0, 0.95, 0.0), Vec3::Y),
            controller: PreviewCameraController {
                orbit: game_editor::PreviewOrbitCamera::default(),
                focus_anchor: game_editor::PreviewOrbitCamera::default().focus,
                viewport_rect: None,
                rotate_drag_active: false,
                pan_drag_active: false,
                block_pointer_input: false,
                allow_rotate: true,
                allow_pan: true,
                allow_zoom: true,
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
            floor_size: Vec2::new(5.0, 5.0),
            floor_color: Color::srgb(0.22, 0.235, 0.26),
            spawn_scene_host: false,
        },
    );
    commands.entity(stage.preview_camera).insert(PreviewCamera);
    commands
        .entity(stage.egui_camera)
        .insert(RenderLayers::none());
}
