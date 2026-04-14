//! 外观页。
//! 负责显示当前外观预览结果和试装槽位，不参与 AI 预览逻辑。

use bevy_egui::egui;
use game_data::CharacterDefinition;
use game_editor::PreviewCameraController;

use crate::preview::refresh_preview_state;
use crate::state::{non_empty, EditorData, EditorUiState, PreviewState};

use super::common::key_value;

// 外观页主入口，展示解析结果并提供试装交互。
pub(crate) fn render_appearance_tab(
    ui: &mut egui::Ui,
    character: &CharacterDefinition,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
    preview_camera: &mut PreviewCameraController,
) {
    key_value(ui, "外观配置", non_empty(&character.appearance_profile_id));
    if let Some(preview) = preview_state.resolved_preview.as_ref() {
        key_value(ui, "基础模型", &preview.base_model_asset);
        key_value(ui, "相机预设", &preview.preview_camera_preset_id);
        key_value(ui, "挂点预设", &preview.equip_anchor_profile_id);
        key_value(ui, "隐藏区域", &preview.hidden_base_regions.join(", "));
        if !preview.diagnostics.is_empty() {
            ui.colored_label(
                egui::Color32::from_rgb(224, 176, 72),
                preview.diagnostics.join("\n"),
            );
        }
    }
    if let Some(error) = &preview_state.appearance_error {
        ui.colored_label(egui::Color32::from_rgb(240, 110, 110), error);
    }
    ui.separator();
    ui.horizontal(|ui| {
        ui.label("当前槽位");
        egui::ComboBox::from_id_salt("appearance_slot")
            .selected_text(&ui_state.selected_slot)
            .show_ui(ui, |ui| {
                for slot in data.item_catalog_by_slot.keys() {
                    ui.selectable_value(&mut ui_state.selected_slot, slot.clone(), slot);
                }
            });
    });
    if let Some(items) = data.item_catalog_by_slot.get(&ui_state.selected_slot) {
        let selected_text = ui_state
            .try_on
            .get(&ui_state.selected_slot)
            .and_then(|item_id| items.iter().find(|item| item.id == *item_id))
            .map(|item| format!("{} [{}]", item.name, item.id))
            .unwrap_or_else(|| "未装备".to_string());
        egui::ComboBox::from_id_salt("appearance_choice")
            .selected_text(selected_text)
            .show_ui(ui, |ui| {
                if ui
                    .add_sized(
                        [ui.available_width(), 0.0],
                        egui::Button::new("未装备")
                            .selected(!ui_state.try_on.contains_key(&ui_state.selected_slot))
                            .truncate(),
                    )
                    .clicked()
                {
                    ui_state.try_on.remove(&ui_state.selected_slot);
                    refresh_preview_state(data, ui_state, preview_state, preview_camera, false);
                }
                for item in items {
                    let label = format!("{} [{}]", item.name, item.id);
                    if ui
                        .add_sized(
                            [ui.available_width(), 0.0],
                            egui::Button::new(label.as_str())
                                .selected(
                                    ui_state.try_on.get(&ui_state.selected_slot) == Some(&item.id),
                                )
                                .truncate(),
                        )
                        .on_hover_text(label)
                        .clicked()
                    {
                        ui_state
                            .try_on
                            .insert(ui_state.selected_slot.clone(), item.id);
                        refresh_preview_state(data, ui_state, preview_state, preview_camera, false);
                    }
                }
            });
    }
}
