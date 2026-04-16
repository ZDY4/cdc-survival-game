use bevy_egui::egui;
use game_data::CharacterAiPreview;

pub(super) fn render_execution_sections(ui: &mut egui::Ui, preview: &CharacterAiPreview) {
    super::render_action_results(ui, preview);
}
