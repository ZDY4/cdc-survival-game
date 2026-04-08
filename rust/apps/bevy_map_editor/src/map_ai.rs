use bevy_egui::egui;
use game_data::{
    GridCoord, MapCellDefinition, MapDefinition, MapEditDiagnostic, MapEditError,
    MapEntryPointDefinition, MapId, MapObjectDefinition, MapSize,
};
use game_editor::ai_chat::{
    conversation_payload, prepare_prompt_submission, start_generation_job, AiChatMessage,
    AiChatSettings, AiChatState, AiChatWorkerState, ProviderSuccess,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::{
    draw_diagnostic, map_display_name, validate_document, EditorState, LibraryView,
    WorkingMapDocument,
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

pub fn start_map_ai_generation(
    editor: &EditorState,
    ai: &mut AiChatState<AiProposalView>,
    worker: &mut AiChatWorkerState<AiProposalView>,
) {
    let Some(selected_map_id) = editor.selected_map_id.clone() else {
        ai.provider_status = "No map selected.".to_string();
        return;
    };
    let Some(document) = editor.maps.get(&selected_map_id) else {
        ai.provider_status = "Selected map is no longer available.".to_string();
        return;
    };
    let submission = match prepare_prompt_submission(ai) {
        Ok(submission) => submission,
        Err(error) => {
            ai.provider_status = error;
            return;
        }
    };

    let selected_map = document.definition.clone();
    let available_map_ids = editor.maps.keys().cloned().collect::<Vec<_>>();
    let payload = build_map_prompt_payload(
        &submission.settings,
        &selected_map,
        &available_map_ids,
        &submission.conversation,
        &submission.prompt,
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
    editor.selected_view = LibraryView::Maps;
    editor.selected_map_id = Some(target_map_id.clone());
    editor.current_map_level = prepared.definition.default_level;
    editor.scene_dirty = true;
    Ok(format!(
        "Applied proposal to preview map {}. Save to write JSON.",
        map_display_name(&target_map_id)
    ))
}

pub fn build_map_prompt_payload(
    settings: &AiChatSettings,
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
                    "recent_conversation": conversation_payload(conversation),
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            }
        ]
    })
}

pub fn parse_map_generation_response(response: ProviderSuccess) -> Result<AiProposalView, String> {
    serde_json::from_value::<AiMapProposal>(response.payload)
        .map(|proposal| AiProposalView {
            raw_output: response.raw_text,
            proposal,
        })
        .map_err(|error| format!("AI proposal schema invalid: {error}"))
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
