use bevy::diagnostic::{DiagnosticsStore, FrameTimeDiagnosticsPlugin};
use bevy::log::{info, warn};
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use game_data::{
    load_map_library, load_overworld_library, MapEditDiagnostic, MapEditDiagnosticSeverity,
    OverworldId,
};
use game_editor::ai_chat::{
    persist_ai_chat_settings, poll_generation_job, render_ai_chat_panel, render_ai_settings_window,
    start_connection_test, AiChatUiAction,
};
use game_editor::{game_ui_font_bytes, GAME_UI_FONT_NAME};

use crate::camera::{CAMERA_PAN_SPEED_MULTIPLIER_MAX, CAMERA_PAN_SPEED_MULTIPLIER_MIN};
use crate::map_ai::{
    apply_prepared_proposal, assistant_summary_text, render_map_ai_result, start_map_ai_generation,
    success_status_text, MapAiUiAction,
};
use crate::scene::{map_focus_target, overworld_focus_target};
use crate::state::{
    build_working_maps, map_display_name, map_library_item_label, project_data_dir,
    validate_document, yes_no, EditorEguiFontState, EditorState, EditorUiState, LibraryView,
    MapAiState, MapAiWorkerState, OrbitCameraState,
};

pub(crate) fn configure_editor_egui_fonts_system(
    mut contexts: EguiContexts,
    mut font_state: ResMut<EditorEguiFontState>,
) {
    if font_state.initialized {
        return;
    }

    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    let mut fonts = egui::FontDefinitions::default();
    fonts.font_data.insert(
        GAME_UI_FONT_NAME.to_string(),
        egui::FontData::from_owned(game_ui_font_bytes().to_vec()).into(),
    );
    for family in [egui::FontFamily::Proportional, egui::FontFamily::Monospace] {
        fonts
            .families
            .entry(family)
            .or_default()
            .insert(0, GAME_UI_FONT_NAME.to_string());
    }
    ctx.set_fonts(fonts);
    font_state.initialized = true;
}

