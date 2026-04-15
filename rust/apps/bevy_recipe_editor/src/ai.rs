use std::collections::BTreeSet;

use bevy::log::{info, warn};
use bevy_egui::egui;
use game_data::{RecipeDefinition, RecipeEditDiagnostic};
use game_editor::ai_chat::{
    conversation_payload, prepare_prompt_submission, start_generation_job, AiChatMessage,
    AiChatSettings, ProviderSuccess,
};
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::data::validate_all_documents;
use crate::state::{
    EditorState, RecipeAiState, RecipeAiWorkerState, RecipeEditorCatalogs, WorkingRecipeDocument,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct AiRecipeProposal {
    pub(crate) summary: String,
    #[serde(default)]
    pub(crate) warnings: Vec<String>,
    pub(crate) target: AiRecipeProposalTarget,
    pub(crate) recipe: RecipeDefinition,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub(crate) enum AiRecipeProposalTarget {
    CurrentRecipe,
    NewRecipe,
}

#[derive(Debug, Clone)]
pub(crate) struct AiRecipeProposalView {
    pub(crate) raw_output: String,
    pub(crate) proposal: AiRecipeProposal,
}

#[derive(Debug, Clone)]
pub(crate) struct PreparedRecipeProposal {
    pub(crate) document_key: String,
    pub(crate) original_id: Option<String>,
    pub(crate) file_name: String,
    pub(crate) relative_path: String,
    pub(crate) definition: RecipeDefinition,
    pub(crate) diagnostics: Vec<RecipeEditDiagnostic>,
    pub(crate) is_new_recipe: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RecipeAiUiAction {
    ApplyProposal,
}

pub(crate) fn start_recipe_ai_generation(
    editor: &EditorState,
    catalogs: &RecipeEditorCatalogs,
    ai: &mut RecipeAiState,
    worker: &mut RecipeAiWorkerState,
) {
    let Some(document) = editor.selected_document() else {
        ai.provider_status = "No recipe selected.".to_string();
        warn!("recipe editor ai generation aborted: no selected recipe");
        return;
    };
    let submission = match prepare_prompt_submission(ai) {
        Ok(submission) => submission,
        Err(error) => {
            ai.provider_status = error;
            return;
        }
    };
    let payload = build_recipe_prompt_payload(
        &submission.settings,
        document,
        editor,
        catalogs,
        &submission.conversation,
        &submission.prompt,
    );
    info!(
        "recipe editor ai generation started: recipe_id={}, prompt_chars={}",
        document.definition.id,
        submission.prompt.len()
    );
    start_generation_job(
        ai,
        worker,
        format!(
            "Generating proposal for recipe {}...",
            document.definition.id
        ),
        payload,
        parse_recipe_generation_response,
    );
}

pub(crate) fn assistant_summary_text(proposal: &AiRecipeProposalView) -> String {
    format!(
        "Summary: {}\nTarget: {}\nWarnings: {}",
        proposal.proposal.summary,
        match proposal.proposal.target {
            AiRecipeProposalTarget::CurrentRecipe => "current_recipe",
            AiRecipeProposalTarget::NewRecipe => "new_recipe",
        },
        if proposal.proposal.warnings.is_empty() {
            "none".to_string()
        } else {
            proposal.proposal.warnings.join("; ")
        }
    )
}

pub(crate) fn success_status_text(proposal: &AiRecipeProposalView) -> String {
    format!(
        "Received {} proposal for recipe {}.",
        match proposal.proposal.target {
            AiRecipeProposalTarget::CurrentRecipe => "current",
            AiRecipeProposalTarget::NewRecipe => "new",
        },
        proposal.proposal.recipe.id
    )
}

pub(crate) fn render_recipe_ai_result(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &RecipeEditorCatalogs,
    proposal: &AiRecipeProposalView,
    busy: bool,
) -> Option<RecipeAiUiAction> {
    ui.strong("Proposal Review");
    ui.label(format!("Summary: {}", proposal.proposal.summary));
    ui.label(format!(
        "Target: {}",
        match proposal.proposal.target {
            AiRecipeProposalTarget::CurrentRecipe => "Current recipe",
            AiRecipeProposalTarget::NewRecipe => "New recipe",
        }
    ));
    if !proposal.proposal.warnings.is_empty() {
        ui.add_space(6.0);
        ui.label("Warnings");
        for warning in &proposal.proposal.warnings {
            ui.label(format!("- {warning}"));
        }
    }

    match prepare_proposal(editor, catalogs, proposal) {
        Ok(prepared) => {
            ui.add_space(6.0);
            ui.label(format!("Result recipe: {}", prepared.definition.id));
            ui.label(format!(
                "Mode: {}",
                if prepared.is_new_recipe {
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
            ui.collapsing("Generated Recipe JSON", |ui| {
                let raw = serde_json::to_string_pretty(&prepared.definition)
                    .unwrap_or_else(|_| "{}".to_string());
                ui.code(raw);
            });
            if ui
                .add_enabled(!busy, egui::Button::new("Apply Proposal To Draft"))
                .clicked()
            {
                return Some(RecipeAiUiAction::ApplyProposal);
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
    catalogs: &RecipeEditorCatalogs,
    proposal: &AiRecipeProposalView,
) -> Result<String, String> {
    let prepared = prepare_proposal(editor, catalogs, proposal)?;
    let dirty = match editor.documents.get(&prepared.document_key) {
        Some(document) => document.definition != prepared.definition,
        None => true,
    };

    editor.documents.insert(
        prepared.document_key.clone(),
        WorkingRecipeDocument {
            document_key: prepared.document_key.clone(),
            original_id: prepared.original_id.clone(),
            file_name: prepared.file_name.clone(),
            relative_path: prepared.relative_path.clone(),
            definition: prepared.definition.clone(),
            dirty,
            diagnostics: prepared.diagnostics.clone(),
            last_save_message: None,
        },
    );
    editor.selected_document_key = Some(prepared.document_key.clone());
    validate_all_documents(editor, catalogs)?;
    info!(
        "recipe editor applied ai proposal: recipe_id={}, target_new={}",
        prepared.definition.id, prepared.is_new_recipe
    );
    Ok(format!(
        "Applied proposal to draft recipe {}. Save to write JSON.",
        prepared.definition.id
    ))
}

fn prepare_proposal(
    editor: &EditorState,
    catalogs: &RecipeEditorCatalogs,
    proposal: &AiRecipeProposalView,
) -> Result<PreparedRecipeProposal, String> {
    let selected_key = editor
        .selected_document_key
        .clone()
        .ok_or_else(|| "No recipe selected.".to_string())?;
    let selected_document = editor
        .documents
        .get(&selected_key)
        .ok_or_else(|| "Selected recipe is no longer loaded.".to_string())?;

    let next_key = match proposal.proposal.target {
        AiRecipeProposalTarget::CurrentRecipe => selected_key,
        AiRecipeProposalTarget::NewRecipe => format!("{}.json", proposal.proposal.recipe.id),
    };
    let original_id = match proposal.proposal.target {
        AiRecipeProposalTarget::CurrentRecipe => selected_document.original_id.clone(),
        AiRecipeProposalTarget::NewRecipe => None,
    };

    for (key, document) in &editor.documents {
        if document.definition.id != proposal.proposal.recipe.id {
            continue;
        }
        let conflicts = match proposal.proposal.target {
            AiRecipeProposalTarget::CurrentRecipe => key != &selected_document.document_key,
            AiRecipeProposalTarget::NewRecipe => true,
        };
        if conflicts {
            return Err(format!(
                "proposal recipe id {} conflicts with existing draft {}",
                proposal.proposal.recipe.id, document.file_name
            ));
        }
    }

    let mut recipe_ids = editor.current_recipe_ids();
    if let AiRecipeProposalTarget::CurrentRecipe = proposal.proposal.target {
        recipe_ids.remove(&selected_document.definition.id);
    }
    recipe_ids.insert(proposal.proposal.recipe.id.clone());

    let item_ids = catalogs.item_ids.iter().copied().collect::<BTreeSet<_>>();
    let skill_ids = catalogs.skill_ids.iter().cloned().collect::<BTreeSet<_>>();
    let diagnostics = editor
        .service
        .validate_definition_with_catalog(
            &proposal.proposal.recipe,
            item_ids,
            skill_ids,
            recipe_ids,
        )
        .map_err(|error| error.to_string())?
        .diagnostics;

    Ok(PreparedRecipeProposal {
        document_key: next_key,
        original_id,
        file_name: format!("{}.json", proposal.proposal.recipe.id),
        relative_path: format!("recipes/{}.json", proposal.proposal.recipe.id),
        definition: proposal.proposal.recipe.clone(),
        diagnostics,
        is_new_recipe: matches!(proposal.proposal.target, AiRecipeProposalTarget::NewRecipe),
    })
}

pub(crate) fn parse_recipe_generation_response(
    response: ProviderSuccess,
) -> Result<AiRecipeProposalView, String> {
    let proposal: AiRecipeProposal =
        serde_json::from_value(response.payload).map_err(|error| error.to_string())?;
    Ok(AiRecipeProposalView {
        raw_output: response.raw_text,
        proposal,
    })
}

fn build_recipe_prompt_payload(
    settings: &AiChatSettings,
    current_document: &WorkingRecipeDocument,
    editor: &EditorState,
    catalogs: &RecipeEditorCatalogs,
    conversation: &[AiChatMessage],
    user_prompt: &str,
) -> serde_json::Value {
    let system_prompt = [
        "You are generating a structured recipe edit proposal for the Rust/Bevy CDC recipe editor.",
        "Return exactly one JSON object. Do not emit markdown, prose, or code fences.",
        "The object must contain summary, warnings, target, and recipe fields.",
        "target.kind must be current_recipe or new_recipe.",
        "recipe must be a complete RecipeDefinition JSON object that matches the shared Rust schema.",
        "Use only known item ids and skill ids from the provided catalogs.",
        "If you create a new recipe, choose an unused id and prefer the suggested_next_recipe_id unless the prompt requests another valid id.",
        "If you modify the current recipe, preserve existing fields unless the prompt explicitly changes them.",
        "Do not invent unsupported schema fields.",
    ]
    .join("\n");

    let item_catalog = catalogs
        .item_name_lookup
        .iter()
        .map(|(item_id, name)| {
            json!({
                "id": item_id,
                "name": name,
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
                    "selected_recipe": current_document.definition,
                    "selected_document": {
                        "file_name": current_document.file_name,
                        "relative_path": current_document.relative_path,
                        "original_id": current_document.original_id,
                    },
                    "suggested_next_recipe_id": editor.suggested_next_recipe_id(),
                    "known_recipe_ids": editor.current_recipe_ids().into_iter().collect::<Vec<_>>(),
                    "item_catalog": item_catalog,
                    "skill_ids": catalogs.skill_ids,
                    "recent_conversation": conversation_payload(conversation),
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            }
        ]
    })
}
