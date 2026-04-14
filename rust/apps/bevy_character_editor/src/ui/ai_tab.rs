//! AI 预览页。
//! 负责展示 AI 输入上下文、据点关联、推导过程和行动阻断原因，不写回任何数据。

use bevy_egui::egui;
use game_data::{
    AiBlackboardEntryPreview, AiConditionTracePreview, CharacterAiPreview, CharacterDefinition,
    ScheduleDay,
};
use game_editor::PreviewCameraController;

use crate::preview::{refresh_preview_state, settlement_for_character};
use crate::state::{
    non_empty, npc_role_label, schedule_day_label, EditorData, EditorUiState, PreviewState,
};

use super::common::{key_value, negative_text, neutral_text, positive_text, warning_text};

// AI 页主入口，组织上下文输入、推导诊断和执行诊断三类视图。
pub(crate) fn render_ai_tab(
    ui: &mut egui::Ui,
    character: &CharacterDefinition,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
    preview_camera: &mut PreviewCameraController,
) {
    let settlement = settlement_for_character(character, &data.settlements);
    let mut changed = false;
    ui.collapsing("上下文", |ui| {
        ui.horizontal(|ui| {
            ui.label("星期");
            egui::ComboBox::from_id_salt("preview_day")
                .selected_text(schedule_day_label(ui_state.preview_context.day))
                .show_ui(ui, |ui| {
                    for day in [
                        ScheduleDay::Monday,
                        ScheduleDay::Tuesday,
                        ScheduleDay::Wednesday,
                        ScheduleDay::Thursday,
                        ScheduleDay::Friday,
                        ScheduleDay::Saturday,
                        ScheduleDay::Sunday,
                    ] {
                        changed |= ui
                            .selectable_value(
                                &mut ui_state.preview_context.day,
                                day,
                                schedule_day_label(day),
                            )
                            .changed();
                    }
                });
            changed |= ui
                .add(
                    egui::Slider::new(&mut ui_state.preview_context.minute_of_day, 0..=1439)
                        .text("分钟"),
                )
                .changed();
        });
        ui.horizontal(|ui| {
            changed |= ui
                .add(
                    egui::Slider::new(&mut ui_state.preview_context.hunger, 0.0..=100.0)
                        .text("饥饿"),
                )
                .changed();
            changed |= ui
                .add(
                    egui::Slider::new(&mut ui_state.preview_context.energy, 0.0..=100.0)
                        .text("精力"),
                )
                .changed();
            changed |= ui
                .add(
                    egui::Slider::new(&mut ui_state.preview_context.morale, 0.0..=100.0)
                        .text("士气"),
                )
                .changed();
        });
        ui.horizontal(|ui| {
            changed |= ui
                .checkbox(&mut ui_state.preview_context.world_alert_active, "世界警报")
                .changed();
            changed |= ui
                .add(
                    egui::DragValue::new(&mut ui_state.preview_context.active_guards)
                        .prefix("值班守卫 "),
                )
                .changed();
            changed |= ui
                .add(
                    egui::DragValue::new(&mut ui_state.preview_context.min_guard_on_duty)
                        .prefix("最低守卫 "),
                )
                .changed();
        });
        ui.horizontal(|ui| {
            ui.label("当前锚点");
            let selected_anchor = ui_state
                .preview_context
                .current_anchor
                .clone()
                .unwrap_or_default();
            egui::ComboBox::from_id_salt("preview_anchor_combo")
                .selected_text(non_empty(&selected_anchor))
                .show_ui(ui, |ui| {
                    if let Some(settlement) = settlement {
                        for anchor in &settlement.anchors {
                            changed |= ui
                                .selectable_value(
                                    ui_state
                                        .preview_context
                                        .current_anchor
                                        .get_or_insert_with(String::new),
                                    anchor.id.clone(),
                                    anchor.id.as_str(),
                                )
                                .changed();
                        }
                    }
                });
            changed |= ui
                .add(
                    egui::TextEdit::singleline(
                        ui_state
                            .preview_context
                            .current_anchor
                            .get_or_insert_with(String::new),
                    )
                    .hint_text("自定义锚点"),
                )
                .changed();
        });
        ui.horizontal_wrapped(|ui| {
            changed |= ui
                .checkbox(
                    &mut ui_state.preview_context.availability.guard_post_available,
                    "guard_post",
                )
                .changed();
            changed |= ui
                .checkbox(
                    &mut ui_state.preview_context.availability.meal_object_available,
                    "meal_object",
                )
                .changed();
            changed |= ui
                .checkbox(
                    &mut ui_state
                        .preview_context
                        .availability
                        .leisure_object_available,
                    "leisure_object",
                )
                .changed();
            changed |= ui
                .checkbox(
                    &mut ui_state
                        .preview_context
                        .availability
                        .medical_station_available,
                    "medical_station",
                )
                .changed();
            changed |= ui
                .checkbox(
                    &mut ui_state.preview_context.availability.patrol_route_available,
                    "patrol_route",
                )
                .changed();
            changed |= ui
                .checkbox(
                    &mut ui_state.preview_context.availability.bed_available,
                    "bed",
                )
                .changed();
        });
    });
    if changed {
        refresh_preview_state(data, ui_state, preview_state, preview_camera, false);
    }

    ui.separator();
    if let Some(error) = &preview_state.ai_error {
        ui.colored_label(egui::Color32::from_rgb(240, 110, 110), error);
        return;
    }
    let Some(preview) = preview_state.ai_preview.as_ref() else {
        ui.label("当前没有 AI 预览结果。");
        return;
    };
    ui.collapsing("据点关联", |ui| {
        key_value(ui, "据点", &preview.life.settlement_id);
        key_value(ui, "角色职责", npc_role_label(preview.life.role));
        key_value(ui, "行为包", &preview.behavior.id);
        key_value(ui, "家锚点", &preview.life.home_anchor);
        key_value(ui, "执勤路线", non_empty(&preview.life.duty_route_id));
        render_resolved_anchor_row(
            ui,
            &preview.diagnostics.blackboard_entries,
            "anchor.duty",
            "Duty 锚点",
        );
        render_resolved_anchor_row(
            ui,
            &preview.diagnostics.blackboard_entries,
            "anchor.canteen",
            "Canteen 锚点",
        );
        render_resolved_anchor_row(
            ui,
            &preview.diagnostics.blackboard_entries,
            "anchor.leisure",
            "Leisure 锚点",
        );
        render_resolved_anchor_row(
            ui,
            &preview.diagnostics.blackboard_entries,
            "anchor.alarm",
            "Alarm 锚点",
        );
        ui.separator();
        ui.label("访问规则");
        for rule in &preview.smart_object_access.rules {
            let tags = if rule.preferred_tags.is_empty() {
                "-".to_string()
            } else {
                rule.preferred_tags.join(", ")
            };
            ui.small(format!(
                "{:?} | tags={} | fallback_any={}",
                rule.kind, tags, rule.fallback_to_any
            ));
        }
    });
    ui.collapsing("输入态", |ui| {
        key_value(ui, "当前日程块", preview_schedule_entry_label(preview));
        key_value(ui, "行为包", &preview.behavior.id);
        key_value(
            ui,
            "默认目标",
            preview.behavior.default_goal_id.as_deref().unwrap_or("-"),
        );
        key_value(
            ui,
            "警报目标",
            preview.behavior.alert_goal_id.as_deref().unwrap_or("-"),
        );
        key_value(ui, "家锚点", &preview.life.home_anchor);
        key_value(ui, "执勤路线", non_empty(&preview.life.duty_route_id));
        ui.separator();
        render_blackboard_table(ui, &preview.diagnostics.blackboard_entries);
    });
    ui.collapsing("推导态", |ui| {
        ui.label("Goal 摘要");
        for goal in &preview.goal_scores {
            let tone = if goal.score > 0 {
                positive_text(format!(
                    "{} [{}] -> {} ({})",
                    goal.display_name,
                    goal.goal_id,
                    goal.score,
                    goal.matched_rule_ids.join(", ")
                ))
            } else {
                neutral_text(format!(
                    "{} [{}] -> {}",
                    goal.display_name, goal.goal_id, goal.score
                ))
            };
            ui.label(tone);
        }
        ui.separator();
        ui.label("Fact 评估");
        for fact in &preview.diagnostics.fact_evaluations {
            egui::CollapsingHeader::new(format!(
                "{} [{}] {}",
                fact.display_name,
                fact.fact_id,
                if fact.matched { "matched" } else { "unmatched" }
            ))
            .show(ui, |ui| {
                ui.label(match fact.matched {
                    true => positive_text("命中".to_string()),
                    false => negative_text("未命中".to_string()),
                });
                render_condition_trace(ui, &fact.trace, 0);
            });
        }
        ui.separator();
        ui.label("Goal 规则详情");
        for goal in &preview.diagnostics.goal_evaluations {
            egui::CollapsingHeader::new(format!(
                "{} [{}] -> {}",
                goal.display_name, goal.goal_id, goal.final_score
            ))
            .show(ui, |ui| {
                for rule in &goal.rules {
                    egui::CollapsingHeader::new(format!(
                        "{} [{}] {} contributed {}",
                        rule.display_name,
                        rule.rule_id,
                        if rule.matched { "matched" } else { "skipped" },
                        rule.contributed_score
                    ))
                    .show(ui, |ui| {
                        key_value(ui, "score_delta", &rule.score_delta.to_string());
                        key_value(
                            ui,
                            "multiplier_key",
                            rule.multiplier_key.as_deref().unwrap_or("-"),
                        );
                        key_value(
                            ui,
                            "multiplier_value",
                            &rule
                                .multiplier_value
                                .map(|value| format!("{value:.2}"))
                                .unwrap_or_else(|| "-".to_string()),
                        );
                        key_value(ui, "contributed_score", &rule.contributed_score.to_string());
                        if let Some(trace) = &rule.trace {
                            ui.separator();
                            render_condition_trace(ui, trace, 0);
                        } else {
                            ui.small("无条件规则，始终参与打分。");
                        }
                    });
                }
            });
        }
    });
    ui.collapsing("执行态", |ui| {
        for action in &preview.diagnostics.action_evaluations {
            egui::CollapsingHeader::new(format!(
                "{} [{}] {}",
                action.display_name,
                action.action_id,
                if action.available {
                    "available"
                } else {
                    "blocked"
                }
            ))
            .show(ui, |ui| {
                ui.label(if action.available {
                    positive_text("可执行".to_string())
                } else {
                    negative_text("已阻断".to_string())
                });
                key_value(
                    ui,
                    "target_anchor",
                    action.resolved_target_anchor.as_deref().unwrap_or("-"),
                );
                key_value(
                    ui,
                    "reservation_target",
                    action.reservation_target.as_deref().unwrap_or("-"),
                );
                if action.blockers.is_empty() {
                    ui.small("无 blocker。");
                } else {
                    for blocker in &action.blockers {
                        ui.label(negative_text(format!(
                            "{:?}: {} ({})",
                            blocker.kind, blocker.message, blocker.subject
                        )));
                    }
                }
            });
        }
    });
}

