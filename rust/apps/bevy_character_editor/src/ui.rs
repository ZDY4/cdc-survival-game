//! 顶层 UI 布局层。
//! 负责整体面板编排、左侧角色列表、中央预览区和子模块路由，不承载具体业务解释逻辑。

mod ai_tab;
mod appearance_tab;
mod common;
mod detail_panel;

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_bevy::MeshPickIndex;
use game_editor::{
    render_model_preview_hud, selectable_list_row, GameUiFontsState, ModelPreviewHud,
    PreviewCameraController, PreviewGroundVisibility, PreviewPivotVisibility, PreviewViewportRect,
};

use crate::camera_mode::{PreviewCameraMode, PreviewCameraModeState};
use crate::commands::CharacterEditorCommand;
use crate::preview::PreviewCamera;
use crate::state::{non_empty, CharacterUiStyleState, EditorData, EditorUiState, PreviewState};
use common::build_diagnostic_hover_text;
use detail_panel::render_detail_panel;

const LIST_PANEL_WIDTH: f32 = 250.0;
const DETAIL_PANEL_WIDTH: f32 = 430.0;

// 初始化编辑器统一字体和基础控件样式。
pub(crate) fn configure_character_ui_style_system(
    mut contexts: EguiContexts,
    fonts_state: Res<GameUiFontsState>,
    mut style_state: ResMut<CharacterUiStyleState>,
) {
    if !fonts_state.initialized || style_state.initialized {
        return;
    }
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    let mut style = (*ctx.style()).clone();
    style.spacing.item_spacing = egui::vec2(6.0, 4.0);
    style.spacing.button_padding = egui::vec2(8.0, 4.0);
    style.visuals.widgets.noninteractive.corner_radius = 4.0.into();
    style.visuals.widgets.inactive.corner_radius = 4.0.into();
    style.visuals.widgets.hovered.corner_radius = 4.0.into();
    style.visuals.widgets.active.corner_radius = 4.0.into();
    style.text_styles.insert(
        egui::TextStyle::Heading,
        egui::FontId::new(18.0, egui::FontFamily::Proportional),
    );
    style.text_styles.insert(
        egui::TextStyle::Body,
        egui::FontId::new(13.0, egui::FontFamily::Proportional),
    );
    style.text_styles.insert(
        egui::TextStyle::Button,
        egui::FontId::new(12.0, egui::FontFamily::Proportional),
    );
    style.text_styles.insert(
        egui::TextStyle::Small,
        egui::FontId::new(11.0, egui::FontFamily::Proportional),
    );
    ctx.set_style(style);
    style_state.initialized = true;
}

// 加载态占位 UI。
pub(crate) fn loading_ui_system(mut contexts: EguiContexts) {
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    egui::CentralPanel::default().show(ctx, |ui| {
        ui.vertical_centered(|ui| {
            ui.add_space(ui.available_height() / 2.0 - 40.0);
            ui.heading("正在加载编辑器数据…");
            ui.add_space(16.0);
            ui.spinner();
        });
    });
}

