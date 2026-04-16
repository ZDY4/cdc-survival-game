//! AI 预览页。
//! 负责展示 AI 输入上下文、据点关联、推导过程和行动阻断原因，不写回任何数据。

mod context;
mod derivation;
mod execution;

use std::collections::BTreeSet;

use bevy::prelude::*;
use bevy_egui::egui;
use game_data::{
    AiActionAvailabilityPreview, AiActionBlockerKind, AiActionEvaluationPreview,
    AiBlackboardEntryPreview, AiConditionTracePreview, AiFactEvaluationPreview, CharacterAiPreview,
    CharacterDefinition, ScheduleDay, WeeklyScheduleEntryPreview,
};

use crate::commands::CharacterEditorCommand;
use crate::preview::{default_context_for_character, settlement_for_character};
use crate::state::{
    default_preview_context, non_empty, npc_role_label, schedule_day_label, EditorData,
    EditorUiState, PreviewState,
};

use super::common::{
    key_value_with_tooltip, label_with_tooltip, negative_text, neutral_text, positive_text,
    section_header, small_label_with_tooltip, status_badge, summary_card, warning_text,
};

// AI 页主入口，组织场景切换、结果摘要和高级诊断三类视图。
pub(crate) fn render_ai_tab(
    ui: &mut egui::Ui,
    character: &CharacterDefinition,
    data: &EditorData,
    ui_state: &EditorUiState,
    preview_state: &PreviewState,
    requests: &mut MessageWriter<CharacterEditorCommand>,
) {
    let settlement = settlement_for_character(character, &data.settlements);

    if let Some(error) = &preview_state.ai_error {
        ui.colored_label(egui::Color32::from_rgb(240, 110, 110), error);
        return;
    }
    {
        let Some(preview) = preview_state.ai_preview.as_ref() else {
            ui.label("当前没有 AI 预览结果。");
            return;
        };
        render_scene_controls(
            ui,
            character,
            data,
            settlement.is_some(),
            preview,
            ui_state,
            requests,
        );
    }

    let Some(preview) = preview_state.ai_preview.as_ref() else {
        ui.label("当前没有 AI 预览结果。");
        return;
    };

    ui.separator();
    context::render_context_sections(ui, data, preview, ui_state);
    ui.separator();
    derivation::render_derivation_sections(ui, preview, ui_state);
    ui.separator();
    execution::render_execution_sections(ui, preview);
}

