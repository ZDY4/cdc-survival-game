use bevy::prelude::*;
use bevy_egui::egui;
use game_data::{CharacterAiPreview, CharacterDefinition, WeeklyScheduleEntryPreview};

use crate::commands::CharacterEditorCommand;
use crate::preview::default_context_for_character;
use crate::state::{default_preview_context, EditorData, EditorUiState};
use crate::ui::common::{section_header, small_label_with_tooltip, status_badge, warning_text};

use super::helpers::{
    ai_context_tooltip, format_minute, resolved_anchor_tooltip, schedule_day_name,
    schedule_day_options,
};

pub(super) fn render_scene_controls(
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
                    .selected_text(schedule_day_name(next_context.day))
                    .show_ui(ui, |ui| {
                        for day in schedule_day_options() {
                            changed |= ui
                                .selectable_value(
                                    &mut next_context.day,
                                    day,
                                    schedule_day_name(day),
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
            .map(|day| schedule_day_name(*day))
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
