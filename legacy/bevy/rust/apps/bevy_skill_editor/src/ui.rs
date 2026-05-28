mod graph;
mod panels;

use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use crate::commands::SkillEditorCommand;
use crate::state::{EditorState, SkillEditorCatalogs};

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    catalogs: Res<SkillEditorCatalogs>,
    mut commands: MessageWriter<SkillEditorCommand>,
) {
    let Ok(ctx) = contexts.ctx_mut() else {
        warn!("skill editor ui skipped: primary egui context is missing");
        return;
    };
    editor.ensure_selection(&catalogs);

    egui::TopBottomPanel::top("skill_editor_topbar").show(ctx, |ui| {
        panels::render_top_bar(ui, &editor, &catalogs, &mut commands);
    });

    egui::SidePanel::left("skill_editor_left")
        .default_width(panels::LEFT_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            panels::render_left_panel(ui, &mut editor, &catalogs, &mut commands);
        });

    egui::SidePanel::right("skill_editor_detail")
        .default_width(panels::RIGHT_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| panels::render_detail_panel(ui, &editor, &catalogs));
        });

    egui::CentralPanel::default().show(ctx, |ui| {
        panels::render_tree_graph_panel(ui, &editor, &catalogs, &mut commands);
    });
}
