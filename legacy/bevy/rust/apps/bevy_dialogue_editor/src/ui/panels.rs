use std::collections::BTreeMap;

use bevy_egui::egui;
use game_data::{DialogueAction, DialogueNode, DialogueOption};
use serde_json::Value;

use crate::commands::DialogueEditorCommand;
use crate::graph::{DialogueConnectionView, DialogueFlowView};
use crate::state::{DialogueEditorCatalogs, EditorState};

pub(crate) const LIST_PANEL_WIDTH: f32 = 360.0;
pub(crate) const DETAIL_PANEL_WIDTH: f32 = 500.0;

pub(crate) fn render_top_bar(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &DialogueEditorCatalogs,
    selected_view: Option<&DialogueFlowView>,
    commands: &mut bevy::ecs::message::MessageWriter<DialogueEditorCommand>,
) {
    let selected_summary = editor
        .selected_dialogue_id
        .as_deref()
        .and_then(|dialogue_id| catalogs.dialogue(dialogue_id))
        .map(|dialogue| {
            format!(
                "{} nodes / {} connections",
                dialogue.nodes.len(),
                selected_view
                    .map(|view| view.connection_count)
                    .unwrap_or(dialogue.connections.len())
            )
        })
        .unwrap_or_else(|| "No dialogue selected".to_string());

    ui.horizontal(|ui| {
        ui.heading("对话查看器");
        ui.separator();
        ui.label(format!("对话 {}", catalogs.definitions.len()));
        ui.separator();
        ui.label(selected_summary);
        ui.separator();
        ui.small(&editor.status);

        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if ui.button("重新加载").clicked() {
                commands.write(DialogueEditorCommand::Reload);
            }
        });
    });
}

pub(crate) fn render_dialogue_list_panel(
    ui: &mut egui::Ui,
    editor: &mut EditorState,
    catalogs: &DialogueEditorCatalogs,
) {
    ui.horizontal(|ui| {
        ui.label("搜索");
        ui.add(
            egui::TextEdit::singleline(&mut editor.search_text)
                .hint_text("dialog_id / 节点 / speaker / text / next / action")
                .desired_width(f32::INFINITY),
        );
    });
    ui.separator();

    let needle = editor.search_text.trim().to_lowercase();
    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            for entry in &catalogs.search_entries {
                if !needle.is_empty() && !entry.search_blob.contains(&needle) {
                    continue;
                }

                let selected =
                    editor.selected_dialogue_id.as_deref() == Some(entry.dialogue_id.as_str());
                let label = if entry.summary.trim().is_empty() {
                    entry.dialogue_id.clone()
                } else {
                    format!("{} · {}", entry.dialogue_id, entry.summary)
                };
                if ui
                    .add(
                        egui::Button::selectable(selected, label.as_str())
                            .truncate()
                            .min_size(egui::vec2(ui.available_width(), 0.0)),
                    )
                    .on_hover_text(label.as_str())
                    .clicked()
                {
                    if editor.select_dialogue(&entry.dialogue_id, catalogs) {
                        editor.status = format!("Selected dialogue {}.", entry.dialogue_id);
                    }
                }
            }
        });
}

