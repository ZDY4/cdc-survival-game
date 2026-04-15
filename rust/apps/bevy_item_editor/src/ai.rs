use bevy::log::{info, warn};
use bevy_egui::egui;
use game_data::ItemDefinition;
use game_editor::ai_chat::{
    conversation_payload, prepare_prompt_submission, start_generation_job, AiChatMessage,
    AiChatSettings, ProviderSuccess,
};
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::data::validate_all_documents;
use crate::state::{
    EditorState, ItemAiState, ItemAiWorkerState, ItemEditorCatalogs, WorkingItemDocument,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AiItemProposal {
    pub(crate) summary: String,
    #[serde(default)]
    pub(crate) warnings: Vec<String>,
    pub(crate) target: AiItemProposalTarget,
    pub(crate) item: ItemDefinition,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum AiItemProposalTarget {
    CurrentItem,
    NewItem,
}

#[derive(Debug, Clone)]
pub(crate) struct AiItemProposalView {
    pub(crate) raw_output: String,
    pub(crate) proposal: AiItemProposal,
}

#[derive(Debug, Clone)]
pub(crate) struct PreparedItemProposal {
    pub(crate) document_key: String,
    pub(crate) original_id: Option<u32>,
    pub(crate) file_name: String,
    pub(crate) relative_path: String,
    pub(crate) definition: ItemDefinition,
    pub(crate) diagnostics: Vec<game_data::ItemEditDiagnostic>,
    pub(crate) is_new_item: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ItemAiUiAction {
    ApplyProposal,
}

pub(crate) fn start_item_ai_generation(
    editor: &EditorState,
    catalogs: &ItemEditorCatalogs,
    ai: &mut ItemAiState,
    worker: &mut ItemAiWorkerState,
) {
    let Some(document) = editor.selected_document() else {
        ai.provider_status = "No item selected.".to_string();
        warn!("item editor ai generation aborted: no selected item");
        return;
    };
    let submission = match prepare_prompt_submission(ai) {
        Ok(submission) => submission,
        Err(error) => {
            ai.provider_status = error;
            return;
        }
    };
    let payload = build_item_prompt_payload(
        &submission.settings,
        document,
        editor,
        catalogs,
        &submission.conversation,
        &submission.prompt,
    );
    info!(
        "item editor ai generation started: item_id={}, prompt_chars={}",
        document.definition.id,
        submission.prompt.len()
    );
    start_generation_job(
        ai,
        worker,
        format!("Generating proposal for item {}...", document.definition.id),
        payload,
        parse_item_generation_response,
    );
}

pub(crate) fn assistant_summary_text(proposal: &AiItemProposalView) -> String {
    format!(
        "Summary: {}\nTarget: {}\nWarnings: {}",
        proposal.proposal.summary,
        match proposal.proposal.target {
            AiItemProposalTarget::CurrentItem => "current_item",
            AiItemProposalTarget::NewItem => "new_item",
        },
        if proposal.proposal.warnings.is_empty() {
            "none".to_string()
        } else {
            proposal.proposal.warnings.join("; ")
        }
    )
}

pub(crate) fn success_status_text(proposal: &AiItemProposalView) -> String {
    format!(
        "Received {} proposal for item {}.",
        match proposal.proposal.target {
            AiItemProposalTarget::CurrentItem => "current",
            AiItemProposalTarget::NewItem => "new",
        },
        proposal.proposal.item.id
    )
}

pub(crate) fn render_item_ai_result(
    ui: &mut egui::Ui,
    editor: &EditorState,
    proposal: &AiItemProposalView,
    busy: bool,
) -> Option<ItemAiUiAction> {
    ui.strong("Proposal Review");
    ui.label(format!("Summary: {}", proposal.proposal.summary));
    ui.label(format!(
        "Target: {}",
        match proposal.proposal.target {
            AiItemProposalTarget::CurrentItem => "Current item",
            AiItemProposalTarget::NewItem => "New item",
        }
    ));
    if !proposal.proposal.warnings.is_empty() {
        ui.add_space(6.0);
        ui.label("Warnings");
        for warning in &proposal.proposal.warnings {
            ui.label(format!("- {warning}"));
        }
    }

    match prepare_proposal(editor, proposal) {
        Ok(prepared) => {
            ui.add_space(6.0);
            ui.label(format!(
                "Result item: #{} · {}",
                prepared.definition.id, prepared.definition.name
            ));
            ui.label(format!(
                "Mode: {}",
                if prepared.is_new_item {
                    "Create draft"
                } else {
                    "Replace selected draft"
                }
            ));
            if !prepared.diagnostics.is_empty() {
                ui.add_space(6.0);
                ui.label("Diagnostics");
                for diagnostic in &prepared.diagnostics {
                    ui.colored_label(
                        egui::Color32::from_rgb(242, 94, 94),
                        format!("[{}] {}", diagnostic.code, diagnostic.message),
                    );
                }
            }
            ui.add_space(6.0);
            ui.collapsing("Generated Item JSON", |ui| {
                let raw = serde_json::to_string_pretty(&prepared.definition)
                    .unwrap_or_else(|_| "{}".to_string());
                ui.code(raw);
            });
            if ui
                .add_enabled(!busy, egui::Button::new("Apply Proposal To Draft"))
                .clicked()
            {
                return Some(ItemAiUiAction::ApplyProposal);
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
    None
}

pub(crate) fn apply_prepared_proposal(
    editor: &mut EditorState,
    proposal: &AiItemProposalView,
) -> Result<String, String> {
    let prepared = prepare_proposal(editor, proposal)?;
    let dirty = match editor.documents.get(&prepared.document_key) {
        Some(document) => document.definition != prepared.definition,
        None => true,
    };

    editor.documents.insert(
        prepared.document_key.clone(),
        WorkingItemDocument {
            document_key: prepared.document_key.clone(),
            original_id: prepared.original_id,
            file_name: prepared.file_name.clone(),
            relative_path: prepared.relative_path.clone(),
            definition: prepared.definition.clone(),
            dirty,
            diagnostics: prepared.diagnostics.clone(),
            last_save_message: None,
        },
    );
    editor.selected_document_key = Some(prepared.document_key.clone());
    validate_all_documents(editor)?;
    info!(
        "item editor applied ai proposal: item_id={}, target_new={}",
        prepared.definition.id, prepared.is_new_item
    );
    Ok(format!(
        "Applied proposal to draft item {}. Save to write JSON.",
        prepared.definition.id
    ))
}

pub(crate) fn prepare_proposal(
    editor: &EditorState,
    proposal: &AiItemProposalView,
) -> Result<PreparedItemProposal, String> {
    let selected_key = editor
        .selected_document_key
        .clone()
        .ok_or_else(|| "No item selected.".to_string())?;
    let selected_document = editor
        .documents
        .get(&selected_key)
        .ok_or_else(|| "Selected item is no longer loaded.".to_string())?;

    let next_key = match proposal.proposal.target {
        AiItemProposalTarget::CurrentItem => selected_key,
        AiItemProposalTarget::NewItem => format!("draft-{}.json", proposal.proposal.item.id),
    };
    let original_id = match proposal.proposal.target {
        AiItemProposalTarget::CurrentItem => selected_document.original_id,
        AiItemProposalTarget::NewItem => None,
    };

    for (key, document) in &editor.documents {
        if document.definition.id != proposal.proposal.item.id {
            continue;
        }
        let conflicts = match proposal.proposal.target {
            AiItemProposalTarget::CurrentItem => key != &selected_document.document_key,
            AiItemProposalTarget::NewItem => true,
        };
        if conflicts {
            return Err(format!(
                "proposal item id {} conflicts with existing draft {}",
                proposal.proposal.item.id, document.file_name
            ));
        }
    }

    let mut item_ids = editor.current_item_ids();
    if let AiItemProposalTarget::CurrentItem = proposal.proposal.target {
        item_ids.remove(&selected_document.definition.id);
    }
    item_ids.insert(proposal.proposal.item.id);
    let diagnostics = editor
        .service
        .validate_definition_with_item_ids(&proposal.proposal.item, item_ids)
        .map_err(|error| error.to_string())?
        .diagnostics;

    Ok(PreparedItemProposal {
        document_key: next_key,
        original_id,
        file_name: format!("{}.json", proposal.proposal.item.id),
        relative_path: format!("items/{}.json", proposal.proposal.item.id),
        definition: proposal.proposal.item.clone(),
        diagnostics,
        is_new_item: matches!(proposal.proposal.target, AiItemProposalTarget::NewItem),
    })
}

pub(crate) fn parse_item_generation_response(
    response: ProviderSuccess,
) -> Result<AiItemProposalView, String> {
    let proposal: AiItemProposal =
        serde_json::from_value(response.payload).map_err(|error| error.to_string())?;
    Ok(AiItemProposalView {
        raw_output: response.raw_text,
        proposal,
    })
}

fn build_item_prompt_payload(
    settings: &AiChatSettings,
    current_document: &WorkingItemDocument,
    editor: &EditorState,
    catalogs: &ItemEditorCatalogs,
    conversation: &[AiChatMessage],
    user_prompt: &str,
) -> serde_json::Value {
    let system_prompt = [
        "You are generating a structured item edit proposal for the Rust/Bevy CDC item editor.",
        "Return exactly one JSON object. Do not emit markdown, prose, or code fences.",
        "The object must contain summary, warnings, target, and item fields.",
        "target.kind must be current_item or new_item.",
        "item must be a complete ItemDefinition JSON object that matches the shared Rust schema.",
        "Use only effect ids from the provided effect catalog.",
        "If you create a new item, choose an unused id and prefer the suggested_next_item_id unless the prompt requests another valid id.",
        "If you modify the current item, preserve existing fields unless the prompt explicitly changes them.",
        "Do not invent unsupported fragment kinds or schema fields.",
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
                    "selected_item": current_document.definition,
                    "selected_document": {
                        "file_name": current_document.file_name,
                        "relative_path": current_document.relative_path,
                        "original_id": current_document.original_id,
                    },
                    "suggested_next_item_id": editor.suggested_next_item_id(),
                    "known_item_ids": editor.current_item_ids().into_iter().collect::<Vec<_>>(),
                    "effect_ids": catalogs.effect_ids,
                    "equipment_slots": catalogs.equipment_slots,
                    "known_subtypes": catalogs.known_subtypes,
                    "recent_conversation": conversation_payload(conversation),
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            }
        ]
    })
}
