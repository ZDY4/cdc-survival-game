use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::diagnostic::{DiagnosticsStore, FrameTimeDiagnosticsPlugin};
use bevy::input::mouse::MouseWheel;
use bevy::prelude::*;
use bevy_egui::input::EguiWantsInput;
use bevy_egui::{egui, EguiContexts, EguiPlugin, EguiPrimaryContextPass};
use game_bevy::world_render::{
    apply_world_render_camera_projection, build_world_render_scene_from_map_definition,
    build_world_render_scene_from_overworld_definition, spawn_world_render_light_rig,
    spawn_world_render_scene, BuildingWallGridMaterial, GridGroundMaterial, WorldRenderConfig,
    WorldRenderPalette, WorldRenderPlugin, WorldRenderStyleProfile,
};
use game_bevy::{game_ui_font_bytes, load_game_ui_font, GAME_UI_FONT_NAME};
use game_data::{
    load_map_library, load_overworld_library, GridCoord, MapDefinition, MapEditDiagnostic,
    MapEditDiagnosticSeverity, MapEditorService, MapId, MapObjectDefinition, MapObjectKind,
    OverworldDefinition, OverworldId, OverworldLibrary,
};
use game_editor::ai_chat::{
    persist_ai_chat_settings, poll_generation_job, render_ai_chat_panel, render_ai_settings_window,
    start_connection_test, AiChatState, AiChatUiAction, AiChatWorkerState,
};

mod map_ai;

use map_ai::{
    apply_prepared_proposal, assistant_summary_text, render_map_ai_result, start_map_ai_generation,
    success_status_text, AiProposalView, MapAiUiAction,
};

const TEMP_CAMERA_YAW_OFFSET_DEGREES: f32 = 45.0;
const PERSPECTIVE_DISTANCE_DEFAULT: f32 = 28.0;
const TOP_DOWN_DISTANCE_DEFAULT: f32 = 40.0;
const CAMERA_DISTANCE_MIN: f32 = 6.0;
const CAMERA_DISTANCE_MAX: f32 = 160.0;
const DEFAULT_CAMERA_PAN_SPEED_MULTIPLIER: f32 = 1.0;
const CAMERA_PAN_SPEED_MULTIPLIER_MIN: f32 = 0.25;
const CAMERA_PAN_SPEED_MULTIPLIER_MAX: f32 = 4.0;
const HOVERED_GRID_OUTLINE_COLOR: Color = Color::srgba(0.96, 0.97, 0.99, 0.98);
const HOVERED_GRID_OUTLINE_Y_OFFSET: f32 = 0.14;
const HOVERED_GRID_OUTLINE_EXTENT_SCALE: f32 = 0.94;
const EDITOR_GRID_WORLD_SIZE: f32 = 1.0;

type MapAiState = AiChatState<AiProposalView>;
type MapAiWorkerState = AiChatWorkerState<AiProposalView>;

fn main() {
    let render_palette = WorldRenderPalette::default();
    let render_style = WorldRenderStyleProfile::default();
    let render_config = WorldRenderConfig::default();
    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "CDC Map Editor".into(),
                resolution: (1680, 980).into(),
                ..default()
            }),
            ..default()
        }))
        .add_plugins(WorldRenderPlugin)
        .add_plugins(FrameTimeDiagnosticsPlugin::default())
        .add_plugins(EguiPlugin::default())
        .insert_resource(ClearColor(render_palette.clear_color))
        .insert_resource(render_palette)
        .insert_resource(render_style)
        .insert_resource(render_config)
        .insert_resource(load_editor_state())
        .insert_resource(MapAiState::load("bevy_map_editor"))
        .insert_resource(EditorUiState::default())
        .insert_resource(EditorEguiFontState::default())
        .insert_resource(OrbitCameraState::default())
        .insert_resource(MiddleClickState::default())
        .insert_resource(MapAiWorkerState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(
            EguiPrimaryContextPass,
            (configure_editor_egui_fonts_system, editor_ui_system).chain(),
        )
        .add_systems(
            Update,
            (
                rebuild_scene_system,
                camera_input_system,
                apply_camera_transform_system,
                update_hover_info_system,
                draw_hovered_grid_outline_system,
            )
                .chain(),
        )
        .add_systems(Update, poll_ai_worker_system)
        .run();
}

#[derive(Component)]
struct EditorCamera;

#[derive(Component)]
struct SceneEntity;

#[derive(Resource, Clone)]
struct EditorWorldLabelFont(Handle<Font>);

