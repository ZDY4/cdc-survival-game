use bevy::log::{info, warn};
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_editor::ai_chat::{
    persist_ai_chat_settings, poll_generation_job, render_ai_chat_panel, render_ai_settings_window,
    start_connection_test, AiChatUiAction,
};
use game_editor::{install_game_ui_fonts, PreviewCameraController, PreviewViewportRect};

use crate::ai::{
    apply_prepared_proposal, assistant_summary_text, render_item_ai_result,
    start_item_ai_generation, success_status_text, ItemAiUiAction,
};
use crate::data::{load_editor_resources, validate_all_documents};
use crate::preview::{PreviewCamera, PreviewState};
use crate::state::{
    EditorEguiFontState, EditorState, ItemAiState, ItemAiWorkerState, ItemEditorCatalogs,
};

const LIST_PANEL_WIDTH: f32 = 280.0;
const DETAIL_PANEL_WIDTH: f32 = 500.0;

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
    catalogs: Res<ItemEditorCatalogs>,
    mut ai: ResMut<ItemAiState>,
    mut worker: ResMut<ItemAiWorkerState>,
    preview_state: Res<PreviewState>,
    mut preview_camera: Single<&mut PreviewCameraController, With<PreviewCamera>>,
) {
    let ctx = contexts
        .ctx_mut()
        .expect("primary egui context should exist for the item editor");
    editor.ensure_selection();

    egui::TopBottomPanel::top("item_editor_topbar").show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.heading("物品编辑器");
            ui.separator();
            ui.label(format!("物品 {}", editor.documents.len()));
            ui.separator();
            ui.small(format!("仓库 {}", editor.repo_root.display()));
            ui.separator();
            ui.small(&editor.status);

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("删除当前").clicked() {
                    editor.status =
                        delete_current_document(&mut editor).unwrap_or_else(|error| error);
                }
                if ui.button("保存全部脏草稿").clicked() {
                    editor.status =
                        save_all_dirty_documents(&mut editor).unwrap_or_else(|error| error);
                }
                if ui.button("保存当前").clicked() {
                    editor.status =
                        save_current_document(&mut editor).unwrap_or_else(|error| error);
                }
                if ui.button("校验当前").clicked() {
                    editor.status =
                        validate_current_document(&mut editor).unwrap_or_else(|error| error);
                }
                if ui.button("重新加载").clicked() {
                    ai.clear_result();
                    editor.status =
                        reload_editor_content(&mut editor).unwrap_or_else(|error| error);
                }
            });
        });
    });

    egui::SidePanel::left("item_list")
        .default_width(LIST_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| render_item_list_panel(ui, &mut editor));

    egui::SidePanel::right("item_details")
        .default_width(DETAIL_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| {
                render_detail_panel(
                    ui,
                    &mut editor,
                    &catalogs,
                    &mut ai,
                    &mut worker,
                    &preview_state,
                );
            });
        });

    egui::CentralPanel::default()
        .frame(egui::Frame::NONE.fill(egui::Color32::TRANSPARENT))
        .show(ctx, |ui| {
            let rect = ui.max_rect();
            preview_camera.viewport_rect = Some(PreviewViewportRect {
                min_x: rect.left(),
                min_y: rect.top(),
                width: rect.width(),
                height: rect.height(),
            });
            ui.allocate_rect(rect, egui::Sense::hover());
            render_preview_overlay(ui.ctx(), rect, &editor, &preview_state);
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
    mut ai: ResMut<ItemAiState>,
    mut worker: ResMut<ItemAiWorkerState>,
) {
    poll_generation_job(
        &mut ai,
        &mut worker,
        assistant_summary_text,
        success_status_text,
    );
}

fn render_item_list_panel(ui: &mut egui::Ui, editor: &mut EditorState) {
    ui.horizontal(|ui| {
        ui.label("搜索");
        ui.add(
            egui::TextEdit::singleline(&mut editor.search_text)
                .hint_text("物品名 / ID")
                .desired_width(f32::INFINITY),
        );
    });
    ui.separator();

    let needle = editor.search_text.trim().to_lowercase();
    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            let items = editor
                .documents
                .iter()
                .map(|(key, document)| {
                    let label = if document.definition.name.trim().is_empty() {
                        format!("#{}", document.definition.id)
                    } else {
                        format!(
                            "{}  [#{}]",
                            document.definition.name, document.definition.id
                        )
                    };
                    (
                        key.clone(),
                        label,
                        document.dirty,
                        !document.diagnostics.is_empty(),
                    )
                })
                .collect::<Vec<_>>();
            for (key, label, dirty, has_diagnostics) in items {
                if !needle.is_empty() && !label.to_lowercase().contains(&needle) {
                    continue;
                }

                let selected = editor.selected_document_key.as_deref() == Some(key.as_str());
                let suffix = match (dirty, has_diagnostics) {
                    (true, true) => " [dirty, diag]",
                    (true, false) => " [dirty]",
                    (false, true) => " [diag]",
                    (false, false) => "",
                };
                let display = format!("{label}{suffix}");
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

fn render_detail_panel(
    ui: &mut egui::Ui,
    editor: &mut EditorState,
    catalogs: &ItemEditorCatalogs,
    ai: &mut ItemAiState,
    worker: &mut ItemAiWorkerState,
    preview_state: &PreviewState,
) {
    let Some(document) = editor.selected_document().cloned() else {
        ui.label("未选择物品。");
        return;
    };

    ui.heading(if document.definition.name.trim().is_empty() {
        format!("#{}", document.definition.id)
    } else {
        format!("{} · #{}", document.definition.name, document.definition.id)
    });
    ui.label(format!("源文件: {}", document.relative_path));
    ui.label(format!(
        "状态: {}",
        if document.dirty { "Unsaved" } else { "Synced" }
    ));
    ui.label(format!("预览: {}", preview_state.load_status.label()));
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
            "图标: {}",
            empty_placeholder(&document.definition.icon_path)
        ));
        ui.label(format!("价值: {}", document.definition.value));
        ui.label(format!("重量: {:.2}", document.definition.weight));
        ui.label(format!(
            "Fragments: {}",
            document.definition.fragments.len()
        ));
    });

    ui.add_space(8.0);
    ui.collapsing(format!("诊断 ({})", document.diagnostics.len()), |ui| {
        if document.diagnostics.is_empty() {
            ui.label("当前没有诊断。");
        } else {
            for diagnostic in &document.diagnostics {
                ui.colored_label(
                    egui::Color32::from_rgb(242, 94, 94),
                    format!("[{}] {}", diagnostic.code, diagnostic.message),
                );
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing("当前物品 JSON", |ui| {
        let raw =
            serde_json::to_string_pretty(&document.definition).unwrap_or_else(|_| "{}".to_string());
        ui.code(raw);
    });

    ui.add_space(12.0);
    let actions = render_ai_chat_panel(
        ui,
        ai,
        worker.is_busy(),
        "AI 修改物品",
        "生成提案",
        |ui, proposal, busy| render_item_ai_result(ui, editor, proposal, busy),
    );
    for action in actions {
        match action {
            AiChatUiAction::OpenSettings => ai.show_settings_window = true,
            AiChatUiAction::SubmitPrompt => {
                start_item_ai_generation(editor, catalogs, ai, worker);
            }
            AiChatUiAction::Host(ItemAiUiAction::ApplyProposal) => {
                editor.status = apply_prepared_proposal(
                    editor,
                    ai.result.as_ref().expect("proposal result should exist"),
                )
                .unwrap_or_else(|error| error);
            }
            AiChatUiAction::SaveSettings | AiChatUiAction::TestConnection => {}
        }
    }
}

fn render_preview_overlay(
    ctx: &egui::Context,
    rect: egui::Rect,
    editor: &EditorState,
    preview_state: &PreviewState,
) {
    egui::Area::new("item_preview_overlay".into())
        .order(egui::Order::Foreground)
        .fixed_pos(rect.left_top() + egui::vec2(10.0, 10.0))
        .show(ctx, |ui| {
            egui::Frame::new()
                .fill(egui::Color32::from_rgba_unmultiplied(18, 21, 28, 176))
                .corner_radius(6.0)
                .inner_margin(egui::Margin::same(10))
                .show(ui, |ui| {
                    ui.set_width(380.0);
                    ui.label(
                        egui::RichText::new("物品模型预览")
                            .size(14.0)
                            .color(egui::Color32::from_rgb(228, 231, 238)),
                    );
                    ui.label(
                        egui::RichText::new(
                            editor
                                .selected_document()
                                .map(|document| {
                                    if document.definition.name.trim().is_empty() {
                                        format!("#{}", document.definition.id)
                                    } else {
                                        format!(
                                            "{} · #{}",
                                            document.definition.name, document.definition.id
                                        )
                                    }
                                })
                                .unwrap_or_else(|| "未选择物品".to_string()),
                        )
                        .size(11.0)
                        .color(egui::Color32::from_rgb(164, 170, 184)),
                    );
                    ui.label(
                        egui::RichText::new(preview_state.load_status.label())
                            .size(11.0)
                            .color(egui::Color32::from_rgb(164, 170, 184)),
                    );
                });
        });
}

fn reload_editor_content(editor: &mut EditorState) -> Result<String, String> {
    if editor.has_dirty_documents() {
        warn!("item editor reload blocked: dirty drafts exist");
        return Err("Save or delete dirty item drafts before reloading content.".to_string());
    }

    let selected_id = editor
        .selected_document()
        .map(|document| document.definition.id);
    let (mut next_editor, _) = load_editor_resources(None)?;
    next_editor.selected_document_key = selected_id.and_then(|item_id| {
        next_editor
            .documents
            .iter()
            .find(|(_, document)| document.definition.id == item_id)
            .map(|(key, _)| key.clone())
    });
    next_editor.ensure_selection();

    let message = format!("Reloaded {} item documents.", next_editor.documents.len());
    *editor = next_editor;
    info!(
        "item editor reloaded content: items={}",
        editor.documents.len()
    );
    Ok(message)
}

fn validate_current_document(editor: &mut EditorState) -> Result<String, String> {
    validate_all_documents(editor)?;
    let Some(document) = editor.selected_document() else {
        return Err("No item selected.".to_string());
    };
    Ok(format!(
        "Validated item {} ({} diagnostics).",
        document.definition.id,
        document.diagnostics.len()
    ))
}

fn save_current_document(editor: &mut EditorState) -> Result<String, String> {
    let key = editor
        .selected_document_key
        .clone()
        .ok_or_else(|| "No item selected.".to_string())?;
    save_document_by_key(editor, &key)
}

fn save_all_dirty_documents(editor: &mut EditorState) -> Result<String, String> {
    let keys = editor.dirty_document_keys();
    if keys.is_empty() {
        return Ok("No unsaved item changes.".to_string());
    }

    for key in keys.clone() {
        if editor.documents.contains_key(&key) {
            save_document_by_key(editor, &key)?;
        }
    }
    Ok(format!("Saved {} dirty item documents.", keys.len()))
}

fn save_document_by_key(editor: &mut EditorState, key: &str) -> Result<String, String> {
    validate_all_documents(editor)?;
    if editor.has_duplicate_ids() {
        return Err("Resolve duplicate item ids before saving.".to_string());
    }

    let item_ids = editor.current_item_ids();
    let document = editor
        .documents
        .get(key)
        .cloned()
        .ok_or_else(|| format!("item draft {key} is no longer loaded"))?;
    if document.diagnostics.iter().any(|diagnostic| {
        matches!(
            diagnostic.severity,
            game_data::ItemEditDiagnosticSeverity::Error
        )
    }) {
        return Err(format!(
            "item {} has validation errors and cannot be saved",
            document.definition.id
        ));
    }

    let result = editor
        .service
        .save_item_definition(document.original_id, &document.definition, item_ids)
        .map_err(|error| error.to_string())?;

    let next_key = format!("{}.json", document.definition.id);
    let mut next_document = document.clone();
    next_document.document_key = next_key.clone();
    next_document.original_id = Some(document.definition.id);
    next_document.file_name = next_key.clone();
    next_document.relative_path = format!("items/{}.json", document.definition.id);
    next_document.dirty = false;
    next_document.last_save_message = Some(result.summary.details.join("; "));
    editor.documents.remove(key);
    editor.documents.insert(next_key.clone(), next_document);
    editor.selected_document_key = Some(next_key);
    validate_all_documents(editor)?;
    info!("item editor saved item: item_id={}", document.definition.id);
    Ok(format!("Saved item {}.", document.definition.id))
}

fn delete_current_document(editor: &mut EditorState) -> Result<String, String> {
    let key = editor
        .selected_document_key
        .clone()
        .ok_or_else(|| "No item selected.".to_string())?;
    let document = editor
        .documents
        .get(&key)
        .cloned()
        .ok_or_else(|| "Selected item is no longer loaded.".to_string())?;

    if let Some(original_id) = document.original_id {
        let delete_id = if document.dirty && document.definition.id != original_id {
            original_id
        } else {
            document.definition.id
        };
        editor
            .service
            .delete_item_definition(delete_id)
            .map_err(|error| error.to_string())?;
    }

    editor.documents.remove(&key);
    editor.ensure_selection();
    validate_all_documents(editor)?;
    Ok(format!("Deleted item draft {}.", document.definition.id))
}

fn empty_placeholder(value: &str) -> &str {
    if value.trim().is_empty() {
        "-"
    } else {
        value
    }
}
