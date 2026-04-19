use bevy_egui::egui;

use crate::commands::RecipeEditorCommand;
use crate::navigation::open_item_in_editor;
use crate::state::{EditorState, RecipeEditorCatalogs};

pub(crate) const LIST_PANEL_WIDTH: f32 = 300.0;

pub(crate) fn render_top_bar(
    ui: &mut egui::Ui,
    editor: &EditorState,
    commands: &mut bevy::ecs::message::MessageWriter<RecipeEditorCommand>,
) {
    ui.horizontal(|ui| {
        ui.heading("配方编辑器");
        ui.separator();
        ui.label(format!("配方 {}", editor.workspace.len()));
        ui.separator();
        ui.label(format!("错误 {}", editor.recipe_error_count()));
        ui.separator();
        ui.small(format!("仓库 {}", editor.repo_root.display()));
        ui.separator();
        ui.small(&editor.status);

        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if ui.button("删除当前").clicked() {
                commands.write(RecipeEditorCommand::DeleteCurrent);
            }
            if ui.button("保存全部脏草稿").clicked() {
                commands.write(RecipeEditorCommand::SaveAllDirty);
            }
            if ui.button("保存当前").clicked() {
                commands.write(RecipeEditorCommand::SaveCurrent);
            }
            if ui.button("校验当前").clicked() {
                commands.write(RecipeEditorCommand::ValidateCurrent);
            }
            if ui.button("重新加载").clicked() {
                commands.write(RecipeEditorCommand::Reload);
            }
        });
    });
}

pub(crate) fn render_recipe_list_panel(
    ui: &mut egui::Ui,
    editor: &mut EditorState,
    commands: &mut bevy::ecs::message::MessageWriter<RecipeEditorCommand>,
) {
    ui.horizontal(|ui| {
        ui.label("搜索");
        ui.add(
            egui::TextEdit::singleline(&mut editor.search_text)
                .hint_text("配方名 / ID / 分类")
                .desired_width(f32::INFINITY),
        );
    });
    ui.separator();

    let needle = editor.search_text.trim().to_lowercase();
    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            let rows = editor
                .workspace
                .iter()
                .map(|(key, document)| {
                    (
                        key.clone(),
                        document.definition.id.clone(),
                        document.definition.name.clone(),
                        document.definition.category.clone(),
                        document.dirty,
                        !document.diagnostics.is_empty(),
                    )
                })
                .collect::<Vec<_>>();

            for (key, recipe_id, name, category, dirty, has_diagnostics) in rows {
                let label = if name.trim().is_empty() {
                    recipe_id.clone()
                } else {
                    format!("{name}  [{recipe_id}]")
                };
                let search_blob = format!("{label} {}", category).to_lowercase();
                if !needle.is_empty() && !search_blob.contains(&needle) {
                    continue;
                }

                let selected = editor.workspace.selected_document_key().map(String::as_str)
                    == Some(key.as_str());
                let suffix = match (dirty, has_diagnostics) {
                    (true, true) => " [dirty, diag]",
                    (true, false) => " [dirty]",
                    (false, true) => " [diag]",
                    (false, false) => "",
                };
                let category_label = if category.trim().is_empty() {
                    "uncategorized".to_string()
                } else {
                    category
                };
                let display = format!("{label} <{category_label}>{suffix}");
                if ui
                    .add(
                        egui::Button::selectable(selected, display.as_str())
                            .truncate()
                            .min_size(egui::vec2(ui.available_width(), 0.0)),
                    )
                    .on_hover_text(display)
                    .clicked()
                {
                    commands.write(RecipeEditorCommand::SelectDocument { key });
                }
            }
        });
}

