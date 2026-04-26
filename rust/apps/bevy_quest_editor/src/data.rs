use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::log::info;
use game_bevy::{load_quest_definitions, QuestDefinitionPath};
use game_data::QuestDefinition;
use game_editor::FlowGraphCanvasState;

use crate::state::{display_quest_title, EditorState, QuestEditorCatalogs, QuestSearchEntry};

pub(crate) fn load_editor_resources(
    initial_quest_id: Option<String>,
) -> Result<(EditorState, QuestEditorCatalogs), String> {
    let repo_root = repo_root();
    let path = QuestDefinitionPath::default().0;
    let definitions = load_quest_definitions(&path).map_err(|error| {
        format!(
            "failed to load quest catalog from {}: {error}",
            path.display()
        )
    })?;
    let catalogs = build_catalogs(definitions.0);

    let mut editor = EditorState {
        repo_root,
        selected_quest_id: None,
        selected_node_id: None,
        search_text: String::new(),
        status: "Loaded quest catalog.".to_string(),
        graph_canvas_state: FlowGraphCanvasState::default(),
    };

    if let Some(quest_id) = initial_quest_id.as_deref() {
        if editor.select_quest(quest_id, &catalogs) {
            editor.status = format!("Loaded quest catalog and selected quest {quest_id}.");
        } else {
            editor.status =
                format!("Loaded quest catalog. Requested quest {quest_id} was not found.");
            editor.ensure_selection(&catalogs);
        }
    } else {
        editor.ensure_selection(&catalogs);
    }

    info!(
        "quest editor data loaded: quests={}",
        catalogs.definitions.len()
    );

    Ok((editor, catalogs))
}

pub(crate) fn reload_editor_content(
    editor: &mut EditorState,
    catalogs: &mut QuestEditorCatalogs,
) -> Result<String, String> {
    let selected_quest_id = editor.selected_quest_id.clone();
    let selected_node_id = editor.selected_node_id.clone();
    let search_text = editor.search_text.clone();
    let graph_canvas_state = editor.graph_canvas_state.clone();

    let (mut reloaded_editor, reloaded_catalogs) = load_editor_resources(selected_quest_id)?;
    reloaded_editor.search_text = search_text;
    reloaded_editor.selected_node_id = selected_node_id;
    reloaded_editor.graph_canvas_state = graph_canvas_state;
    reloaded_editor.ensure_selection(&reloaded_catalogs);
    reloaded_editor.status = "Reloaded quest catalog.".to_string();

    *catalogs = reloaded_catalogs;
    *editor = reloaded_editor;

    Ok("Reloaded quest catalog.".to_string())
}

fn build_catalogs(definitions: game_data::QuestLibrary) -> QuestEditorCatalogs {
    let definitions = definitions
        .iter()
        .map(|(quest_id, definition)| (quest_id.clone(), definition.clone()))
        .collect::<BTreeMap<_, _>>();

    let mut ordered_ids = definitions.keys().cloned().collect::<Vec<_>>();
    ordered_ids.sort_by(|left, right| {
        let left_name = definitions
            .get(left)
            .map(display_quest_title)
            .unwrap_or_else(|| left.clone());
        let right_name = definitions
            .get(right)
            .map(display_quest_title)
            .unwrap_or_else(|| right.clone());
        left_name.cmp(&right_name).then(left.cmp(right))
    });

    let relative_paths = definitions
        .keys()
        .map(|quest_id| (quest_id.clone(), format!("data/quests/{quest_id}.json")))
        .collect::<BTreeMap<_, _>>();

    let mut search_entries = ordered_ids
        .iter()
        .filter_map(|quest_id| {
            definitions.get(quest_id).map(|quest| QuestSearchEntry {
                quest_id: quest_id.clone(),
                title: display_quest_title(quest),
                summary: summarize_quest(quest),
                search_blob: build_search_blob(quest),
            })
        })
        .collect::<Vec<_>>();
    search_entries.sort_by(|left, right| {
        left.title
            .cmp(&right.title)
            .then(left.quest_id.cmp(&right.quest_id))
    });

    QuestEditorCatalogs {
        definitions,
        ordered_ids,
        relative_paths,
        search_entries,
    }
}

fn summarize_quest(quest: &QuestDefinition) -> String {
    let node_count = quest.flow.nodes.len();
    let prerequisite_count = quest.prerequisites.len();
    format!("{node_count} nodes · {prerequisite_count} prereqs")
}

fn build_search_blob(quest: &QuestDefinition) -> String {
    let mut parts = vec![
        quest.quest_id.clone(),
        quest.title.clone(),
        quest.description.clone(),
        quest.prerequisites.join(" "),
    ];

    for node in quest.flow.nodes.values() {
        parts.push(node.id.clone());
        parts.push(node.title.clone());
        parts.push(node.dialog_id.clone());
        parts.push(node.target.clone());
    }

    parts.join(" ").to_lowercase()
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}
