mod panels;

use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_editor::render_read_only_flow_graph;

use crate::commands::DialogueEditorCommand;
use crate::graph::build_dialogue_flow_view;
use crate::state::{DialogueEditorCatalogs, EditorState};

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    catalogs: Res<DialogueEditorCatalogs>,
    mut commands: MessageWriter<DialogueEditorCommand>,
) {
    let Ok(ctx) = contexts.ctx_mut() else {
        warn!("dialogue editor ui skipped: primary egui context is missing");
        return;
    };
    editor.ensure_selection(&catalogs);
    let topbar_view = editor
        .selected_dialogue_id
        .as_deref()
        .and_then(|dialogue_id| {
            catalogs.dialogue(dialogue_id).map(|dialogue| {
                build_dialogue_flow_view(
                    dialogue,
                    catalogs
                        .relative_path(dialogue_id)
                        .unwrap_or("data/dialogues/<unknown>.json"),
                )
            })
        });

    egui::TopBottomPanel::top("dialogue_editor_topbar").show(ctx, |ui| {
        panels::render_top_bar(ui, &editor, &catalogs, topbar_view.as_ref(), &mut commands);
    });

    egui::SidePanel::left("dialogue_list")
        .default_width(panels::LIST_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            panels::render_dialogue_list_panel(ui, &mut editor, &catalogs);
        });

    let selected_view = editor
        .selected_dialogue_id
        .as_deref()
        .and_then(|dialogue_id| {
            catalogs.dialogue(dialogue_id).map(|dialogue| {
                build_dialogue_flow_view(
                    dialogue,
                    catalogs
                        .relative_path(dialogue_id)
                        .unwrap_or("data/dialogues/<unknown>.json"),
                )
            })
        });

    egui::SidePanel::right("dialogue_detail")
        .default_width(panels::DETAIL_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    panels::render_dialogue_detail_panel(
                        ui,
                        &editor,
                        &catalogs,
                        selected_view.as_ref(),
                    );
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
                ui.label("未选择对话。");
            });
        }
    });
}
