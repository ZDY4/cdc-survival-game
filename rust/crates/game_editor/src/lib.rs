pub mod ai_chat;
pub mod app_shell;
pub mod character_preview;
pub mod editor_handoff;
pub mod fonts;
pub mod preview;
pub mod preview_stage;
pub mod window_size_persistence;

pub use app_shell::{configure_editor_app_shell, EditorAppShellConfig};
pub use character_preview::{
    character_preview_is_available, parse_preview_color, spawn_character_preview_scene,
    CharacterPreviewPart, CharacterPreviewRoot,
};
pub use editor_handoff::{
    clear_item_editor_selection_request, clear_item_editor_session,
    item_editor_selection_request_path, item_editor_session_is_recent, item_editor_session_path,
    read_item_editor_selection_request, read_item_editor_session,
    write_item_editor_selection_request, write_item_editor_session, ItemEditorSelectionRequest,
    ItemEditorSession,
};
pub use fonts::{
    configure_game_ui_fonts_system, game_ui_font_bytes, install_game_ui_fonts, load_game_ui_font,
    GameUiFontsState, GAME_UI_FONT_NAME,
};
pub use preview::{
    apply_preview_orbit_camera, preview_camera_input_system, preview_camera_sync_system,
    replace_preview_scene, spawn_preview_floor, spawn_preview_light_rig, spawn_preview_origin_axes,
    spawn_preview_scene_host, PreviewCameraController, PreviewFloor, PreviewOrbitCamera,
    PreviewOriginAxes, PreviewSceneHost, PreviewSceneInstance, PreviewViewportRect,
};
pub use preview_stage::{setup_preview_stage, PreviewStageConfig, PreviewStageEntities};
pub use window_size_persistence::{
    build_persisted_primary_window, WindowSizePersistenceConfig, WindowSizePersistencePlugin,
};
