use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::EguiPrimaryContextPass;
use game_bevy::rust_asset_dir;
use game_editor::{
    configure_editor_app_shell, configure_game_ui_fonts_system, setup_primary_egui_context_camera,
    write_editor_session, EditorAppShellConfig, EditorKind, GameUiFontsState,
    WindowSizePersistenceConfig,
};

use crate::commands::{handle_dialogue_editor_commands, DialogueEditorCommand};
use crate::data::load_editor_resources;
use crate::handoff::poll_external_selection_system;
use crate::state::ExternalDialogueSelectionState;
use crate::ui::editor_ui_system;

pub(crate) fn run(initial_dialogue_id: Option<String>) -> Result<(), String> {
    let (editor_state, catalogs) = load_editor_resources(initial_dialogue_id)
        .map_err(|error| format!("dialogue editor failed to load: {error}"))?;
    let repo_root = editor_state.repo_root.clone();
    if let Err(error) = write_editor_session(&repo_root, EditorKind::Dialogue, std::process::id()) {
        warn!("dialogue editor failed to create initial handoff session: {error}");
    }

    let mut app = App::new();
    configure_editor_app_shell(
        &mut app,
        &EditorAppShellConfig::new(
            "bevy_dialogue_editor",
            "CDC Dialogue Viewer",
            rust_asset_dir(),
            WindowSizePersistenceConfig::new("bevy_dialogue_editor", 1700.0, 980.0, 1280.0, 720.0),
        ),
    );

    app.add_message::<DialogueEditorCommand>()
        .insert_resource(editor_state)
        .insert_resource(catalogs)
        .insert_resource(ExternalDialogueSelectionState::new(repo_root))
        .insert_resource(GameUiFontsState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(
            EguiPrimaryContextPass,
            (configure_game_ui_fonts_system, editor_ui_system).chain(),
        )
        .add_systems(
            Update,
            (
                handle_dialogue_editor_commands,
                poll_external_selection_system,
            ),
        )
        .run();

    Ok(())
}

fn setup_editor(
    mut commands: Commands,
    mut egui_global_settings: ResMut<bevy_egui::EguiGlobalSettings>,
) {
    setup_primary_egui_context_camera(&mut commands, &mut egui_global_settings);
}
