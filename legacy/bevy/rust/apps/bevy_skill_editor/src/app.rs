use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::EguiPrimaryContextPass;
use game_bevy::rust_asset_dir;
use game_editor::{
    configure_editor_app_shell, configure_game_ui_fonts_system, setup_primary_egui_context_camera,
    write_editor_session, EditorAppShellConfig, EditorKind, GameUiFontsState,
    WindowSizePersistenceConfig,
};

use crate::commands::{handle_skill_editor_commands, SkillEditorCommand};
use crate::data::load_editor_resources;
use crate::handoff::poll_external_selection_system;
use crate::state::ExternalSkillSelectionState;
use crate::ui::editor_ui_system;

pub(crate) fn run(initial_skill_id: Option<String>, initial_tree_id: Option<String>) {
    let (editor_state, catalogs) = match load_editor_resources(initial_skill_id, initial_tree_id) {
        Ok(value) => value,
        Err(error) => {
            eprintln!("skill editor failed to load: {error}");
            return;
        }
    };
    let repo_root = editor_state.repo_root.clone();
    if let Err(error) = write_editor_session(&repo_root, EditorKind::Skill, std::process::id()) {
        warn!("skill editor failed to create initial handoff session: {error}");
    }

    let mut app = App::new();
    configure_editor_app_shell(
        &mut app,
        &EditorAppShellConfig::new(
            "bevy_skill_editor",
            "CDC Skill Editor",
            rust_asset_dir(),
            WindowSizePersistenceConfig::new("bevy_skill_editor", 1760.0, 1020.0, 1280.0, 720.0),
        ),
    );

    app.add_message::<SkillEditorCommand>()
        .insert_resource(editor_state)
        .insert_resource(catalogs)
        .insert_resource(ExternalSkillSelectionState::new(repo_root))
        .insert_resource(GameUiFontsState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(
            EguiPrimaryContextPass,
            (configure_game_ui_fonts_system, editor_ui_system).chain(),
        )
        .add_systems(
            Update,
            (handle_skill_editor_commands, poll_external_selection_system),
        )
        .run();
}

fn setup_editor(
    mut commands: Commands,
    mut egui_global_settings: ResMut<bevy_egui::EguiGlobalSettings>,
) {
    setup_primary_egui_context_camera(&mut commands, &mut egui_global_settings);
}