#[derive(Resource, Debug, Clone)]
struct OrbitCameraState {
    base_yaw: f32,
    base_pitch: f32,
    yaw_offset: f32,
    is_top_down: bool,
    perspective_distance: f32,
    top_down_distance: f32,
    target: Vec3,
}

impl Default for OrbitCameraState {
    fn default() -> Self {
        let render_config = WorldRenderConfig::default();
        Self {
            base_yaw: render_config.camera_yaw_radians(),
            base_pitch: render_config.camera_pitch_radians(),
            yaw_offset: 0.0,
            is_top_down: false,
            perspective_distance: PERSPECTIVE_DISTANCE_DEFAULT,
            top_down_distance: TOP_DOWN_DISTANCE_DEFAULT,
            target: Vec3::ZERO,
        }
    }
}

impl OrbitCameraState {
    fn reset_to_default_view(&mut self) {
        self.yaw_offset = 0.0;
        self.is_top_down = false;
        self.perspective_distance = PERSPECTIVE_DISTANCE_DEFAULT;
        self.top_down_distance = TOP_DOWN_DISTANCE_DEFAULT;
    }

    fn active_distance(&self) -> f32 {
        if self.is_top_down {
            self.top_down_distance
        } else {
            self.perspective_distance
        }
    }

    fn active_distance_mut(&mut self) -> &mut f32 {
        if self.is_top_down {
            &mut self.top_down_distance
        } else {
            &mut self.perspective_distance
        }
    }
}

#[derive(Resource, Debug, Clone, Default)]
struct MiddleClickState {
    drag_anchor_world: Option<Vec2>,
}

#[derive(Debug, Clone, Default)]
struct HoveredCellInfo {
    grid: GridCoord,
    title: String,
    lines: Vec<String>,
}

#[derive(Resource, Debug, Clone)]
struct EditorUiState {
    show_fps_overlay: bool,
    camera_pan_speed_multiplier: f32,
    hovered_cell: Option<HoveredCellInfo>,
    hovered_grid: Option<GridCoord>,
}

impl Default for EditorUiState {
    fn default() -> Self {
        Self {
            show_fps_overlay: false,
            camera_pan_speed_multiplier: DEFAULT_CAMERA_PAN_SPEED_MULTIPLIER,
            hovered_cell: None,
            hovered_grid: None,
        }
    }
}

