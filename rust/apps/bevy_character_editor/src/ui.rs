//! 顶层 UI 布局层。
//! 负责整体面板编排、左侧角色列表、中央预览区和子模块路由，不承载具体业务解释逻辑。

mod ai_tab;
mod appearance_tab;
mod common;
mod detail_panel;

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_editor::{install_game_ui_fonts, PreviewCameraController, PreviewViewportRect};

use crate::preview::{ensure_selected_character, select_character, PreviewCamera};
use crate::state::{non_empty, EditorData, EditorEguiFontState, EditorUiState, PreviewState};
use common::build_diagnostic_hover_text;
use detail_panel::render_detail_panel;

const LIST_PANEL_WIDTH: f32 = 250.0;
const DETAIL_PANEL_WIDTH: f32 = 430.0;

// 初始化编辑器统一字体和基础控件样式。
pub(crate) fn configure_egui_fonts_system(
    mut contexts: EguiContexts,
    mut font_state: ResMut<EditorEguiFontState>,
) {
    if font_state.initialized {
        return;
    }
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    install_game_ui_fonts(ctx);

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
    font_state.initialized = true;
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
    mut preview_state: ResMut<PreviewState>,
    mut preview_camera: Single<&mut PreviewCameraController, With<PreviewCamera>>,
) {
    let ctx = contexts
        .ctx_mut()
        .expect("primary egui context should exist for the character editor");

    ensure_selected_character(
        &data,
        &mut ui_state,
        &mut preview_state,
        &mut preview_camera,
    );

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
            render_character_list_panel(
                ui,
                &data,
                &mut ui_state,
                &mut preview_state,
                &mut preview_camera,
            );
        });

    egui::SidePanel::left("character_details")
        .default_width(DETAIL_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            render_detail_panel(
                ui,
                &data,
                &mut ui_state,
                &mut preview_state,
                &mut preview_camera,
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
            ui.allocate_rect(rect, egui::Sense::hover());
            let info_rect = egui::Rect::from_min_size(
                rect.left_top() + egui::vec2(10.0, 10.0),
                egui::vec2(380.0, 56.0),
            );
            ui.painter().rect_filled(
                info_rect,
                6.0,
                egui::Color32::from_rgba_unmultiplied(18, 21, 28, 176),
            );
            ui.painter().text(
                rect.left_top() + egui::vec2(14.0, 12.0),
                egui::Align2::LEFT_TOP,
                "角色外观预览",
                egui::FontId::new(14.0, egui::FontFamily::Proportional),
                egui::Color32::from_rgb(228, 231, 238),
            );
            ui.painter().text(
                rect.left_top() + egui::vec2(14.0, 32.0),
                egui::Align2::LEFT_TOP,
                "左键拖拽旋转，滚轮缩放，右侧页签中可切换试装槽位。",
                egui::FontId::new(11.0, egui::FontFamily::Proportional),
                egui::Color32::from_rgb(164, 170, 184),
            );
            if let Some(notice) = preview_state.preview_notice.as_deref() {
                ui.painter().text(
                    rect.left_top() + egui::vec2(14.0, 52.0),
                    egui::Align2::LEFT_TOP,
                    notice,
                    egui::FontId::new(11.0, egui::FontFamily::Proportional),
                    egui::Color32::from_rgb(210, 184, 120),
                );
            }
        });
}

// 左侧角色列表，只负责筛选、展示和触发角色切换。
fn render_character_list_panel(
    ui: &mut egui::Ui,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
    preview_camera: &mut PreviewCameraController,
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
                let response = ui.add_sized(
                    [ui.available_width(), 0.0],
                    egui::Button::new(label.as_str())
                        .selected(selected)
                        .truncate(),
                );
                let response = response.on_hover_text(format!(
                    "{}\n\n据点: {}\n角色职责: {}\n行为包: {}",
                    label,
                    non_empty(&summary.settlement_id),
                    non_empty(&summary.role),
                    non_empty(&summary.behavior_profile_id)
                ));
                if response.clicked() && !selected {
                    select_character(
                        summary.id.clone(),
                        data,
                        ui_state,
                        preview_state,
                        preview_camera,
                    );
                }
            }
        });
}
