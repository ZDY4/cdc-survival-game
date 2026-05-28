use crate::ui::common::{
    key_value_with_tooltip, label_with_tooltip, negative_text, positive_text, section_header,
    small_label_with_tooltip, summary_card,
};
use bevy_egui::egui;
use game_data::{
    AiBlackboardEntryPreview, AiConditionTracePreview, AiFactEvaluationPreview, CharacterAiPreview,
};

use super::helpers::{
    ai_metric_tooltip, blackboard_group_tooltip, blackboard_header_tooltip, blackboard_key_tooltip,
    blocker_label, goal_label, score_badge_fill,
};

pub(super) fn render_derivation_sections(ui: &mut egui::Ui, preview: &CharacterAiPreview) {
    render_goal_ranking(ui, preview);
    ui.separator();
    render_fact_results(ui, preview);
    ui.separator();
    render_advanced_diagnostics(ui, preview);
}

fn render_goal_ranking(ui: &mut egui::Ui, preview: &CharacterAiPreview) {
    section_header(
        ui,
        "目标排序",
        "按最终分数从高到低展示当前 goal 排名，帮助快速判断 AI 最倾向做什么。",
    );

    let mut goals = preview.goal_scores.iter().collect::<Vec<_>>();
    goals.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| left.display_name.cmp(&right.display_name))
    });

    if goals.is_empty() {
        ui.small("当前没有 goal 排序结果。");
        return;
    }

    for (index, goal) in goals.into_iter().enumerate() {
        egui::Frame::group(ui.style()).show(ui, |ui| {
            ui.horizontal(|ui| {
                if index == 0 {
                    crate::ui::common::status_badge(
                        ui,
                        "当前最优目标",
                        egui::Color32::from_rgb(82, 63, 24),
                        egui::Color32::from_rgb(245, 224, 163),
                    );
                }
                ui.label(goal_label(goal));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    crate::ui::common::status_badge(
                        ui,
                        format!("score {}", goal.score).as_str(),
                        score_badge_fill(goal.score),
                        egui::Color32::from_rgb(238, 241, 245),
                    );
                });
            });
            ui.small(format!("命中规则 {} 条", goal.matched_rule_ids.len()));
            if index == 0 {
                ui.small(format!(
                    "当前 AI 更倾向于 {}，因为它在当前输入下得分最高。",
                    goal.display_name
                ));
            }
        });
        ui.add_space(4.0);
    }
}

fn render_fact_results(ui: &mut egui::Ui, preview: &CharacterAiPreview) {
    section_header(
        ui,
        "事实命中",
        "先看命中数量，再看每条 fact 的条件链，方便理解为什么某些条件成立或失败。",
    );

    let mut matched = preview
        .diagnostics
        .fact_evaluations
        .iter()
        .filter(|fact| fact.matched)
        .collect::<Vec<_>>();
    let mut unmatched = preview
        .diagnostics
        .fact_evaluations
        .iter()
        .filter(|fact| !fact.matched)
        .collect::<Vec<_>>();

    matched.sort_by(|left, right| left.display_name.cmp(&right.display_name));
    unmatched.sort_by(|left, right| left.display_name.cmp(&right.display_name));

    ui.horizontal_wrapped(|ui| {
        summary_card(
            ui,
            "命中 fact",
            matched.len().to_string().as_str(),
            "当前条件成立",
            "当前命中的 fact 数量。",
        );
        summary_card(
            ui,
            "未命中 fact",
            unmatched.len().to_string().as_str(),
            "当前条件不成立",
            "当前未命中的 fact 数量。",
        );
    });

    ui.add_space(4.0);
    render_fact_group(ui, "命中", &matched, true);
    ui.add_space(6.0);
    render_fact_group(ui, "未命中", &unmatched, false);
}

fn render_advanced_diagnostics(ui: &mut egui::Ui, preview: &CharacterAiPreview) {
    egui::CollapsingHeader::new("高级诊断")
        .id_salt("ai_preview_advanced_diagnostics")
        .default_open(false)
        .show(ui, |ui| {
            ui.small("保留原始技术诊断，方便 LLM 或开发者继续排查。");
            ui.separator();

            section_header(
                ui,
                "解析锚点",
                "展示 blackboard 中解析出的关键锚点结果，可用于核对 duty/canteen/leisure/alarm 的解析是否符合预期。",
            );
            render_resolved_anchor_row(
                ui,
                &preview.diagnostics.blackboard_entries,
                "anchor.home",
                "Home 锚点",
            );
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
            section_header(
                ui,
                "访问规则",
                "当前 smart object access profile 的规则明细。用于查看种类、偏好标签和 fallback 策略。",
            );
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

            ui.separator();
            section_header(
                ui,
                "Blackboard",
                "进入 AI 推导前的 blackboard 原始键值。",
            );
            render_blackboard_table(ui, &preview.diagnostics.blackboard_entries);

            ui.separator();
            section_header(
                ui,
                "Goal 规则详情",
                "原始 goal 规则级诊断，包括 score_delta、乘数和 trace。",
            );
            render_goal_rule_details(ui, preview);

            ui.separator();
            section_header(
                ui,
                "Action 诊断详情",
                "原始 action 可用性诊断，保留 target_anchor、reservation_target 和 blocker 明细。",
            );
            render_action_diagnostic_details(ui, preview);
        })
        .header_response
        .on_hover_text(
            "默认折叠的技术诊断区。这里保留 blackboard、规则明细和动作诊断，不再抢占主阅读流。",
        );
}