pub(crate) fn render_dialogue_detail_panel(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &DialogueEditorCatalogs,
    selected_view: Option<&DialogueFlowView>,
) {
    let Some(dialogue_id) = editor.selected_dialogue_id.as_deref() else {
        ui.label("未选择对话。");
        return;
    };
    let Some(dialogue) = catalogs.dialogue(dialogue_id) else {
        ui.label("当前选中的对话不存在。");
        return;
    };
    let Some(view) = selected_view else {
        ui.label("当前对话图视图不可用。");
        return;
    };

    let selected_node = editor
        .selected_node_id
        .as_deref()
        .and_then(|node_id| dialogue.nodes.iter().find(|node| node.id == node_id));

    ui.heading(dialogue.dialog_id.as_str());

    if let Some(node) = selected_node {
        ui.add_space(8.0);
        ui.collapsing("当前节点", |ui| {
            render_node_fields(ui, node);
        });
    }

    ui.add_space(8.0);
    ui.collapsing("概览", |ui| {
        ui.label(format!("dialog_id: {}", dialogue.dialog_id));
        ui.label(format!("relative_path: {}", view.relative_path));
        ui.label(format!("node_count: {}", dialogue.nodes.len()));
        ui.label(format!("connection_count: {}", view.connection_count));
        ui.label(format!(
            "start_node_id: {}",
            view.start_node_id.as_deref().unwrap_or("-")
        ));
        render_json_extras(ui, "dialogue.extra", &dialogue.extra);
    });

    ui.add_space(8.0);
    ui.collapsing("流程摘要", |ui| {
        ui.label(format!("start_node_count: {}", view.start_node_count));
        ui.label(format!("end_node_count: {}", view.end_node_count));
        ui.label(format!("choice_branch_count: {}", view.choice_branch_count));
        ui.label(format!(
            "condition_branch_count: {}",
            view.condition_branch_count
        ));

        if view.node_type_counts.is_empty() {
            ui.label("node_type_counts: none");
        } else {
            for (node_type, count) in &view.node_type_counts {
                ui.label(format!("type[{node_type}] = {count}"));
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing(format!("节点 ({})", dialogue.nodes.len()), |ui| {
        let mut nodes = dialogue.nodes.iter().collect::<Vec<_>>();
        nodes.sort_by(|left, right| {
            let left_rank = usize::from(view.start_node_id.as_deref() != Some(left.id.as_str()));
            let right_rank = usize::from(view.start_node_id.as_deref() != Some(right.id.as_str()));
            left_rank.cmp(&right_rank).then(left.id.cmp(&right.id))
        });

        for node in nodes {
            render_node_section(
                ui,
                node,
                editor.selected_node_id.as_deref() == Some(node.id.as_str()),
            );
            ui.add_space(6.0);
        }
    });

    ui.add_space(8.0);
    ui.collapsing(format!("连接 ({})", view.connections.len()), |ui| {
        if view.connections.is_empty() {
            ui.label("无连接。");
            return;
        }

        egui::Grid::new("dialogue_connections_grid")
            .striped(true)
            .min_col_width(72.0)
            .show(ui, |ui| {
                ui.strong("from");
                ui.strong("from_port");
                ui.strong("to");
                ui.strong("to_port");
                ui.end_row();

                for (index, connection) in view.connections.iter().enumerate() {
                    ui.label(connection.from.as_str());
                    ui.label(connection.from_port.to_string());
                    ui.label(connection.to.as_str());
                    ui.label(connection.to_port.to_string());
                    ui.end_row();

                    render_connection_extra(ui, index, connection);
                }
            });
    });
}

fn render_node_section(ui: &mut egui::Ui, node: &DialogueNode, is_selected: bool) {
    let prefix = if is_selected { "[当前] " } else { "" };
    let title = if node.title.trim().is_empty() {
        format!("{prefix}{}", node.id)
    } else {
        format!("{prefix}{} · {}", node.title, node.id)
    };

    ui.collapsing(title, |ui| {
        render_node_fields(ui, node);
    });
}

fn render_node_fields(ui: &mut egui::Ui, node: &DialogueNode) {
    ui.label(format!("id: {}", node.id));
    ui.label(format!("type: {}", text_or_placeholder(&node.node_type)));
    ui.label(format!("title: {}", text_or_placeholder(&node.title)));
    ui.label(format!("speaker: {}", text_or_placeholder(&node.speaker)));
    ui.label(format!("text: {}", text_or_placeholder(&node.text)));
    ui.label(format!("portrait: {}", text_or_placeholder(&node.portrait)));
    ui.label(format!("is_start: {}", node.is_start));
    ui.label(format!("next: {}", text_or_placeholder(&node.next)));
    ui.label(format!(
        "condition: {}",
        text_or_placeholder(&node.condition)
    ));
    ui.label(format!(
        "true_next: {}",
        text_or_placeholder(&node.true_next)
    ));
    ui.label(format!(
        "false_next: {}",
        text_or_placeholder(&node.false_next)
    ));
    ui.label(format!("end_type: {}", text_or_placeholder(&node.end_type)));

    ui.collapsing(format!("options ({})", node.options.len()), |ui| {
        if node.options.is_empty() {
            ui.label("无 options。");
        } else {
            for (index, option) in node.options.iter().enumerate() {
                render_option_section(ui, index, option);
            }
        }
    });

    ui.collapsing(format!("actions ({})", node.actions.len()), |ui| {
        if node.actions.is_empty() {
            ui.label("无 actions。");
        } else {
            for (index, action) in node.actions.iter().enumerate() {
                render_action_section(ui, index, action);
            }
        }
    });

    let position_label = node
        .position
        .as_ref()
        .map(|position| format!("({}, {})", position.x, position.y))
        .unwrap_or_else(|| "-".to_string());
    ui.label(format!("position: {position_label}"));
    render_json_extras(ui, "node.extra", &node.extra);
}

fn render_option_section(ui: &mut egui::Ui, index: usize, option: &DialogueOption) {
    ui.collapsing(format!("option[{index}]"), |ui| {
        ui.label(format!("text: {}", text_or_placeholder(&option.text)));
        ui.label(format!("next: {}", text_or_placeholder(&option.next)));
        render_json_extras(ui, "option.extra", &option.extra);
    });
}

fn render_action_section(ui: &mut egui::Ui, index: usize, action: &DialogueAction) {
    ui.collapsing(format!("action[{index}]"), |ui| {
        ui.label(format!(
            "type: {}",
            text_or_placeholder(&action.action_type)
        ));
        render_json_extras(ui, "action.extra", &action.extra);
    });
}

fn render_connection_extra(ui: &mut egui::Ui, index: usize, connection: &DialogueConnectionView) {
    render_json_extras(ui, &format!("connection[{index}].extra"), &connection.extra);
}

fn render_json_extras(ui: &mut egui::Ui, label: &str, extra: &BTreeMap<String, Value>) {
    if extra.is_empty() {
        return;
    }

    ui.collapsing(label, |ui| {
        let mut pretty = serde_json::to_string_pretty(extra).unwrap_or_else(|_| "{}".to_string());
        let desired_rows = pretty.lines().count().max(4);
        ui.add(
            egui::TextEdit::multiline(&mut pretty)
                .font(egui::TextStyle::Monospace)
                .desired_width(f32::INFINITY)
                .desired_rows(desired_rows)
                .interactive(false),
        );
    });
}

fn text_or_placeholder(value: &str) -> String {
    if value.trim().is_empty() {
        "-".to_string()
    } else {
        value.to_string()
    }
}
