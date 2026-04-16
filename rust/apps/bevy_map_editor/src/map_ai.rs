use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use bevy::log::{info, warn};
use bevy_egui::egui;
use game_bevy::container_visuals::ContainerVisualRegistry;
use game_data::{
    load_character_library, load_item_library, load_world_tile_library, GridCoord,
    MapCellDefinition, MapDefinition, MapEditDiagnostic, MapEditDiagnosticSeverity, MapEditError,
    MapEntryPointDefinition, MapId, MapObjectDefinition, MapSize,
};
use game_editor::ai_chat::{
    conversation_payload, prepare_prompt_submission, start_generation_job, AiChatMessage,
    AiChatSettings, AiChatState, AiChatWorkerState, ProviderSuccess,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::{
    state::{map_display_name, validate_document, EditorState, WorkingMapDocument},
    ui::panels::draw_diagnostic,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiMapProposal {
    pub summary: String,
    #[serde(default)]
    pub warnings: Vec<String>,
    pub target: AiProposalTarget,
    #[serde(default)]
    pub operations: Vec<AiMapOperation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum AiProposalTarget {
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
pub enum AiMapOperation {
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
pub struct PreparedProposal {
    pub target_map_id: String,
    pub original_id: Option<MapId>,
    pub definition: MapDefinition,
    pub details: Vec<String>,
    pub diagnostics: Vec<MapEditDiagnostic>,
    pub review: ProposalReview,
    pub is_new_map: bool,
}

#[derive(Debug, Clone)]
pub struct AiProposalView {
    pub raw_output: String,
    pub proposal: AiMapProposal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MapAiUiAction {
    ApplyProposal,
}

#[derive(Default)]
struct MapCounts {
    levels: usize,
    entry_points: usize,
    objects: usize,
    cells: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ProposalChangeKind {
    Added,
    Removed,
    Updated,
}

#[derive(Debug, Clone)]
struct ProposalEntityChange {
    kind: ProposalChangeKind,
    label: String,
    details: Vec<String>,
    diagnostics: Vec<MapEditDiagnostic>,
}

#[derive(Debug, Clone, Default)]
struct ProposalLevelReview {
    added: Vec<i32>,
    removed: Vec<i32>,
    diagnostics: Vec<MapEditDiagnostic>,
}

#[derive(Debug, Clone)]
struct ProposalCellChangeGroup {
    level: i32,
    added: usize,
    removed: usize,
    updated: usize,
    samples: Vec<String>,
    diagnostics: Vec<MapEditDiagnostic>,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct ProposalReview {
    levels: ProposalLevelReview,
    entry_points: Vec<ProposalEntityChange>,
    objects: Vec<ProposalEntityChange>,
    cells: Vec<ProposalCellChangeGroup>,
}

#[derive(Debug, Clone, Serialize, Default)]
struct MapAiAvailableContent {
    item_ids: Vec<String>,
    character_ids: Vec<String>,
    prototype_ids: Vec<String>,
    wall_set_ids: Vec<String>,
    surface_set_ids: Vec<String>,
    container_visual_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
struct MapAiObjectKindGuidance {
    kind: &'static str,
    required_fields: Vec<&'static str>,
    notes: Vec<&'static str>,
}

#[derive(Debug, Clone, Serialize)]
struct MapAiGenerationContext {
    available_object_kinds: Vec<&'static str>,
    object_kind_guidance: Vec<MapAiObjectKindGuidance>,
    placement_rules: Vec<&'static str>,
    available_content: MapAiAvailableContent,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    load_warnings: Vec<String>,
}

pub fn start_map_ai_generation(
    editor: &EditorState,
    ai: &mut AiChatState<AiProposalView>,
    worker: &mut AiChatWorkerState<AiProposalView>,
) {
    let Some(selected_map_id) = editor.selected_map_id.clone() else {
        ai.provider_status = "No map selected.".to_string();
        warn!("map editor ai generation aborted: no selected map");
        return;
    };
    let Some(document) = editor.maps.get(&selected_map_id) else {
        ai.provider_status = "Selected map is no longer available.".to_string();
        warn!("map editor ai generation aborted: selected map missing");
        return;
    };
    let selected_map = document.definition.clone();
    let selected_map_diagnostics = validate_document(&editor.map_service, &selected_map);
    let selected_map_error_count = selected_map_diagnostics
        .iter()
        .filter(|diagnostic| diagnostic.severity == MapEditDiagnosticSeverity::Error)
        .count();
    if selected_map_error_count > 0 {
        ai.provider_status = format!(
            "Selected map has {selected_map_error_count} validation error(s). Fix them before generating a proposal."
        );
        warn!(
            "map editor ai generation aborted: map_id={} has {} validation errors",
            selected_map.id.as_str(),
            selected_map_error_count
        );
        return;
    }
    let submission = match prepare_prompt_submission(ai) {
        Ok(submission) => submission,
        Err(error) => {
            ai.provider_status = error;
            warn!("map editor ai generation aborted: invalid prompt submission");
            return;
        }
    };

    let available_map_ids = editor.maps.keys().cloned().collect::<Vec<_>>();
    let generation_context = build_map_ai_generation_context(editor);
    let provider_notes = build_generation_provider_status(
        &selected_map_diagnostics,
        &generation_context.load_warnings,
    );
    if !provider_notes.is_empty() {
        ai.provider_status = provider_notes;
    }
    let payload = build_map_prompt_payload(
        &submission.settings,
        &selected_map,
        &available_map_ids,
        &generation_context,
        &submission.conversation,
        &submission.prompt,
    );
    info!(
        "map editor ai generation started: map_id={}, prompt_chars={}",
        selected_map.id.as_str(),
        submission.prompt.len()
    );
    start_generation_job(
        ai,
        worker,
        format!(
            "Generating proposal for {}...",
            map_display_name(selected_map.id.as_str())
        ),
        payload,
        parse_map_generation_response,
    );
}

pub fn assistant_summary_text(proposal: &AiProposalView) -> String {
    format!(
        "Summary: {}\nOperations: {}\nWarnings: {}",
        proposal.proposal.summary,
        proposal.proposal.operations.len(),
        if proposal.proposal.warnings.is_empty() {
            "none".to_string()
        } else {
            proposal.proposal.warnings.join("; ")
        }
    )
}

pub fn success_status_text(proposal: &AiProposalView) -> String {
    format!(
        "Received proposal with {} operation(s).",
        proposal.proposal.operations.len()
    )
}

pub fn render_map_ai_result(
    ui: &mut egui::Ui,
    editor: &EditorState,
    proposal: &AiProposalView,
    busy: bool,
) -> Option<MapAiUiAction> {
    ui.strong("Proposal Review");
    ui.label(format!("Summary: {}", proposal.proposal.summary));
    if !proposal.proposal.warnings.is_empty() {
        ui.add_space(4.0);
        ui.label("Warnings");
        for warning in &proposal.proposal.warnings {
            ui.label(format!("- {warning}"));
        }
    }

    let prepared = prepare_proposal(editor, &proposal.proposal);
    match &prepared {
        Ok(prepared) => {
            ui.add_space(6.0);
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
            ui.add_space(6.0);
            render_proposal_review(ui, &prepared.review);
            if !prepared.diagnostics.is_empty() {
                ui.add_space(6.0);
                ui.label("Diagnostics");
                for diagnostic in &prepared.diagnostics {
                    draw_diagnostic(ui, diagnostic);
                }
            }
        }
        Err(error) => {
            ui.add_space(6.0);
            ui.colored_label(egui::Color32::from_rgb(242, 94, 94), error);
        }
    }
    ui.add_space(6.0);
    ui.collapsing("Raw Output", |ui| {
        ui.code(&proposal.raw_output);
    });

    if ui
        .add_enabled(
            prepared.is_ok() && !busy,
            egui::Button::new("Apply Proposal To Preview"),
        )
        .clicked()
    {
        return Some(MapAiUiAction::ApplyProposal);
    }
    None
}

pub fn apply_prepared_proposal(
    editor: &mut EditorState,
    proposal: &AiProposalView,
) -> Result<String, String> {
    let prepared = prepare_proposal(editor, &proposal.proposal)?;
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
    editor.show_map(target_map_id.clone(), prepared.definition.default_level);
    info!(
        "map editor applied ai proposal: target_map_id={}, operations={}, diagnostics={}, is_new_map={}",
        target_map_id,
        proposal.proposal.operations.len(),
        prepared.diagnostics.len(),
        prepared.is_new_map
    );
    Ok(format!(
        "Applied proposal to preview map {}. Save to write JSON.",
        map_display_name(&target_map_id)
    ))
}

fn build_map_prompt_payload(
    settings: &AiChatSettings,
    selected_map: &MapDefinition,
    available_map_ids: &[String],
    generation_context: &MapAiGenerationContext,
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
        "Use only the object kinds and content IDs listed in generation_context.available_content and generation_context.available_object_kinds.",
        "Do not invent wall_set_id, surface_set_id, prototype_id, item_id, character_id, or container visual_id values.",
        "For terrain and floors, prefer paint_cells and cell.visual.surface_set_id instead of fake prop objects.",
        "If the request asks for unavailable content, keep the proposal valid, add a warning, and choose the closest supported content already listed in the catalog.",
        "Prefer the smallest valid change set that satisfies the request.",
    ]
    .join("\n");

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
                    "generation_context": generation_context,
                    "recent_conversation": conversation_payload(conversation),
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            }
        ]
    })
}

fn build_map_ai_generation_context(editor: &EditorState) -> MapAiGenerationContext {
    let mut load_warnings = Vec::new();
    let available_content = editor
        .map_service
        .data_root()
        .map(|data_root| load_available_content(data_root, &mut load_warnings))
        .unwrap_or_else(|| {
            load_warnings.push(
                "Editor map service has no data_root; AI content catalog is incomplete."
                    .to_string(),
            );
            MapAiAvailableContent::default()
        });

    MapAiGenerationContext {
        available_object_kinds: vec![
            "building",
            "prop",
            "pickup",
            "interactive",
            "trigger",
            "ai_spawn",
        ],
        object_kind_guidance: vec![
            MapAiObjectKindGuidance {
                kind: "building",
                required_fields: vec![
                    "object.kind=building",
                    "object.anchor",
                    "object.footprint",
                    "props.building.prefab_id",
                    "props.building.wall_visual.kind",
                    "props.building.tile_set.wall_set_id",
                ],
                notes: vec![
                    "Use props.building.tile_set.floor_surface_set_id only when the building should paint floors.",
                    "Use props.building.tile_set.door_prototype_id only with a prototype_id from the catalog.",
                    "Only include props.building.layout when you actually need procedural building layout data.",
                ],
            },
            MapAiObjectKindGuidance {
                kind: "prop",
                required_fields: vec![
                    "object.kind=prop",
                    "object.anchor",
                    "object.footprint",
                ],
                notes: vec![
                    "Use props.visual.prototype_id for static scene props backed by world tile prototypes.",
                    "Set blocks_movement and blocks_sight to match the intended collision behavior.",
                ],
            },
            MapAiObjectKindGuidance {
                kind: "pickup",
                required_fields: vec![
                    "object.kind=pickup",
                    "object.anchor",
                    "props.pickup.item_id",
                    "props.pickup.min_count",
                    "props.pickup.max_count",
                ],
                notes: vec![
                    "item_id must come from the item catalog.",
                    "max_count must be >= min_count and both must be >= 1.",
                ],
            },
            MapAiObjectKindGuidance {
                kind: "interactive",
                required_fields: vec![
                    "object.kind=interactive",
                    "object.anchor",
                    "props.interactive.interaction_kind",
                ],
                notes: vec![
                    "Lootable/openable containers should usually be interactive objects with both props.interactive and props.container.",
                    "If props.container.visual_id is set, use a value from container_visual_ids.",
                    "Container inventory item_ids must come from the item catalog.",
                ],
            },
            MapAiObjectKindGuidance {
                kind: "trigger",
                required_fields: vec![
                    "object.kind=trigger",
                    "object.anchor",
                    "props.trigger.interaction_kind",
                ],
                notes: vec![
                    "Trigger options are reserved for scene-transition style interactions.",
                ],
            },
            MapAiObjectKindGuidance {
                kind: "ai_spawn",
                required_fields: vec![
                    "object.kind=ai_spawn",
                    "object.anchor",
                    "props.ai_spawn.spawn_id",
                    "props.ai_spawn.character_id",
                ],
                notes: vec![
                    "spawn_id must be unique within the map.",
                    "character_id must come from the character catalog.",
                ],
            },
        ],
        placement_rules: vec![
            "Use only IDs listed under available_content.",
            "For new floor or ground visuals, use paint_cells and set cell.visual.surface_set_id.",
            "For static world meshes, prefer prop objects with props.visual.prototype_id.",
            "For building shells, use building objects with tile_set IDs from the catalog instead of inventing ad hoc wall cells.",
            "Keep object_ids and spawn_ids stable and descriptive.",
            "Prefer editing the current map unless the user explicitly asks for a new map.",
        ],
        available_content,
        load_warnings,
    }
}

fn load_available_content(
    data_root: &Path,
    load_warnings: &mut Vec<String>,
) -> MapAiAvailableContent {
    let items_dir = data_root.join("items");
    let item_ids = if items_dir.exists() {
        match load_item_library(&items_dir, None) {
            Ok(library) => library
                .iter()
                .map(|(id, _)| id.to_string())
                .collect::<Vec<_>>(),
            Err(error) => {
                load_warnings.push(format!(
                    "Failed to load item catalog from {}: {error}",
                    items_dir.display()
                ));
                Vec::new()
            }
        }
    } else {
        Vec::new()
    };

    let characters_dir = data_root.join("characters");
    let character_ids = if characters_dir.exists() {
        match load_character_library(&characters_dir) {
            Ok(library) => library
                .iter()
                .map(|(id, _)| id.as_str().to_string())
                .collect::<Vec<_>>(),
            Err(error) => {
                load_warnings.push(format!(
                    "Failed to load character catalog from {}: {error}",
                    characters_dir.display()
                ));
                Vec::new()
            }
        }
    } else {
        Vec::new()
    };

    let world_tiles_dir = data_root.join("world_tiles");
    let (prototype_ids, wall_set_ids, surface_set_ids) = if world_tiles_dir.exists() {
        match load_world_tile_library(&world_tiles_dir) {
            Ok(library) => (
                library.prototype_ids().into_iter().collect::<Vec<_>>(),
                library.wall_set_ids().into_iter().collect::<Vec<_>>(),
                library.surface_set_ids().into_iter().collect::<Vec<_>>(),
            ),
            Err(error) => {
                load_warnings.push(format!(
                    "Failed to load world tile catalog from {}: {error}",
                    world_tiles_dir.display()
                ));
                (Vec::new(), Vec::new(), Vec::new())
            }
        }
    } else {
        (Vec::new(), Vec::new(), Vec::new())
    };

    MapAiAvailableContent {
        item_ids,
        character_ids,
        prototype_ids,
        wall_set_ids,
        surface_set_ids,
        container_visual_ids: ContainerVisualRegistry::builtin().ids(),
    }
}

pub fn parse_map_generation_response(response: ProviderSuccess) -> Result<AiProposalView, String> {
    serde_json::from_value::<AiMapProposal>(response.payload)
        .map(|proposal| {
            info!(
                "map editor ai generation completed: operations={}, warnings={}",
                proposal.operations.len(),
                proposal.warnings.len()
            );
            AiProposalView {
                raw_output: response.raw_text,
                proposal,
            }
        })
        .map_err(|error| {
            warn!("map editor ai proposal schema invalid: {error}");
            format!("AI proposal schema invalid: {error}")
        })
}

pub fn prepare_proposal(
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
    let review = build_proposal_review(
        if is_new_map {
            None
        } else {
            editor.maps.get(&target_map_id)
        },
        &definition,
        &diagnostics,
    );
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
        review,
        is_new_map,
    })
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
    map_service: &game_data::MapEditorService,
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

fn build_generation_provider_status(
    selected_map_diagnostics: &[MapEditDiagnostic],
    catalog_warnings: &[String],
) -> String {
    let warning_count = selected_map_diagnostics
        .iter()
        .filter(|diagnostic| diagnostic.severity == MapEditDiagnosticSeverity::Warning)
        .count();
    let info_count = selected_map_diagnostics
        .iter()
        .filter(|diagnostic| diagnostic.severity == MapEditDiagnosticSeverity::Info)
        .count();
    let mut parts = Vec::new();
    if warning_count > 0 || info_count > 0 {
        parts.push(format!(
            "Selected map preflight: {warning_count} warning(s), {info_count} info item(s)."
        ));
    }
    if !catalog_warnings.is_empty() {
        parts.push(format!(
            "AI content catalog warnings: {}",
            catalog_warnings.join(" | ")
        ));
    }
    parts.join(" ")
}

fn build_proposal_review(
    before_document: Option<&WorkingMapDocument>,
    after_definition: &MapDefinition,
    diagnostics: &[MapEditDiagnostic],
) -> ProposalReview {
    let Some(before_definition) = before_document.map(|document| &document.definition) else {
        return build_new_map_review(after_definition, diagnostics);
    };

    ProposalReview {
        levels: build_level_review(before_definition, after_definition, diagnostics),
        entry_points: build_entry_point_review(before_definition, after_definition, diagnostics),
        objects: build_object_review(before_definition, after_definition, diagnostics),
        cells: build_cell_review(before_definition, after_definition, diagnostics),
    }
}

fn build_new_map_review(
    definition: &MapDefinition,
    diagnostics: &[MapEditDiagnostic],
) -> ProposalReview {
    let entry_points = definition
        .entry_points
        .iter()
        .map(|entry_point| ProposalEntityChange {
            kind: ProposalChangeKind::Added,
            label: entry_point.id.clone(),
            details: vec![
                format!("grid {}", grid_label(entry_point.grid)),
                format!("facing {}", entry_point.facing.as_deref().unwrap_or("none")),
            ],
            diagnostics: diagnostics_matching(diagnostics, &[entry_point.id.clone()]),
        })
        .collect();
    let objects = definition
        .objects
        .iter()
        .map(|object| ProposalEntityChange {
            kind: ProposalChangeKind::Added,
            label: object.object_id.clone(),
            details: object_summary(object),
            diagnostics: diagnostics_matching(diagnostics, &[object.object_id.clone()]),
        })
        .collect();
    let mut level_cells = BTreeMap::<i32, Vec<String>>::new();
    for level in &definition.levels {
        for cell in &level.cells {
            level_cells.entry(level.y).or_default().push(format!(
                "({}, {}) {}",
                cell.x,
                cell.z,
                cell_brief(cell)
            ));
        }
    }
    let cells = level_cells
        .into_iter()
        .map(|(level, samples)| ProposalCellChangeGroup {
            level,
            added: samples.len(),
            removed: 0,
            updated: 0,
            samples: samples.into_iter().take(6).collect(),
            diagnostics: diagnostics_matching(diagnostics, &[format!("level {level}")]),
        })
        .collect();

    ProposalReview {
        levels: ProposalLevelReview {
            added: definition.levels.iter().map(|level| level.y).collect(),
            removed: Vec::new(),
            diagnostics: Vec::new(),
        },
        entry_points,
        objects,
        cells,
    }
}

fn build_level_review(
    before: &MapDefinition,
    after: &MapDefinition,
    diagnostics: &[MapEditDiagnostic],
) -> ProposalLevelReview {
    let before_levels = before
        .levels
        .iter()
        .map(|level| level.y)
        .collect::<BTreeSet<_>>();
    let after_levels = after
        .levels
        .iter()
        .map(|level| level.y)
        .collect::<BTreeSet<_>>();
    let added = after_levels
        .difference(&before_levels)
        .copied()
        .collect::<Vec<_>>();
    let removed = before_levels
        .difference(&after_levels)
        .copied()
        .collect::<Vec<_>>();
    let mut patterns = added
        .iter()
        .chain(removed.iter())
        .map(|level| format!("level {level}"))
        .collect::<Vec<_>>();
    patterns.extend(
        added
            .iter()
            .chain(removed.iter())
            .map(|level| format!(" y {level}")),
    );
    ProposalLevelReview {
        added,
        removed,
        diagnostics: diagnostics_matching(diagnostics, &patterns),
    }
}

fn build_entry_point_review(
    before: &MapDefinition,
    after: &MapDefinition,
    diagnostics: &[MapEditDiagnostic],
) -> Vec<ProposalEntityChange> {
    let before_map = before
        .entry_points
        .iter()
        .map(|entry_point| (entry_point.id.as_str(), entry_point))
        .collect::<BTreeMap<_, _>>();
    let after_map = after
        .entry_points
        .iter()
        .map(|entry_point| (entry_point.id.as_str(), entry_point))
        .collect::<BTreeMap<_, _>>();
    let ids = before_map
        .keys()
        .chain(after_map.keys())
        .copied()
        .collect::<BTreeSet<_>>();
    let mut changes = Vec::new();
    for id in ids {
        match (before_map.get(id), after_map.get(id)) {
            (None, Some(entry_point)) => changes.push(ProposalEntityChange {
                kind: ProposalChangeKind::Added,
                label: id.to_string(),
                details: vec![
                    format!("grid {}", grid_label(entry_point.grid)),
                    format!("facing {}", entry_point.facing.as_deref().unwrap_or("none")),
                ],
                diagnostics: diagnostics_matching(diagnostics, &[id.to_string()]),
            }),
            (Some(entry_point), None) => changes.push(ProposalEntityChange {
                kind: ProposalChangeKind::Removed,
                label: id.to_string(),
                details: vec![format!("removed from {}", grid_label(entry_point.grid))],
                diagnostics: diagnostics_matching(diagnostics, &[id.to_string()]),
            }),
            (Some(before_entry_point), Some(after_entry_point))
                if before_entry_point != after_entry_point =>
            {
                changes.push(ProposalEntityChange {
                    kind: ProposalChangeKind::Updated,
                    label: id.to_string(),
                    details: entry_point_delta(before_entry_point, after_entry_point),
                    diagnostics: diagnostics_matching(diagnostics, &[id.to_string()]),
                });
            }
            _ => {}
        }
    }
    changes
}

fn build_object_review(
    before: &MapDefinition,
    after: &MapDefinition,
    diagnostics: &[MapEditDiagnostic],
) -> Vec<ProposalEntityChange> {
    let before_map = before
        .objects
        .iter()
        .map(|object| (object.object_id.as_str(), object))
        .collect::<BTreeMap<_, _>>();
    let after_map = after
        .objects
        .iter()
        .map(|object| (object.object_id.as_str(), object))
        .collect::<BTreeMap<_, _>>();
    let ids = before_map
        .keys()
        .chain(after_map.keys())
        .copied()
        .collect::<BTreeSet<_>>();
    let mut changes = Vec::new();
    for id in ids {
        match (before_map.get(id), after_map.get(id)) {
            (None, Some(object)) => changes.push(ProposalEntityChange {
                kind: ProposalChangeKind::Added,
                label: id.to_string(),
                details: object_summary(object),
                diagnostics: diagnostics_matching(diagnostics, &[id.to_string()]),
            }),
            (Some(object), None) => changes.push(ProposalEntityChange {
                kind: ProposalChangeKind::Removed,
                label: id.to_string(),
                details: vec![format!("removed {}", object_kind_label(object))],
                diagnostics: diagnostics_matching(diagnostics, &[id.to_string()]),
            }),
            (Some(before_object), Some(after_object)) if before_object != after_object => {
                changes.push(ProposalEntityChange {
                    kind: ProposalChangeKind::Updated,
                    label: id.to_string(),
                    details: object_delta(before_object, after_object),
                    diagnostics: diagnostics_matching(diagnostics, &[id.to_string()]),
                });
            }
            _ => {}
        }
    }
    changes
}

fn build_cell_review(
    before: &MapDefinition,
    after: &MapDefinition,
    diagnostics: &[MapEditDiagnostic],
) -> Vec<ProposalCellChangeGroup> {
    let before_cells = collect_cells(before);
    let after_cells = collect_cells(after);
    let keys = before_cells
        .keys()
        .chain(after_cells.keys())
        .copied()
        .collect::<BTreeSet<_>>();
    let mut by_level = BTreeMap::<i32, ProposalCellChangeGroup>::new();

    for key @ (level, x, z) in keys {
        let group = by_level
            .entry(level)
            .or_insert_with(|| ProposalCellChangeGroup {
                level,
                added: 0,
                removed: 0,
                updated: 0,
                samples: Vec::new(),
                diagnostics: Vec::new(),
            });
        match (before_cells.get(&key), after_cells.get(&key)) {
            (None, Some(after_cell)) => {
                group.added += 1;
                push_cell_sample(
                    &mut group.samples,
                    format!("({}, {}) added {}", x, z, cell_brief(after_cell)),
                );
            }
            (Some(before_cell), None) => {
                group.removed += 1;
                push_cell_sample(
                    &mut group.samples,
                    format!("({}, {}) removed {}", x, z, cell_brief(before_cell)),
                );
            }
            (Some(before_cell), Some(after_cell)) if before_cell != after_cell => {
                group.updated += 1;
                push_cell_sample(
                    &mut group.samples,
                    format!("({}, {}) {}", x, z, cell_delta(before_cell, after_cell)),
                );
            }
            _ => {}
        }
    }

    for group in by_level.values_mut() {
        group.diagnostics = diagnostics_matching(
            diagnostics,
            &[
                format!("level {}", group.level),
                format!(", {},", group.level),
            ],
        );
    }

    by_level
        .into_values()
        .filter(|group| group.added > 0 || group.removed > 0 || group.updated > 0)
        .collect()
}

fn collect_cells(definition: &MapDefinition) -> BTreeMap<(i32, u32, u32), MapCellDefinition> {
    let mut cells = BTreeMap::new();
    for level in &definition.levels {
        for cell in &level.cells {
            cells.insert((level.y, cell.x, cell.z), cell.clone());
        }
    }
    cells
}

fn entry_point_delta(
    before: &MapEntryPointDefinition,
    after: &MapEntryPointDefinition,
) -> Vec<String> {
    let mut details = Vec::new();
    if before.grid != after.grid {
        details.push(format!(
            "grid {} -> {}",
            grid_label(before.grid),
            grid_label(after.grid)
        ));
    }
    if before.facing != after.facing {
        details.push(format!(
            "facing {} -> {}",
            before.facing.as_deref().unwrap_or("none"),
            after.facing.as_deref().unwrap_or("none")
        ));
    }
    if before.extra != after.extra {
        details.push("extra fields changed".to_string());
    }
    if details.is_empty() {
        details.push("definition changed".to_string());
    }
    details
}

fn object_summary(object: &MapObjectDefinition) -> Vec<String> {
    vec![
        object_kind_label(object).to_string(),
        format!("anchor {}", grid_label(object.anchor)),
        format!(
            "footprint {}x{}",
            object.footprint.width, object.footprint.height
        ),
    ]
}

fn object_delta(before: &MapObjectDefinition, after: &MapObjectDefinition) -> Vec<String> {
    let mut details = Vec::new();
    if before.kind != after.kind {
        details.push(format!(
            "kind {} -> {}",
            object_kind_label(before),
            object_kind_label(after)
        ));
    }
    if before.anchor != after.anchor {
        details.push(format!(
            "anchor {} -> {}",
            grid_label(before.anchor),
            grid_label(after.anchor)
        ));
    }
    if before.footprint != after.footprint {
        details.push(format!(
            "footprint {}x{} -> {}x{}",
            before.footprint.width,
            before.footprint.height,
            after.footprint.width,
            after.footprint.height
        ));
    }
    if before.rotation != after.rotation {
        details.push(format!(
            "rotation {:?} -> {:?}",
            before.rotation, after.rotation
        ));
    }
    if before.blocks_movement != after.blocks_movement {
        details.push(format!(
            "blocks_movement {} -> {}",
            before.blocks_movement, after.blocks_movement
        ));
    }
    if before.blocks_sight != after.blocks_sight {
        details.push(format!(
            "blocks_sight {} -> {}",
            before.blocks_sight, after.blocks_sight
        ));
    }
    if before.props != after.props {
        details.push("props changed".to_string());
    }
    if details.is_empty() {
        details.push("definition changed".to_string());
    }
    details
}

fn object_kind_label(object: &MapObjectDefinition) -> &'static str {
    match object.kind {
        game_data::MapObjectKind::Building => "building",
        game_data::MapObjectKind::Prop => "prop",
        game_data::MapObjectKind::Pickup => "pickup",
        game_data::MapObjectKind::Interactive => "interactive",
        game_data::MapObjectKind::Trigger => "trigger",
        game_data::MapObjectKind::AiSpawn => "ai_spawn",
    }
}

fn grid_label(grid: GridCoord) -> String {
    format!("({}, {}, {})", grid.x, grid.y, grid.z)
}

fn cell_brief(cell: &MapCellDefinition) -> String {
    let mut parts = Vec::new();
    if !cell.terrain.trim().is_empty() {
        parts.push(format!("terrain={}", cell.terrain));
    }
    if let Some(visual) = cell.visual.as_ref() {
        if let Some(surface_set_id) = visual.surface_set_id.as_ref() {
            parts.push(format!("surface={}", surface_set_id.as_str()));
        }
    }
    if parts.is_empty() {
        "cell".to_string()
    } else {
        parts.join(", ")
    }
}

fn cell_delta(before: &MapCellDefinition, after: &MapCellDefinition) -> String {
    let mut parts = Vec::new();
    if before.terrain != after.terrain {
        parts.push(format!("terrain {} -> {}", before.terrain, after.terrain));
    }
    if before.blocks_movement != after.blocks_movement {
        parts.push(format!(
            "blocks_movement {} -> {}",
            before.blocks_movement, after.blocks_movement
        ));
    }
    if before.blocks_sight != after.blocks_sight {
        parts.push(format!(
            "blocks_sight {} -> {}",
            before.blocks_sight, after.blocks_sight
        ));
    }
    if before.visual != after.visual {
        parts.push(format!(
            "visual {} -> {}",
            cell_visual_label(before),
            cell_visual_label(after)
        ));
    }
    if before.extra != after.extra {
        parts.push("extra fields changed".to_string());
    }
    if parts.is_empty() {
        "updated".to_string()
    } else {
        parts.join("; ")
    }
}

fn cell_visual_label(cell: &MapCellDefinition) -> String {
    cell.visual
        .as_ref()
        .and_then(|visual| visual.surface_set_id.as_ref())
        .map(|surface_set_id| surface_set_id.as_str().to_string())
        .unwrap_or_else(|| "none".to_string())
}

fn diagnostics_matching(
    diagnostics: &[MapEditDiagnostic],
    patterns: &[String],
) -> Vec<MapEditDiagnostic> {
    diagnostics
        .iter()
        .filter(|diagnostic| {
            patterns
                .iter()
                .any(|pattern| diagnostic.message.contains(pattern))
        })
        .cloned()
        .collect()
}

fn push_cell_sample(samples: &mut Vec<String>, sample: String) {
    if samples.len() < 6 {
        samples.push(sample);
    }
}

fn render_proposal_review(ui: &mut egui::Ui, review: &ProposalReview) {
    ui.label("Structured Changes");

    let level_change_count = review.levels.added.len() + review.levels.removed.len();
    let entry_point_change_count = review.entry_points.len();
    let object_change_count = review.objects.len();
    let cell_change_count = review.cells.len();
    if level_change_count == 0
        && entry_point_change_count == 0
        && object_change_count == 0
        && cell_change_count == 0
    {
        ui.label("- No structural changes detected.");
        return;
    }

    if level_change_count > 0 {
        ui.collapsing(format!("Levels ({level_change_count})"), |ui| {
            for level in &review.levels.added {
                render_change_row(ui, ProposalChangeKind::Added, format!("level {level}"), &[]);
            }
            for level in &review.levels.removed {
                render_change_row(
                    ui,
                    ProposalChangeKind::Removed,
                    format!("level {level}"),
                    &[],
                );
            }
            for diagnostic in &review.levels.diagnostics {
                draw_diagnostic(ui, diagnostic);
            }
        });
    }

    if entry_point_change_count > 0 {
        ui.collapsing(format!("Entry Points ({entry_point_change_count})"), |ui| {
            for change in &review.entry_points {
                render_entity_change(ui, change);
            }
        });
    }

    if object_change_count > 0 {
        ui.collapsing(format!("Objects ({object_change_count})"), |ui| {
            for change in &review.objects {
                render_entity_change(ui, change);
            }
        });
    }

    if cell_change_count > 0 {
        ui.collapsing(
            format!("Cells ({cell_change_count} levels touched)"),
            |ui| {
                for group in &review.cells {
                    ui.label(format!(
                        "Level {}: +{} / -{} / ~{}",
                        group.level, group.added, group.removed, group.updated
                    ));
                    for sample in &group.samples {
                        ui.small(format!("· {sample}"));
                    }
                    for diagnostic in &group.diagnostics {
                        draw_diagnostic(ui, diagnostic);
                    }
                    ui.add_space(4.0);
                }
            },
        );
    }
}

fn render_entity_change(ui: &mut egui::Ui, change: &ProposalEntityChange) {
    render_change_row(ui, change.kind, change.label.clone(), &change.details);
    for diagnostic in &change.diagnostics {
        draw_diagnostic(ui, diagnostic);
    }
    ui.add_space(4.0);
}

fn render_change_row(
    ui: &mut egui::Ui,
    kind: ProposalChangeKind,
    label: String,
    details: &[String],
) {
    let (prefix, color) = match kind {
        ProposalChangeKind::Added => ("+", egui::Color32::from_rgb(80, 180, 110)),
        ProposalChangeKind::Removed => ("-", egui::Color32::from_rgb(220, 100, 100)),
        ProposalChangeKind::Updated => ("~", egui::Color32::from_rgb(233, 180, 64)),
    };
    ui.colored_label(color, format!("{prefix} {label}"));
    for detail in details {
        ui.small(format!("· {detail}"));
    }
}
