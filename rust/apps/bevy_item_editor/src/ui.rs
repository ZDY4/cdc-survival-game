mod panels;

use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_editor::PreviewViewportRect;

use crate::commands::ItemEditorCommand;
use crate::preview::{PreviewCamera, PreviewState};
use crate::state::EditorState;

const DETAIL_PANEL_WIDTH: f32 = 500.0;

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    preview_state: Res<PreviewState>,
    mut preview_camera: Single<&mut game_editor::PreviewCameraController, With<PreviewCamera>>,
    mut commands: MessageWriter<ItemEditorCommand>,
) {
    let Ok(ctx) = contexts.ctx_mut() else {
        warn!("item editor ui skipped: primary egui context is missing");
        return;
    };
    editor.ensure_selection();

    egui::TopBottomPanel::top("item_editor_topbar").show(ctx, |ui| {
        panels::render_top_bar(ui, &editor, &mut commands);
    });

    egui::SidePanel::left("item_list")
        .default_width(panels::LIST_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            panels::render_item_list_panel(ui, &mut editor, &mut commands)
        });

    egui::SidePanel::right("item_details")
        .default_width(DETAIL_PANEL_WIDTH)
        .resizable(true)
        .show(ctx, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| {
                panels::render_detail_panel(ui, &editor, &preview_state);
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
            panels::render_preview_overlay(ui.ctx(), rect, &editor, &preview_state);
        });
}
