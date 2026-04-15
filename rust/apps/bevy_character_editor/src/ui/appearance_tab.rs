//! 外观页。
//! 负责显示当前外观预览结果和全部试装槽位，不参与 AI 预览逻辑。

use bevy::prelude::Projection;
use bevy_egui::egui;
use game_data::CharacterDefinition;
use game_editor::PreviewCameraController;

use crate::camera_mode::PreviewCameraModeState;
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
    camera_mode: &mut PreviewCameraModeState,
    preview_camera: &mut PreviewCameraController,
    preview_projection: &mut Projection,
) {
    let mut pending_try_on_change: Option<(String, Option<u32>)> = None;

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
    if data.item_catalog_by_slot.is_empty() {
        ui.small("当前仓库没有可试装的装备槽位。");
    }

    for (slot, items) in &data.item_catalog_by_slot {
        let selected_item_id = ui_state.try_on.get(slot).copied();
        let selected_text = selected_item_id
            .and_then(|item_id| items.iter().find(|item| item.id == item_id))
            .map(|item| format!("{} [{}]", item.name, item.id))
            .unwrap_or_else(|| "未装备".to_string());

        egui::Frame::group(ui.style()).show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.label(egui::RichText::new(slot).strong());
            egui::ComboBox::from_id_salt(("appearance_choice", slot))
                .selected_text(selected_text)
                .width(ui.available_width())
                .show_ui(ui, |ui| {
                    if ui
                        .selectable_label(selected_item_id.is_none(), "未装备")
                        .clicked()
                    {
                        pending_try_on_change = Some((slot.clone(), None));
                    }
                    for item in items {
                        let label = format!("{} [{}]", item.name, item.id);
                        if ui
                            .selectable_label(selected_item_id == Some(item.id), label.as_str())
                            .on_hover_text(label)
                            .clicked()
                        {
                            pending_try_on_change = Some((slot.clone(), Some(item.id)));
                        }
                    }
                });
        });
        ui.add_space(6.0);
    }

    if let Some((slot, item_id)) = pending_try_on_change {
        match item_id {
            Some(item_id) => {
                ui_state.try_on.insert(slot, item_id);
            }
            None => {
                ui_state.try_on.remove(&slot);
            }
        }
        refresh_preview_state(
            data,
            ui_state,
            preview_state,
            camera_mode,
            preview_camera,
            preview_projection,
            false,
        );
    }
}
