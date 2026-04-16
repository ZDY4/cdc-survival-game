use bevy_egui::egui;
use game_data::CharacterAiPreview;

use crate::state::EditorUiState;

pub(super) fn render_derivation_sections(
    ui: &mut egui::Ui,
    preview: &CharacterAiPreview,
    ui_state: &EditorUiState,
) {
    super::render_goal_ranking(ui, preview);
    ui.separator();
    super::render_fact_results(ui, preview);
    ui.separator();
    super::render_advanced_diagnostics(ui, preview);
    let _ = ui_state;
}