fn render_scene_controls(
    ui: &mut egui::Ui,
    character: &CharacterDefinition,
    data: &EditorData,
    has_settlement: bool,
    preview: &CharacterAiPreview,
    ui_state: &EditorUiState,
    requests: &mut MessageWriter<CharacterEditorCommand>,
) {
    let mut next_context = ui_state.preview_context.clone();
    let mut changed = false;
    section_header(
        ui,
        "预览场景",
        "只保留少量高价值场景切换，方便人类快速切场景看结果。底层输入收进默认折叠的高级区。",
    );
    ui.horizontal_wrapped(|ui| {
        status_badge(
            ui,
            if next_context.world_alert_active {
                "警报中"
            } else {
                "正常"
            },
            if next_context.world_alert_active {
                egui::Color32::from_rgb(110, 38, 38)
            } else {
                egui::Color32::from_rgb(44, 76, 56)
            },
            egui::Color32::from_rgb(236, 240, 244),
        );
        if ui
            .small_button(if next_context.world_alert_active {
                "切换为正常"
            } else {
                "切换为警报"
            })
            .on_hover_text(ai_context_tooltip("世界警报"))
            .clicked()
        {
            next_context.world_alert_active = !next_context.world_alert_active;
            changed = true;
        }
        if ui
            .small_button("重置场景")
            .on_hover_text(
                "恢复为当前角色的默认 AI 预览上下文。不会修改角色数据，只重置场景模拟输入。",
            )
            .clicked()
        {
            next_context = default_context_for_character(character, data)
                .unwrap_or_else(default_preview_context);
            changed = true;
        }
    });

    ui.add_space(4.0);
    small_label_with_tooltip(
        ui,
        "时间块快捷切换",
        "按角色的真实日程块快速切换时间场景。点击后会把预览时间跳到对应日程块中段。",
    );
    ui.horizontal_wrapped(|ui| {
        for entry in &preview.schedule.entries {
            let selected = schedule_entry_matches(entry, &next_context);
            let label = format!(
                "{} {}-{}",
                entry.label,
                format_minute(entry.start_minute),
                format_minute(entry.end_minute)
            );
            if ui
                .add(
                    egui::Button::new(label.as_str())
                        .selected(selected)
                        .truncate(),
                )
                .on_hover_text(schedule_entry_tooltip(entry))
                .clicked()
            {
                apply_schedule_entry(&mut next_context, entry);
                changed = true;
            }
        }
    });

    ui.add_space(6.0);
    small_label_with_tooltip(
        ui,
        "当前位置快捷切换",
        "使用当前预览已经解析出的关键锚点快速切换角色位置，方便观察不同场景下的结果。",
    );
    ui.horizontal_wrapped(|ui| {
        for (slot_key, label, anchor_id) in quick_anchor_options(preview) {
            let selected = next_context.current_anchor.as_deref() == Some(anchor_id.as_str());
            if ui
                .add(
                    egui::Button::new(format!("{label} [{anchor_id}]"))
                        .selected(selected)
                        .truncate(),
                )
                .on_hover_text(resolved_anchor_tooltip(slot_key))
                .clicked()
            {
                next_context.current_anchor = Some(anchor_id);
                changed = true;
            }
        }
    });

    egui::CollapsingHeader::new("高级输入")
        .id_salt("ai_preview_advanced_inputs")
        .default_open(false)
        .show(ui, |ui| {
            ui.small("保留底层输入供 LLM 或少量人工诊断使用，默认不作为主操作入口。");
            ui.add_space(4.0);

            ui.horizontal(|ui| {
                small_label_with_tooltip(ui, "星期", ai_context_tooltip("星期"));
                egui::ComboBox::from_id_salt("preview_day")
                    .selected_text(schedule_day_label(next_context.day))
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
                                    &mut next_context.day,
                                    day,
                                    schedule_day_label(day),
                                )
                                .changed();
                        }
                    })
                    .response
                    .on_hover_text(ai_context_tooltip("星期"));
                changed |= ui
                    .add(egui::Slider::new(&mut next_context.minute_of_day, 0..=1439).text("分钟"))
                    .on_hover_text(ai_context_tooltip("分钟"))
                    .changed();
            });
            ui.horizontal(|ui| {
                changed |= ui
                    .add(egui::Slider::new(&mut next_context.hunger, 0.0..=100.0).text("饥饿"))
                    .on_hover_text(ai_context_tooltip("饥饿"))
                    .changed();
                changed |= ui
                    .add(egui::Slider::new(&mut next_context.energy, 0.0..=100.0).text("精力"))
                    .on_hover_text(ai_context_tooltip("精力"))
                    .changed();
                changed |= ui
                    .add(egui::Slider::new(&mut next_context.morale, 0.0..=100.0).text("士气"))
                    .on_hover_text(ai_context_tooltip("士气"))
                    .changed();
            });
            ui.horizontal(|ui| {
                changed |= ui
                    .add(egui::DragValue::new(&mut next_context.active_guards).prefix("值班守卫 "))
                    .on_hover_text(ai_context_tooltip("值班守卫"))
                    .changed();
                changed |= ui
                    .add(
                        egui::DragValue::new(&mut next_context.min_guard_on_duty)
                            .prefix("最低守卫 "),
                    )
                    .on_hover_text(ai_context_tooltip("最低守卫"))
                    .changed();
            });
            ui.horizontal(|ui| {
                small_label_with_tooltip(ui, "当前锚点", ai_context_tooltip("当前锚点"));
                let current_anchor = next_context.current_anchor.get_or_insert_with(String::new);
                changed |= ui
                    .add(egui::TextEdit::singleline(current_anchor).hint_text("自定义锚点"))
                    .on_hover_text(ai_context_tooltip("当前锚点"))
                    .changed();
            });
            ui.horizontal_wrapped(|ui| {
                changed |= ui
                    .checkbox(
                        &mut next_context.availability.guard_post_available,
                        "guard_post",
                    )
                    .on_hover_text(ai_context_tooltip("guard_post"))
                    .changed();
                changed |= ui
                    .checkbox(
                        &mut next_context.availability.meal_object_available,
                        "meal_object",
                    )
                    .on_hover_text(ai_context_tooltip("meal_object"))
                    .changed();
                changed |= ui
                    .checkbox(
                        &mut next_context.availability.leisure_object_available,
                        "leisure_object",
                    )
                    .on_hover_text(ai_context_tooltip("leisure_object"))
                    .changed();
                changed |= ui
                    .checkbox(
                        &mut next_context.availability.medical_station_available,
                        "medical_station",
                    )
                    .on_hover_text(ai_context_tooltip("medical_station"))
                    .changed();
                changed |= ui
                    .checkbox(
                        &mut next_context.availability.patrol_route_available,
                        "patrol_route",
                    )
                    .on_hover_text(ai_context_tooltip("patrol_route"))
                    .changed();
                changed |= ui
                    .checkbox(&mut next_context.availability.bed_available, "bed")
                    .on_hover_text(ai_context_tooltip("bed"))
                    .changed();
            });

            if !has_settlement {
                ui.add_space(4.0);
                ui.label(warning_text(
                    "当前角色没有可用据点引用，部分锚点和可用性输入可能无法正确解析。".to_string(),
                ));
            }
        })
        .header_response
        .on_hover_text(
            "默认折叠的低层输入区。这里保留精细调节能力，但主界面优先使用上面的场景快捷切换。",
        );

    if changed {
        requests.write(CharacterEditorCommand::UpdatePreviewContext(next_context));
    }
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
    let blocked_actions = blocked_actions(preview);
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
                schedule_day_label(ui_state.preview_context.day),
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
            schedule_day_label(ui_state.preview_context.day),
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
        schedule_day_label(ui_state.preview_context.day),
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
                    status_badge(
                        ui,
                        "当前最优目标",
                        egui::Color32::from_rgb(82, 63, 24),
                        egui::Color32::from_rgb(245, 224, 163),
                    );
                }
                ui.label(goal_label(goal));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    status_badge(
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

    ui.label(if let Some(action) = available_actions.first() {
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

// 提取当前激活日程块名称，用于输入态摘要。
fn preview_schedule_entry_label(preview: &CharacterAiPreview) -> &str {
    preview
        .diagnostics
        .active_schedule_entry
        .as_ref()
        .map(|entry| entry.label.as_str())
        .unwrap_or("-")
}

// 渲染解析锚点行，并突出未解析状态。
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
            resolved_anchor_tooltip(key),
        );
        if value == "-" {
            ui.label(warning_text("未解析".to_string()));
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

fn best_goal(preview: &CharacterAiPreview) -> Option<&game_data::AiGoalScorePreview> {
    preview.goal_scores.iter().max_by(|left, right| {
        left.score
            .cmp(&right.score)
            .then_with(|| right.display_name.cmp(&left.display_name))
    })
}

fn recommended_action(preview: &CharacterAiPreview) -> Option<&AiActionAvailabilityPreview> {
    preview
        .available_actions
        .iter()
        .find(|action| action.available)
}

fn blocked_actions(preview: &CharacterAiPreview) -> Vec<&AiActionEvaluationPreview> {
    preview
        .diagnostics
        .action_evaluations
        .iter()
        .filter(|action| !action.available)
        .collect()
}

fn blocker_summary(preview: &CharacterAiPreview) -> Vec<String> {
    let kinds = preview
        .diagnostics
        .action_evaluations
        .iter()
        .flat_map(|action| {
            action
                .blockers
                .iter()
                .map(|blocker| blocker_label(blocker.kind))
        })
        .collect::<BTreeSet<_>>();
    kinds.into_iter().map(str::to_string).collect()
}

fn resolve_schedule_display_name(data: &EditorData, preview: &CharacterAiPreview) -> String {
    data.ai_library
        .as_ref()
        .and_then(|library| library.schedule_templates.get(&preview.schedule.profile_id))
        .map(|schedule| {
            if schedule.meta.display_name.trim().is_empty() {
                schedule.id.clone()
            } else {
                schedule.meta.display_name.clone()
            }
        })
        .unwrap_or_else(|| preview.schedule.profile_id.clone())
}

fn schedule_entry_matches(
    entry: &WeeklyScheduleEntryPreview,
    context: &game_data::CharacterAiPreviewContext,
) -> bool {
    entry.days.contains(&context.day)
        && context.minute_of_day >= entry.start_minute
        && context.minute_of_day < entry.end_minute
}

fn apply_schedule_entry(
    context: &mut game_data::CharacterAiPreviewContext,
    entry: &WeeklyScheduleEntryPreview,
) {
    if let Some(day) = entry.days.first().copied() {
        context.day = day;
    }
    context.minute_of_day = ((entry.start_minute as u32 + entry.end_minute as u32) / 2) as u16;
}

fn schedule_entry_tooltip(entry: &WeeklyScheduleEntryPreview) -> String {
    let day_text = if entry.days.is_empty() {
        "无星期限制".to_string()
    } else {
        entry
            .days
            .iter()
            .map(|day| schedule_day_label(*day))
            .collect::<Vec<_>>()
            .join(" / ")
    };
    let tag_text = if entry.tags.is_empty() {
        "无标签".to_string()
    } else {
        entry.tags.join(", ")
    };
    format!(
        "{}\n{} - {}\n{}\n标签: {}",
        entry.label,
        format_minute(entry.start_minute),
        format_minute(entry.end_minute),
        day_text,
        tag_text
    )
}

fn quick_anchor_options(preview: &CharacterAiPreview) -> Vec<(&'static str, &'static str, String)> {
    let mut options = Vec::new();
    for (key, label) in [
        ("anchor.home", "Home"),
        ("anchor.duty", "Duty"),
        ("anchor.canteen", "Canteen"),
        ("anchor.leisure", "Leisure"),
        ("anchor.alarm", "Alarm"),
    ] {
        if let Some(value) = preview
            .diagnostics
            .blackboard_entries
            .iter()
            .find(|entry| entry.key == key)
            .map(|entry| entry.value_text.clone())
            .filter(|value| !value.trim().is_empty() && value != "-")
        {
            options.push((key, label, value));
        }
    }
    options
}

fn goal_label(goal: &game_data::AiGoalScorePreview) -> egui::RichText {
    let text = format!("{} [{}]", goal.display_name, goal.goal_id);
    if goal.score > 0 {
        positive_text(text)
    } else if goal.score < 0 {
        negative_text(text)
    } else {
        neutral_text(text)
    }
}

fn score_badge_fill(score: i32) -> egui::Color32 {
    if score > 0 {
        egui::Color32::from_rgb(44, 76, 56)
    } else if score < 0 {
        egui::Color32::from_rgb(110, 38, 38)
    } else {
        egui::Color32::from_rgb(58, 64, 78)
    }
}

fn format_minute(minute_of_day: u16) -> String {
    format!("{:02}:{:02}", minute_of_day / 60, minute_of_day % 60)
}

fn blocker_label(kind: AiActionBlockerKind) -> &'static str {
    match kind {
        AiActionBlockerKind::PreconditionMismatch => "前置条件不满足",
        AiActionBlockerKind::PreconditionUnresolved => "前置条件未解析",
        AiActionBlockerKind::MissingTargetAnchor => "缺少目标锚点",
        AiActionBlockerKind::ReservationUnavailable => "预占目标不可用",
    }
}

fn ai_context_tooltip(label: &str) -> &'static str {
    match label {
        "星期" => "模拟当前是星期几。它会决定匹配哪一组日程块。",
        "分钟" => "模拟一天中的分钟数。AI 会用它定位当前日程时段。",
        "饥饿" => "模拟当前饥饿程度。该值会进入 need blackboard，影响进食相关目标评分。",
        "精力" => "模拟当前体力与疲劳程度。该值会进入 need blackboard，影响休息和工作类行为。",
        "士气" => "模拟当前情绪或士气状态。它会进入 blackboard，影响休闲、工作等行为倾向。",
        "世界警报" => "模拟当前是否处于全局警报。开启后 AI 会优先考虑警戒或应急目标。",
        "值班守卫" => "模拟当前据点已在岗的守卫人数。它会参与守卫缺口与巡逻相关判断。",
        "最低守卫" => "模拟据点要求的最低在岗守卫人数。AI 会用它判断是否需要补足守卫。",
        "当前锚点" => "模拟角色当前所在锚点。路径、目标选择和锚点相关 fact 会从这里出发。",
        "guard_post" => "模拟据点内是否存在可用的 guard post。它会写入 availability blackboard。",
        "meal_object" => "模拟是否存在可用进食对象。进食类 goal 和 action 会读取这个可用性输入。",
        "leisure_object" => "模拟是否存在可用休闲对象。娱乐或放松类行为会据此判断能否执行。",
        "medical_station" => "模拟是否存在可用医疗站对象。治疗或恢复类行为会读取这个输入。",
        "patrol_route" => "模拟是否存在可用巡逻路线。巡逻、值守等移动行为会据此判断可行性。",
        "bed" => "模拟是否存在可用床位对象。休息、睡眠类行为会读取这个可用性输入。",
        _ => "",
    }
}

fn ai_relation_tooltip(label: &str) -> &'static str {
    match label {
        "据点" => "当前 AI 预览绑定的据点 ID。锚点、路线和服务规则都从这个据点解析。",
        "角色职责" => "当前角色在据点中的职责类型。它会影响默认日程、守卫要求和目标选择。",
        "家锚点" => "角色默认归属的 home 锚点。回家、休息或缺省定位时会优先使用它。",
        "执勤路线" => "角色绑定的 duty route ID。巡逻与值守类行为会用它解析移动路线。",
        _ => "",
    }
}

