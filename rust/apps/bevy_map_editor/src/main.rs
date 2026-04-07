use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{
    mpsc::{self, Receiver, TryRecvError},
    Arc, Mutex,
};
use std::thread;
use std::time::Duration;

use bevy::diagnostic::{DiagnosticsStore, FrameTimeDiagnosticsPlugin};
use bevy::input::mouse::MouseWheel;
use bevy::prelude::*;
use bevy_egui::input::EguiWantsInput;
use bevy_egui::{egui, EguiContexts, EguiPlugin, EguiPrimaryContextPass};
use game_bevy::static_world::{
    build_static_world_from_map_definition, build_static_world_from_overworld_definition,
    spawn_static_world_visuals, StaticWorldBuildConfig,
};
use game_data::{
    load_map_library, load_overworld_library, GridCoord, MapCellDefinition, MapDefinition,
    MapEditDiagnostic, MapEditDiagnosticSeverity, MapEditError, MapEditorService,
    MapEntryPointDefinition, MapId, MapObjectDefinition, MapObjectKind, MapSize,
    OverworldDefinition, OverworldId, OverworldLibrary,
};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const VIEWER_CAMERA_YAW_DEGREES: f32 = 0.0;
const VIEWER_CAMERA_PITCH_DEGREES: f32 = 36.0;
const VIEWER_CAMERA_FOV_DEGREES: f32 = 30.0;
const TEMP_CAMERA_YAW_OFFSET_DEGREES: f32 = 45.0;
const PERSPECTIVE_DISTANCE_DEFAULT: f32 = 28.0;
const TOP_DOWN_DISTANCE_DEFAULT: f32 = 40.0;
const CAMERA_DISTANCE_MIN: f32 = 6.0;
const CAMERA_DISTANCE_MAX: f32 = 160.0;
const DEFAULT_BASE_URL: &str = "https://api.openai.com/v1";
const DEFAULT_MODEL: &str = "gpt-4.1-mini";
const DEFAULT_TIMEOUT_SEC: u64 = 45;
const DEFAULT_MAX_CONTEXT_RECORDS: usize = 24;
const CHAT_COMPLETIONS_PATH: &str = "/chat/completions";
const MODELS_PATH: &str = "/models";
const DEFAULT_CAMERA_PAN_SPEED_MULTIPLIER: f32 = 1.0;
const CAMERA_PAN_SPEED_MULTIPLIER_MIN: f32 = 0.25;
const CAMERA_PAN_SPEED_MULTIPLIER_MAX: f32 = 4.0;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "CDC Map Editor".into(),
                resolution: (1680, 980).into(),
                ..default()
            }),
            ..default()
        }))
        .add_plugins(FrameTimeDiagnosticsPlugin::default())
        .add_plugins(EguiPlugin::default())
        .insert_resource(ClearColor(Color::srgb(0.055, 0.06, 0.075)))
        .insert_resource(load_editor_state())
        .insert_resource(load_ai_state())
        .insert_resource(EditorUiState::default())
        .insert_resource(OrbitCameraState::default())
        .insert_resource(MiddleClickState::default())
        .insert_resource(AiWorkerState::default())
        .add_systems(Startup, setup_editor)
        .add_systems(EguiPrimaryContextPass, editor_ui_system)
        .add_systems(
            Update,
            (
                rebuild_scene_system,
                camera_input_system,
                apply_camera_transform_system,
                update_hover_info_system,
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
        Self {
            base_yaw: VIEWER_CAMERA_YAW_DEGREES.to_radians(),
            base_pitch: VIEWER_CAMERA_PITCH_DEGREES.to_radians(),
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
    title: String,
    lines: Vec<String>,
}

#[derive(Resource, Debug, Clone)]
struct EditorUiState {
    show_fps_overlay: bool,
    show_settings_window: bool,
    camera_pan_speed_multiplier: f32,
    hovered_cell: Option<HoveredCellInfo>,
}

impl Default for EditorUiState {
    fn default() -> Self {
        Self {
            show_fps_overlay: false,
            show_settings_window: false,
            camera_pan_speed_multiplier: DEFAULT_CAMERA_PAN_SPEED_MULTIPLIER,
            hovered_cell: None,
        }
    }
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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AiSettings {
    base_url: String,
    model: String,
    api_key: String,
    timeout_sec: u64,
    max_context_records: usize,
}

impl Default for AiSettings {
    fn default() -> Self {
        Self {
            base_url: DEFAULT_BASE_URL.to_string(),
            model: DEFAULT_MODEL.to_string(),
            api_key: String::new(),
            timeout_sec: DEFAULT_TIMEOUT_SEC,
            max_context_records: DEFAULT_MAX_CONTEXT_RECORDS,
        }
    }
}

impl AiSettings {
    fn normalized(mut self) -> Self {
        self.base_url = if self.base_url.trim().is_empty() {
            DEFAULT_BASE_URL.to_string()
        } else {
            self.base_url.trim().trim_end_matches('/').to_string()
        };
        self.model = if self.model.trim().is_empty() {
            DEFAULT_MODEL.to_string()
        } else {
            self.model.trim().to_string()
        };
        self.api_key = self.api_key.trim().to_string();
        self.timeout_sec = self.timeout_sec.max(5);
        self.max_context_records = self.max_context_records.max(6);
        self
    }

    fn effective_api_key(&self) -> String {
        if !self.api_key.trim().is_empty() {
            return self.api_key.trim().to_string();
        }
        for env_key in ["OPENAI_API_KEY", "AI_API_KEY"] {
            let value = std::env::var(env_key).unwrap_or_default();
            if !value.trim().is_empty() {
                return value.trim().to_string();
            }
        }
        String::new()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AiMapProposal {
    summary: String,
    #[serde(default)]
    warnings: Vec<String>,
    target: AiProposalTarget,
    #[serde(default)]
    operations: Vec<AiMapOperation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum AiProposalTarget {
    CurrentMap,
    NewMap {
        map_id: String,
        #[serde(default)]
        name: Option<String>,
        size: MapSize,
        #[serde(default)]
        default_level: i32,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum AiMapOperation {
    AddLevel {
        level: i32,
    },
    RemoveLevel {
        level: i32,
    },
    UpsertEntryPoint {
        entry_point: MapEntryPointDefinition,
    },
    RemoveEntryPoint {
        entry_point_id: String,
    },
    UpsertObject {
        object: MapObjectDefinition,
    },
    RemoveObject {
        object_id: String,
    },
    PaintCells {
        level: i32,
        cells: Vec<MapCellDefinition>,
    },
    ClearCells {
        level: i32,
        cells: Vec<GridCoord>,
    },
}

#[derive(Debug, Clone)]
struct PreparedProposal {
    target_map_id: String,
    original_id: Option<MapId>,
    definition: MapDefinition,
    details: Vec<String>,
    diagnostics: Vec<MapEditDiagnostic>,
    is_new_map: bool,
}

#[derive(Debug, Clone)]
struct AiProposalView {
    raw_output: String,
    proposal: AiMapProposal,
    prepared: Result<PreparedProposal, String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AiChatRole {
    System,
    User,
    Assistant,
}

#[derive(Debug, Clone)]
struct AiChatMessage {
    role: AiChatRole,
    content: String,
}

#[derive(Resource, Debug)]
struct AiState {
    settings: AiSettings,
    prompt_input: String,
    conversation: Vec<AiChatMessage>,
    proposal: Option<AiProposalView>,
    provider_status: String,
    pending_status: String,
}

#[derive(Resource, Default)]
struct AiWorkerState {
    receiver: Option<Arc<Mutex<Receiver<AiWorkerResult>>>>,
}

enum AiWorkerResult {
    ConnectionTest(Result<String, String>),
    Proposal(Result<AiProviderGenerateSuccess, String>),
}

#[derive(Debug)]
struct AiProviderGenerateSuccess {
    raw_output: String,
    proposal: AiMapProposal,
}

#[derive(Debug)]
struct ProviderSuccess {
    raw_text: String,
    payload: Value,
}

#[derive(Debug)]
struct ProviderFailure {
    status_code: u16,
    error: String,
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

fn map_library_item_label(map_id: &str, name: &str, dirty: bool, has_diagnostics: bool) -> String {
    let suffix = match (dirty, has_diagnostics) {
        (true, true) => " [dirty, diag]",
        (true, false) => " [dirty]",
        (false, true) => " [diag]",
        (false, false) => "",
    };
    let trimmed_name = name.trim();
    if trimmed_name.is_empty() {
        return format!("{map_id}{suffix}");
    }
    if normalized_map_label_key(trimmed_name) == normalized_map_label_key(map_id) {
        return format!("{trimmed_name}{suffix}");
    }

    format!("{trimmed_name} · {map_id}{suffix}")
}

fn load_ai_state() -> AiState {
    let settings = read_ai_settings().unwrap_or_else(|_| AiSettings::default());
    AiState {
        settings,
        prompt_input: String::new(),
        conversation: Vec::new(),
        proposal: None,
        provider_status: String::new(),
        pending_status: String::new(),
    }
}

fn push_ai_chat_message(ai: &mut AiState, role: AiChatRole, content: impl Into<String>) {
    let content = content.into();
    if content.trim().is_empty() {
        return;
    }
    ai.conversation.push(AiChatMessage { role, content });
    let max_messages = ai.settings.max_context_records.max(6);
    let overflow = ai.conversation.len().saturating_sub(max_messages);
    if overflow > 0 {
        ai.conversation.drain(0..overflow);
    }
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

fn setup_editor(mut commands: Commands) {
    commands.insert_resource(GlobalAmbientLight {
        color: Color::WHITE,
        brightness: 350.0,
        affects_lightmapped_meshes: true,
    });
    commands.spawn((
        Camera3d::default(),
        Msaa::Sample4,
        Projection::from(PerspectiveProjection {
            fov: VIEWER_CAMERA_FOV_DEGREES.to_radians(),
            near: 0.1,
            far: 2000.0,
            ..PerspectiveProjection::default()
        }),
        Transform::from_xyz(18.0, 18.0, 18.0).looking_at(Vec3::ZERO, Vec3::Y),
        EditorCamera,
    ));
    commands.spawn((
        DirectionalLight {
            shadows_enabled: true,
            illuminance: 32_000.0,
            ..default()
        },
        Transform::from_xyz(14.0, 22.0, 10.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
}

fn editor_ui_system(
    mut contexts: EguiContexts,
    mut editor: ResMut<EditorState>,
    mut ui_state: ResMut<EditorUiState>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    mut ai: ResMut<AiState>,
    mut worker: ResMut<AiWorkerState>,
    diagnostics: Res<DiagnosticsStore>,
) {
    let ctx = contexts
        .ctx_mut()
        .expect("primary egui context should exist for the map editor");

    egui::TopBottomPanel::top("top").show(ctx, |ui| {
        egui::MenuBar::new().ui(ui, |ui| {
            ui.menu_button("File", |ui| {
                if ui.button("Reload").clicked() {
                    ai.proposal = None;
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
                    ui_state.show_settings_window = true;
                    ui.close();
                }
            });

            ui.separator();
            ui.heading("CDC Map Editor");
            ui.label("Bevy-native map authoring shell");

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
                            editor.selected_map_id = Some(map_id.clone());
                            editor.current_map_level = default_level;
                            editor.scene_dirty = true;
                            if let Some(doc) = editor.maps.get(&map_id) {
                                orbit_camera.target = map_focus_target(&doc.definition);
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
            egui::ScrollArea::vertical().show(ui, |ui| {
                match editor.selected_view {
                    LibraryView::Maps => {
                        if let Some(selected_map_id) = editor.selected_map_id.clone() {
                            if let Some(doc) = editor.maps.get(&selected_map_id).cloned() {
                                ui.heading("Map");
                                ui.label(format!("Id: {}", doc.definition.id.as_str()));
                                ui.label(format!(
                                    "Size: {} x {} · levels: {} · objects: {}",
                                    doc.definition.size.width,
                                    doc.definition.size.height,
                                    doc.definition.levels.len(),
                                    doc.definition.objects.len()
                                ));
                                ui.label(format!(
                                    "Dirty: {}",
                                    if doc.dirty { "yes" } else { "no" }
                                ));
                                for diagnostic in &doc.diagnostics {
                                    draw_diagnostic(ui, diagnostic);
                                }
                            }
                        }
                    }
                    LibraryView::Overworlds => {
                        ui.heading("Overworld");
                        ui.label(
                            "Overworld is view-first in this phase. AI authoring targets maps.",
                        );
                    }
                }

                ui.separator();
                ui.heading("AI");
                ui.horizontal(|ui| {
                    if ui.button("Settings").clicked() {
                        ui_state.show_settings_window = true;
                    }
                    ui.label(format!("Model: {}", ai.settings.model));
                });
                ui.label("Prompt");
                ui.add(egui::TextEdit::multiline(&mut ai.prompt_input).desired_rows(6));
                if !ai.conversation.is_empty() {
                    ui.label("Session");
                    egui::ScrollArea::vertical()
                        .max_height(180.0)
                        .show(ui, |ui| {
                            for message in &ai.conversation {
                                let prefix = match message.role {
                                    AiChatRole::System => "System",
                                    AiChatRole::User => "User",
                                    AiChatRole::Assistant => "Assistant",
                                };
                                ui.group(|ui| {
                                    ui.label(format!("{prefix}:"));
                                    ui.label(&message.content);
                                });
                            }
                        });
                }
                if ui
                    .add_enabled(
                        worker.receiver.is_none(),
                        egui::Button::new("Generate Proposal"),
                    )
                    .clicked()
                {
                    start_ai_generation(&editor, &mut ai, &mut worker);
                }
                if let Some(proposal) = ai.proposal.clone() {
                    ui.separator();
                    ui.label(format!("Summary: {}", proposal.proposal.summary));
                    for warning in &proposal.proposal.warnings {
                        ui.label(format!("- {warning}"));
                    }
                    match &proposal.prepared {
                        Ok(prepared) => {
                            ui.label(format!(
                                "Preview target: {}{}",
                                prepared.target_map_id,
                                if prepared.is_new_map {
                                    " (new map)"
                                } else {
                                    ""
                                }
                            ));
                            for detail in &prepared.details {
                                ui.label(format!("- {detail}"));
                            }
                            for diagnostic in &prepared.diagnostics {
                                draw_diagnostic(ui, diagnostic);
                            }
                        }
                        Err(error) => {
                            ui.colored_label(egui::Color32::from_rgb(242, 94, 94), error);
                        }
                    }
                    ui.collapsing("Raw Output", |ui| {
                        ui.code(&proposal.raw_output);
                    });
                    if ui
                        .add_enabled(
                            proposal.prepared.is_ok() && worker.receiver.is_none(),
                            egui::Button::new("Apply Proposal To Preview"),
                        )
                        .clicked()
                    {
                        editor.status = apply_prepared_proposal(&mut editor, &mut ai, &proposal)
                            .unwrap_or_else(|error| error);
                    }
                }
            });
        });

    if ui_state.show_settings_window {
        let mut open = ui_state.show_settings_window;
        egui::Window::new("AI Settings")
            .open(&mut open)
            .collapsible(false)
            .resizable(true)
            .default_width(420.0)
            .show(ctx, |ui| {
                ui.label("Base URL");
                ui.text_edit_singleline(&mut ai.settings.base_url);
                ui.label("Model");
                ui.text_edit_singleline(&mut ai.settings.model);
                ui.label("API Key");
                ui.add(egui::TextEdit::singleline(&mut ai.settings.api_key).password(true));
                ui.label("Timeout (sec)");
                ui.add(egui::DragValue::new(&mut ai.settings.timeout_sec).range(5..=300));
                ui.label("Context messages");
                ui.add(egui::DragValue::new(&mut ai.settings.max_context_records).range(6..=128));

                ui.separator();
                ui.horizontal(|ui| {
                    if ui.button("Save Settings").clicked() {
                        ai.provider_status =
                            persist_ai_settings(&mut ai).unwrap_or_else(|error| error);
                    }
                    if ui
                        .add_enabled(
                            worker.receiver.is_none(),
                            egui::Button::new("Test Connection"),
                        )
                        .clicked()
                    {
                        start_ai_connection_test(&mut ai, &mut worker);
                    }
                });

                if !ai.provider_status.is_empty() {
                    ui.separator();
                    ui.label(&ai.provider_status);
                }
                if !ai.pending_status.is_empty() {
                    ui.label(&ai.pending_status);
                }
            });
        ui_state.show_settings_window = open;
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
                        ui.strong(&hovered_cell.title);
                        for line in &hovered_cell.lines {
                            ui.label(line);
                        }
                    });
                });
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
    Ok(format!("Saved map {}.", next_map_id))
}

fn ai_settings_path() -> PathBuf {
    if let Ok(app_data) = std::env::var("APPDATA") {
        let trimmed = app_data.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed)
                .join("cdc-survival-game")
                .join("bevy_map_editor")
                .join("ai_settings.json");
        }
    }
    repo_root()
        .join(".local")
        .join("bevy_map_editor")
        .join("ai_settings.json")
}

fn read_ai_settings() -> Result<AiSettings, String> {
    let path = ai_settings_path();
    if !path.exists() {
        return Ok(AiSettings::default());
    }
    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: AiSettings = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    Ok(parsed.normalized())
}

fn write_ai_settings(settings: &AiSettings) -> Result<(), String> {
    let path = ai_settings_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
    }
    let raw = serde_json::to_string_pretty(&settings.clone().normalized())
        .map_err(|error| format!("failed to serialize AI settings: {error}"))?;
    fs::write(&path, raw).map_err(|error| format!("failed to write {}: {error}", path.display()))
}

fn persist_ai_settings(ai: &mut AiState) -> Result<String, String> {
    let normalized = ai.settings.clone().normalized();
    write_ai_settings(&normalized)?;
    ai.settings = normalized;
    Ok(format!(
        "Saved AI settings to {}.",
        ai_settings_path().display()
    ))
}

fn build_map_prompt_payload(
    settings: &AiSettings,
    selected_map: &MapDefinition,
    available_map_ids: &[String],
    conversation: &[AiChatMessage],
    user_prompt: &str,
) -> Value {
    let system_prompt = [
        "You are generating a structured tactical map edit proposal for the Bevy-native CDC map editor.",
        "Return exactly one JSON object. Do not emit markdown, prose, or code fences.",
        "The object must have summary, warnings, target, and operations fields.",
        "target.kind must be current_map or new_map.",
        "Supported operation kinds: add_level, remove_level, upsert_entry_point, remove_entry_point, upsert_object, remove_object, paint_cells, clear_cells.",
        "Use the existing map JSON schema exactly for entry_point, object, cell, and grid payloads.",
        "Prefer the smallest valid change set that satisfies the request.",
    ]
    .join("\n");

    let conversation_payload = conversation
        .iter()
        .map(|message| {
            json!({
                "role": match message.role {
                    AiChatRole::User => "user",
                    AiChatRole::Assistant => "assistant",
                    AiChatRole::System => "system",
                },
                "content": message.content,
            })
        })
        .collect::<Vec<_>>();

    json!({
        "provider_config": {
            "base_url": settings.base_url,
            "model": settings.model,
            "api_key": settings.effective_api_key(),
            "timeout_sec": settings.timeout_sec,
        },
        "temperature": 0.2,
        "max_tokens": 2600,
        "messages": [
            { "role": "system", "content": system_prompt },
            {
                "role": "user",
                "content": serde_json::to_string_pretty(&json!({
                    "task": user_prompt,
                    "selected_map_id": selected_map.id.as_str(),
                    "selected_map": selected_map,
                    "available_map_ids": available_map_ids,
                    "recent_conversation": conversation_payload,
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            }
        ]
    })
}

fn test_ai_provider_connection(settings: &AiSettings) -> Result<String, String> {
    let settings = settings.clone().normalized();
    let base_url = settings.base_url.trim().trim_end_matches('/').to_string();
    let api_key = settings.effective_api_key();
    if base_url.is_empty() {
        return Err("Base URL cannot be empty.".to_string());
    }
    if api_key.is_empty() {
        return Err("API key is not configured.".to_string());
    }

    let client = build_http_client(settings.timeout_sec)?;
    let response = client
        .get(format!("{base_url}{MODELS_PATH}"))
        .bearer_auth(api_key)
        .header("Accept", "application/json")
        .send();

    match response {
        Ok(response) if response.status().is_success() => {
            Ok("AI provider connection succeeded.".to_string())
        }
        Ok(response) => {
            let status = response.status().as_u16();
            let body = response.text().unwrap_or_default();
            Err(map_http_error(status, &body))
        }
        Err(error) => Err(format!("Network failure: {error}")),
    }
}

fn perform_chat_completion(
    settings: &AiSettings,
    payload: &Value,
) -> Result<ProviderSuccess, ProviderFailure> {
    let provider_config = payload
        .get("provider_config")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let base_url = provider_config
        .get("base_url")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .trim_end_matches('/')
        .to_string();
    let api_key = provider_config
        .get("api_key")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();
    let model = provider_config
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    if base_url.is_empty() {
        return Err(ProviderFailure {
            status_code: 0,
            error: "Base URL cannot be empty.".to_string(),
        });
    }
    if model.is_empty() {
        return Err(ProviderFailure {
            status_code: 0,
            error: "Model cannot be empty.".to_string(),
        });
    }
    if api_key.is_empty() {
        return Err(ProviderFailure {
            status_code: 0,
            error: "API key is not configured.".to_string(),
        });
    }

    let client = build_http_client(settings.timeout_sec).map_err(|error| ProviderFailure {
        status_code: 0,
        error,
    })?;
    let request_body = json!({
        "model": model,
        "messages": payload.get("messages").cloned().unwrap_or_else(|| json!([])),
        "temperature": payload.get("temperature").and_then(Value::as_f64).unwrap_or(0.2),
        "response_format": { "type": "json_object" },
        "max_tokens": payload.get("max_tokens").and_then(Value::as_u64).unwrap_or(2600),
    });

    for attempt in 0..=1 {
        let response = client
            .post(format!("{base_url}{CHAT_COMPLETIONS_PATH}"))
            .bearer_auth(&api_key)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .json(&request_body)
            .send();

        match response {
            Ok(response) => {
                let status = response.status().as_u16();
                let raw_body = response.text().unwrap_or_default();
                if !(200..300).contains(&status) {
                    if attempt == 0 && (status == 429 || status >= 500) {
                        thread::sleep(Duration::from_secs(1));
                        continue;
                    }
                    return Err(ProviderFailure {
                        status_code: status,
                        error: map_http_error(status, &raw_body),
                    });
                }

                let response_data: Value =
                    serde_json::from_str(&raw_body).map_err(|error| ProviderFailure {
                        status_code: status,
                        error: format!("Response is not valid JSON: {error}"),
                    })?;
                let raw_content = extract_message_content(&response_data);
                let payload =
                    extract_json_payload(&raw_content).map_err(|error| ProviderFailure {
                        status_code: status,
                        error,
                    })?;

                return Ok(ProviderSuccess {
                    raw_text: raw_content,
                    payload,
                });
            }
            Err(error) => {
                if attempt == 0 {
                    continue;
                }
                return Err(ProviderFailure {
                    status_code: 0,
                    error: format!("Network request failed: {error}"),
                });
            }
        }
    }

    Err(ProviderFailure {
        status_code: 0,
        error: "AI generation failed.".to_string(),
    })
}

fn build_http_client(timeout_sec: u64) -> Result<Client, String> {
    Client::builder()
        .timeout(Duration::from_secs(timeout_sec.max(5)))
        .build()
        .map_err(|error| format!("Request initialization failed: {error}"))
}

fn extract_json_payload(raw_text: &str) -> Result<Value, String> {
    let trimmed = raw_text.trim();
    if trimmed.is_empty() {
        return Err("Response was empty.".to_string());
    }
    if let Ok(parsed) = serde_json::from_str::<Value>(trimmed) {
        if parsed.is_object() {
            return Ok(parsed);
        }
    }
    let start_index = trimmed
        .find('{')
        .ok_or_else(|| "Could not find JSON object in the response.".to_string())?;
    let end_index = trimmed
        .rfind('}')
        .ok_or_else(|| "Could not find JSON object in the response.".to_string())?;
    let slice = &trimmed[start_index..=end_index];
    let reparsed: Value =
        serde_json::from_str(slice).map_err(|error| format!("JSON parse failed: {error}"))?;
    if !reparsed.is_object() {
        return Err("Response JSON must be an object.".to_string());
    }
    Ok(reparsed)
}

fn extract_message_content(response_data: &Value) -> String {
    if let Some(content) = response_data
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
        .and_then(|choice| choice.get("message"))
        .and_then(|message| message.get("content"))
    {
        match content {
            Value::String(text) => return text.clone(),
            Value::Array(parts) => {
                let joined = parts
                    .iter()
                    .filter_map(|part| part.get("text").and_then(Value::as_str))
                    .collect::<Vec<_>>()
                    .join("\n");
                if !joined.trim().is_empty() {
                    return joined;
                }
            }
            _ => {}
        }
    }
    String::new()
}

fn map_http_error(status_code: u16, raw_text: &str) -> String {
    match status_code {
        400 => "Bad request (400).".to_string(),
        401 => "Authentication failed. Check the API key (401).".to_string(),
        403 => "Request was rejected (403).".to_string(),
        404 => "Endpoint was not found (404).".to_string(),
        408 => "Request timed out (408).".to_string(),
        429 => "Rate limited. Retry later (429).".to_string(),
        500 | 502 | 503 | 504 => format!("AI service is temporarily unavailable ({status_code})."),
        _ => {
            if raw_text.trim().is_empty() {
                format!("HTTP error {status_code}")
            } else {
                format!(
                    "HTTP error {status_code}: {}",
                    raw_text.chars().take(160).collect::<String>()
                )
            }
        }
    }
}

fn normalize_provider_error(error: &ProviderFailure) -> String {
    if error.status_code == 401 || error.error.contains("Authentication") {
        return format!("Authentication failed: {}", error.error);
    }
    if error.status_code == 429 || error.error.contains("Rate limited") {
        return format!("Rate limited: {}", error.error);
    }
    if error.status_code >= 500 || error.error.contains("temporarily unavailable") {
        return format!("Provider service error: {}", error.error);
    }
    if error.error.contains("JSON") {
        return format!("Provider output was not valid JSON: {}", error.error);
    }
    if error.error.contains("Network") || error.error.contains("Request initialization") {
        return format!("Network failure: {}", error.error);
    }
    error.error.clone()
}

#[derive(Default)]
struct MapCounts {
    levels: usize,
    entry_points: usize,
    objects: usize,
    cells: usize,
}

fn map_counts(definition: &MapDefinition) -> MapCounts {
    MapCounts {
        levels: definition.levels.len(),
        entry_points: definition.entry_points.len(),
        objects: definition.objects.len(),
        cells: definition
            .levels
            .iter()
            .map(|level| level.cells.len())
            .sum(),
    }
}

fn apply_proposal_operation(
    map_service: &MapEditorService,
    definition: &MapDefinition,
    operation: &AiMapOperation,
) -> Result<MapDefinition, MapEditError> {
    match operation {
        AiMapOperation::AddLevel { level } => map_service.add_level_definition(definition, *level),
        AiMapOperation::RemoveLevel { level } => {
            map_service.remove_level_definition(definition, *level)
        }
        AiMapOperation::UpsertEntryPoint { entry_point } => {
            map_service.upsert_entry_point_definition(definition, entry_point.clone())
        }
        AiMapOperation::RemoveEntryPoint { entry_point_id } => {
            map_service.remove_entry_point_definition(definition, entry_point_id)
        }
        AiMapOperation::UpsertObject { object } => {
            map_service.upsert_object_definition(definition, object.clone())
        }
        AiMapOperation::RemoveObject { object_id } => {
            map_service.remove_object_definition(definition, object_id)
        }
        AiMapOperation::PaintCells { level, cells } => {
            map_service.paint_cells_definition(definition, *level, cells.clone())
        }
        AiMapOperation::ClearCells { level, cells } => {
            map_service.clear_cells_definition(definition, *level, cells.clone())
        }
    }
}

fn apply_prepared_proposal(
    editor: &mut EditorState,
    ai: &mut AiState,
    proposal: &AiProposalView,
) -> Result<String, String> {
    let prepared = proposal.prepared.clone()?;
    let target_map_id = prepared.target_map_id.clone();
    let dirty = prepared.is_new_map
        || editor
            .maps
            .get(&target_map_id)
            .map(|document| document.definition != prepared.definition)
            .unwrap_or(true);

    editor.maps.insert(
        target_map_id.clone(),
        WorkingMapDocument {
            original_id: prepared.original_id.clone(),
            definition: prepared.definition.clone(),
            dirty,
            diagnostics: prepared.diagnostics.clone(),
            last_save_message: None,
        },
    );
    editor.selected_view = LibraryView::Maps;
    editor.selected_map_id = Some(target_map_id.clone());
    editor.current_map_level = prepared.definition.default_level;
    editor.scene_dirty = true;
    ai.pending_status.clear();
    Ok(format!(
        "Applied proposal to preview map {}. Save to write JSON.",
        target_map_id
    ))
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
    mut cameras: Query<(&mut Projection, &mut Transform), With<EditorCamera>>,
) {
    let Ok((mut projection, mut transform)) = cameras.single_mut() else {
        return;
    };

    if let Projection::Perspective(perspective) = &mut *projection {
        perspective.fov = VIEWER_CAMERA_FOV_DEGREES.to_radians();
        perspective.near = 0.1;
        perspective.far = 2000.0;
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
    mut images: ResMut<Assets<Image>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
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
            let scene = build_static_world_from_map_definition(
                &document.definition,
                editor.current_map_level,
                StaticWorldBuildConfig::default(),
            );
            for entity in spawn_static_world_visuals(
                &mut commands,
                &mut meshes,
                &mut materials,
                &mut images,
                &scene,
            ) {
                commands.entity(entity).insert(SceneEntity);
            }
            editor.status = format!(
                "Rendering map {} at level {} in native Bevy 3D.",
                document.definition.id.as_str(),
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
            let scene = build_static_world_from_overworld_definition(&definition);
            for entity in spawn_static_world_visuals(
                &mut commands,
                &mut meshes,
                &mut materials,
                &mut images,
                &scene,
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
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        ui_state.hovered_cell = None;
        return;
    };

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let Ok(ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
        ui_state.hovered_cell = None;
        return;
    };
    let Some(point) = ray_point_on_horizontal_plane(ray, 0.0) else {
        ui_state.hovered_cell = None;
        return;
    };

    ui_state.hovered_cell = match editor.selected_view {
        LibraryView::Maps => build_map_hover_info(&editor, point),
        LibraryView::Overworlds => build_overworld_hover_info(&editor, point),
    };
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

    let mut lines = vec![format!("Map: {}", document.definition.id.as_str())];
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
        lines.push(format!("Blocked: {}", yes_no(cell.blocked)));
    }
    if let Some(location) = location {
        lines.push(format!("Location: {}", location.id.as_str()));
        if !location.name.trim().is_empty() {
            lines.push(format!("Name: {}", location.name));
        }
        lines.push(format!(
            "Kind: {}",
            overworld_location_kind_label(location.kind)
        ));
        lines.push(format!("Map: {}", location.map_id.as_str()));
        if !location.entry_point_id.trim().is_empty() {
            lines.push(format!("Entry: {}", location.entry_point_id));
        }
    }

    Some(HoveredCellInfo {
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

fn start_ai_connection_test(ai: &mut AiState, worker: &mut AiWorkerState) {
    let settings = ai.settings.clone().normalized();
    ai.pending_status = "Testing AI provider connection...".to_string();
    let (sender, receiver) = mpsc::channel();
    worker.receiver = Some(Arc::new(Mutex::new(receiver)));
    thread::spawn(move || {
        let _ = sender.send(AiWorkerResult::ConnectionTest(test_ai_provider_connection(
            &settings,
        )));
    });
}

fn start_ai_generation(editor: &EditorState, ai: &mut AiState, worker: &mut AiWorkerState) {
    let Some(selected_map_id) = editor.selected_map_id.clone() else {
        ai.provider_status = "No map selected.".to_string();
        return;
    };
    let Some(document) = editor.maps.get(&selected_map_id) else {
        ai.provider_status = "Selected map is no longer available.".to_string();
        return;
    };
    if ai.prompt_input.trim().is_empty() {
        ai.provider_status = "Prompt cannot be empty.".to_string();
        return;
    }

    let settings = ai.settings.clone().normalized();
    let prompt = ai.prompt_input.trim().to_string();
    let selected_map = document.definition.clone();
    let available_map_ids = editor.maps.keys().cloned().collect::<Vec<_>>();
    let conversation = ai.conversation.clone();
    push_ai_chat_message(ai, AiChatRole::User, prompt.clone());
    ai.prompt_input.clear();
    ai.pending_status = format!("Generating proposal for {}...", selected_map.id.as_str());
    ai.provider_status.clear();
    ai.proposal = None;

    let (sender, receiver) = mpsc::channel();
    worker.receiver = Some(Arc::new(Mutex::new(receiver)));
    thread::spawn(move || {
        let payload = build_map_prompt_payload(
            &settings,
            &selected_map,
            &available_map_ids,
            &conversation,
            &prompt,
        );
        let result = perform_chat_completion(&settings, &payload)
            .map_err(|error| normalize_provider_error(&error))
            .and_then(|response| {
                serde_json::from_value::<AiMapProposal>(response.payload)
                    .map(|proposal| AiProviderGenerateSuccess {
                        raw_output: response.raw_text,
                        proposal,
                    })
                    .map_err(|error| format!("AI proposal schema invalid: {error}"))
            });
        let _ = sender.send(AiWorkerResult::Proposal(result));
    });
}

fn poll_ai_worker_system(
    editor: Res<EditorState>,
    mut ai: ResMut<AiState>,
    mut worker: ResMut<AiWorkerState>,
) {
    let Some(receiver) = worker.receiver.as_ref().cloned() else {
        return;
    };
    let message = match receiver.lock() {
        Ok(guard) => match guard.try_recv() {
            Ok(message) => Some(message),
            Err(TryRecvError::Empty) => None,
            Err(TryRecvError::Disconnected) => {
                ai.pending_status.clear();
                ai.provider_status = "AI worker disconnected.".to_string();
                worker.receiver = None;
                return;
            }
        },
        Err(_) => {
            ai.pending_status.clear();
            ai.provider_status = "AI worker lock poisoned.".to_string();
            worker.receiver = None;
            return;
        }
    };
    let Some(message) = message else {
        return;
    };
    worker.receiver = None;
    ai.pending_status.clear();
    match message {
        AiWorkerResult::ConnectionTest(result) => {
            ai.provider_status = result.unwrap_or_else(|error| error);
        }
        AiWorkerResult::Proposal(result) => match result {
            Ok(success) => {
                push_ai_chat_message(
                    &mut ai,
                    AiChatRole::Assistant,
                    format!(
                        "Summary: {}\nOperations: {}\nWarnings: {}",
                        success.proposal.summary,
                        success.proposal.operations.len(),
                        if success.proposal.warnings.is_empty() {
                            "none".to_string()
                        } else {
                            success.proposal.warnings.join("; ")
                        }
                    ),
                );
                ai.provider_status = format!(
                    "Received proposal with {} operation(s).",
                    success.proposal.operations.len()
                );
                ai.proposal = Some(AiProposalView {
                    raw_output: success.raw_output,
                    prepared: prepare_proposal(&editor, &success.proposal),
                    proposal: success.proposal,
                });
            }
            Err(error) => {
                push_ai_chat_message(
                    &mut ai,
                    AiChatRole::System,
                    format!("Generation failed: {error}"),
                );
                ai.provider_status = error;
                ai.proposal = None;
            }
        },
    }
}

fn prepare_proposal(
    editor: &EditorState,
    proposal: &AiMapProposal,
) -> Result<PreparedProposal, String> {
    let (mut definition, original_id, target_map_id, is_new_map, before_counts) = match &proposal
        .target
    {
        AiProposalTarget::CurrentMap => {
            let selected_map_id = editor
                .selected_map_id
                .clone()
                .ok_or_else(|| "No selected map to apply the proposal against.".to_string())?;
            let document = editor
                .maps
                .get(&selected_map_id)
                .ok_or_else(|| format!("Selected map {selected_map_id} is not loaded."))?;
            (
                document.definition.clone(),
                document.original_id.clone(),
                selected_map_id,
                false,
                map_counts(&document.definition),
            )
        }
        AiProposalTarget::NewMap {
            map_id,
            name,
            size,
            default_level,
        } => (
            editor
                .map_service
                .create_map_definition(MapId(map_id.clone()), name.clone(), *size, *default_level)
                .map_err(|error| error.to_string())?,
            None,
            map_id.clone(),
            true,
            MapCounts::default(),
        ),
    };
    for operation in &proposal.operations {
        definition = apply_proposal_operation(&editor.map_service, &definition, operation)
            .map_err(|error| error.to_string())?;
    }
    let after_counts = map_counts(&definition);
    let diagnostics = validate_document(&editor.map_service, &definition);
    Ok(PreparedProposal {
        target_map_id,
        original_id,
        definition,
        details: vec![
            format!(
                "levels: {} -> {}",
                before_counts.levels, after_counts.levels
            ),
            format!(
                "entry points: {} -> {}",
                before_counts.entry_points, after_counts.entry_points
            ),
            format!(
                "objects: {} -> {}",
                before_counts.objects, after_counts.objects
            ),
            format!(
                "painted cells: {} -> {}",
                before_counts.cells, after_counts.cells
            ),
        ],
        diagnostics,
        is_new_map,
    })
}