// 顶层 UI 入口，负责拼装顶部栏、左右侧边栏和中央预览区域。
pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    data: Res<EditorData>,
    mut ui_state: ResMut<EditorUiState>,
    preview_state: Res<PreviewState>,
    pick_index: Res<MeshPickIndex<String>>,
    camera_mode: Res<PreviewCameraModeState>,
    mut ground_visibility: ResMut<PreviewGroundVisibility>,
    mut pivot_visibility: ResMut<PreviewPivotVisibility>,
    mut preview_camera_query: Query<
        (&Camera, &GlobalTransform, &mut PreviewCameraController),
        With<PreviewCamera>,
    >,
    mut requests: MessageWriter<CharacterEditorCommand>,
) {
    let ctx = contexts
        .ctx_mut()
        .expect("primary egui context should exist for the character editor");

    let Ok((preview_camera_component, preview_camera_transform, mut preview_camera)) =
        preview_camera_query.single_mut()
    else {
        return;
    };

    egui::TopBottomPanel::top("character_editor_topbar").show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.heading("角色编辑器");
            ui.separator();
            ui.label(format!("角色 {}", data.character_summaries.len()));
            ui.separator();
            ui.small(format!("仓库 {}", data.repo_root.display()));
            if !data.warnings.is_empty() {
                let diagnostic_hover = build_diagnostic_hover_text(&data, &ui_state);
                ui.separator();
                ui.colored_label(
                    egui::Color32::from_rgb(220, 170, 72),
                    format!("诊断 {}", data.warnings.len()),
                )
                .on_hover_text(diagnostic_hover);
            }
            ui.separator();
            ui.small(&ui_state.status);
        });
    });

    egui::SidePanel::left("character_list")
        .default_width(LIST_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            render_character_list_panel(ui, &data, &mut ui_state, &mut requests);
        });

    egui::SidePanel::left("character_details")
        .default_width(DETAIL_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            render_detail_panel(
                ui,
                &data,
                &mut ui_state,
                &preview_state,
                &camera_mode,
                &mut requests,
            );
        });

    egui::CentralPanel::default()
        .frame(egui::Frame::NONE.fill(egui::Color32::TRANSPARENT))
        .show(ctx, |ui| {
            let rect = ui.max_rect();
            preview_camera.viewport_rect = Some(PreviewViewportRect {
                min_x: rect.left(),
                min_y: rect.top(),
                width: rect.width(),
                height: rect.height(),
            });
            preview_camera.block_pointer_input = false;
            let response = ui.allocate_rect(rect, egui::Sense::hover());
            if response.secondary_clicked() {
                ui_state.preview_context_model_path = picked_preview_model_asset(
                    ui.ctx(),
                    preview_camera_component,
                    preview_camera_transform,
                    &pick_index,
                );
            }
            let context_asset_path = ui_state.preview_context_model_path.clone();
            response.context_menu(|ui| {
                let Some(asset_path) = context_asset_path.as_deref() else {
                    ui.close();
                    return;
                };
                ui.label(asset_path);
                ui.separator();
                if ui.button("用 Blockbench 编辑").clicked() {
                    requests.write(CharacterEditorCommand::OpenPreviewModelInBlockbench(
                        asset_path.to_string(),
                    ));
                    ui.close();
                }
                if ui.button("gltf viewer 中打开").clicked() {
                    requests.write(CharacterEditorCommand::OpenPreviewModelInGltfViewer(
                        asset_path.to_string(),
                    ));
                    ui.close();
                }
                if ui.button("打开模型所在目录").clicked() {
                    requests.write(CharacterEditorCommand::OpenPreviewModelDirectory(
                        asset_path.to_string(),
                    ));
                    ui.close();
                }
            });
            let preview_title = selected_character_label(&data, &ui_state);
            let hud_response = render_preview_overlay(
                ui.ctx(),
                rect,
                preview_title.as_str(),
                &preview_state,
                &camera_mode,
                &mut ground_visibility,
                &mut pivot_visibility,
                &mut preview_camera,
                &mut requests,
            );
            if hud_response.toggle_ground {
                ground_visibility.toggle();
            }
            if hud_response.toggle_pivot {
                pivot_visibility.toggle();
            }
        });
}

// 左侧角色列表，只负责筛选、展示和触发角色切换。
fn render_character_list_panel(
    ui: &mut egui::Ui,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    requests: &mut MessageWriter<CharacterEditorCommand>,
) {
    ui.horizontal(|ui| {
        ui.label("搜索");
        ui.add(
            egui::TextEdit::singleline(&mut ui_state.search_text)
                .hint_text("角色名 / ID")
                .desired_width(f32::INFINITY),
        );
    });
    ui.separator();

    let needle = ui_state.search_text.trim().to_lowercase();
    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            for summary in &data.character_summaries {
                if !needle.is_empty()
                    && !summary.display_name.to_lowercase().contains(&needle)
                    && !summary.id.to_lowercase().contains(&needle)
                {
                    continue;
                }

                let selected =
                    ui_state.selected_character_id.as_deref() == Some(summary.id.as_str());
                let label = format!("{}  [{}]", summary.display_name, summary.id);
                let response =
                    selectable_list_row(ui, selected, label.as_str()).on_hover_text(format!(
                        "{}\n\n据点: {}\n角色职责: {}\n行为包: {}",
                        label,
                        non_empty(&summary.settlement_id),
                        non_empty(&summary.role),
                        non_empty(&summary.behavior_profile_id)
                    ));
                if response.clicked() && !selected {
                    requests.write(CharacterEditorCommand::SelectCharacter(summary.id.clone()));
                }
            }
        });
}