fn ai_metric_tooltip(label: &str) -> &'static str {
    match label {
        "score_delta" => "单条 goal 规则提供的基础分值增量。命中后会在乘算前作为原始加分参与计算。",
        "multiplier_key" => {
            "该规则使用的 blackboard 乘数键。若存在，AI 会读取对应值对 score_delta 做缩放。"
        }
        "multiplier_value" => "本次预览实际读取到的乘数值。它与 score_delta 一起决定最终贡献分。",
        "contributed_score" => "这条规则最终贡献给 goal 的分数结果。它已经考虑命中状态和乘数。",
        "target_anchor" => "动作最终解析出的目标锚点。执行时会据此确定要前往或交互的位置。",
        "reservation_target" => {
            "动作尝试预占的对象或目标标识。AI 用它避免多个角色同时争抢同一资源。"
        }
        _ => "",
    }
}

fn resolved_anchor_tooltip(key: &str) -> &'static str {
    match key {
        "anchor.home" => "从 blackboard 解析出的 home 锚点结果。回家、休息或缺省定位会优先使用它。",
        "anchor.duty" => {
            "从 blackboard 解析出的 duty 锚点结果。执勤、站岗等行为会把它当成目标定位。"
        }
        "anchor.canteen" => "从 blackboard 解析出的食堂或进食锚点结果。进食相关行为会用它寻址。",
        "anchor.leisure" => "从 blackboard 解析出的休闲锚点结果。娱乐或放松行为会用它寻址。",
        "anchor.alarm" => {
            "从 blackboard 解析出的警报集合点或警戒锚点结果。警报响应行为会用它寻址。"
        }
        _ => "",
    }
}

