use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_editor::{
    render_model_hierarchy_panel, render_model_preview_hud, selectable_list_row, GameUiFontsState,
    ModelHierarchyPanelState, ModelHierarchySource, ModelPreviewHud, PreviewCameraController,
    PreviewGroundVisibility, PreviewPivotVisibility, PreviewViewportRect,
};

use crate::bbmodel_links::sync_bbmodel_link_ui_state;
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
    mut ground_visibility: ResMut<PreviewGroundVisibility>,
    mut pivot_visibility: ResMut<PreviewPivotVisibility>,
    mut hierarchy_panel: ResMut<ModelHierarchyPanelState>,
    mut preview_camera: Single<&mut PreviewCameraController, With<PreviewCamera>>,
    mut requests: MessageWriter<GltfViewerCommand>,
) {
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };
    sync_bbmodel_link_ui_state(&catalog.asset_root, &mut ui_state);

    egui::SidePanel::left("model_list")
        .resizable(false)
        .exact_width(MODEL_PANEL_WIDTH)
        .show(ctx, |ui| {
            ui.heading("模型列表");
            ui.label(format!("资产根: {}", catalog.asset_root.display()));
            ui.add_space(8.0);
            ui.label("搜索");
            ui.text_edit_singleline(&mut ui_state.search_text);
            let mut show_socket_editor = ui_state.show_socket_editor;
            if ui
                .checkbox(&mut show_socket_editor, "Socket 编辑")
                .changed()
            {
                requests.write(GltfViewerCommand::ToggleSocketEditor);
            }
            let has_selection = ui_state.selected_model_path.is_some();
            if let Some(status) = ui_state.bbmodel_link_status.as_deref() {
                ui.small(status);
            }
            ui.label("bbmodel 关联");
            ui.add_enabled(
                has_selection,
                egui::TextEdit::singleline(&mut ui_state.bbmodel_link_draft)
                    .hint_text("例如 bevy_preview/characters/foo.bbmodel")
                    .desired_width(f32::INFINITY),
            );
            ui.horizontal(|ui| {
                if ui
                    .add_enabled(has_selection, egui::Button::new("保存关联"))
                    .clicked()
                {
                    requests.write(GltfViewerCommand::SaveBbmodelLink);
                }
                if ui
                    .add_enabled(has_selection, egui::Button::new("清除关联"))
                    .clicked()
                {
                    requests.write(GltfViewerCommand::ClearBbmodelLink);
                }
            });
            if ui
                .add_enabled(has_selection, egui::Button::new("使用同名 bbmodel"))
                .clicked()
            {
                requests.write(GltfViewerCommand::UseSiblingBbmodelLink);
            }
            if ui.button("重扫目录").clicked() {
                requests.write(GltfViewerCommand::RescanCatalog);
            }
            if let Some(status) = ui_state.external_tool_status.as_deref() {
                ui.small(status);
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
                    let model_path = entry.relative_path.clone();
                    let response = selectable_list_row(ui, selected, entry.display_name.as_str())
                        .on_hover_text(entry.relative_path.as_str());
                    let clicked = response.clicked();
                    response.context_menu(|ui| {
                        if ui.button("用 Blockbench 编辑").clicked() {
                            requests.write(GltfViewerCommand::OpenModelInBlockbench(
                                model_path.clone(),
                            ));
                            ui.close();
                        }
                        if ui.button("重载当前模型").clicked() {
                            requests.write(GltfViewerCommand::ReloadModel(model_path.clone()));
                            ui.close();
                        }
                        if ui.button("打开模型所在目录").clicked() {
                            requests
                                .write(GltfViewerCommand::OpenModelDirectory(model_path.clone()));
                            ui.close();
                        }
                    });
                    if clicked && !selected {
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
            let status = preview_status_for_hud(&preview_state);
            let hud_response = render_model_preview_hud(
                ui.ctx(),
                "gltf_viewer_preview_hud",
                rect,
                ModelPreviewHud {
                    title: ui_state
                        .selected_model_path
                        .as_deref()
                        .unwrap_or("未找到可预览的 glTF"),
                    size: preview_state.model_size,
                    status: status.as_deref(),
                    ground_visible: ground_visibility.visible,
                    pivot_visible: pivot_visibility.visible,
                },
                |ui| {
                    let mut hierarchy_visible = hierarchy_panel.visible;
                    if ui.checkbox(&mut hierarchy_visible, "层级树").changed() {
                        hierarchy_panel.visible = hierarchy_visible;
                    }
                },
            );
            if hud_response.toggle_ground {
                ground_visibility.toggle();
            }
            if hud_response.toggle_pivot {
                pivot_visibility.toggle();
            }
            let hierarchy_sources = ui_state
                .selected_model_path
                .as_ref()
                .map(|path| vec![ModelHierarchySource::new("当前模型", path.clone())])
                .unwrap_or_default();
            let hierarchy_response = render_model_hierarchy_panel(
                ui.ctx(),
                "gltf_viewer_model_hierarchy",
                rect,
                &mut hierarchy_panel,
                &catalog.asset_root,
                &hierarchy_sources,
            );
            preview_camera.block_pointer_input =
                ui.ctx().is_using_pointer() || hud_response.hovered || hierarchy_response.hovered;
            paint_axis_gizmo(ui, rect, preview_camera.orbit);
        });
}

fn preview_status_for_hud(preview_state: &PreviewState) -> Option<String> {
    if matches!(
        preview_state.load_status,
        crate::state::PreviewLoadStatus::Ready
    ) {
        None
    } else {
        Some(preview_state.load_status.label())
    }
}
