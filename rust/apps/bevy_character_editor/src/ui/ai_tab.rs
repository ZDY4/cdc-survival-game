//! AI 预览页。
//! 负责展示 AI 输入上下文、据点关联、推导过程和行动阻断原因，不写回任何数据。

mod context;
mod derivation;
mod execution;
mod helpers;
mod scene_controls;

use bevy::prelude::*;
use bevy_egui::egui;
use game_data::CharacterDefinition;

use crate::commands::CharacterEditorCommand;
use crate::preview::settlement_for_character;
use crate::state::{EditorData, EditorUiState, PreviewState};

pub(crate) fn render_ai_tab(
    ui: &mut egui::Ui,
    character: &CharacterDefinition,
    data: &EditorData,
    ui_state: &EditorUiState,
    preview_state: &PreviewState,
    requests: &mut MessageWriter<CharacterEditorCommand>,
) {
    let settlement = settlement_for_character(character, &data.settlements);

    if let Some(error) = &preview_state.ai_error {
        ui.colored_label(egui::Color32::from_rgb(240, 110, 110), error);
        return;
    }

    {
        let Some(preview) = preview_state.ai_preview.as_ref() else {
            ui.label("当前没有 AI 预览结果。");
            return;
        };
        scene_controls::render_scene_controls(
            ui,
            character,
            data,
            settlement.is_some(),
            preview,
            ui_state,
            requests,
        );
    }

    let Some(preview) = preview_state.ai_preview.as_ref() else {
        ui.label("当前没有 AI 预览结果。");
        return;
    };

    ui.separator();
    context::render_context_sections(ui, data, preview, ui_state);
    ui.separator();
    derivation::render_derivation_sections(ui, preview);
    ui.separator();
    execution::render_execution_sections(ui, preview);
}
