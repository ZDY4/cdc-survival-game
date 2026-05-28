//! UI 通用辅助。
//! 放置多个页签共享的小型组件、颜色样式和诊断文本拼装逻辑。

use bevy_egui::egui;

use crate::preview::selected_character;
use crate::state::{CharacterTab, EditorData, EditorUiState};

// 渲染页签按钮并维护当前选中页签。
pub(crate) fn tab_button(
    ui: &mut egui::Ui,
    ui_state: &mut EditorUiState,
    tab: CharacterTab,
    label: &str,
) {
    if ui
        .selectable_label(ui_state.selected_tab == tab, label)
        .clicked()
    {
        ui_state.selected_tab = tab;
    }
}

// 统一的键值对展示样式。
pub(crate) fn key_value(ui: &mut egui::Ui, label: &str, value: &str) {
    ui.horizontal(|ui| {
        ui.small(format!("{label}:"));
        ui.label(value);
    });
}

// 带 hover 说明的键值对展示样式，仅对左侧标签响应 tooltip。
pub(crate) fn key_value_with_tooltip(ui: &mut egui::Ui, label: &str, value: &str, tooltip: &str) {
    ui.horizontal(|ui| {
        ui.small(format!("{label}:")).on_hover_text(tooltip);
        ui.label(value);
    });
}

// 小标签 tooltip 辅助，仅让标签本身承担 hover 说明。
pub(crate) fn small_label_with_tooltip(
    ui: &mut egui::Ui,
    label: &str,
    tooltip: &str,
) -> egui::Response {
    ui.small(label).on_hover_text(tooltip)
}

// 标准标签 tooltip 辅助，适合 section 标题等非键值行。
pub(crate) fn label_with_tooltip(ui: &mut egui::Ui, label: &str, tooltip: &str) -> egui::Response {
    ui.label(label).on_hover_text(tooltip)
}

// 统一的分组标题样式，支持在标题上挂说明。
pub(crate) fn section_header(ui: &mut egui::Ui, title: &str, tooltip: &str) {
    ui.horizontal(|ui| {
        ui.heading(title).on_hover_text(tooltip);
    });
}

// 轻量状态徽章，用于摘要和列表中的状态提示。
pub(crate) fn status_badge(
    ui: &mut egui::Ui,
    label: &str,
    fill: egui::Color32,
    text_color: egui::Color32,
) -> egui::InnerResponse<egui::Response> {
    egui::Frame::new()
        .fill(fill)
        .corner_radius(999.0)
        .inner_margin(egui::Margin::symmetric(8, 3))
        .show(ui, |ui| {
            ui.label(egui::RichText::new(label).size(11.0).color(text_color))
        })
}

// 小型摘要卡片，用于在结果面板顶部展示关键信息。
pub(crate) fn summary_card(
    ui: &mut egui::Ui,
    title: &str,
    value: &str,
    detail: &str,
    tooltip: &str,
) {
    egui::Frame::group(ui.style()).show(ui, |ui| {
        ui.set_min_width(138.0);
        ui.vertical(|ui| {
            ui.small(title).on_hover_text(tooltip);
            ui.add_space(2.0);
            ui.label(egui::RichText::new(value).strong().size(15.0));
            if !detail.trim().is_empty() {
                ui.small(detail);
            }
        });
    });
}

// 成功/命中态文字颜色。
pub(crate) fn positive_text(text: String) -> egui::RichText {
    egui::RichText::new(text).color(egui::Color32::from_rgb(116, 196, 132))
}

// 失败/阻断态文字颜色。
pub(crate) fn negative_text(text: String) -> egui::RichText {
    egui::RichText::new(text).color(egui::Color32::from_rgb(232, 110, 110))
}

// 警示态文字颜色。
pub(crate) fn warning_text(text: String) -> egui::RichText {
    egui::RichText::new(text).color(egui::Color32::from_rgb(220, 178, 88))
}

// 中性态文字颜色。
pub(crate) fn neutral_text(text: String) -> egui::RichText {
    egui::RichText::new(text).color(egui::Color32::from_rgb(196, 201, 212))
}

// 组合顶部诊断 hover 文本，并追加当前角色相关的 AI 问题。
pub(crate) fn build_diagnostic_hover_text(data: &EditorData, ui_state: &EditorUiState) -> String {
    let mut lines = data.warnings.clone();
    if let Some(character_id) = ui_state.selected_character_id.as_deref() {
        let relevant = data
            .ai_issues
            .iter()
            .filter(|issue| {
                issue.character_id.as_deref() == Some(character_id)
                    || selected_character(data, ui_state)
                        .and_then(|character| character.life.as_ref())
                        .is_some_and(|life| {
                            issue.settlement_id.as_deref() == Some(life.settlement_id.as_str())
                        })
            })
            .map(|issue| format!("{} | {} | {}", issue.severity, issue.code, issue.message))
            .collect::<Vec<_>>();
        if !relevant.is_empty() {
            lines.push(String::new());
            lines.push(format!("当前角色相关 AI 诊断 [{}]", character_id));
            lines.extend(relevant);
        }
    }
    lines.join("\n")
}
