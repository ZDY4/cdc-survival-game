pub mod app_shell;
pub mod character_preview;
pub mod editor_handoff;
pub mod flow_graph;
pub mod fonts;
pub mod list_row;
pub mod preview;
pub mod preview_stage;
pub mod primary_egui;
pub mod window_size_persistence;
pub mod workspace;

pub use app_shell::{configure_editor_app_shell, EditorAppShellConfig};
pub use character_preview::{
    character_preview_is_available, parse_preview_color, spawn_character_preview_scene,
    sync_builtin_humanoid_mannequin_scene_system, CharacterPreviewPart, CharacterPreviewRoot,
};
pub use editor_handoff::{
    clear_editor_navigation_request, clear_editor_session, editor_navigation_request_path,
    editor_session_is_recent, editor_session_path, read_editor_navigation_request,
    read_editor_session, write_editor_navigation_request, write_editor_session, EditorKind,
    EditorNavigationAction, EditorNavigationRequest, EditorSession,
};
pub use flow_graph::{
    render_read_only_flow_graph, FlowGraphCanvasState, FlowGraphEdge, FlowGraphModel,
    FlowGraphNode, FlowGraphResponse,
};
pub use fonts::{
    configure_game_ui_fonts_system, game_ui_font_bytes, install_game_ui_fonts, load_game_ui_font,
    GameUiFontsState, GAME_UI_FONT_NAME,
};
pub use list_row::selectable_list_row;
pub use preview::{
    apply_preview_orbit_camera, preview_camera_input_system, preview_camera_sync_system,
    replace_preview_scene, spawn_preview_floor, spawn_preview_light_rig, spawn_preview_origin_axes,
    spawn_preview_scene_host, PreviewCameraController, PreviewFloor, PreviewOrbitCamera,
    PreviewOriginAxes, PreviewSceneHost, PreviewSceneInstance, PreviewViewportRect,
};
pub use preview_stage::{setup_preview_stage, PreviewStageConfig, PreviewStageEntities};
pub use primary_egui::setup_primary_egui_context_camera;
pub use window_size_persistence::{
    build_persisted_primary_window, WindowSizePersistenceConfig, WindowSizePersistencePlugin,
};
pub use workspace::{WorkingDocumentStore, WorkspaceDocument};
