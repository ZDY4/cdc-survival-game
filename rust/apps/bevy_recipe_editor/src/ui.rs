use std::collections::BTreeSet;

use bevy::log::{info, warn};
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_data::RecipeEditDiagnosticSeverity;
use game_editor::ai_chat::{
    persist_ai_chat_settings, poll_generation_job, render_ai_chat_panel, render_ai_settings_window,
    start_connection_test, AiChatUiAction,
};
use game_editor::install_game_ui_fonts;

use crate::ai::{
    apply_prepared_proposal, assistant_summary_text, render_recipe_ai_result,
    start_recipe_ai_generation, success_status_text, RecipeAiUiAction,
};
use crate::data::{load_editor_resources, validate_all_documents};
use crate::navigation::open_item_in_editor;
use crate::state::{
    EditorEguiFontState, EditorState, RecipeAiState, RecipeAiWorkerState, RecipeEditorCatalogs,
};

const LIST_PANEL_WIDTH: f32 = 300.0;
const AI_PANEL_WIDTH: f32 = 480.0;

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

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    catalogs: Res<RecipeEditorCatalogs>,
    mut ai: ResMut<RecipeAiState>,
    mut worker: ResMut<RecipeAiWorkerState>,
) {
    let ctx = contexts
        .ctx_mut()
        .expect("primary egui context should exist for the recipe editor");
    editor.ensure_selection();

    egui::TopBottomPanel::top("recipe_editor_topbar").show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.heading("配方编辑器");
            ui.separator();
            ui.label(format!("配方 {}", editor.documents.len()));
            ui.separator();
            ui.label(format!("错误 {}", editor.recipe_error_count()));
            ui.separator();
            ui.small(format!("仓库 {}", editor.repo_root.display()));
            ui.separator();
            ui.small(&editor.status);

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("删除当前").clicked() {
                    editor.status = delete_current_document(&mut editor, &catalogs)
                        .unwrap_or_else(|error| error);
                }
                if ui.button("保存全部脏草稿").clicked() {
                    editor.status = save_all_dirty_documents(&mut editor, &catalogs)
                        .unwrap_or_else(|error| error);
                }
                if ui.button("保存当前").clicked() {
                    editor.status =
                        save_current_document(&mut editor, &catalogs).unwrap_or_else(|error| error);
                }
                if ui.button("校验当前").clicked() {
                    editor.status = validate_current_document(&mut editor, &catalogs)
                        .unwrap_or_else(|error| error);
                }
                if ui.button("重新加载").clicked() {
                    ai.clear_result();
                    editor.status =
                        reload_editor_content(&mut editor).unwrap_or_else(|error| error);
                }
            });
        });
    });

    egui::SidePanel::left("recipe_list")
        .default_width(LIST_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| render_recipe_list_panel(ui, &mut editor));

    egui::SidePanel::right("recipe_ai")
        .default_width(AI_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            let actions = render_ai_chat_panel(
                ui,
                &mut ai,
                worker.is_busy(),
                "AI 修改配方",
                "生成提案",
                |ui, proposal, busy| {
                    render_recipe_ai_result(ui, &editor, &catalogs, proposal, busy)
                },
            );
            for action in actions {
                match action {
                    AiChatUiAction::OpenSettings => ai.show_settings_window = true,
                    AiChatUiAction::SubmitPrompt => {
                        start_recipe_ai_generation(&editor, &catalogs, &mut ai, &mut worker);
                    }
                    AiChatUiAction::Host(RecipeAiUiAction::ApplyProposal) => {
                        editor.status = apply_prepared_proposal(
                            &mut editor,
                            &catalogs,
                            ai.result.as_ref().expect("proposal result should exist"),
                        )
                        .unwrap_or_else(|error| error);
                    }
                    AiChatUiAction::SaveSettings | AiChatUiAction::TestConnection => {}
                }
            }
        });

    egui::CentralPanel::default().show(ctx, |ui| {
        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                if let Some(status) = render_recipe_detail_panel(ui, &editor, &catalogs) {
                    editor.status = status;
                }
            });
    });

    for action in render_ai_settings_window(ctx, &mut ai, worker.is_busy()) {
        match action {
            AiChatUiAction::SaveSettings => {
                ai.provider_status =
                    persist_ai_chat_settings(&mut ai).unwrap_or_else(|error| error);
            }
            AiChatUiAction::TestConnection => start_connection_test(&mut ai, &mut worker),
            AiChatUiAction::OpenSettings
            | AiChatUiAction::SubmitPrompt
            | AiChatUiAction::Host(_) => {}
        }
    }
}

pub(crate) fn poll_ai_worker_system(
    mut ai: ResMut<RecipeAiState>,
    mut worker: ResMut<RecipeAiWorkerState>,
) {
    poll_generation_job(
        &mut ai,
        &mut worker,
        assistant_summary_text,
        success_status_text,
    );
}

fn render_recipe_list_panel(ui: &mut egui::Ui, editor: &mut EditorState) {
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
                .documents
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

                let selected = editor.selected_document_key.as_deref() == Some(key.as_str());
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
                    editor.selected_document_key = Some(key);
                }
            }
        });
}

