use std::collections::BTreeMap;

use bevy_egui::egui;
use game_data::QuestNode;
use serde_json::Value;

use crate::commands::QuestEditorCommand;
use crate::graph::{QuestConnectionView, QuestFlowView};
use crate::state::{display_quest_title, EditorState, QuestEditorCatalogs};

pub(crate) const LIST_PANEL_WIDTH: f32 = 340.0;
pub(crate) const DETAIL_PANEL_WIDTH: f32 = 520.0;

pub(crate) enum QuestDetailAction {
    OpenDialogue(String),
}

pub(crate) fn render_top_bar(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &QuestEditorCatalogs,
    selected_view: Option<&QuestFlowView>,
    commands: &mut bevy::ecs::message::MessageWriter<QuestEditorCommand>,
) {
    let selected_summary = editor
        .selected_quest_id
        .as_deref()
        .and_then(|quest_id| catalogs.quest(quest_id))
        .map(|quest| {
            format!(
                "{} nodes / {} connections",
                quest.flow.nodes.len(),
                selected_view
                    .map(|view| view.connection_count)
                    .unwrap_or(quest.flow.connections.len())
            )
        })
        .unwrap_or_else(|| "No quest selected".to_string());

    ui.horizontal(|ui| {
        ui.heading("任务查看器");
        ui.separator();
        ui.label(format!("任务 {}", catalogs.definitions.len()));
        ui.separator();
        ui.label(selected_summary);
        ui.separator();
        ui.small(&editor.status);

        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if ui.button("重新加载").clicked() {
                commands.write(QuestEditorCommand::Reload);
            }
        });
    });
}

pub(crate) fn render_quest_list_panel(
    ui: &mut egui::Ui,
    editor: &mut EditorState,
    catalogs: &QuestEditorCatalogs,
) {
    ui.horizontal(|ui| {
        ui.label("搜索");
        ui.add(
            egui::TextEdit::singleline(&mut editor.search_text)
                .hint_text("quest_id / 标题 / 节点 / dialog_id / target")
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

                let selected = editor.selected_quest_id.as_deref() == Some(entry.quest_id.as_str());
                let label = if entry.title == entry.quest_id {
                    format!("{} · {}", entry.quest_id, entry.summary)
                } else {
                    format!("{} · {} · {}", entry.title, entry.quest_id, entry.summary)
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
                    if editor.select_quest(&entry.quest_id, catalogs) {
                        editor.status = format!("Selected quest {}.", entry.quest_id);
                    }
                }
            }
        });
}

