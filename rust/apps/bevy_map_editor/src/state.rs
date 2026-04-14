use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::prelude::*;
use game_bevy::world_render::WorldRenderConfig;
use game_data::{
    load_map_library, load_overworld_library, load_world_tile_library, GridCoord, MapDefinition,
    MapEditDiagnostic, MapEditorService, MapId, OverworldLibrary, WorldTileLibrary,
};
use game_editor::ai_chat::{AiChatState, AiChatWorkerState};

use crate::map_ai::AiProposalView;

const PERSPECTIVE_DISTANCE_DEFAULT: f32 = 28.0;
const TOP_DOWN_DISTANCE_DEFAULT: f32 = 40.0;
const DEFAULT_CAMERA_PAN_SPEED_MULTIPLIER: f32 = 1.0;

pub(crate) type MapAiState = AiChatState<AiProposalView>;
pub(crate) type MapAiWorkerState = AiChatWorkerState<AiProposalView>;

#[derive(Component)]
pub(crate) struct EditorCamera;

#[derive(Component)]
pub(crate) struct SceneEntity;

#[derive(Resource, Clone)]
pub(crate) struct EditorWorldLabelFont(pub(crate) Handle<Font>);

#[derive(Resource, Debug, Clone)]
pub(crate) struct OrbitCameraState {
    pub(crate) base_yaw: f32,
    pub(crate) base_pitch: f32,
    pub(crate) yaw_offset: f32,
    pub(crate) is_top_down: bool,
    pub(crate) perspective_distance: f32,
    pub(crate) top_down_distance: f32,
    pub(crate) target: Vec3,
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
    pub(crate) fn reset_to_default_view(&mut self) {
        self.yaw_offset = 0.0;
        self.is_top_down = false;
        self.perspective_distance = PERSPECTIVE_DISTANCE_DEFAULT;
        self.top_down_distance = TOP_DOWN_DISTANCE_DEFAULT;
    }

    pub(crate) fn active_distance(&self) -> f32 {
        if self.is_top_down {
            self.top_down_distance
        } else {
            self.perspective_distance
        }
    }

    pub(crate) fn active_distance_mut(&mut self) -> &mut f32 {
        if self.is_top_down {
            &mut self.top_down_distance
        } else {
            &mut self.perspective_distance
        }
    }
}

#[derive(Resource, Debug, Clone, Default)]
pub(crate) struct MiddleClickState {
    pub(crate) drag_anchor_world: Option<Vec2>,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct HoveredCellInfo {
    pub(crate) grid: GridCoord,
    pub(crate) title: String,
    pub(crate) lines: Vec<String>,
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct EditorUiState {
    pub(crate) show_fps_overlay: bool,
    pub(crate) camera_pan_speed_multiplier: f32,
    pub(crate) hovered_cell: Option<HoveredCellInfo>,
    pub(crate) hovered_grid: Option<GridCoord>,
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
pub(crate) struct EditorEguiFontState {
    pub(crate) initialized: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum LibraryView {
    Maps,
    Overworlds,
}

#[derive(Debug, Clone)]
pub(crate) struct WorkingMapDocument {
    pub(crate) original_id: Option<MapId>,
    pub(crate) definition: MapDefinition,
    pub(crate) dirty: bool,
    pub(crate) diagnostics: Vec<MapEditDiagnostic>,
    pub(crate) last_save_message: Option<String>,
}

#[derive(Resource, Clone)]
pub(crate) struct EditorWorldTileDefinitions(pub(crate) WorldTileLibrary);

#[derive(Resource)]
pub(crate) struct EditorState {
    pub(crate) map_service: MapEditorService,
    pub(crate) maps: BTreeMap<String, WorkingMapDocument>,
    pub(crate) overworld_library: OverworldLibrary,
    pub(crate) selected_view: LibraryView,
    pub(crate) selected_map_id: Option<String>,
    pub(crate) selected_overworld_id: Option<String>,
    pub(crate) current_map_level: i32,
    pub(crate) search_text: String,
    pub(crate) status: String,
    pub(crate) scene_dirty: bool,
    pub(crate) scene_revision: u64,
}

pub(crate) fn load_editor_state() -> EditorState {
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

pub(crate) fn load_editor_world_tiles() -> EditorWorldTileDefinitions {
    let world_tiles_dir = project_data_dir("world_tiles");
    EditorWorldTileDefinitions(load_world_tile_library(&world_tiles_dir).unwrap_or_default())
}

fn normalized_map_label_key(value: &str) -> String {
    value
        .chars()
        .filter(|ch| !matches!(ch, '_' | '-' | ' '))
        .flat_map(|ch| ch.to_lowercase())
        .collect()
}

pub(crate) fn map_display_name(map_id: &str) -> &str {
    map_id
}

pub(crate) fn map_library_item_label(
    map_id: &str,
    name: &str,
    dirty: bool,
    has_diagnostics: bool,
) -> String {
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

pub(crate) fn build_working_maps(
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

pub(crate) fn validate_document(
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

pub(crate) fn project_data_dir(kind: &str) -> PathBuf {
    repo_root().join("data").join(kind)
}

pub(crate) fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

pub(crate) fn yes_no(value: bool) -> &'static str {
    if value {
        "yes"
    } else {
        "no"
    }
}
