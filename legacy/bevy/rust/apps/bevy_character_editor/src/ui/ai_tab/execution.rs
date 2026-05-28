use crate::ui::common::{
    key_value_with_tooltip, label_with_tooltip, negative_text, section_header, status_badge,
};
use bevy_egui::egui;
use game_data::CharacterAiPreview;

use super::helpers::{ai_metric_tooltip, blocked_actions, blocker_label, recommended_action};

pub(super) fn render_execution_sections(ui: &mut egui::Ui, preview: &CharacterAiPreview) {
    render_action_results(ui, preview);
}

fn render_action_results(ui: &mut egui::Ui, preview: &CharacterAiPreview) {
    section_header(
        ui,
        "动作结果",
        "先看可执行动作，再看被阻断动作，帮助快速定位 AI 现在能做什么和做不了什么。",
    );

    let available_actions = preview
        .available_actions
        .iter()
        .filter(|action| action.available)
        .collect::<Vec<_>>();
    let mut blocked_actions = blocked_actions(preview);
    blocked_actions.sort_by(|left, right| left.display_name.cmp(&right.display_name));

    ui.label(if let Some(action) = recommended_action(preview) {
        format!("当前最可能执行 {}。", action.display_name)
    } else {
        "当前没有可执行动作，需查看阻断原因。".to_string()
    });

    ui.add_space(4.0);
    label_with_tooltip(
        ui,
        "可执行动作",
        "已经通过当前 precondition、锚点解析和 reservation 检查的动作。",
    );
    if available_actions.is_empty() {
        ui.small("当前没有可执行动作。");
    } else {
        for action in available_actions {
            egui::Frame::group(ui.style()).show(ui, |ui| {
                ui.horizontal(|ui| {
                    status_badge(
                        ui,
                        "可执行",
                        egui::Color32::from_rgb(44, 76, 56),
                        egui::Color32::from_rgb(236, 240, 244),
                    );
                    ui.label(format!("{} [{}]", action.display_name, action.action_id));
                });
                if !action.blocked_by.is_empty() {
                    ui.small(format!("额外诊断: {}", action.blocked_by.join(", ")));
                }
            });
            ui.add_space(4.0);
        }
    }

    ui.add_space(4.0);
    label_with_tooltip(
        ui,
        "已阻断动作",
        "这些动作当前不可执行。展开后可以看到目标锚点、reservation 和 blocker 明细。",
    );
    if blocked_actions.is_empty() {
        ui.small("当前没有被阻断的动作。");
        return;
    }

    for action in blocked_actions {
        egui::CollapsingHeader::new(format!(
            "{} [{}] blocked · {} 个 blocker",
            action.display_name,
            action.action_id,
            action.blockers.len()
        ))
        .default_open(false)
        .show(ui, |ui| {
            key_value_with_tooltip(
                ui,
                "target_anchor",
                action.resolved_target_anchor.as_deref().unwrap_or("-"),
                ai_metric_tooltip("target_anchor"),
            );
            key_value_with_tooltip(
                ui,
                "reservation_target",
                action.reservation_target.as_deref().unwrap_or("-"),
                ai_metric_tooltip("reservation_target"),
            );
            for blocker in &action.blockers {
                ui.label(negative_text(format!(
                    "{}: {} ({})",
                    blocker_label(blocker.kind),
                    blocker.message,
                    blocker.subject
                )));
            }
        });
    }
}