fn render_recipe_detail_panel(
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
        if navigation_status.is_none() {
            navigation_status = render_item_link_row(
                ui,
                editor,
                catalogs,
                "output.item_id",
                document.definition.output.item_id,
            );
        } else {
            let _ = render_item_link_row(
                ui,
                editor,
                catalogs,
                "output.item_id",
                document.definition.output.item_id,
            );
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
            .documents
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

fn reload_editor_content(editor: &mut EditorState) -> Result<String, String> {
    if editor.has_dirty_documents() {
        warn!("recipe editor reload blocked: dirty drafts exist");
        return Err("Save or delete dirty recipe drafts before reloading content.".to_string());
    }

    let selected_id = editor
        .selected_document()
        .map(|document| document.definition.id.clone());
    let (mut next_editor, _) = load_editor_resources()?;
    next_editor.selected_document_key = selected_id.and_then(|recipe_id| {
        next_editor
            .documents
            .iter()
            .find(|(_, document)| document.definition.id == recipe_id)
            .map(|(key, _)| key.clone())
    });
    next_editor.ensure_selection();

    let message = format!("Reloaded {} recipe documents.", next_editor.documents.len());
    *editor = next_editor;
    info!(
        "recipe editor reloaded content: recipes={}",
        editor.documents.len()
    );
    Ok(message)
}

fn validate_current_document(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Result<String, String> {
    validate_all_documents(editor, catalogs)?;
    let Some(document) = editor.selected_document() else {
        return Err("No recipe selected.".to_string());
    };
    Ok(format!(
        "Validated recipe {} ({} diagnostics).",
        document.definition.id,
        document.diagnostics.len()
    ))
}

fn save_current_document(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Result<String, String> {
    let key = editor
        .selected_document_key
        .clone()
        .ok_or_else(|| "No recipe selected.".to_string())?;
    save_document_by_key(editor, catalogs, &key)
}

fn save_all_dirty_documents(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Result<String, String> {
    let keys = editor.dirty_document_keys();
    if keys.is_empty() {
        return Ok("No unsaved recipe changes.".to_string());
    }

    for key in keys.clone() {
        if editor.documents.contains_key(&key) {
            save_document_by_key(editor, catalogs, &key)?;
        }
    }
    Ok(format!("Saved {} dirty recipe documents.", keys.len()))
}

fn save_document_by_key(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
    key: &str,
) -> Result<String, String> {
    validate_all_documents(editor, catalogs)?;
    if editor.has_duplicate_ids() {
        return Err("Resolve duplicate recipe ids before saving.".to_string());
    }

    let document = editor
        .documents
        .get(key)
        .cloned()
        .ok_or_else(|| format!("recipe draft {key} is no longer loaded"))?;
    if document
        .diagnostics
        .iter()
        .any(|diagnostic| matches!(diagnostic.severity, RecipeEditDiagnosticSeverity::Error))
    {
        return Err(format!(
            "recipe {} has validation errors and cannot be saved",
            document.definition.id
        ));
    }

    let result = editor
        .service
        .save_recipe_definition(
            document.original_id.as_deref(),
            &document.definition,
            catalogs.item_ids.iter().copied().collect::<BTreeSet<_>>(),
            catalogs.skill_ids.iter().cloned().collect::<BTreeSet<_>>(),
            editor.current_recipe_ids(),
        )
        .map_err(|error| error.to_string())?;

    let next_key = format!("{}.json", document.definition.id);
    let mut next_document = document.clone();
    next_document.document_key = next_key.clone();
    next_document.original_id = Some(document.definition.id.clone());
    next_document.file_name = next_key.clone();
    next_document.relative_path = format!("recipes/{}.json", document.definition.id);
    next_document.dirty = false;
    next_document.last_save_message = Some(result.summary.details.join("; "));
    editor.documents.remove(key);
    editor.documents.insert(next_key.clone(), next_document);
    editor.selected_document_key = Some(next_key);
    validate_all_documents(editor, catalogs)?;
    info!(
        "recipe editor saved recipe: recipe_id={}",
        document.definition.id
    );
    Ok(format!("Saved recipe {}.", document.definition.id))
}

fn delete_current_document(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Result<String, String> {
    let key = editor
        .selected_document_key
        .clone()
        .ok_or_else(|| "No recipe selected.".to_string())?;
    let document = editor
        .documents
        .get(&key)
        .cloned()
        .ok_or_else(|| "Selected recipe is no longer loaded.".to_string())?;

    if let Some(original_id) = document.original_id.clone() {
        let delete_id = if document.dirty && document.definition.id != original_id {
            original_id
        } else {
            document.definition.id.clone()
        };
        editor
            .service
            .delete_recipe_definition(&delete_id)
            .map_err(|error| error.to_string())?;
    }

    editor.documents.remove(&key);
    editor.ensure_selection();
    validate_all_documents(editor, catalogs)?;
    Ok(format!("Deleted recipe draft {}.", document.definition.id))
}

fn diagnostic_color(severity: RecipeEditDiagnosticSeverity) -> egui::Color32 {
    match severity {
        RecipeEditDiagnosticSeverity::Error => egui::Color32::from_rgb(242, 94, 94),
        RecipeEditDiagnosticSeverity::Warning => egui::Color32::from_rgb(242, 190, 94),
        RecipeEditDiagnosticSeverity::Info => egui::Color32::from_rgb(130, 171, 255),
    }
}

fn empty_placeholder(value: &str) -> &str {
    if value.trim().is_empty() {
        "-"
    } else {
        value
    }
}
