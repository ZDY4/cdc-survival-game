mod panels;

use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_bevy::MeshPickIndex;
use game_editor::PreviewViewportRect;

use crate::commands::ItemEditorCommand;
use crate::preview::{PreviewCamera, PreviewState};
use crate::state::EditorState;

const DETAIL_PANEL_WIDTH: f32 = 500.0;

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    preview_state: Res<PreviewState>,
    pick_index: Res<MeshPickIndex<String>>,
    mut preview_camera: Query<
        (
            &Camera,
            &GlobalTransform,
            &mut game_editor::PreviewCameraController,
        ),
        With<PreviewCamera>,
    >,
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

    let Ok((preview_camera_component, preview_camera_transform, mut preview_camera)) =
        preview_camera.single_mut()
    else {
        return;
    };

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
            let response = ui.allocate_rect(rect, egui::Sense::hover());
            if response.secondary_clicked() {
                editor.preview_context_model_path = picked_preview_model_asset(
                    ui.ctx(),
                    preview_camera_component,
                    preview_camera_transform,
                    &pick_index,
                );
            }
            let context_asset_path = editor.preview_context_model_path.clone();
            response.context_menu(|ui| {
                let Some(asset_path) = context_asset_path.as_deref() else {
                    ui.close();
                    return;
                };
                ui.label(asset_path);
                ui.separator();
                if ui.button("用 Blockbench 编辑").clicked() {
                    commands.write(ItemEditorCommand::OpenPreviewModelInBlockbench(
                        asset_path.to_string(),
                    ));
                    ui.close();
                }
                if ui.button("gltf viewer 中打开").clicked() {
                    commands.write(ItemEditorCommand::OpenPreviewModelInGltfViewer(
                        asset_path.to_string(),
                    ));
                    ui.close();
                }
                if ui.button("打开模型所在目录").clicked() {
                    commands.write(ItemEditorCommand::OpenPreviewModelDirectory(
                        asset_path.to_string(),
                    ));
                    ui.close();
                }
            });
            panels::render_preview_overlay(ui.ctx(), rect, &editor, &preview_state);
        });
}

fn picked_preview_model_asset(
    ctx: &egui::Context,
    camera: &Camera,
    camera_transform: &GlobalTransform,
    pick_index: &MeshPickIndex<String>,
) -> Option<String> {
    let cursor = ctx.pointer_latest_pos()?;
    let cursor = Vec2::new(cursor.x, cursor.y);
    let ray = camera.viewport_to_world(camera_transform, cursor).ok()?;
    pick_index.query_nearest(ray).map(|hit| hit.data)
}