// 递归渲染条件 trace，帮助查看事实/目标命中的原因链。
fn render_condition_trace(ui: &mut egui::Ui, trace: &AiConditionTracePreview, depth: usize) {
    let indent = "  ".repeat(depth);
    let status = if trace.passed {
        positive_text(format!("{indent}{}: {}", trace.label, trace.detail))
    } else {
        negative_text(format!("{indent}{}: {}", trace.label, trace.detail))
    };
    ui.label(status);
    for child in &trace.children {
        render_condition_trace(ui, child, depth + 1);
    }
}

// 按 blackboard 分组渲染输入态表格。
fn render_blackboard_table(ui: &mut egui::Ui, entries: &[AiBlackboardEntryPreview]) {
    for group in [
        "need",
        "personality",
        "schedule",
        "world",
        "settlement",
        "availability",
        "reservation",
        "anchor",
    ] {
        let group_entries = entries
            .iter()
            .filter(|entry| entry.key.starts_with(&format!("{group}.")))
            .collect::<Vec<_>>();
        if group_entries.is_empty() {
            continue;
        }
        ui.separator();
        ui.small(group);
        egui::Grid::new(format!("blackboard_grid_{group}"))
            .num_columns(3)
            .striped(true)
            .show(ui, |ui| {
                ui.small("key");
                ui.small("value");
                ui.small("source");
                ui.end_row();
                for entry in group_entries {
                    ui.small(&entry.key);
                    ui.small(&entry.value_text);
                    ui.small(&entry.source);
                    ui.end_row();
                }
            });
    }
}

// 提取当前激活日程块名称，用于输入态摘要。
fn preview_schedule_entry_label(preview: &CharacterAiPreview) -> &str {
    preview
        .diagnostics
        .active_schedule_entry
        .as_ref()
        .map(|entry| entry.label.as_str())
        .unwrap_or("-")
}

// 渲染据点关联中的解析锚点行，并突出未解析状态。
fn render_resolved_anchor_row(
    ui: &mut egui::Ui,
    entries: &[AiBlackboardEntryPreview],
    key: &str,
    label: &str,
) {
    let value = entries
        .iter()
        .find(|entry| entry.key == key)
        .map(|entry| entry.value_text.as_str())
        .unwrap_or("-");
    ui.horizontal(|ui| {
        ui.small(format!("{label}:"));
        if value == "-" {
            ui.label(warning_text("未解析".to_string()));
        } else {
            ui.label(value);
        }
    });
}
