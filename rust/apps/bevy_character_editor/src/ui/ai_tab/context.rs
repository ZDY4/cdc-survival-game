use bevy_egui::egui;
use game_data::CharacterAiPreview;

use crate::state::{EditorData, EditorUiState};

pub(super) fn render_context_sections(
    ui: &mut egui::Ui,
    data: &EditorData,
    preview: &CharacterAiPreview,
    ui_state: &EditorUiState,
) {
    super::render_conclusion_summary(ui, preview, ui_state);
    ui.separator();
    super::render_effective_profiles(ui, data, preview);
    ui.separator();
    super::render_scene_snapshot(ui, preview, ui_state);
}