fn blackboard_header_tooltip(label: &str) -> &'static str {
    match label {
        "key" => "blackboard 键名。用于标识这条输入在 AI 内部的读取路径。",
        "value" => "当前预览下解析出的 blackboard 值。goal、fact 和 action 会读取它参与判断。",
        "source" => "这条 blackboard 值的来源。可用来判断它来自需求、日程、据点还是手动上下文。",
        _ => "",
    }
}

fn blackboard_group_tooltip(group: &str) -> &'static str {
    match group {
        "need" => "需求相关 blackboard 项，如饥饿和休息。goal 规则会读取这些值判断角色当前缺什么。",
        "personality" => "性格与偏好相关 blackboard 项。用于让不同角色在相同环境下做出不同倾向。",
        "schedule" => "日程相关 blackboard 项。表示当前命中的时间块和日程上下文。",
        "world" => "世界状态相关 blackboard 项。警报等全局条件会从这里进入 AI 计算。",
        "settlement" => "据点级别输入，如守卫人数或服务规则。AI 会用它判断据点运行状态。",
        "availability" => {
            "可用性输入，表示某类对象或路线当前是否可用。动作和目标会用它做前置筛选。"
        }
        "reservation" => "预占用状态输入，用于协调多个 AI 对对象的竞争。",
        "anchor" => "解析后的锚点输入。动作定位和部分 fact 会读取这些目标位置。",
        _ => "",
    }
}

fn blackboard_key_tooltip(key: &str) -> Option<&'static str> {
    match key {
        "anchor.home" => Some("home 锚点键。角色回家、休息或默认归属位置会使用它。"),
        "anchor.duty" => Some("执勤目标锚点键。站岗、巡逻等行为会读取它确定 duty 位置。"),
        "anchor.canteen" => Some("进食目标锚点键。寻找食堂或餐食对象时会先读取它。"),
        "anchor.leisure" => Some("休闲目标锚点键。娱乐或放松类行为会用它定位去哪里。"),
        "anchor.alarm" => Some("警报目标锚点键。警报响应和集结行为会用它确定目标位置。"),
        _ => None,
    }
}
