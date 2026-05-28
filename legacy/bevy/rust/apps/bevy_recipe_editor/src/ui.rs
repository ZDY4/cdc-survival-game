mod panels;

use crate::commands::RecipeEditorCommand;
use crate::state::{EditorState, RecipeEditorCatalogs};
use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    catalogs: Res<RecipeEditorCatalogs>,
    mut commands: MessageWriter<RecipeEditorCommand>,
) {
    let Ok(ctx) = contexts.ctx_mut() else {
        warn!("recipe editor ui skipped: primary egui context is missing");
        return;
    };
    editor.ensure_selection();

    egui::TopBottomPanel::top("recipe_editor_topbar").show(ctx, |ui| {
        panels::render_top_bar(ui, &editor, &mut commands);
    });

    egui::SidePanel::left("recipe_list")
        .default_width(panels::LIST_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            panels::render_recipe_list_panel(ui, &mut editor, &mut commands)
        });

    egui::CentralPanel::default().show(ctx, |ui| {
        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                if let Some(status) = panels::render_recipe_detail_panel(ui, &editor, &catalogs) {
                    editor.status = status;
                }
            });
    });
}
