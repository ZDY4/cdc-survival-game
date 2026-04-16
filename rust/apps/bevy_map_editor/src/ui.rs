pub(crate) mod actions;
pub(crate) mod panels;

use bevy::diagnostic::DiagnosticsStore;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_editor::ai_chat::{
    persist_ai_chat_settings, poll_generation_job, render_ai_chat_panel, render_ai_settings_window,
    start_connection_test, AiChatUiAction,
};

use crate::camera::{CAMERA_PAN_SPEED_MULTIPLIER_MAX, CAMERA_PAN_SPEED_MULTIPLIER_MIN};
use crate::commands::MapEditorCommand;
use crate::map_ai::{
    assistant_summary_text, render_map_ai_result, success_status_text, MapAiUiAction,
};
use crate::state::{map_library_item_label, EditorState, EditorUiState, LibraryView, MapAiState, MapAiWorkerState, OrbitCameraState};
use panels::{current_fps_label, draw_diagnostic, editor_top_summary};

pub(crate) fn loading_ui_system(mut contexts: EguiContexts) {
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };
    egui::CentralPanel::default().show(ctx, |ui| {
        ui.vertical_centered(|ui| {
            ui.add_space(ui.available_height() / 2.0 - 40.0);
            ui.heading("正在加载地图与 overworld 数据…");
            ui.add_space(16.0);
            ui.spinner();
        });
    });
}

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    mut ui_state: ResMut<EditorUiState>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    mut ai: ResMut<MapAiState>,
    mut worker: ResMut<MapAiWorkerState>,
    diagnostics: Res<DiagnosticsStore>,
    mut requests: MessageWriter<MapEditorCommand>,
) {
    let ctx = contexts
        .ctx_mut()
        .expect("primary egui context should exist for the map editor");
    let top_summary = editor_top_summary(&editor);

    egui::TopBottomPanel::top("top").show(ctx, |ui| {
        egui::MenuBar::new().ui(ui, |ui| {
            ui.menu_button("File", |ui| {
                if ui.button("Reload").clicked() {
                    requests.write(MapEditorCommand::Reload);
                    ui.close();
                }
                if ui.button("Save Current").clicked() {
                    requests.write(MapEditorCommand::SaveCurrent);
                    ui.close();
                }
                if ui.button("Validate Current").clicked() {
                    requests.write(MapEditorCommand::ValidateCurrent);
                    ui.close();
                }
            });
            ui.menu_button("View", |ui| {
                if ui
                    .checkbox(&mut ui_state.show_fps_overlay, "Show FPS")
                    .clicked()
                {
                    editor.status = format!(
                        "FPS overlay {}.",
                        if ui_state.show_fps_overlay {
                            "enabled"
                        } else {
                            "disabled"
                        }
                    );
                }
                if ui.button("Toggle Top View [T]").clicked() {
                    orbit_camera.is_top_down = !orbit_camera.is_top_down;
                    orbit_camera.yaw_offset = 0.0;
                    editor.status = if orbit_camera.is_top_down {
                        "Camera switched to top-down view.".to_string()
                    } else {
                        "Camera restored to perspective view.".to_string()
                    };
                    ui.close();
                }
                if ui.button("Reset Camera").clicked() {
                    orbit_camera.reset_to_default_view();
                    editor.status = "Camera reset.".to_string();
                    ui.close();
                }
            });
            ui.menu_button("Camera", |ui| {
                ui.label("Pan Speed");
                if ui
                    .add(
                        egui::Slider::new(
                            &mut ui_state.camera_pan_speed_multiplier,
                            CAMERA_PAN_SPEED_MULTIPLIER_MIN..=CAMERA_PAN_SPEED_MULTIPLIER_MAX,
                        )
                        .logarithmic(true)
                        .suffix("x"),
                    )
                    .changed()
                {
                    editor.status = format!(
                        "Camera pan speed set to {:.2}x.",
                        ui_state.camera_pan_speed_multiplier
                    );
                }
                ui.separator();
                ui.label("Middle mouse drag: pan camera");
                ui.label("T: toggle top-down");
                ui.label("Q / E: temporary yaw offset");
            });
            ui.menu_button("Settings", |ui| {
                if ui.button("Open AI Settings").clicked() {
                    ai.show_settings_window = true;
                    ui.close();
                }
            });

            ui.separator();
            ui.strong(top_summary);

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui_state.show_fps_overlay {
                    ui.strong(format!("FPS {}", current_fps_label(&diagnostics)));
                }
                ui.label(format!("Pan {:.2}x", ui_state.camera_pan_speed_multiplier));
            });
        });
    });

    egui::TopBottomPanel::bottom("bottom").show(ctx, |ui| {
        ui.horizontal_wrapped(|ui| {
            ui.label(&editor.status);
            if !ai.pending_status.is_empty() {
                ui.separator();
                ui.label(&ai.pending_status);
            }
            if !ai.provider_status.is_empty() {
                ui.separator();
                ui.label(&ai.provider_status);
            }
        });
    });

    egui::SidePanel::left("library")
        .default_width(320.0)
        .show(ctx, |ui| {
            let mut requested_view = editor.selected_view;
            ui.horizontal(|ui| {
                ui.selectable_value(&mut requested_view, LibraryView::Maps, "Maps");
                ui.selectable_value(&mut requested_view, LibraryView::Overworlds, "Overworlds");
            });
            if requested_view != editor.selected_view {
                requests.write(MapEditorCommand::SetSelectedView(requested_view));
            }
            ui.text_edit_singleline(&mut editor.search_text);
            let query = editor.search_text.trim().to_lowercase();
            egui::ScrollArea::vertical().show(ui, |ui| {
                ui.with_layout(egui::Layout::top_down_justified(egui::Align::LEFT), |ui| {
                    match editor.selected_view {
                        LibraryView::Maps => {
                            let items = editor
                                .maps
                                .iter()
                                .map(|(map_id, doc)| {
                                    (
                                        map_id.clone(),
                                        doc.definition.name.clone(),
                                        doc.definition.default_level,
                                        doc.dirty,
                                        !doc.diagnostics.is_empty(),
                                    )
                                })
                                .collect::<Vec<_>>();
                            for (map_id, name, default_level, dirty, has_diagnostics) in items {
                                if !query.is_empty()
                                    && !map_id.to_lowercase().contains(&query)
                                    && !name.to_lowercase().contains(&query)
                                {
                                    continue;
                                }
                                let label =
                                    map_library_item_label(&map_id, &name, dirty, has_diagnostics);
                                if ui
                                    .add_sized(
                                        [ui.available_width(), 0.0],
                                        egui::Button::new(label.as_str())
                                            .selected(
                                                editor.selected_map_id.as_deref()
                                                    == Some(map_id.as_str()),
                                            )
                                            .truncate(),
                                    )
                                    .on_hover_text(label)
                                    .clicked()
                                {
                                    let level = if editor.selected_map_id.as_deref()
                                        == Some(map_id.as_str())
                                    {
                                        editor.current_map_level
                                    } else {
                                        default_level
                                    };
                                    requests.write(MapEditorCommand::SelectMap {
                                        map_id: map_id.clone(),
                                        level,
                                    });
                                }
                            }
                        }
                        LibraryView::Overworlds => {
                            let items = editor
                                .overworld_library
                                .iter()
                                .map(|(id, def)| {
                                    (id.as_str().to_string(), def.locations.len(), def.clone())
                                })
                                .collect::<Vec<_>>();
                            for (overworld_id, locations, _definition) in items {
                                if !query.is_empty()
                                    && !overworld_id.to_lowercase().contains(&query)
                                {
                                    continue;
                                }
                                let label = format!("{overworld_id} · {locations} locations");
                                if ui
                                    .add_sized(
                                        [ui.available_width(), 0.0],
                                        egui::Button::new(label.as_str())
                                            .selected(
                                                editor.selected_overworld_id.as_deref()
                                                    == Some(overworld_id.as_str()),
                                            )
                                            .truncate(),
                                    )
                                    .on_hover_text(label)
                                    .clicked()
                                {
                                    requests.write(MapEditorCommand::SelectOverworld {
                                        overworld_id: overworld_id.clone(),
                                    });
                                }
                            }
                        }
                    }
                });
            });
        });

    egui::SidePanel::right("authoring")
        .default_width(430.0)
        .show(ctx, |ui| {
            match editor.selected_view {
                LibraryView::Maps => {
                    if let Some(selected_map_id) = editor.selected_map_id.clone() {
                        if let Some(doc) = editor.maps.get(&selected_map_id).cloned() {
                            if !doc.diagnostics.is_empty() {
                                ui.label("Current Map Diagnostics");
                                egui::ScrollArea::vertical()
                                    .max_height(160.0)
                                    .show(ui, |ui| {
                                        for diagnostic in &doc.diagnostics {
                                            draw_diagnostic(ui, diagnostic);
                                        }
                                    });
                            }
                        }
                    }
                }
                LibraryView::Overworlds => {
                    ui.heading("Overworld");
                    ui.label("Overworld is view-first in this phase. AI authoring targets maps.");
                }
            }

            ui.separator();
            ui.allocate_ui_with_layout(
                egui::vec2(ui.available_width(), ui.available_height().max(0.0)),
                egui::Layout::top_down(egui::Align::Min),
                |ui| {
                    let ai_actions = render_ai_chat_panel(
                        ui,
                        &mut ai,
                        worker.is_busy(),
                        "AI",
                        "Generate Proposal",
                        |ui, proposal, busy| render_map_ai_result(ui, &editor, proposal, busy),
                    );
                    for action in ai_actions {
                        match action {
                            AiChatUiAction::OpenSettings => ai.show_settings_window = true,
                            AiChatUiAction::SubmitPrompt => {
                                requests.write(MapEditorCommand::StartAiGeneration);
                            }
                            AiChatUiAction::Host(MapAiUiAction::ApplyProposal) => {
                                requests.write(MapEditorCommand::ApplyAiProposal);
                            }
                            AiChatUiAction::SaveSettings | AiChatUiAction::TestConnection => {}
                        }
                    }
                },
            );
        });

    for action in render_ai_settings_window(ctx, &mut ai, worker.is_busy()) {
        match action {
            AiChatUiAction::SaveSettings => {
                ai.provider_status =
                    persist_ai_chat_settings(&mut ai).unwrap_or_else(|error| error);
            }
            AiChatUiAction::TestConnection => start_connection_test(&mut ai, &mut worker),
            AiChatUiAction::OpenSettings
            | AiChatUiAction::SubmitPrompt
            | AiChatUiAction::Host(_) => {}
        }
    }

    if ui_state.show_fps_overlay {
        egui::Area::new("fps_overlay".into())
            .anchor(egui::Align2::RIGHT_TOP, egui::vec2(-14.0, 42.0))
            .order(egui::Order::Foreground)
            .show(ctx, |ui| {
                egui::Frame::popup(ui.style()).show(ui, |ui| {
                    ui.strong(format!("FPS {}", current_fps_label(&diagnostics)));
                });
            });
    }

    if let Some(hovered_cell) = ui_state.hovered_cell.as_ref() {
        if let Some(pointer_pos) = ctx.input(|input| input.pointer.hover_pos()) {
            egui::Area::new("hovered_cell_info".into())
                .fixed_pos(pointer_pos + egui::vec2(18.0, 18.0))
                .order(egui::Order::Tooltip)
                .show(ctx, |ui| {
                    egui::Frame::popup(ui.style()).show(ui, |ui| {
                        ui.style_mut().wrap_mode = Some(egui::TextWrapMode::Extend);
                        ui.strong(&hovered_cell.title);
                        for line in &hovered_cell.lines {
                            ui.label(line);
                        }
                    });
                });
        }
    }
}

pub(crate) fn poll_ai_worker_system(
    mut ai: ResMut<MapAiState>,
    mut worker: ResMut<MapAiWorkerState>,
) {
    poll_generation_job(
        &mut ai,
        &mut worker,
        assistant_summary_text,
        success_status_text,
    );
}