#[derive(Resource, Debug, Clone, Default)]
struct EditorEguiFontState {
    initialized: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LibraryView {
    Maps,
    Overworlds,
}

#[derive(Debug, Clone)]
struct WorkingMapDocument {
    original_id: Option<MapId>,
    definition: MapDefinition,
    dirty: bool,
    diagnostics: Vec<MapEditDiagnostic>,
    last_save_message: Option<String>,
}

#[derive(Resource)]
struct EditorState {
    map_service: MapEditorService,
    maps: BTreeMap<String, WorkingMapDocument>,
    overworld_library: OverworldLibrary,
    selected_view: LibraryView,
    selected_map_id: Option<String>,
    selected_overworld_id: Option<String>,
    current_map_level: i32,
    search_text: String,
    status: String,
    scene_dirty: bool,
    scene_revision: u64,
}

fn load_editor_state() -> EditorState {
    let maps_dir = project_data_dir("maps");
    let map_service = MapEditorService::new(maps_dir.clone());
    let overworld_dir = project_data_dir("overworld");
    let map_library = load_map_library(&maps_dir).unwrap_or_default();
    let overworld_library = load_overworld_library(&overworld_dir).unwrap_or_default();
    let maps = map_library
        .iter()
        .map(|(map_id, definition)| {
            (
                map_id.as_str().to_string(),
                WorkingMapDocument {
                    original_id: Some(map_id.clone()),
                    definition: definition.clone(),
                    dirty: false,
                    diagnostics: validate_document(&map_service, definition),
                    last_save_message: None,
                },
            )
        })
        .collect::<BTreeMap<_, _>>();
    let selected_map_id = maps.keys().next().cloned();
    let selected_overworld_id = overworld_library
        .iter()
        .next()
        .map(|(id, _)| id.as_str().to_string());
    let current_map_level = selected_map_id
        .as_ref()
        .and_then(|id| maps.get(id))
        .map(|document| document.definition.default_level)
        .unwrap_or(0);
    EditorState {
        map_service,
        maps,
        overworld_library,
        selected_view: LibraryView::Maps,
        selected_map_id,
        selected_overworld_id,
        current_map_level,
        search_text: String::new(),
        status: "Loaded map and overworld content.".to_string(),
        scene_dirty: true,
        scene_revision: 0,
    }
}

fn normalized_map_label_key(value: &str) -> String {
    value
        .chars()
        .filter(|ch| !matches!(ch, '_' | '-' | ' '))
        .flat_map(|ch| ch.to_lowercase())
        .collect()
}

fn map_display_name(map_id: &str) -> &str {
    map_id
}

fn map_library_item_label(map_id: &str, name: &str, dirty: bool, has_diagnostics: bool) -> String {
    let display_map_id = map_display_name(map_id);
    let suffix = match (dirty, has_diagnostics) {
        (true, true) => " [dirty, diag]",
        (true, false) => " [dirty]",
        (false, true) => " [diag]",
        (false, false) => "",
    };
    let trimmed_name = name.trim();
    if trimmed_name.is_empty() {
        return format!("{display_map_id}{suffix}");
    }
    if normalized_map_label_key(trimmed_name) == normalized_map_label_key(display_map_id) {
        return format!("{trimmed_name}{suffix}");
    }

    format!("{trimmed_name} · {display_map_id}{suffix}")
}

fn build_working_maps(
    map_service: &MapEditorService,
    map_library: &game_data::MapLibrary,
) -> BTreeMap<String, WorkingMapDocument> {
    map_library
        .iter()
        .map(|(map_id, definition)| {
            (
                map_id.as_str().to_string(),
                WorkingMapDocument {
                    original_id: Some(map_id.clone()),
                    definition: definition.clone(),
                    dirty: false,
                    diagnostics: validate_document(map_service, definition),
                    last_save_message: None,
                },
            )
        })
        .collect()
}

fn project_data_dir(kind: &str) -> PathBuf {
    repo_root().join("data").join(kind)
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

fn setup_editor(
    mut commands: Commands,
    mut font_assets: ResMut<Assets<Font>>,
    render_palette: Res<WorldRenderPalette>,
    render_style: Res<WorldRenderStyleProfile>,
    render_config: Res<WorldRenderConfig>,
) {
    let world_label_font = load_game_ui_font(&mut font_assets);
    commands.insert_resource(EditorWorldLabelFont(world_label_font));
    spawn_world_render_light_rig(&mut commands, &render_palette, &render_style);
    let mut perspective = PerspectiveProjection::default();
    apply_world_render_camera_projection(&mut perspective, *render_config);
    commands.spawn((
        Camera3d::default(),
        Msaa::Sample4,
        Projection::from(perspective),
        Transform::from_xyz(18.0, 18.0, 18.0).looking_at(Vec3::ZERO, Vec3::Y),
        EditorCamera,
    ));
}

fn configure_editor_egui_fonts_system(
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

fn editor_ui_system(
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
                    ui.close();
                }
                if ui.button("Save Current").clicked() {
                    editor.status = save_current_map(&mut editor).unwrap_or_else(|error| error);
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
            ui.horizontal(|ui| {
                ui.selectable_value(&mut editor.selected_view, LibraryView::Maps, "Maps");
                ui.selectable_value(
                    &mut editor.selected_view,
                    LibraryView::Overworlds,
                    "Overworlds",
                );
            });
            ui.text_edit_singleline(&mut editor.search_text);
            let query = editor.search_text.trim().to_lowercase();
            egui::ScrollArea::vertical().show(ui, |ui| match editor.selected_view {
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
                        let label = map_library_item_label(&map_id, &name, dirty, has_diagnostics);
                        if ui
                            .selectable_label(
                                editor.selected_map_id.as_deref() == Some(map_id.as_str()),
                                label,
                            )
                            .clicked()
                        {
                            let already_selected =
                                editor.selected_map_id.as_deref() == Some(map_id.as_str());
                            if !already_selected {
                                editor.selected_map_id = Some(map_id.clone());
                                editor.current_map_level = default_level;
                                editor.scene_dirty = true;
                                if let Some(doc) = editor.maps.get(&map_id) {
                                    orbit_camera.target = map_focus_target(&doc.definition);
                                }
                            }
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
                        if !query.is_empty() && !overworld_id.to_lowercase().contains(&query) {
                            continue;
                        }
                        if ui
                            .selectable_label(
                                editor.selected_overworld_id.as_deref()
                                    == Some(overworld_id.as_str()),
                                format!("{overworld_id} · {locations} locations"),
                            )
                            .clicked()
                        {
                            editor.selected_overworld_id = Some(overworld_id.clone());
                            editor.scene_dirty = true;
                            orbit_camera.target = overworld_focus_target(&definition);
                        }
                    }
                }
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
                                    editor.status = apply_prepared_proposal(&mut editor, proposal)
                                        .unwrap_or_else(|error| error);
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

fn validate_document(
    map_service: &MapEditorService,
    definition: &MapDefinition,
) -> Vec<MapEditDiagnostic> {
    match map_service.validate_definition_result(definition) {
        Ok(result) => result.diagnostics,
        Err(error) => vec![MapEditDiagnostic::error(
            "map_edit_error",
            error.to_string(),
        )],
    }
}

fn reload_editor_content(editor: &mut EditorState) -> String {
    if editor.maps.values().any(|document| document.dirty) {
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
            editor.selected_map_id = previous_selected_map
                .filter(|id| editor.maps.contains_key(id))
                .or_else(|| editor.maps.keys().next().cloned());
            editor.selected_overworld_id = previous_selected_overworld
                .filter(|id| {
                    editor
                        .overworld_library
                        .get(&OverworldId(id.clone()))
                        .is_some()
                })
                .or_else(|| {
                    editor
                        .overworld_library
                        .iter()
                        .next()
                        .map(|(id, _)| id.as_str().to_string())
                });
            editor.current_map_level = editor
                .selected_map_id
                .as_ref()
                .and_then(|id| editor.maps.get(id))
                .map(|document| document.definition.default_level)
                .unwrap_or(0);
            editor.scene_dirty = true;
            format!(
                "Reloaded {} maps and {} overworld documents.",
                editor.maps.len(),
                editor.overworld_library.len()
            )
        }
        (Err(map_error), Ok(_)) => format!("Failed to reload maps: {map_error}"),
        (Ok(_), Err(overworld_error)) => format!("Failed to reload overworlds: {overworld_error}"),
        (Err(map_error), Err(overworld_error)) => {
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
    Ok(format!(
        "Validated map {} ({} diagnostic entries).",
        selected_map_id,
        document.diagnostics.len()
    ))
}

fn save_current_map(editor: &mut EditorState) -> Result<String, String> {
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
    editor.selected_map_id = Some(next_map_id.clone());
    editor.scene_dirty = true;
    Ok(format!("Saved map {}.", map_display_name(&next_map_id)))
}

fn camera_input_system(
    time: Res<Time>,
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<EditorCamera>>,
    keys: Res<ButtonInput<KeyCode>>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut wheel_events: MessageReader<MouseWheel>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    ui_state: Res<EditorUiState>,
    mut middle_click_state: ResMut<MiddleClickState>,
    egui_wants_input: Res<EguiWantsInput>,
    mut editor: ResMut<EditorState>,
) {
    let wants_keyboard_input = egui_wants_input.wants_any_keyboard_input();
    let wants_pointer_input = egui_wants_input.wants_any_pointer_input();

    if wants_keyboard_input {
        orbit_camera.yaw_offset = 0.0;
    } else if orbit_camera.is_top_down {
        orbit_camera.yaw_offset = 0.0;
    } else if keys.pressed(KeyCode::KeyQ) && !keys.pressed(KeyCode::KeyE) {
        orbit_camera.yaw_offset = -TEMP_CAMERA_YAW_OFFSET_DEGREES.to_radians();
    } else if keys.pressed(KeyCode::KeyE) && !keys.pressed(KeyCode::KeyQ) {
        orbit_camera.yaw_offset = TEMP_CAMERA_YAW_OFFSET_DEGREES.to_radians();
    } else {
        orbit_camera.yaw_offset = 0.0;
    }

    if !wants_keyboard_input && keys.just_pressed(KeyCode::KeyT) {
        orbit_camera.is_top_down = !orbit_camera.is_top_down;
        orbit_camera.yaw_offset = 0.0;
        editor.status = if orbit_camera.is_top_down {
            "Camera switched to top-down view.".to_string()
        } else {
            "Camera restored to perspective view.".to_string()
        };
    }

    if !wants_keyboard_input {
        let movement = gather_keyboard_movement(&keys);
        if movement != Vec2::ZERO {
            let move_speed = camera_pan_speed(
                orbit_camera.active_distance(),
                ui_state.camera_pan_speed_multiplier,
            ) * time.delta_secs();
            let world_delta = camera_pan_delta(&orbit_camera, movement.normalize(), move_speed);
            orbit_camera.target += world_delta;
        }
    }

    if wants_pointer_input {
        for _ in wheel_events.read() {}
        middle_click_state.drag_anchor_world = None;
    } else {
        for event in wheel_events.read() {
            let unit_scale = match event.unit {
                bevy::input::mouse::MouseScrollUnit::Line => 1.0,
                bevy::input::mouse::MouseScrollUnit::Pixel => 0.1,
            };
            let next_distance = (*orbit_camera.active_distance_mut() - event.y * unit_scale * 1.8)
                .clamp(CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX);
            *orbit_camera.active_distance_mut() = next_distance;
        }
    }

    if !buttons.pressed(MouseButton::Middle) {
        middle_click_state.drag_anchor_world = None;
        return;
    }

    if wants_pointer_input {
        middle_click_state.drag_anchor_world = None;
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        middle_click_state.drag_anchor_world = None;
        return;
    };

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let Ok(ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
        middle_click_state.drag_anchor_world = None;
        return;
    };
    let Some(current_point) = ray_point_on_horizontal_plane(ray, 0.0) else {
        middle_click_state.drag_anchor_world = None;
        return;
    };
    let current_world = Vec2::new(current_point.x, current_point.z);

    if buttons.just_pressed(MouseButton::Middle) || middle_click_state.drag_anchor_world.is_none() {
        middle_click_state.drag_anchor_world = Some(current_world);
        return;
    }

    let Some(anchor_world) = middle_click_state.drag_anchor_world else {
        return;
    };
    let pan_delta = anchor_world - current_world;
    if pan_delta.length_squared() <= f32::EPSILON {
        return;
    }

    orbit_camera.target += Vec3::new(pan_delta.x, 0.0, pan_delta.y);
}

fn apply_camera_transform_system(
    orbit_camera: Res<OrbitCameraState>,
    render_config: Res<WorldRenderConfig>,
    mut cameras: Query<(&mut Projection, &mut Transform), With<EditorCamera>>,
) {
    let Ok((mut projection, mut transform)) = cameras.single_mut() else {
        return;
    };

    if let Projection::Perspective(perspective) = &mut *projection {
        apply_world_render_camera_projection(perspective, *render_config);
    }

    let pitch = if orbit_camera.is_top_down {
        90.0_f32.to_radians()
    } else {
        orbit_camera.base_pitch
    };
    let yaw = if orbit_camera.is_top_down {
        0.0
    } else {
        orbit_camera.base_yaw + orbit_camera.yaw_offset
    };
    let distance = if orbit_camera.is_top_down {
        orbit_camera.top_down_distance
    } else {
        orbit_camera.perspective_distance
    };
    let horizontal = distance * pitch.cos();
    let eye = orbit_camera.target
        + Vec3::new(
            horizontal * yaw.sin(),
            distance * pitch.sin(),
            -horizontal * yaw.cos(),
        );

    transform.translation = eye;
    transform.look_at(
        orbit_camera.target,
        if orbit_camera.is_top_down {
            Vec3::Z
        } else {
            Vec3::Y
        },
    );
}

fn rebuild_scene_system(
    mut commands: Commands,
    mut editor: ResMut<EditorState>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    render_config: Res<WorldRenderConfig>,
    render_palette: Res<WorldRenderPalette>,
    mut images: ResMut<Assets<Image>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    mut ground_materials: ResMut<Assets<GridGroundMaterial>>,
    mut building_wall_materials: ResMut<Assets<BuildingWallGridMaterial>>,
    world_label_font: Res<EditorWorldLabelFont>,
    scene_entities: Query<Entity, With<SceneEntity>>,
) {
    if !editor.scene_dirty {
        return;
    }

    for entity in scene_entities.iter() {
        commands.entity(entity).despawn();
    }

    match editor.selected_view {
        LibraryView::Maps => {
            let Some(selected_map_id) = editor.selected_map_id.clone() else {
                editor.status = "No tactical map available to render.".to_string();
                editor.scene_dirty = false;
                return;
            };
            let Some(document) = editor.maps.get(&selected_map_id).cloned() else {
                editor.status = "Selected tactical map is no longer loaded.".to_string();
                editor.scene_dirty = false;
                return;
            };
            orbit_camera.target = map_focus_target(&document.definition);
            let scene = build_world_render_scene_from_map_definition(
                &document.definition,
                editor.current_map_level,
                *render_config,
            );
            for entity in spawn_world_render_scene(
                &mut commands,
                &mut meshes,
                &mut materials,
                &mut ground_materials,
                &mut building_wall_materials,
                &mut images,
                Some(world_label_font.0.clone()),
                &scene,
                *render_config,
                &render_palette,
            ) {
                commands.entity(entity).insert(SceneEntity);
            }
            editor.status = format!(
                "Rendering map {} at level {} in native Bevy 3D.",
                map_display_name(document.definition.id.as_str()),
                editor.current_map_level
            );
        }
        LibraryView::Overworlds => {
            let Some(selected_overworld_id) = editor.selected_overworld_id.clone() else {
                editor.status = "No overworld available to render.".to_string();
                editor.scene_dirty = false;
                return;
            };
            let Some(definition) = editor
                .overworld_library
                .get(&OverworldId(selected_overworld_id))
                .cloned()
            else {
                editor.status = "Selected overworld is no longer loaded.".to_string();
                editor.scene_dirty = false;
                return;
            };
            orbit_camera.target = overworld_focus_target(&definition);
            let scene = build_world_render_scene_from_overworld_definition(&definition);
            for entity in spawn_world_render_scene(
                &mut commands,
                &mut meshes,
                &mut materials,
                &mut ground_materials,
                &mut building_wall_materials,
                &mut images,
                Some(world_label_font.0.clone()),
                &scene,
                *render_config,
                &render_palette,
            ) {
                commands.entity(entity).insert(SceneEntity);
            }
            editor.status = format!(
                "Rendering overworld {} in native Bevy 3D.",
                definition.id.as_str()
            );
        }
    }

    editor.scene_dirty = false;
    editor.scene_revision = editor.scene_revision.saturating_add(1);
}

fn map_focus_target(definition: &MapDefinition) -> Vec3 {
    Vec3::new(
        definition.size.width.saturating_sub(1) as f32 * 0.5,
        0.0,
        definition.size.height.saturating_sub(1) as f32 * 0.5,
    )
}

fn overworld_focus_target(definition: &OverworldDefinition) -> Vec3 {
    Vec3::new(
        definition.size.width.saturating_sub(1) as f32 * 0.5,
        0.0,
        definition.size.height.saturating_sub(1) as f32 * 0.5,
    )
}

fn gather_keyboard_movement(keys: &ButtonInput<KeyCode>) -> Vec2 {
    let mut movement = Vec2::ZERO;
    if keys.pressed(KeyCode::KeyW) {
        movement.y += 1.0;
    }
    if keys.pressed(KeyCode::KeyS) {
        movement.y -= 1.0;
    }
    if keys.pressed(KeyCode::KeyD) {
        movement.x += 1.0;
    }
    if keys.pressed(KeyCode::KeyA) {
        movement.x -= 1.0;
    }
    movement
}

fn camera_pan_speed(distance: f32, multiplier: f32) -> f32 {
    (distance * 0.45 * multiplier).clamp(4.0, 72.0)
}

fn camera_pan_delta(orbit_camera: &OrbitCameraState, movement: Vec2, move_speed: f32) -> Vec3 {
    if orbit_camera.is_top_down {
        return Vec3::new(movement.x, 0.0, movement.y) * move_speed;
    }

    let yaw = orbit_camera.base_yaw + orbit_camera.yaw_offset;
    let forward = Vec3::new(yaw.sin(), 0.0, yaw.cos());
    let right = Vec3::new(-forward.z, 0.0, forward.x);
    (forward * movement.y + right * movement.x) * move_speed
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

fn ray_point_on_horizontal_plane(ray: Ray3d, plane_height: f32) -> Option<Vec3> {
    let plane_origin = Vec3::new(0.0, plane_height, 0.0);
    ray.plane_intersection_point(plane_origin, InfinitePlane3d::new(Vec3::Y))
}

fn update_hover_info_system(
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<EditorCamera>>,
    egui_wants_input: Res<EguiWantsInput>,
    editor: Res<EditorState>,
    mut ui_state: ResMut<EditorUiState>,
) {
    if egui_wants_input.wants_any_pointer_input() {
        ui_state.hovered_cell = None;
        ui_state.hovered_grid = None;
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        ui_state.hovered_cell = None;
        ui_state.hovered_grid = None;
        return;
    };

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let Ok(ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
        ui_state.hovered_cell = None;
        ui_state.hovered_grid = None;
        return;
    };
    let Some(point) = ray_point_on_horizontal_plane(ray, 0.0) else {
        ui_state.hovered_cell = None;
        ui_state.hovered_grid = None;
        return;
    };

    let hovered = match editor.selected_view {
        LibraryView::Maps => build_map_hover_info(&editor, point),
        LibraryView::Overworlds => build_overworld_hover_info(&editor, point),
    };
    ui_state.hovered_grid = hovered.as_ref().map(|hovered| hovered.grid);
    ui_state.hovered_cell = hovered;
}

fn draw_hovered_grid_outline_system(
    mut gizmos: Gizmos,
    ui_state: Res<EditorUiState>,
    render_config: Res<WorldRenderConfig>,
) {
    let Some(grid) = ui_state.hovered_grid else {
        return;
    };

    draw_grid_outline(
        &mut gizmos,
        grid,
        EDITOR_GRID_WORLD_SIZE,
        render_config
            .floor_thickness_world
            .max(HOVERED_GRID_OUTLINE_Y_OFFSET),
        HOVERED_GRID_OUTLINE_EXTENT_SCALE,
        HOVERED_GRID_OUTLINE_COLOR,
    );
}

fn draw_grid_outline(
    gizmos: &mut Gizmos,
    grid: GridCoord,
    grid_size: f32,
    y_offset: f32,
    extent_scale: f32,
    color: Color,
) {
    let inset = (1.0 - extent_scale).max(0.0) * 0.5 * grid_size;
    let x0 = grid.x as f32 * grid_size + inset;
    let x1 = (grid.x + 1) as f32 * grid_size - inset;
    let z0 = grid.z as f32 * grid_size + inset;
    let z1 = (grid.z + 1) as f32 * grid_size - inset;
    let y = grid.y as f32 * grid_size + y_offset;

    let a = Vec3::new(x0, y, z0);
    let b = Vec3::new(x1, y, z0);
    let c = Vec3::new(x1, y, z1);
    let d = Vec3::new(x0, y, z1);

    gizmos.line(a, b, color);
    gizmos.line(b, c, color);
    gizmos.line(c, d, color);
    gizmos.line(d, a, color);
}

fn build_map_hover_info(editor: &EditorState, point: Vec3) -> Option<HoveredCellInfo> {
    let selected_map_id = editor.selected_map_id.as_ref()?;
    let document = editor.maps.get(selected_map_id)?;
    let grid = GridCoord::new(
        point.x.floor() as i32,
        editor.current_map_level,
        point.z.floor() as i32,
    );

    if grid.x < 0
        || grid.z < 0
        || grid.x >= document.definition.size.width as i32
        || grid.z >= document.definition.size.height as i32
    {
        return None;
    }

    let level = document
        .definition
        .levels
        .iter()
        .find(|level| level.y == editor.current_map_level)?;
    let cell_x = grid.x as u32;
    let cell_z = grid.z as u32;
    let cell = level
        .cells
        .iter()
        .find(|cell| cell.x == cell_x && cell.z == cell_z);
    let objects = document
        .definition
        .objects
        .iter()
        .filter(|object| object_covers_grid(object, grid))
        .collect::<Vec<_>>();

    let mut lines = Vec::new();
    if let Some(cell) = cell {
        lines.push(format!(
            "Cell: terrain={} move_block={} sight_block={}",
            cell.terrain,
            yes_no(cell.blocks_movement),
            yes_no(cell.blocks_sight),
        ));
    } else {
        lines.push("Cell: missing".to_string());
    }

    if objects.is_empty() {
        lines.push("Objects: none".to_string());
    } else {
        lines.push(format!("Objects: {}", objects.len()));
        for object in objects {
            lines.extend(describe_map_object(object));
        }
    }

    Some(HoveredCellInfo {
        grid,
        title: format!("Grid ({}, {}, {})", grid.x, grid.y, grid.z),
        lines,
    })
}

fn build_overworld_hover_info(editor: &EditorState, point: Vec3) -> Option<HoveredCellInfo> {
    let selected_overworld_id = editor.selected_overworld_id.as_ref()?;
    let definition = editor
        .overworld_library
        .get(&OverworldId(selected_overworld_id.clone()))?;
    let grid = GridCoord::new(point.x.floor() as i32, 0, point.z.floor() as i32);
    if grid.x < 0
        || grid.z < 0
        || grid.x >= definition.size.width as i32
        || grid.z >= definition.size.height as i32
    {
        return None;
    }
    let location = definition.locations.iter().find(|location| {
        location.overworld_cell.x == grid.x && location.overworld_cell.z == grid.z
    });
    let cell = definition
        .cells
        .iter()
        .find(|cell| cell.grid.x == grid.x && cell.grid.z == grid.z);

    let mut lines = vec![format!("Overworld: {}", definition.id.as_str())];
    if let Some(cell) = cell {
        lines.push(format!("Terrain: {}", cell.terrain));
        lines.push(format!(
            "Move cost: {}",
            cell.terrain
                .move_cost()
                .map(|cost| cost.to_string())
                .unwrap_or_else(|| "impassable".to_string())
        ));
        lines.push(format!("Blocked: {}", yes_no(cell.blocked)));
        lines.push(format!(
            "Passable: {}",
            yes_no(!cell.blocked && cell.terrain.is_passable())
        ));
    }
    lines.push(format!("Location cell: {}", yes_no(location.is_some())));
    if let Some(location) = location {
        lines.push(format!("Location: {}", location.id.as_str()));
        if !location.name.trim().is_empty() {
            lines.push(format!("Name: {}", location.name));
        }
        lines.push(format!(
            "Kind: {}",
            overworld_location_kind_label(location.kind)
        ));
        lines.push(format!(
            "Map: {}",
            map_display_name(location.map_id.as_str())
        ));
        if !location.entry_point_id.trim().is_empty() {
            lines.push(format!("Entry: {}", location.entry_point_id));
        }
    }

    Some(HoveredCellInfo {
        grid,
        title: format!("Grid ({}, {}, {})", grid.x, grid.y, grid.z),
        lines,
    })
}

fn object_covers_grid(object: &MapObjectDefinition, grid: GridCoord) -> bool {
    if object.anchor.y != grid.y {
        return false;
    }
    let width = object.footprint.width.max(1) as i32;
    let height = object.footprint.height.max(1) as i32;
    grid.x >= object.anchor.x
        && grid.x < object.anchor.x + width
        && grid.z >= object.anchor.z
        && grid.z < object.anchor.z + height
}

fn describe_map_object(object: &MapObjectDefinition) -> Vec<String> {
    let mut lines = vec![format!(
        "- {} [{}] anchor=({}, {}, {}) footprint={}x{}",
        object.object_id,
        map_object_kind_label(object.kind),
        object.anchor.x,
        object.anchor.y,
        object.anchor.z,
        object.footprint.width.max(1),
        object.footprint.height.max(1),
    )];
    lines.push(format!(
        "  blocks: movement={} sight={}",
        yes_no(object.blocks_movement),
        yes_no(object.blocks_sight),
    ));

    match object.kind {
        MapObjectKind::Building => {
            if let Some(building) = &object.props.building {
                if !building.prefab_id.trim().is_empty() {
                    lines.push(format!("  prefab: {}", building.prefab_id));
                }
            }
        }
        MapObjectKind::Pickup => {
            if let Some(pickup) = &object.props.pickup {
                lines.push(format!(
                    "  pickup: item={} count={}..{}",
                    pickup.item_id, pickup.min_count, pickup.max_count
                ));
            }
        }
        MapObjectKind::Interactive => {
            if let Some(interactive) = &object.props.interactive {
                if !interactive.display_name.trim().is_empty() {
                    lines.push(format!("  name: {}", interactive.display_name));
                }
                lines.push(format!("  interaction: {}", interactive.interaction_kind));
                if let Some(target_id) = interactive.target_id.as_deref() {
                    lines.push(format!("  target: {}", target_id));
                }
            }
        }
        MapObjectKind::Trigger => {
            if let Some(trigger) = &object.props.trigger {
                if !trigger.display_name.trim().is_empty() {
                    lines.push(format!("  name: {}", trigger.display_name));
                }
                lines.push(format!("  interaction: {}", trigger.interaction_kind));
                if let Some(target_id) = trigger.target_id.as_deref() {
                    lines.push(format!("  target: {}", target_id));
                }
            }
        }
        MapObjectKind::AiSpawn => {
            if let Some(spawn) = &object.props.ai_spawn {
                lines.push(format!(
                    "  spawn: id={} character={}",
                    spawn.spawn_id, spawn.character_id
                ));
            }
        }
    }

    lines
}

fn map_object_kind_label(kind: MapObjectKind) -> &'static str {
    match kind {
        MapObjectKind::Building => "building",
        MapObjectKind::Pickup => "pickup",
        MapObjectKind::Interactive => "interactive",
        MapObjectKind::Trigger => "trigger",
        MapObjectKind::AiSpawn => "ai_spawn",
    }
}

fn overworld_location_kind_label(kind: game_data::OverworldLocationKind) -> &'static str {
    match kind {
        game_data::OverworldLocationKind::Outdoor => "outdoor",
        game_data::OverworldLocationKind::Interior => "interior",
        game_data::OverworldLocationKind::Dungeon => "dungeon",
    }
}

fn yes_no(value: bool) -> &'static str {
    if value {
        "yes"
    } else {
        "no"
    }
}

fn draw_diagnostic(ui: &mut egui::Ui, diagnostic: &MapEditDiagnostic) {
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

fn poll_ai_worker_system(mut ai: ResMut<MapAiState>, mut worker: ResMut<MapAiWorkerState>) {
    poll_generation_job(
        &mut ai,
        &mut worker,
        assistant_summary_text,
        success_status_text,
    );
}
