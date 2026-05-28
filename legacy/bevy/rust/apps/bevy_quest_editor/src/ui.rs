mod panels;

use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_editor::render_read_only_flow_graph;

use crate::commands::QuestEditorCommand;
use crate::graph::build_quest_flow_view;
use crate::state::{EditorState, QuestEditorCatalogs};

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    catalogs: Res<QuestEditorCatalogs>,
    mut commands: MessageWriter<QuestEditorCommand>,
) {
    let Ok(ctx) = contexts.ctx_mut() else {
        warn!("quest editor ui skipped: primary egui context is missing");
        return;
    };
    editor.ensure_selection(&catalogs);
    let topbar_view = editor.selected_quest_id.as_deref().and_then(|quest_id| {
        catalogs.quest(quest_id).map(|quest| {
            build_quest_flow_view(
                quest,
                catalogs
                    .relative_path(quest_id)
                    .unwrap_or("data/quests/<unknown>.json"),
            )
        })
    });

    egui::TopBottomPanel::top("quest_editor_topbar").show(ctx, |ui| {
        panels::render_top_bar(ui, &editor, &catalogs, topbar_view.as_ref(), &mut commands);
    });

    egui::SidePanel::left("quest_list")
        .default_width(panels::LIST_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            panels::render_quest_list_panel(ui, &mut editor, &catalogs);
        });

    let selected_view = editor.selected_quest_id.as_deref().and_then(|quest_id| {
        catalogs.quest(quest_id).map(|quest| {
            build_quest_flow_view(
                quest,
                catalogs
                    .relative_path(quest_id)
                    .unwrap_or("data/quests/<unknown>.json"),
            )
        })
    });

    egui::SidePanel::right("quest_detail")
        .default_width(panels::DETAIL_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    if let Some(action) = panels::render_quest_detail_panel(
                        ui,
                        &editor,
                        &catalogs,
                        selected_view.as_ref(),
                    ) {
                        match action {
                            panels::QuestDetailAction::OpenDialogue(dialogue_id) => {
                                commands.write(QuestEditorCommand::OpenDialogue(dialogue_id));
                            }
                        }
                    }
                });
        });

    egui::CentralPanel::default().show(ctx, |ui| {
        if let Some(view) = selected_view.as_ref() {
            let selected_node_id = editor.selected_node_id.clone();
            let response = render_read_only_flow_graph(
                ui,
                &mut editor.graph_canvas_state,
                &view.graph_model,
                selected_node_id.as_deref(),
            );
            if let Some(node_id) = response.clicked_node_id {
                if editor.select_node(&node_id, &catalogs) {
                    editor.status = format!("Selected node {node_id}.");
                    ctx.request_repaint();
                }
            }
        } else {
            ui.centered_and_justified(|ui| {
                ui.label("未选择任务。");
            });
        }
    });
}
