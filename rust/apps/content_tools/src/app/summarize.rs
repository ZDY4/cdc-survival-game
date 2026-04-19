use std::collections::BTreeMap;
use std::path::Path;

use game_data::ItemFragment;

use super::content::{
    find_character_document, find_item_document, find_map_document, find_recipe_document,
};
use super::ContentKind;

pub(super) fn summarize_content(
    kind: ContentKind,
    target_id: &str,
    repo_root: &Path,
) -> Result<i32, String> {
    match kind {
        ContentKind::Item => summarize_item(target_id, repo_root),
        ContentKind::Recipe => summarize_recipe(target_id, repo_root),
        ContentKind::Character => summarize_character(target_id, repo_root),
        ContentKind::Map => summarize_map(target_id, repo_root),
    }
}

fn summarize_item(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let document = find_item_document(target_id, repo_root)?;
    let fragment_kinds = document
        .definition
        .fragments
        .iter()
        .map(ItemFragment::kind)
        .collect::<Vec<_>>();
    let equip_slots = document.definition.equip_slots();

    println!("kind: item");
    println!("id: {}", document.definition.id);
    println!("relative_path: {}", document.relative_path);
    println!("name: {}", document.definition.name);
    println!("value: {}", document.definition.value);
    println!("weight: {}", document.definition.weight);
    println!("fragment_count: {}", document.definition.fragments.len());
    println!("fragment_kinds: {}", join_or_dash(&fragment_kinds));
    println!("equip_slots: {}", join_or_dash(&equip_slots));
    Ok(0)
}

fn summarize_recipe(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let document = find_recipe_document(target_id, repo_root)?;

    println!("kind: recipe");
    println!("id: {}", document.definition.id);
    println!("relative_path: {}", document.relative_path);
    println!("name: {}", document.definition.name);
    println!("output_item_id: {}", document.definition.output.item_id);
    println!("output_count: {}", document.definition.output.count);
    println!("materials_count: {}", document.definition.materials.len());
    println!(
        "required_tools_count: {}",
        document.definition.required_tools.len()
    );
    println!(
        "optional_tools_count: {}",
        document.definition.optional_tools.len()
    );
    println!(
        "unlock_conditions_count: {}",
        document.definition.unlock_conditions.len()
    );
    Ok(0)
}

fn summarize_character(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let entry = find_character_document(target_id, repo_root)?;
    let settlement_id = entry
        .definition
        .life
        .as_ref()
        .map(|life| life.settlement_id.as_str())
        .unwrap_or("-");

    println!("kind: character");
    println!("id: {}", entry.definition.id);
    println!("relative_path: {}", entry.relative_path);
    println!("display_name: {}", entry.definition.identity.display_name);
    println!("archetype: {:?}", entry.definition.archetype);
    println!("camp_id: {}", entry.definition.faction.camp_id);
    println!("disposition: {:?}", entry.definition.faction.disposition);
    println!("behavior: {}", entry.definition.combat.behavior);
    println!("level: {}", entry.definition.progression.level);
    println!("settlement_id: {settlement_id}");
    println!(
        "appearance_profile_id: {}",
        empty_as_dash(&entry.definition.appearance_profile_id)
    );
    println!(
        "model_path: {}",
        empty_as_dash(&entry.definition.presentation.model_path)
    );
    println!("loot_entries: {}", entry.definition.combat.loot.len());
    Ok(0)
}

fn summarize_map(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let entry = find_map_document(target_id, repo_root)?;
    let total_cells = entry
        .definition
        .levels
        .iter()
        .map(|level| level.cells.len())
        .sum::<usize>();
    let level_ids = entry
        .definition
        .levels
        .iter()
        .map(|level| level.y.to_string())
        .collect::<Vec<_>>();
    let object_kind_counts = format_object_kind_counts(&entry.definition);

    println!("kind: map");
    println!("id: {}", entry.definition.id);
    println!("relative_path: {}", entry.relative_path);
    println!("name: {}", entry.definition.name);
    println!(
        "size: {}x{}",
        entry.definition.size.width, entry.definition.size.height
    );
    println!("default_level: {}", entry.definition.default_level);
    println!("level_count: {}", entry.definition.levels.len());
    println!("levels: {}", join_or_dash(&level_ids));
    println!("entry_points: {}", entry.definition.entry_points.len());
    println!("objects: {}", entry.definition.objects.len());
    println!("cells: {total_cells}");
    println!("object_kinds: {}", join_or_dash(&object_kind_counts));
    Ok(0)
}

fn format_object_kind_counts(definition: &game_data::MapDefinition) -> Vec<String> {
    let mut counts = BTreeMap::<String, usize>::new();
    for object in &definition.objects {
        let key = format!("{:?}", object.kind);
        *counts.entry(key).or_default() += 1;
    }
    counts
        .into_iter()
        .map(|(kind, count)| format!("{kind}={count}"))
        .collect()
}

fn empty_as_dash(value: &str) -> &str {
    let trimmed = value.trim();
    if trimmed.is_empty() { "-" } else { trimmed }
}

fn join_or_dash<T>(values: &[T]) -> String
where
    T: ToString,
{
    if values.is_empty() {
        "-".to_string()
    } else {
        values
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(", ")
    }
}
