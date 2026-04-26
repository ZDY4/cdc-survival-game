use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::log::info;
use game_bevy::{load_dialogue_definitions, DialogueDefinitionPath};
use game_data::{resolve_dialogue_start_node_id, DialogueData, DialogueLibrary};
use game_editor::FlowGraphCanvasState;

use crate::state::{DialogueEditorCatalogs, DialogueSearchEntry, EditorState};

pub(crate) fn load_editor_resources(
    initial_dialogue_id: Option<String>,
) -> Result<(EditorState, DialogueEditorCatalogs), String> {
    let repo_root = repo_root();
    let path = DialogueDefinitionPath::default().0;
    let definitions = load_dialogue_definitions(&path).map_err(|error| {
        format!(
            "failed to load dialogue catalog from {}: {error}",
            path.display()
        )
    })?;
    let catalogs = build_catalogs(definitions.0);

    let mut editor = EditorState {
        repo_root,
        selected_dialogue_id: None,
        selected_node_id: None,
        search_text: String::new(),
        status: "Loaded dialogue catalog.".to_string(),
        graph_canvas_state: FlowGraphCanvasState::default(),
    };

    if let Some(dialogue_id) = initial_dialogue_id.as_deref() {
        if editor.select_dialogue(dialogue_id, &catalogs) {
            editor.status = format!("Loaded dialogue catalog and selected dialogue {dialogue_id}.");
        } else {
            editor.status =
                format!("Loaded dialogue catalog. Requested dialogue {dialogue_id} was not found.");
            editor.ensure_selection(&catalogs);
        }
    } else {
        editor.ensure_selection(&catalogs);
    }

    info!(
        "dialogue editor data loaded: dialogues={}",
        catalogs.definitions.len()
    );

    Ok((editor, catalogs))
}

pub(crate) fn reload_editor_content(
    editor: &mut EditorState,
    catalogs: &mut DialogueEditorCatalogs,
) -> Result<String, String> {
    let selected_dialogue_id = editor.selected_dialogue_id.clone();
    let selected_node_id = editor.selected_node_id.clone();
    let search_text = editor.search_text.clone();
    let graph_canvas_state = editor.graph_canvas_state.clone();

    let (mut reloaded_editor, reloaded_catalogs) = load_editor_resources(selected_dialogue_id)?;
    reloaded_editor.search_text = search_text;
    reloaded_editor.selected_node_id = selected_node_id;
    reloaded_editor.graph_canvas_state = graph_canvas_state;
    reloaded_editor.ensure_selection(&reloaded_catalogs);
    reloaded_editor.status = "Reloaded dialogue catalog.".to_string();

    *catalogs = reloaded_catalogs;
    *editor = reloaded_editor;

    Ok("Reloaded dialogue catalog.".to_string())
}

fn build_catalogs(definitions: DialogueLibrary) -> DialogueEditorCatalogs {
    let definitions = definitions
        .iter()
        .map(|(dialogue_id, definition)| (dialogue_id.clone(), definition.clone()))
        .collect::<BTreeMap<String, DialogueData>>();

    let mut ordered_ids = definitions.keys().cloned().collect::<Vec<_>>();
    ordered_ids.sort();

    let relative_paths = definitions
        .keys()
        .map(|dialogue_id| {
            (
                dialogue_id.clone(),
                format!("data/dialogues/{dialogue_id}.json"),
            )
        })
        .collect::<BTreeMap<String, String>>();

    let search_entries = ordered_ids
        .iter()
        .filter_map(|dialogue_id| {
            definitions
                .get(dialogue_id)
                .map(|dialogue| DialogueSearchEntry {
                    dialogue_id: dialogue_id.clone(),
                    summary: summarize_dialogue(dialogue),
                    search_blob: build_search_blob(dialogue),
                })
        })
        .collect::<Vec<_>>();

    DialogueEditorCatalogs {
        definitions,
        ordered_ids,
        relative_paths,
        search_entries,
    }
}

fn summarize_dialogue(dialogue: &DialogueData) -> String {
    let node_count = dialogue.nodes.len();
    let connection_count = dialogue.connections.len();
    let start_summary = resolve_dialogue_start_node_id(dialogue)
        .as_deref()
        .and_then(|start_id| dialogue.nodes.iter().find(|node| node.id == start_id))
        .map(|node| {
            let speaker = node.speaker.trim();
            let text = node.text.trim();
            if !speaker.is_empty() && !text.is_empty() {
                format!("{speaker}: {}", truncate_text(text, 48))
            } else if !node.title.trim().is_empty() {
                truncate_text(node.title.trim(), 48)
            } else if !text.is_empty() {
                truncate_text(text, 48)
            } else {
                node.id.clone()
            }
        });

    match start_summary {
        Some(summary) if !summary.is_empty() => {
            format!("{node_count} nodes · {connection_count} connections · {summary}")
        }
        _ => format!("{node_count} nodes · {connection_count} connections"),
    }
}

fn build_search_blob(dialogue: &DialogueData) -> String {
    let mut parts = vec![dialogue.dialog_id.clone()];

    for node in &dialogue.nodes {
        parts.push(node.id.clone());
        parts.push(node.node_type.clone());
        parts.push(node.title.clone());
        parts.push(node.speaker.clone());
        parts.push(node.text.clone());
        parts.push(node.portrait.clone());
        parts.push(node.next.clone());
        parts.push(node.condition.clone());
        parts.push(node.true_next.clone());
        parts.push(node.false_next.clone());
        parts.push(node.end_type.clone());

        for option in &node.options {
            parts.push(option.text.clone());
            parts.push(option.next.clone());
        }

        for action in &node.actions {
            parts.push(action.action_type.clone());
        }
    }

    parts.join(" ").to_lowercase()
}

fn truncate_text(value: &str, max_chars: usize) -> String {
    let mut chars = value.chars();
    let truncated = chars.by_ref().take(max_chars).collect::<String>();
    if chars.next().is_some() {
        format!("{truncated}...")
    } else {
        truncated
    }
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}
