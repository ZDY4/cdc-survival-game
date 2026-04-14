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