pub(crate) fn render_quest_detail_panel(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &QuestEditorCatalogs,
    selected_view: Option<&QuestFlowView>,
) -> Option<QuestDetailAction> {
    let Some(quest_id) = editor.selected_quest_id.as_deref() else {
        ui.label("未选择任务。");
        return None;
    };
    let Some(quest) = catalogs.quest(quest_id) else {
        ui.label("当前选中的任务不存在。");
        return None;
    };
    let Some(view) = selected_view else {
        ui.label("当前任务图视图不可用。");
        return None;
    };

    let mut action = None;
    let heading = display_quest_title(quest);
    if heading == quest.quest_id {
        ui.heading(heading);
    } else {
        ui.heading(format!("{heading} · {}", quest.quest_id));
    }

    if let Some(node) = editor
        .selected_node_id
        .as_deref()
        .and_then(|node_id| quest.flow.nodes.get(node_id))
    {
        ui.add_space(8.0);
        ui.collapsing("当前节点", |ui| {
            render_node_fields(ui, node, &mut action);
        });
    }

    ui.add_space(8.0);
    ui.collapsing("概览", |ui| {
        ui.label(format!("quest_id: {}", quest.quest_id));
        ui.label(format!("title: {}", text_or_placeholder(&quest.title)));
        ui.label(format!(
            "description: {}",
            text_or_placeholder(&quest.description)
        ));
        ui.label(format!("relative_path: {}", view.relative_path));
        ui.label(format!("time_limit: {}", quest.time_limit));
        render_json_extras(ui, "quest.extra", &quest.extra);
    });

    ui.add_space(8.0);
    ui.collapsing(
        format!("前置任务 ({})", quest.prerequisites.len()),
        |ui| {
            if quest.prerequisites.is_empty() {
                ui.label("无前置任务。");
            } else {
                for prerequisite in &quest.prerequisites {
                    ui.label(prerequisite);
                }
            }
        },
    );

    ui.add_space(8.0);
    ui.collapsing("流程摘要", |ui| {
        ui.label(format!("start_node_id: {}", quest.flow.start_node_id));
        ui.label(format!("node_count: {}", quest.flow.nodes.len()));
        ui.label(format!("connection_count: {}", view.connection_count));
        if view.node_type_counts.is_empty() {
            ui.label("node_type_counts: none");
        } else {
            for (node_type, count) in &view.node_type_counts {
                ui.label(format!("type[{node_type}] = {count}"));
            }
        }
        render_json_extras(ui, "flow.extra", &quest.flow.extra);
    });

    ui.add_space(8.0);
    ui.collapsing(format!("节点 ({})", quest.flow.nodes.len()), |ui| {
        let mut nodes = quest.flow.nodes.values().collect::<Vec<_>>();
        nodes.sort_by(|left, right| {
            let left_rank = usize::from(left.id != quest.flow.start_node_id);
            let right_rank = usize::from(right.id != quest.flow.start_node_id);
            left_rank.cmp(&right_rank).then(left.id.cmp(&right.id))
        });

        for node in nodes {
            render_node_section(
                ui,
                node,
                editor.selected_node_id.as_deref() == Some(node.id.as_str()),
                &mut action,
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

        egui::Grid::new("quest_connections_grid")
            .striped(true)
            .min_col_width(80.0)
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

    action
}

fn render_node_section(
    ui: &mut egui::Ui,
    node: &QuestNode,
    is_selected: bool,
    action: &mut Option<QuestDetailAction>,
) {
    let prefix = if is_selected { "[当前] " } else { "" };
    let title = if node.title.trim().is_empty() {
        format!("{prefix}{}", node.id)
    } else {
        format!("{prefix}{} · {}", node.title, node.id)
    };

    ui.collapsing(title, |ui| {
        render_node_fields(ui, node, action);
    });
}

fn render_node_fields(ui: &mut egui::Ui, node: &QuestNode, action: &mut Option<QuestDetailAction>) {
    ui.label(format!("id: {}", node.id));
    ui.label(format!("type: {}", text_or_placeholder(&node.node_type)));
    ui.label(format!("title: {}", text_or_placeholder(&node.title)));
    ui.label(format!(
        "description: {}",
        text_or_placeholder(&node.description)
    ));
    ui.label(format!(
        "objective_type: {}",
        text_or_placeholder(&node.objective_type)
    ));
    ui.label(format!("target: {}", text_or_placeholder(&node.target)));
    ui.label(format!(
        "item_id: {}",
        node.item_id
            .map(|value| value.to_string())
            .unwrap_or_else(|| "-".to_string())
    ));
    ui.label(format!("count: {}", node.count));

    let dialog_id = node.dialog_id.trim();
    if dialog_id.is_empty() {
        ui.label("dialog_id: -");
    } else {
        ui.horizontal(|ui| {
            ui.label("dialog_id:");
            if ui.link(dialog_id).clicked() {
                *action = Some(QuestDetailAction::OpenDialogue(dialog_id.to_string()));
            }
        });
    }

    ui.collapsing(format!("options ({})", node.options.len()), |ui| {
        if node.options.is_empty() {
            ui.label("无 options。");
        } else {
            for (index, option) in node.options.iter().enumerate() {
                ui.label(format!(
                    "[{index}] text={} next={}",
                    text_or_placeholder(&option.text),
                    text_or_placeholder(&option.next)
                ));
                render_json_extras(ui, &format!("option[{index}].extra"), &option.extra);
            }
        }
    });

    ui.collapsing(
        format!("rewards.items ({})", node.rewards.items.len()),
        |ui| {
            if node.rewards.items.is_empty() {
                ui.label("无奖励物品。");
            } else {
                for (index, item) in node.rewards.items.iter().enumerate() {
                    ui.label(format!("[{index}] id={} count={}", item.id, item.count));
                    render_json_extras(ui, &format!("reward_item[{index}].extra"), &item.extra);
                }
            }
        },
    );

    ui.label(format!("rewards.experience: {}", node.rewards.experience));
    ui.label(format!(
        "rewards.skill_points: {}",
        node.rewards.skill_points
    ));
    ui.label(format!(
        "rewards.unlock_location: {}",
        text_or_placeholder(&node.rewards.unlock_location)
    ));
    ui.label(format!(
        "rewards.unlock_recipes: {}",
        if node.rewards.unlock_recipes.is_empty() {
            "-".to_string()
        } else {
            node.rewards.unlock_recipes.join(", ")
        }
    ));
    ui.label(format!(
        "rewards.title: {}",
        text_or_placeholder(&node.rewards.title)
    ));
    render_json_extras(ui, "rewards.extra", &node.rewards.extra);

    let position_label = node
        .position
        .as_ref()
        .map(|position| format!("({}, {})", position.x, position.y))
        .unwrap_or_else(|| "-".to_string());
    ui.label(format!("position: {position_label}"));
    render_json_extras(ui, "node.extra", &node.extra);
}

fn render_connection_extra(ui: &mut egui::Ui, index: usize, connection: &QuestConnectionView) {
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