fn render_goal_rule_details(ui: &mut egui::Ui, preview: &CharacterAiPreview) {
    for goal in &preview.diagnostics.goal_evaluations {
        egui::CollapsingHeader::new(format!(
            "{} [{}] -> {}",
            goal.display_name, goal.goal_id, goal.final_score
        ))
        .default_open(false)
        .show(ui, |ui| {
            for rule in &goal.rules {
                egui::CollapsingHeader::new(format!(
                    "{} [{}] {} contributed {}",
                    rule.display_name,
                    rule.rule_id,
                    if rule.matched { "matched" } else { "skipped" },
                    rule.contributed_score
                ))
                .default_open(false)
                .show(ui, |ui| {
                    key_value_with_tooltip(
                        ui,
                        "score_delta",
                        &rule.score_delta.to_string(),
                        ai_metric_tooltip("score_delta"),
                    );
                    key_value_with_tooltip(
                        ui,
                        "multiplier_key",
                        rule.multiplier_key.as_deref().unwrap_or("-"),
                        ai_metric_tooltip("multiplier_key"),
                    );
                    key_value_with_tooltip(
                        ui,
                        "multiplier_value",
                        &rule
                            .multiplier_value
                            .map(|value| format!("{value:.2}"))
                            .unwrap_or_else(|| "-".to_string()),
                        ai_metric_tooltip("multiplier_value"),
                    );
                    key_value_with_tooltip(
                        ui,
                        "contributed_score",
                        &rule.contributed_score.to_string(),
                        ai_metric_tooltip("contributed_score"),
                    );
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
}

fn render_action_diagnostic_details(ui: &mut egui::Ui, preview: &CharacterAiPreview) {
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
        .default_open(false)
        .show(ui, |ui| {
            ui.label(if action.available {
                positive_text("可执行".to_string())
            } else {
                negative_text("已阻断".to_string())
            });
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
            if action.blockers.is_empty() {
                ui.small("无 blocker。");
            } else {
                for blocker in &action.blockers {
                    ui.label(negative_text(format!(
                        "{}: {} ({})",
                        blocker_label(blocker.kind),
                        blocker.message,
                        blocker.subject
                    )));
                }
            }
        });
    }
}

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
        small_label_with_tooltip(ui, group, blackboard_group_tooltip(group));
        egui::Grid::new(format!("blackboard_grid_{group}"))
            .num_columns(3)
            .striped(true)
            .show(ui, |ui| {
                small_label_with_tooltip(ui, "key", blackboard_header_tooltip("key"));
                small_label_with_tooltip(ui, "value", blackboard_header_tooltip("value"));
                small_label_with_tooltip(ui, "source", blackboard_header_tooltip("source"));
                ui.end_row();
                for entry in group_entries {
                    if let Some(tooltip) = blackboard_key_tooltip(&entry.key) {
                        small_label_with_tooltip(ui, &entry.key, tooltip);
                    } else {
                        ui.small(&entry.key);
                    }
                    ui.small(&entry.value_text);
                    ui.small(&entry.source);
                    ui.end_row();
                }
            });
    }
}

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
        small_label_with_tooltip(
            ui,
            format!("{label}:").as_str(),
            super::helpers::resolved_anchor_tooltip(key),
        );
        if value == "-" {
            ui.label(crate::ui::common::warning_text("未解析".to_string()));
        } else {
            ui.label(value);
        }
    });
}

fn render_fact_group(
    ui: &mut egui::Ui,
    title: &str,
    facts: &[&AiFactEvaluationPreview],
    matched: bool,
) {
    label_with_tooltip(
        ui,
        title,
        if matched {
            "当前命中的 fact，说明这些条件链在此场景下成立。"
        } else {
            "当前未命中的 fact，说明这些条件链在此场景下失败。"
        },
    );
    if facts.is_empty() {
        ui.small(if matched {
            "当前没有命中的 fact。"
        } else {
            "当前没有未命中的 fact。"
        });
        return;
    }

    for fact in facts {
        egui::CollapsingHeader::new(format!(
            "{} [{}] {}",
            fact.display_name,
            fact.fact_id,
            if fact.matched { "matched" } else { "unmatched" }
        ))
        .default_open(false)
        .show(ui, |ui| {
            ui.label(match fact.matched {
                true => positive_text("命中".to_string()),
                false => negative_text("未命中".to_string()),
            });
            render_condition_trace(ui, &fact.trace, 0);
        });
    }
}
