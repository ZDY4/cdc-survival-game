use bevy_egui::egui;
use game_data::CharacterAiPreview;

use crate::state::{non_empty, npc_role_label, EditorData, EditorUiState};
use crate::ui::common::{key_value_with_tooltip, section_header, status_badge, summary_card};

use super::helpers::{
    ai_relation_tooltip, best_goal, blocker_summary, format_minute, preview_schedule_entry_label,
    recommended_action, resolve_schedule_display_name,
};

pub(super) fn render_context_sections(
    ui: &mut egui::Ui,
    data: &EditorData,
    preview: &CharacterAiPreview,
    ui_state: &EditorUiState,
) {
    render_conclusion_summary(ui, preview, ui_state);
    ui.separator();
    render_effective_profiles(ui, data, preview);
    ui.separator();
    render_scene_snapshot(ui, preview, ui_state);
}

fn render_conclusion_summary(
    ui: &mut egui::Ui,
    preview: &CharacterAiPreview,
    ui_state: &EditorUiState,
) {
    section_header(
        ui,
        "结论摘要",
        "先看 AI 当前最可能做什么、能不能做，以及最关键的阻断原因。",
    );

    let best_goal = best_goal(preview);
    let recommended_action = recommended_action(preview);
    let blocked_actions = super::helpers::blocked_actions(preview);
    let blocker_summary = blocker_summary(preview);
    let blocker_detail = if blocker_summary.len() > 1 {
        blocker_summary[1..].join(" / ")
    } else {
        String::new()
    };

    ui.horizontal_wrapped(|ui| {
        summary_card(
            ui,
            "当前日程块",
            preview_schedule_entry_label(preview),
            format!(
                "{} {}",
                crate::state::schedule_day_label(ui_state.preview_context.day),
                format_minute(ui_state.preview_context.minute_of_day)
            )
            .as_str(),
            "当前时间命中的日程块，以及本次预览所在的时间点。",
        );
        summary_card(
            ui,
            "当前主目标",
            best_goal
                .map(|goal| goal.display_name.as_str())
                .unwrap_or("无目标"),
            best_goal
                .map(|goal| format!("score {}", goal.score))
                .unwrap_or_else(|| "没有 goal 数据".to_string())
                .as_str(),
            "当前得分最高的 goal，可视为 AI 此刻最倾向追求的目标。",
        );
        summary_card(
            ui,
            "当前推荐动作",
            recommended_action
                .map(|action| action.display_name.as_str())
                .unwrap_or("当前无可执行动作"),
            recommended_action
                .map(|action| action.action_id.as_str())
                .unwrap_or("需查看阻断原因"),
            "当前最可能执行的 action。若为空，说明现阶段所有动作都被阻断。",
        );
        summary_card(
            ui,
            "阻断动作数",
            blocked_actions.len().to_string().as_str(),
            format!("总动作 {}", preview.diagnostics.action_evaluations.len()).as_str(),
            "当前被阻断、不可执行的动作数量。",
        );
        summary_card(
            ui,
            "关键阻断原因",
            if blocker_summary.is_empty() {
                "无阻断"
            } else {
                blocker_summary[0].as_str()
            },
            blocker_detail.as_str(),
            "从所有阻断动作中汇总出的关键 blocker 类型，帮助快速定位为什么没有动作可执行。",
        );
    });

    ui.add_space(4.0);
    if let Some(goal) = best_goal {
        ui.label(format!(
            "当前 AI 更倾向于 {}，因为它在当前输入下得分最高。",
            goal.display_name
        ));
    } else {
        ui.label("当前 AI 没有可用的目标评分结果。");
    }
    if let Some(action) = recommended_action {
        ui.label(format!("当前最可能执行 {}。", action.display_name));
    } else {
        ui.label("当前没有可执行动作，需查看阻断原因。");
    }
}

fn render_effective_profiles(ui: &mut egui::Ui, data: &EditorData, preview: &CharacterAiPreview) {
    section_header(
        ui,
        "生效配置",
        "当前这次 AI 预览真正使用到的行为包、日程、人格、需求和 smart object 访问配置。",
    );
    ui.horizontal_wrapped(|ui| {
        summary_card(
            ui,
            "行为包",
            preview.behavior.display_name.as_str(),
            format!("[{}]", preview.behavior.id).as_str(),
            "当前生效的 AI 行为包。",
        );
        summary_card(
            ui,
            "日程模板",
            resolve_schedule_display_name(data, preview).as_str(),
            format!("[{}]", preview.schedule.profile_id).as_str(),
            "当前生效的日程模板。",
        );
        summary_card(
            ui,
            "性格模板",
            preview.personality.display_name.as_str(),
            format!("[{}]", preview.personality.id).as_str(),
            "当前生效的人格模板。",
        );
        summary_card(
            ui,
            "需求模板",
            preview.need_profile.display_name.as_str(),
            format!("[{}]", preview.need_profile.id).as_str(),
            "当前生效的需求模板。",
        );
        summary_card(
            ui,
            "访问配置",
            preview.smart_object_access.display_name.as_str(),
            format!(
                "[{}] / 规则 {} 条",
                preview.smart_object_access.id,
                preview.smart_object_access.rules.len()
            )
            .as_str(),
            "当前生效的 smart object 访问配置。",
        );
    });
}

fn render_scene_snapshot(
    ui: &mut egui::Ui,
    preview: &CharacterAiPreview,
    ui_state: &EditorUiState,
) {
    section_header(
        ui,
        "当前场景快照",
        "把这次预览的时间、警报、当前位置和关键 life 绑定收敛成一眼能看的摘要。",
    );
    ui.horizontal_wrapped(|ui| {
        status_badge(
            ui,
            if ui_state.preview_context.world_alert_active {
                "警报开"
            } else {
                "警报关"
            },
            if ui_state.preview_context.world_alert_active {
                egui::Color32::from_rgb(110, 38, 38)
            } else {
                egui::Color32::from_rgb(44, 76, 56)
            },
            egui::Color32::from_rgb(236, 240, 244),
        );
        status_badge(
            ui,
            crate::state::schedule_day_label(ui_state.preview_context.day),
            egui::Color32::from_rgb(54, 66, 92),
            egui::Color32::from_rgb(232, 236, 244),
        );
        status_badge(
            ui,
            format_minute(ui_state.preview_context.minute_of_day).as_str(),
            egui::Color32::from_rgb(54, 66, 92),
            egui::Color32::from_rgb(232, 236, 244),
        );
    });
    ui.label(format!(
        "{} {} / {} / {} / {}",
        crate::state::schedule_day_label(ui_state.preview_context.day),
        format_minute(ui_state.preview_context.minute_of_day),
        preview_schedule_entry_label(preview),
        non_empty(
            ui_state
                .preview_context
                .current_anchor
                .as_deref()
                .unwrap_or_default()
        ),
        if ui_state.preview_context.world_alert_active {
            "警报开"
        } else {
            "警报关"
        }
    ));
    key_value_with_tooltip(
        ui,
        "据点",
        &preview.life.settlement_id,
        ai_relation_tooltip("据点"),
    );
    key_value_with_tooltip(
        ui,
        "角色职责",
        npc_role_label(preview.life.role),
        ai_relation_tooltip("角色职责"),
    );
    key_value_with_tooltip(
        ui,
        "家锚点",
        &preview.life.home_anchor,
        ai_relation_tooltip("家锚点"),
    );
    key_value_with_tooltip(
        ui,
        "执勤路线",
        non_empty(&preview.life.duty_route_id),
        ai_relation_tooltip("执勤路线"),
    );
}