pub(crate) fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    mut ui_state: ResMut<EditorUiState>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    mut ai: ResMut<MapAiState>,
    mut worker: ResMut<MapAiWorkerState>,
    diagnostics: Res<DiagnosticsStore>,
) {
    let ctx = contexts
        .ctx_mut()
        .expect("primary egui context should exist for the map editor");
    let top_summary = editor_top_summary(&editor);

    egui::TopBottomPanel::top("top").show(ctx, |ui| {
        egui::MenuBar::new().ui(ui, |ui| {
            ui.menu_button("File", |ui| {
                if ui.button("Reload").clicked() {
                    ai.clear_result();
                    editor.status = reload_editor_content(&mut editor);
                    sync_camera_target_to_selected_view(&editor, &mut orbit_camera);
                    ui.close();
                }
                if ui.button("Save Current").clicked() {
                    editor.status = save_current_map(&mut editor).unwrap_or_else(|error| error);
                    sync_camera_target_to_selected_view(&editor, &mut orbit_camera);
                    ui.close();
                }
                if ui.button("Validate Current").clicked() {
                    editor.status =
                        refresh_current_map_diagnostics(&mut editor).unwrap_or_else(|error| error);
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
                ui.selectable_value(
                    &mut requested_view,
                    LibraryView::Overworlds,
                    "Overworlds",
                );
            });
            if requested_view != editor.selected_view {
                editor.set_selected_view(requested_view);
                sync_camera_target_to_selected_view(&editor, &mut orbit_camera);
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
                                    let level =
                                        if editor.selected_map_id.as_deref() == Some(map_id.as_str())
                                        {
                                            editor.current_map_level
                                        } else {
                                            default_level
                                        };
                                    editor.update_map_selection(map_id.clone(), level);
                                    sync_camera_target_to_selected_view(
                                        &editor,
                                        &mut orbit_camera,
                                    );
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
                            for (overworld_id, locations, definition) in items {
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
                                    editor.update_overworld_selection(overworld_id.clone());
                                    orbit_camera.target = overworld_focus_target(&definition);
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
                                start_map_ai_generation(&editor, &mut ai, &mut worker);
                            }
                            AiChatUiAction::Host(MapAiUiAction::ApplyProposal) => {
                                if let Some(proposal) = ai.result.as_ref() {
                                    match apply_prepared_proposal(&mut editor, proposal) {
                                        Ok(status) => {
                                            editor.status = status;
                                            sync_camera_target_to_selected_view(
                                                &editor,
                                                &mut orbit_camera,
                                            );
                                        }
                                        Err(error) => {
                                            editor.status = error;
                                        }
                                    }
                                }
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

fn editor_top_summary(editor: &EditorState) -> String {
    match editor.selected_view {
        LibraryView::Maps => {
            let Some(selected_map_id) = editor.selected_map_id.as_ref() else {
                return "Map: none".to_string();
            };
            let Some(doc) = editor.maps.get(selected_map_id) else {
                return format!("Map: {} (missing)", map_display_name(selected_map_id));
            };
            let diagnostic_count = doc.diagnostics.len();
            format!(
                "Map {} · {} x {} · levels {} · objects {} · dirty {} · diagnostics {}",
                map_display_name(doc.definition.id.as_str()),
                doc.definition.size.width,
                doc.definition.size.height,
                doc.definition.levels.len(),
                doc.definition.objects.len(),
                yes_no(doc.dirty),
                diagnostic_count
            )
        }
        LibraryView::Overworlds => {
            let Some(selected_overworld_id) = editor.selected_overworld_id.as_ref() else {
                return "Overworld: none".to_string();
            };
            let Some(definition) = editor
                .overworld_library
                .get(&OverworldId(selected_overworld_id.clone()))
            else {
                return format!("Overworld {} (missing)", selected_overworld_id);
            };
            format!(
                "Overworld {} · {} x {} · locations {}",
                definition.id.as_str(),
                definition.size.width,
                definition.size.height,
                definition.locations.len()
            )
        }
    }
}

fn reload_editor_content(editor: &mut EditorState) -> String {
    if editor.maps.values().any(|document| document.dirty) {
        warn!("map editor reload blocked: dirty drafts exist");
        return "Save or discard dirty map drafts before reloading content.".to_string();
    }

    let maps_dir = project_data_dir("maps");
    let overworld_dir = project_data_dir("overworld");
    match (
        load_map_library(&maps_dir),
        load_overworld_library(&overworld_dir),
    ) {
        (Ok(map_library), Ok(overworld_library)) => {
            let previous_selected_map = editor.selected_map_id.clone();
            let previous_selected_overworld = editor.selected_overworld_id.clone();
            editor.maps = build_working_maps(&editor.map_service, &map_library);
            editor.overworld_library = overworld_library;
            editor.restore_selection_after_reload(
                previous_selected_map,
                previous_selected_overworld,
            );
            info!(
                "map editor reloaded content: maps={}, overworlds={}",
                editor.maps.len(),
                editor.overworld_library.len()
            );
            format!(
                "Reloaded {} maps and {} overworld documents.",
                editor.maps.len(),
                editor.overworld_library.len()
            )
        }
        (Err(map_error), Ok(_)) => {
            warn!("map editor reload failed for maps: {map_error}");
            format!("Failed to reload maps: {map_error}")
        }
        (Ok(_), Err(overworld_error)) => {
            warn!("map editor reload failed for overworlds: {overworld_error}");
            format!("Failed to reload overworlds: {overworld_error}")
        }
        (Err(map_error), Err(overworld_error)) => {
            warn!(
                "map editor reload failed: maps={}, overworlds={}",
                map_error, overworld_error
            );
            format!("Failed to reload content. maps={map_error}; overworld={overworld_error}")
        }
    }
}

fn refresh_current_map_diagnostics(editor: &mut EditorState) -> Result<String, String> {
    let selected_map_id = editor
        .selected_map_id
        .clone()
        .ok_or_else(|| "No map selected.".to_string())?;
    let document = editor
        .maps
        .get_mut(&selected_map_id)
        .ok_or_else(|| "Selected map is no longer loaded.".to_string())?;
    document.diagnostics = validate_document(&editor.map_service, &document.definition);
    info!(
        "map editor validated map: map_id={}, diagnostics={}",
        selected_map_id,
        document.diagnostics.len()
    );
    Ok(format!(
        "Validated map {} ({} diagnostic entries).",
        selected_map_id,
        document.diagnostics.len()
    ))
}

fn save_current_map(editor: &mut EditorState) -> Result<String, String> {
    let preserved_level = editor.current_map_level;
    let selected_map_id = editor
        .selected_map_id
        .clone()
        .ok_or_else(|| "No map selected.".to_string())?;
    let document = editor
        .maps
        .get(&selected_map_id)
        .cloned()
        .ok_or_else(|| "Selected map is no longer loaded.".to_string())?;

    let result = editor
        .map_service
        .save_map_definition(document.original_id.as_ref(), &document.definition)
        .map_err(|error| error.to_string())?;

    let next_map_id = document.definition.id.as_str().to_string();
    let mut next_document = document.clone();
    next_document.original_id = Some(document.definition.id.clone());
    next_document.dirty = false;
    next_document.last_save_message = Some(result.summary.details.join("; "));
    next_document.diagnostics = validate_document(&editor.map_service, &next_document.definition);

    if next_map_id != selected_map_id {
        editor.maps.remove(&selected_map_id);
    }
    editor.maps.insert(next_map_id.clone(), next_document);
    editor.update_map_selection(next_map_id.clone(), preserved_level);
    info!("map editor saved map: map_id={next_map_id}");
    Ok(format!("Saved map {}.", map_display_name(&next_map_id)))
}

fn sync_camera_target_to_selected_view(editor: &EditorState, orbit_camera: &mut OrbitCameraState) {
    match editor.selected_view {
        LibraryView::Maps => {
            let Some(selected_map_id) = editor.selected_map_id.as_ref() else {
                return;
            };
            let Some(document) = editor.maps.get(selected_map_id) else {
                return;
            };
            orbit_camera.target = map_focus_target(&document.definition);
        }
        LibraryView::Overworlds => {
            let Some(selected_overworld_id) = editor.selected_overworld_id.as_ref() else {
                return;
            };
            let Some(definition) = editor
                .overworld_library
                .get(&OverworldId(selected_overworld_id.clone()))
            else {
                return;
            };
            orbit_camera.target = overworld_focus_target(definition);
        }
    }
}

fn current_fps_label(diagnostics: &DiagnosticsStore) -> String {
    let fps = diagnostics
        .get(&FrameTimeDiagnosticsPlugin::FPS)
        .and_then(|diagnostic| diagnostic.smoothed())
        .or_else(|| {
            diagnostics
                .get(&FrameTimeDiagnosticsPlugin::FPS)
                .and_then(|diagnostic| diagnostic.average())
        });
    fps.map(|value| format!("{value:.0}"))
        .unwrap_or_else(|| "--".to_string())
}

pub(crate) fn draw_diagnostic(ui: &mut egui::Ui, diagnostic: &MapEditDiagnostic) {
    let color = match diagnostic.severity {
        MapEditDiagnosticSeverity::Error => egui::Color32::from_rgb(242, 94, 94),
        MapEditDiagnosticSeverity::Warning => egui::Color32::from_rgb(233, 180, 64),
        MapEditDiagnosticSeverity::Info => egui::Color32::from_rgb(120, 180, 255),
    };
    ui.colored_label(
        color,
        format!("[{}] {}", diagnostic.code, diagnostic.message),
    );
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
