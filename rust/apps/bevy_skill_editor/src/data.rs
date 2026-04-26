use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use game_data::{
    load_skill_library, load_skill_tree_library, SkillLibrary, SkillTreeLibrary,
    SkillTreeValidationCatalog, SkillValidationCatalog,
};

use crate::state::{
    display_skill_name, display_tree_name, EditorState, SkillEditorCatalogs, SkillSearchEntry,
};

pub(crate) fn load_editor_resources(
    initial_skill_id: Option<String>,
    initial_tree_id: Option<String>,
) -> Result<(EditorState, SkillEditorCatalogs), String> {
    let repo_root = repo_root();
    let data_root = repo_root.join("data");
    let trees_dir = data_root.join("skill_trees");
    let skills_dir = data_root.join("skills");

    let tree_library =
        load_skill_tree_library(&trees_dir, Some(&SkillTreeValidationCatalog::default()))
            .map_err(|error| format!("failed to load skill tree catalog: {error}"))?;
    let skill_library = load_skill_library(
        &skills_dir,
        Some(&SkillValidationCatalog {
            skill_ids: Default::default(),
            tree_ids: tree_library.ids(),
        }),
    )
    .map_err(|error| format!("failed to load skill catalog: {error}"))?;

    let catalogs = build_catalogs(&skill_library, &tree_library);
    let mut editor = EditorState {
        repo_root,
        selected_tree_id: None,
        selected_skill_id: None,
        search_text: String::new(),
        status: "Loaded skill catalog.".to_string(),
    };

    if let Some(skill_id) = initial_skill_id.as_deref() {
        if editor.select_skill(skill_id, &catalogs) {
            editor.status = format!("Loaded skill catalog and selected skill {skill_id}.");
        } else {
            editor.status =
                format!("Loaded skill catalog. Requested skill {skill_id} was not found.");
            editor.ensure_selection(&catalogs);
        }
    } else if let Some(tree_id) = initial_tree_id.as_deref() {
        if editor.select_tree(tree_id, &catalogs) {
            editor.status = format!("Loaded skill catalog and selected tree {tree_id}.");
        } else {
            editor.status =
                format!("Loaded skill catalog. Requested tree {tree_id} was not found.");
            editor.ensure_selection(&catalogs);
        }
    } else {
        editor.ensure_selection(&catalogs);
    }

    Ok((editor, catalogs))
}

pub(crate) fn reload_editor_content(
    editor: &mut EditorState,
    catalogs: &mut SkillEditorCatalogs,
) -> Result<String, String> {
    let selected_skill_id = editor.selected_skill_id.clone();
    let selected_tree_id = editor.selected_tree_id.clone();
    let search_text = editor.search_text.clone();

    let (mut reloaded_editor, reloaded_catalogs) =
        load_editor_resources(selected_skill_id, selected_tree_id)?;
    reloaded_editor.search_text = search_text;
    reloaded_editor.ensure_selection(&reloaded_catalogs);
    reloaded_editor.status = "Reloaded skill catalog.".to_string();

    *catalogs = reloaded_catalogs;
    *editor = reloaded_editor;

    Ok("Reloaded skill catalog.".to_string())
}

fn build_catalogs(skills: &SkillLibrary, trees: &SkillTreeLibrary) -> SkillEditorCatalogs {
    let skill_map = skills
        .iter()
        .map(|(skill_id, definition)| (skill_id.clone(), definition.clone()))
        .collect::<BTreeMap<_, _>>();
    let tree_map = trees
        .iter()
        .map(|(tree_id, definition)| (tree_id.clone(), definition.clone()))
        .collect::<BTreeMap<_, _>>();

    let mut sorted_tree_ids = tree_map.keys().cloned().collect::<Vec<_>>();
    sorted_tree_ids.sort_by(|left, right| {
        let left_name = tree_map
            .get(left)
            .map(display_tree_name)
            .unwrap_or_else(|| left.clone());
        let right_name = tree_map
            .get(right)
            .map(display_tree_name)
            .unwrap_or_else(|| right.clone());
        left_name.cmp(&right_name).then(left.cmp(right))
    });

    let skills_by_tree = sorted_tree_ids
        .iter()
        .map(|tree_id| {
            (
                tree_id.clone(),
                ordered_skill_ids_for_tree(tree_id, &skill_map, &tree_map),
            )
        })
        .collect::<BTreeMap<_, _>>();

    let mut reverse_prerequisites = BTreeMap::<String, Vec<String>>::new();
    for skill in skill_map.values() {
        for prerequisite in &skill.prerequisites {
            reverse_prerequisites
                .entry(prerequisite.clone())
                .or_default()
                .push(skill.id.clone());
        }
    }
    for ids in reverse_prerequisites.values_mut() {
        ids.sort_by(|left, right| {
            let left_name = skill_map
                .get(left)
                .map(display_skill_name)
                .unwrap_or_else(|| left.clone());
            let right_name = skill_map
                .get(right)
                .map(display_skill_name)
                .unwrap_or_else(|| right.clone());
            left_name.cmp(&right_name).then(left.cmp(right))
        });
    }

    let mut search_entries = skill_map
        .values()
        .map(|skill| {
            let tree_name = tree_map
                .get(&skill.tree_id)
                .map(display_tree_name)
                .unwrap_or_else(|| skill.tree_id.clone());
            SkillSearchEntry {
                skill_id: skill.id.clone(),
                tree_id: skill.tree_id.clone(),
                skill_name: display_skill_name(skill),
                tree_name: tree_name.clone(),
                search_blob: format!(
                    "{} {} {} {}",
                    skill.id,
                    display_skill_name(skill),
                    skill.tree_id,
                    tree_name
                )
                .to_lowercase(),
            }
        })
        .collect::<Vec<_>>();
    search_entries.sort_by(|left, right| {
        left.skill_name
            .cmp(&right.skill_name)
            .then(left.tree_name.cmp(&right.tree_name))
            .then(left.skill_id.cmp(&right.skill_id))
    });

    SkillEditorCatalogs {
        skills: skill_map,
        trees: tree_map,
        sorted_tree_ids,
        skills_by_tree,
        reverse_prerequisites,
        search_entries,
    }
}

fn ordered_skill_ids_for_tree(
    tree_id: &str,
    skills: &BTreeMap<String, game_data::SkillDefinition>,
    trees: &BTreeMap<String, game_data::SkillTreeDefinition>,
) -> Vec<String> {
    let listed_ids = trees
        .get(tree_id)
        .map(|tree| {
            tree.skills
                .iter()
                .filter(|skill_id| skills.contains_key(skill_id.as_str()))
                .cloned()
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let mut seen = listed_ids.iter().cloned().collect::<BTreeSet<_>>();
    let mut ordered = listed_ids;

    let mut extras = skills
        .values()
        .filter(|skill| skill.tree_id == tree_id)
        .map(|skill| skill.id.clone())
        .collect::<Vec<_>>();
    extras.sort_by(|left, right| {
        let left_name = skills
            .get(left)
            .map(display_skill_name)
            .unwrap_or_else(|| left.clone());
        let right_name = skills
            .get(right)
            .map(display_skill_name)
            .unwrap_or_else(|| right.clone());
        left_name.cmp(&right_name).then(left.cmp(right))
    });

    for skill_id in extras {
        if seen.insert(skill_id.clone()) {
            ordered.push(skill_id);
        }
    }

    ordered
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}