pub(crate) fn render_recipe_detail_panel(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Option<String> {
    let Some(document) = editor.selected_document().cloned() else {
        ui.label("未选择配方。");
        return None;
    };

    let mut navigation_status = None;

    ui.heading(if document.definition.name.trim().is_empty() {
        document.definition.id.clone()
    } else {
        format!("{} · {}", document.definition.name, document.definition.id)
    });
    ui.label(format!("源文件: {}", document.relative_path));
    ui.label(format!(
        "状态: {}",
        if document.dirty { "Unsaved" } else { "Synced" }
    ));
    if let Some(message) = &document.last_save_message {
        ui.label(format!("上次保存: {message}"));
    }

    ui.add_space(8.0);
    ui.collapsing("基础信息", |ui| {
        ui.label(format!(
            "描述: {}",
            empty_placeholder(&document.definition.description)
        ));
        ui.label(format!(
            "分类: {}",
            empty_placeholder(&document.definition.category)
        ));
        ui.label(format!(
            "工位: {}",
            empty_placeholder(&document.definition.required_station)
        ));
        ui.label(format!("制作时间: {:.2}", document.definition.craft_time));
        ui.label(format!(
            "经验奖励: {}",
            document.definition.experience_reward
        ));
        ui.label(format!(
            "默认解锁: {}",
            if document.definition.is_default_unlocked {
                "Yes"
            } else {
                "No"
            }
        ));
        ui.label(format!(
            "修理配方: {}",
            if document.definition.is_repair {
                "Yes"
            } else {
                "No"
            }
        ));
        ui.label(format!("修理量: {}", document.definition.repair_amount));
        ui.label(format!(
            "耐久影响: {:.2}",
            document.definition.durability_influence
        ));
    });

    ui.add_space(8.0);
    ui.collapsing("产出", |ui| {
        let status = render_item_link_row(
            ui,
            editor,
            catalogs,
            "output.item_id",
            document.definition.output.item_id,
        );
        if navigation_status.is_none() {
            navigation_status = status;
        }
        ui.label(format!("数量: {}", document.definition.output.count));
        ui.label(format!(
            "品质加成: {}",
            document.definition.output.quality_bonus
        ));
    });

    ui.add_space(8.0);
    ui.collapsing(
        format!("材料 ({})", document.definition.materials.len()),
        |ui| {
            if document.definition.materials.is_empty() {
                ui.label("无材料。");
            } else {
                for (index, material) in document.definition.materials.iter().enumerate() {
                    let status = render_item_link_row(
                        ui,
                        editor,
                        catalogs,
                        &format!("materials[{index}].item_id"),
                        material.item_id,
                    );
                    if navigation_status.is_none() {
                        navigation_status = status;
                    }
                    ui.small(format!("数量: {}", material.count));
                    if !material.extra.is_empty() {
                        ui.small(format!(
                            "extra: {}",
                            serde_json::to_string(&material.extra)
                                .unwrap_or_else(|_| "{}".to_string())
                        ));
                    }
                    ui.add_space(4.0);
                }
            }
        },
    );

    ui.add_space(8.0);
    ui.collapsing("工具", |ui| {
        render_tool_list(
            ui,
            editor,
            catalogs,
            "required_tools",
            &document.definition.required_tools,
            &mut navigation_status,
        );
        ui.add_space(6.0);
        render_tool_list(
            ui,
            editor,
            catalogs,
            "optional_tools",
            &document.definition.optional_tools,
            &mut navigation_status,
        );
    });

    ui.add_space(8.0);
    ui.collapsing("技能要求", |ui| {
        if document.definition.skill_requirements.is_empty() {
            ui.label("无技能要求。");
        } else {
            for (skill_id, level) in &document.definition.skill_requirements {
                ui.label(format!("{skill_id}: {level}"));
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing(
        format!("解锁条件 ({})", document.definition.unlock_conditions.len()),
        |ui| {
            if document.definition.unlock_conditions.is_empty() {
                ui.label("无解锁条件。");
            } else {
                for condition in &document.definition.unlock_conditions {
                    let extra = if condition.extra.is_empty() {
                        String::new()
                    } else {
                        format!(
                            " {}",
                            serde_json::to_string(&condition.extra)
                                .unwrap_or_else(|_| "{}".to_string())
                        )
                    };
                    ui.label(format!(
                        "{}: {}{}",
                        empty_placeholder(&condition.condition_type),
                        empty_placeholder(&condition.id),
                        extra
                    ));
                }
            }
        },
    );

    ui.add_space(8.0);
    ui.collapsing("反向引用", |ui| {
        let reverse_refs = editor
            .workspace
            .values()
            .filter(|candidate| candidate.definition.id != document.definition.id)
            .filter(|candidate| {
                candidate
                    .definition
                    .unlock_conditions
                    .iter()
                    .any(|condition| {
                        condition.condition_type == "recipe"
                            && condition.id.trim() == document.definition.id
                    })
            })
            .map(|candidate| {
                if candidate.definition.name.trim().is_empty() {
                    candidate.definition.id.clone()
                } else {
                    format!(
                        "{} · {}",
                        candidate.definition.name, candidate.definition.id
                    )
                }
            })
            .collect::<Vec<_>>();
        if reverse_refs.is_empty() {
            ui.label("没有其他配方通过 unlock_conditions 引用当前配方。");
        } else {
            for entry in reverse_refs {
                ui.label(entry);
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing(format!("诊断 ({})", document.diagnostics.len()), |ui| {
        if document.diagnostics.is_empty() {
            ui.label("当前没有诊断。");
        } else {
            for diagnostic in &document.diagnostics {
                ui.colored_label(
                    diagnostic_color(diagnostic.severity),
                    format!("[{}] {}", diagnostic.code, diagnostic.message),
                );
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing("当前配方 JSON", |ui| {
        let raw =
            serde_json::to_string_pretty(&document.definition).unwrap_or_else(|_| "{}".to_string());
        ui.code(raw);
    });

    navigation_status
}

fn render_tool_list(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &RecipeEditorCatalogs,
    label: &str,
    tools: &[String],
    navigation_status: &mut Option<String>,
) {
    ui.strong(label);
    if tools.is_empty() {
        ui.label("无。");
        return;
    }

    for (index, tool) in tools.iter().enumerate() {
        if let Ok(item_id) = tool.parse::<u32>() {
            let status =
                render_item_link_row(ui, editor, catalogs, &format!("{label}[{index}]"), item_id);
            if navigation_status.is_none() {
                *navigation_status = status;
            }
        } else {
            ui.label(format!("{label}[{index}]: {tool}"));
        }
    }
}

fn render_item_link_row(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &RecipeEditorCatalogs,
    label: &str,
    item_id: u32,
) -> Option<String> {
    let item_name = catalogs
        .item_name(item_id)
        .filter(|name| !name.trim().is_empty())
        .unwrap_or("Unknown item");
    let button_text = format!("{label}: #{item_id} · {item_name}");
    if ui.link(button_text).clicked() {
        return Some(open_item_in_editor(&editor.repo_root, item_id).unwrap_or_else(|error| error));
    }
    None
}

fn diagnostic_color(severity: game_data::RecipeEditDiagnosticSeverity) -> egui::Color32 {
    match severity {
        game_data::RecipeEditDiagnosticSeverity::Error => egui::Color32::from_rgb(242, 94, 94),
        game_data::RecipeEditDiagnosticSeverity::Warning => egui::Color32::from_rgb(242, 190, 94),
        game_data::RecipeEditDiagnosticSeverity::Info => egui::Color32::from_rgb(130, 171, 255),
    }
}

fn empty_placeholder(value: &str) -> &str {
    if value.trim().is_empty() {
        "-"
    } else {
        value
    }
}
