use bevy::diagnostic::FrameTimeDiagnosticsPlugin;
use bevy::log::warn;
use bevy::prelude::*;
use bevy::tasks::{block_on, poll_once, AsyncComputeTaskPool, Task};
use bevy_egui::EguiPrimaryContextPass;
use game_bevy::{
    rust_asset_dir,
    world_render::{
        WorldRenderConfig, WorldRenderPalette, WorldRenderPlugin, WorldRenderStyleProfile,
    },
};
use game_editor::{
    configure_editor_app_shell, configure_game_ui_fonts_system, EditorAppShellConfig,
    GameUiFontsState, WindowSizePersistenceConfig, write_editor_session, EditorKind,
};

use crate::camera::{apply_camera_transform_system, camera_input_system};
use crate::commands::{handle_map_editor_commands, MapEditorCommand};
use crate::handoff::poll_external_selection_system;
use crate::scene::{
    draw_hovered_grid_outline_system, rebuild_scene_system, setup_editor, update_hover_info_system,
};
use crate::state::{
    load_editor_state, load_editor_world_tiles, repo_root, EditorState, EditorUiState,
    ExternalMapSelectionState, MiddleClickState, OrbitCameraState,
};
use crate::ui::{editor_ui_system, loading_ui_system};

#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
enum AppState {
    #[default]
    Loading,
    Ready,
}

#[derive(Resource)]
struct LoadedEditorResources {
    editor: EditorState,
    world_tiles: crate::state::EditorWorldTileDefinitions,
}

#[derive(Resource, Debug, Clone, Default)]
struct InitialMapSelection(Option<String>);

#[derive(Component)]
struct LoadingTask(Task<LoadedEditorResources>);

pub(crate) fn run(initial_map_id: Option<String>) {
    let repo_root = repo_root();
    if let Err(error) = write_editor_session(&repo_root, EditorKind::Map, std::process::id()) {
        warn!("map editor failed to create initial handoff session: {error}");
    }

    let render_palette = WorldRenderPalette::default();
    let render_style = WorldRenderStyleProfile::default();
    let render_config = WorldRenderConfig::default();
    let asset_dir = rust_asset_dir();
    let mut app = App::new();
    configure_editor_app_shell(
        &mut app,
        &EditorAppShellConfig::new(
            "bevy_map_editor",
            "CDC Map Editor",
            asset_dir,
            WindowSizePersistenceConfig::new("bevy_map_editor", 1680.0, 980.0, 1280.0, 720.0),
        ),
    );

    app.init_state::<AppState>()
        .add_message::<MapEditorCommand>()
        .add_plugins(WorldRenderPlugin)
        .add_plugins(FrameTimeDiagnosticsPlugin::default())
        .insert_resource(ClearColor(render_palette.clear_color))
        .insert_resource(render_palette)
        .insert_resource(render_style)
        .insert_resource(render_config)
        .insert_resource(GameUiFontsState::default())
        .insert_resource(EditorUiState::default())
        .insert_resource(OrbitCameraState::default())
        .insert_resource(MiddleClickState::default())
        .insert_resource(ExternalMapSelectionState::new(repo_root))
        .insert_resource(InitialMapSelection(initial_map_id))
        .add_systems(Startup, (setup_editor, load_editor_data_async))
        .add_systems(
            EguiPrimaryContextPass,
            (
                configure_game_ui_fonts_system,
                loading_ui_system.run_if(in_state(AppState::Loading)),
                editor_ui_system.run_if(in_state(AppState::Ready)),
            )
                .chain(),
        )
        .add_systems(
            Update,
            (
                handle_loading_task.run_if(in_state(AppState::Loading)),
                poll_external_selection_system.run_if(in_state(AppState::Ready)),
                handle_map_editor_commands.run_if(in_state(AppState::Ready)),
                (
                    rebuild_scene_system,
                    camera_input_system,
                    apply_camera_transform_system,
                    update_hover_info_system,
                    draw_hovered_grid_outline_system,
                )
                    .chain()
                    .run_if(in_state(AppState::Ready)),
            ),
        )
        .run();
}

fn load_editor_data_async(mut commands: Commands) {
    let task = AsyncComputeTaskPool::get().spawn(async move {
        LoadedEditorResources {
            editor: load_editor_state(),
            world_tiles: load_editor_world_tiles(),
        }
    });
    commands.spawn((LoadingTask(task),));
}

fn handle_loading_task(
    mut commands: Commands,
    mut query: Query<(Entity, &mut LoadingTask)>,
    mut next_state: ResMut<NextState<AppState>>,
    initial_selection: Res<InitialMapSelection>,
) {
    for (entity, mut task) in &mut query {
        if let Some(mut loaded) = block_on(poll_once(&mut task.0)) {
            if let Some(map_id) = initial_selection.0.as_ref() {
                if let Some(document) = loaded.editor.maps.get(map_id) {
                    loaded
                        .editor
                        .show_map(map_id.clone(), document.definition.default_level);
                    loaded.editor.status =
                        format!("Loaded map editor and selected map {map_id}.");
                } else {
                    loaded.editor.status =
                        format!("Loaded map editor. Requested map {map_id} was not found.");
                    warn!("map editor startup selection not found: map_id={map_id}");
                }
            }
            commands.insert_resource(loaded.editor);
            commands.insert_resource(loaded.world_tiles);
            commands.entity(entity).despawn();
            next_state.set(AppState::Ready);
        }
    }
}
