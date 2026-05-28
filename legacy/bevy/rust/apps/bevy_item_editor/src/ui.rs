mod panels;

use bevy::log::warn;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_bevy::{rust_asset_dir, MeshPickIndex};
use game_editor::{
    render_model_hierarchy_panel, render_model_preview_hud, ModelHierarchyPanelState,
    ModelHierarchySource, ModelPreviewHud, PreviewGroundVisibility, PreviewPivotVisibility,
    PreviewViewportRect,
};

use crate::commands::ItemEditorCommand;
use crate::preview::{PreviewCamera, PreviewState};
use crate::state::EditorState;

const DETAIL_PANEL_WIDTH: f32 = 500.0;

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    preview_state: Res<PreviewState>,
    pick_index: Res<MeshPickIndex<String>>,
    mut ground_visibility: ResMut<PreviewGroundVisibility>,
    mut pivot_visibility: ResMut<PreviewPivotVisibility>,
    mut hierarchy_panel: ResMut<ModelHierarchyPanelState>,
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

    egui::SidePanel::left("item_details")
        .default_width(DETAIL_PANEL_WIDTH)
        .width_range(280.0..=760.0)
        .resizable(true)
        .show(ctx, |ui| {
            ui.style_mut().wrap_mode = Some(egui::TextWrapMode::Wrap);
            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    ui.set_max_width(ui.available_width());
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
            let status = preview_status_for_hud(&preview_state);
            let hud_response = render_model_preview_hud(
                ui.ctx(),
                "item_preview_hud",
                rect,
                ModelPreviewHud {
                    title: if preview_state.item_label.trim().is_empty() {
                        "未选择物品"
                    } else {
                        preview_state.item_label.as_str()
                    },
                    size: preview_state.model_size,
                    status: status.as_deref(),
                    ground_visible: ground_visibility.visible,
                    pivot_visible: pivot_visibility.visible,
                },
                |ui| {
                    let mut hierarchy_visible = hierarchy_panel.visible;
                    if ui.checkbox(&mut hierarchy_visible, "层级树").changed() {
                        hierarchy_panel.visible = hierarchy_visible;
                    }
                },
            );
            if hud_response.toggle_ground {
                ground_visibility.toggle();
            }
            if hud_response.toggle_pivot {
                pivot_visibility.toggle();
            }
            let hierarchy_sources = preview_state
                .applied_asset_path
                .as_ref()
                .map(|path| vec![ModelHierarchySource::new("当前物品", path.clone())])
                .unwrap_or_default();
            let asset_root = rust_asset_dir();
            let hierarchy_response = render_model_hierarchy_panel(
                ui.ctx(),
                "item_model_hierarchy",
                rect,
                &mut hierarchy_panel,
                &asset_root,
                &hierarchy_sources,
            );
            preview_camera.block_pointer_input =
                ctx.is_using_pointer() || hud_response.hovered || hierarchy_response.hovered;
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

fn preview_status_for_hud(preview_state: &PreviewState) -> Option<String> {
    if matches!(
        preview_state.load_status,
        crate::preview::PreviewLoadStatus::Ready
    ) {
        None
    } else {
        Some(preview_state.load_status.label())
    }
}
