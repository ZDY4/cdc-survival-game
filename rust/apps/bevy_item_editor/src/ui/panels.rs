use bevy_egui::egui;
use game_editor::selectable_list_row;

use crate::commands::ItemEditorCommand;
use crate::preview::PreviewState;
use crate::state::EditorState;

pub(crate) const LIST_PANEL_WIDTH: f32 = 280.0;

pub(crate) fn render_top_bar(
    ui: &mut egui::Ui,
    editor: &EditorState,
    commands: &mut bevy::ecs::message::MessageWriter<ItemEditorCommand>,
) {
    ui.horizontal(|ui| {
        ui.heading("物品编辑器");
        ui.separator();
        ui.label(format!("物品 {}", editor.workspace.len()));
        ui.separator();
        ui.small(format!("仓库 {}", editor.repo_root.display()));
        ui.separator();
        ui.small(&editor.status);

        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if ui.button("删除当前").clicked() {
                commands.write(ItemEditorCommand::DeleteCurrent);
            }
            if ui.button("保存全部脏草稿").clicked() {
                commands.write(ItemEditorCommand::SaveAllDirty);
            }
            if ui.button("保存当前").clicked() {
                commands.write(ItemEditorCommand::SaveCurrent);
            }
            if ui.button("校验当前").clicked() {
                commands.write(ItemEditorCommand::ValidateCurrent);
            }
            if ui.button("重新加载").clicked() {
                commands.write(ItemEditorCommand::Reload);
            }
        });
    });
}

pub(crate) fn render_item_list_panel(
    ui: &mut egui::Ui,
    editor: &mut EditorState,
    commands: &mut bevy::ecs::message::MessageWriter<ItemEditorCommand>,
) {
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
                .workspace
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

                let selected = editor.workspace.selected_document_key().map(String::as_str)
                    == Some(key.as_str());
                let suffix = match (dirty, has_diagnostics) {
                    (true, true) => " [dirty, diag]",
                    (true, false) => " [dirty]",
                    (false, true) => " [diag]",
                    (false, false) => "",
                };
                let display = format!("{label}{suffix}");
                if selectable_list_row(ui, selected, display.as_str())
                    .on_hover_text(display)
                    .clicked()
                {
                    commands.write(ItemEditorCommand::SelectDocument { key });
                }
            }
        });
}

pub(crate) fn render_detail_panel(
    ui: &mut egui::Ui,
    editor: &EditorState,
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
}

pub(crate) fn render_preview_overlay(
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

fn empty_placeholder(value: &str) -> &str {
    if value.trim().is_empty() {
        "-"
    } else {
        value
    }
}