fn render_preview_overlay(
    ctx: &egui::Context,
    rect: egui::Rect,
    title: &str,
    preview_state: &PreviewState,
    camera_mode: &PreviewCameraModeState,
    ground_visibility: &mut PreviewGroundVisibility,
    pivot_visibility: &mut PreviewPivotVisibility,
    preview_camera: &mut PreviewCameraController,
    requests: &mut MessageWriter<CharacterEditorCommand>,
) -> game_editor::ModelPreviewHudResponse {
    let response = render_model_preview_hud(
        ctx,
        "character_preview_hud",
        rect,
        ModelPreviewHud {
            title,
            size: preview_state.model_size,
            status: None,
            ground_visible: ground_visibility.visible,
            pivot_visible: pivot_visibility.visible,
        },
        |ui| {
            ui.separator();
            ui.label(
                egui::RichText::new(camera_mode.mode.badge_text())
                    .size(12.0)
                    .color(egui::Color32::from_rgb(164, 170, 184)),
            );
            let camera_mode_response = ui
                .small_button(camera_mode.mode.toggle_button_label())
                .on_hover_text(camera_mode.mode.interaction_hint());
            if camera_mode_response.clicked() {
                let next_mode = match camera_mode.mode {
                    PreviewCameraMode::Free => PreviewCameraMode::GameFixed,
                    PreviewCameraMode::GameFixed => PreviewCameraMode::Free,
                };
                requests.write(CharacterEditorCommand::SetCameraMode(next_mode));
            }
        },
    );

    if let Some(notice) = preview_state.preview_notice.as_deref() {
        egui::Area::new("character_preview_notice".into())
            .order(egui::Order::Foreground)
            .anchor(egui::Align2::CENTER_CENTER, egui::Vec2::ZERO)
            .fixed_pos(rect.center())
            .show(ctx, |ui| {
                egui::Frame::NONE
                    .fill(egui::Color32::from_rgba_unmultiplied(18, 21, 28, 212))
                    .corner_radius(8.0)
                    .inner_margin(egui::Margin::symmetric(18, 14))
                    .show(ui, |ui| {
                        ui.set_max_width(420.0);
                        ui.label(
                            egui::RichText::new(notice)
                                .size(16.0)
                                .color(egui::Color32::from_rgb(232, 236, 244)),
                        );
                    });
            });
    }
    preview_camera.block_pointer_input = response.hovered;
    response
}

fn selected_character_label(data: &EditorData, ui_state: &EditorUiState) -> String {
    let Some(selected_id) = ui_state.selected_character_id.as_deref() else {
        return "未选择角色".to_string();
    };
    data.character_summaries
        .iter()
        .find(|summary| summary.id == selected_id)
        .map(|summary| summary.display_name.clone())
        .unwrap_or_else(|| selected_id.to_string())
}

fn picked_preview_model_asset(
    ctx: &egui::Context,
    camera: &Camera,
    camera_transform: &GlobalTransform,
    pick_index: &MeshPickIndex<String>,
) -> Option<String> {
    let cursor = ctx.pointer_latest_pos()?;
    let cursor = Vec2::new(cursor.x, cursor.y);
    let ray = camera.viewport_to_world(camera_transform, cursor).ok()?;
    pick_index.query_nearest(ray).map(|hit| hit.data)
}
