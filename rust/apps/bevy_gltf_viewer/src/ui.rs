use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_editor::{GameUiFontsState, PreviewCameraController, PreviewViewportRect};

use crate::catalog::ModelCatalog;
use crate::commands::GltfViewerCommand;
use crate::preview::paint_axis_gizmo;
use crate::state::{PreviewCamera, PreviewState, ViewerUiState, ViewerUiStyleState};

const MODEL_PANEL_WIDTH: f32 = 320.0;

pub(crate) fn configure_viewer_ui_style_system(
    mut contexts: EguiContexts,
    fonts_state: Res<GameUiFontsState>,
    mut style_state: ResMut<ViewerUiStyleState>,
) {
    if !fonts_state.initialized || style_state.initialized {
        return;
    }
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    let mut style = (*ctx.style()).clone();
    style.spacing.item_spacing = egui::vec2(6.0, 4.0);
    style.spacing.button_padding = egui::vec2(8.0, 5.0);
    style.visuals.widgets.noninteractive.corner_radius = 4.0.into();
    style.visuals.widgets.inactive.corner_radius = 4.0.into();
    style.visuals.widgets.hovered.corner_radius = 4.0.into();
    style.visuals.widgets.active.corner_radius = 4.0.into();
    ctx.set_style(style);
    style_state.initialized = true;
}

pub(crate) fn loading_ui_system(mut contexts: EguiContexts) {
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    egui::CentralPanel::default().show(ctx, |ui| {
        ui.vertical_centered(|ui| {
            ui.add_space(ui.available_height() / 2.0 - 40.0);
            ui.heading("正在扫描模型目录…");
            ui.add_space(16.0);
            ui.spinner();
        });
    });
}

pub(crate) fn viewer_ui_system(
    mut contexts: EguiContexts,
    catalog: Res<ModelCatalog>,
    mut ui_state: ResMut<ViewerUiState>,
    preview_state: Res<PreviewState>,
    mut preview_camera: Single<&mut PreviewCameraController, With<PreviewCamera>>,
    mut requests: MessageWriter<GltfViewerCommand>,
) {
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    egui::SidePanel::left("model_list")
        .resizable(false)
        .exact_width(MODEL_PANEL_WIDTH)
        .show(ctx, |ui| {
            ui.heading("模型列表");
            ui.label(format!("资产根: {}", catalog.asset_root.display()));
            ui.add_space(8.0);
            ui.label("搜索");
            ui.text_edit_singleline(&mut ui_state.search_text);
            let mut show_ground = ui_state.show_ground;
            if ui.checkbox(&mut show_ground, "显示地面").changed() {
                requests.write(GltfViewerCommand::ToggleGround);
            }
            if ui.button("重扫目录").clicked() {
                requests.write(GltfViewerCommand::RescanCatalog);
            }
            ui.add_space(8.0);

            let query = ui_state.search_text.trim().to_ascii_lowercase();
            let filtered = catalog
                .entries
                .iter()
                .filter(|entry| query.is_empty() || entry.search_text.contains(&query))
                .collect::<Vec<_>>();

            ui.small(format!(
                "{} / {} 个模型",
                filtered.len(),
                catalog.entries.len()
            ));
            ui.separator();

            egui::ScrollArea::vertical().show(ui, |ui| {
                for entry in filtered {
                    let selected = ui_state.selected_model_path.as_deref()
                        == Some(entry.relative_path.as_str());
                    let response = ui
                        .add_sized(
                            [ui.available_width(), 0.0],
                            egui::Button::new(entry.display_name.as_str())
                                .selected(selected)
                                .truncate(),
                        )
                        .on_hover_text(entry.relative_path.as_str());
                    if response.clicked() && !selected {
                        requests.write(GltfViewerCommand::SelectModel(entry.relative_path.clone()));
                    }
                }
            });
        });

    egui::CentralPanel::default()
        .frame(egui::Frame::NONE)
        .show(ctx, |ui| {
            let rect = ui.max_rect();
            preview_camera.viewport_rect = Some(PreviewViewportRect {
                min_x: rect.min.x,
                min_y: rect.min.y,
                width: rect.width(),
                height: rect.height(),
            });
            ui.allocate_rect(rect, egui::Sense::hover());
            let info_rect = egui::Rect::from_min_size(
                rect.left_top() + egui::vec2(10.0, 10.0),
                egui::vec2(360.0, 56.0),
            );
            ui.painter().rect_filled(
                info_rect,
                6.0,
                egui::Color32::from_rgba_unmultiplied(18, 21, 28, 176),
            );
            ui.painter().text(
                rect.left_top() + egui::vec2(14.0, 12.0),
                egui::Align2::LEFT_TOP,
                "glTF 预览",
                egui::FontId::new(14.0, egui::FontFamily::Proportional),
                egui::Color32::from_rgb(228, 231, 238),
            );
            ui.painter().text(
                rect.left_top() + egui::vec2(14.0, 32.0),
                egui::Align2::LEFT_TOP,
                ui_state
                    .selected_model_path
                    .as_deref()
                    .unwrap_or("未找到可预览的 glTF/glb"),
                egui::FontId::new(11.0, egui::FontFamily::Proportional),
                egui::Color32::from_rgb(164, 170, 184),
            );
            ui.painter().text(
                rect.left_top() + egui::vec2(14.0, 50.0),
                egui::Align2::LEFT_TOP,
                preview_state.load_status.label(),
                egui::FontId::new(11.0, egui::FontFamily::Proportional),
                egui::Color32::from_rgb(164, 170, 184),
            );
            paint_axis_gizmo(ui, rect, preview_camera.orbit);
        });
}
