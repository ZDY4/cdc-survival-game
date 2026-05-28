use std::path::Path;

use game_data::ItemFragment;

use super::content::{
    find_item_document, find_map_document, normalize_data_relative_path, scan_character_documents,
    scan_map_documents, scan_overworld_documents,
};
use super::ContentKind;

pub(super) fn references_content(
    kind: ContentKind,
    target_id: &str,
    repo_root: &Path,
) -> Result<i32, String> {
    match kind {
        ContentKind::Item => references_item(target_id, repo_root),
        ContentKind::Map => references_map(target_id, repo_root),
        _ => Err(format!(
            "references currently supports item and map, got {}",
            kind.label()
        )),
    }
}

fn references_item(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let item_id = target_id
        .parse::<u32>()
        .map_err(|error| format!("invalid item id {target_id}: {error}"))?;
    let item_document = find_item_document(target_id, repo_root)?;
    let mut hits = Vec::new();
    let data_root = repo_root.join("data");

    for mut document in
        game_data::RecipeEditorService::with_data_root(data_root.join("recipes"), data_root.clone())
            .load_documents()
            .map_err(|error| error.to_string())?
    {
        document.relative_path = normalize_data_relative_path(&document.relative_path);
        if document.definition.output.item_id == item_id {
            hits.push(ReferenceHit::new(
                "recipe",
                document.definition.id.clone(),
                document.relative_path.clone(),
                "output.item_id".to_string(),
            ));
        }
        for (index, material) in document.definition.materials.iter().enumerate() {
            if material.item_id == item_id {
                hits.push(ReferenceHit::new(
                    "recipe",
                    document.definition.id.clone(),
                    document.relative_path.clone(),
                    format!("materials[{index}].item_id"),
                ));
            }
        }
        for (index, tool_id) in document.definition.required_tools.iter().enumerate() {
            if parse_stringish_item_id(tool_id) == Some(item_id) {
                hits.push(ReferenceHit::new(
                    "recipe",
                    document.definition.id.clone(),
                    document.relative_path.clone(),
                    format!("required_tools[{index}]"),
                ));
            }
        }
        for (index, tool_id) in document.definition.optional_tools.iter().enumerate() {
            if parse_stringish_item_id(tool_id) == Some(item_id) {
                hits.push(ReferenceHit::new(
                    "recipe",
                    document.definition.id.clone(),
                    document.relative_path.clone(),
                    format!("optional_tools[{index}]"),
                ));
            }
        }
    }

    for mut document in
        game_data::ItemEditorService::with_data_root(data_root.join("items"), data_root)
            .load_documents()
            .map_err(|error| error.to_string())?
    {
        document.relative_path = normalize_data_relative_path(&document.relative_path);
        for (index, fragment) in document.definition.fragments.iter().enumerate() {
            match fragment {
                ItemFragment::Durability {
                    repair_materials, ..
                } => {
                    for (material_index, material) in repair_materials.iter().enumerate() {
                        if material.item_id == item_id {
                            hits.push(ReferenceHit::new(
                                "item",
                                document.definition.id.to_string(),
                                document.relative_path.clone(),
                                format!(
                                    "fragments[{index}].durability.repair_materials[{material_index}].item_id"
                                ),
                            ));
                        }
                    }
                }
                ItemFragment::Weapon { ammo_type, .. } => {
                    if ammo_type.is_some_and(|ammo_type| ammo_type == item_id) {
                        hits.push(ReferenceHit::new(
                            "item",
                            document.definition.id.to_string(),
                            document.relative_path.clone(),
                            format!("fragments[{index}].weapon.ammo_type"),
                        ));
                    }
                }
                ItemFragment::Crafting {
                    crafting_recipe,
                    deconstruct_yield,
                } => {
                    if let Some(recipe) = crafting_recipe {
                        for (material_index, material) in recipe.materials.iter().enumerate() {
                            if material.item_id == item_id {
                                hits.push(ReferenceHit::new(
                                    "item",
                                    document.definition.id.to_string(),
                                    document.relative_path.clone(),
                                    format!(
                                        "fragments[{index}].crafting.crafting_recipe.materials[{material_index}].item_id"
                                    ),
                                ));
                            }
                        }
                    }
                    for (yield_index, item) in deconstruct_yield.iter().enumerate() {
                        if item.item_id == item_id {
                            hits.push(ReferenceHit::new(
                                "item",
                                document.definition.id.to_string(),
                                document.relative_path.clone(),
                                format!(
                                    "fragments[{index}].crafting.deconstruct_yield[{yield_index}].item_id"
                                ),
                            ));
                        }
                    }
                }
                _ => {}
            }
        }
    }

    for entry in scan_character_documents(repo_root)? {
        for (index, loot) in entry.definition.combat.loot.iter().enumerate() {
            if loot.item_id == item_id {
                hits.push(ReferenceHit::new(
                    "character",
                    entry.definition.id.to_string(),
                    entry.relative_path.clone(),
                    format!("combat.loot[{index}].item_id"),
                ));
            }
        }
    }

    for entry in scan_map_documents(repo_root)? {
        for (index, object) in entry.definition.objects.iter().enumerate() {
            if object
                .props
                .pickup
                .as_ref()
                .and_then(|pickup| parse_stringish_item_id(&pickup.item_id))
                .is_some_and(|pickup_item_id| pickup_item_id == item_id)
            {
                hits.push(ReferenceHit::new(
                    "map",
                    entry.definition.id.to_string(),
                    entry.relative_path.clone(),
                    format!("objects[{index}].props.pickup.item_id"),
                ));
            }
            if let Some(container) = object.props.container.as_ref() {
                for (item_index, item) in container.initial_inventory.iter().enumerate() {
                    if parse_stringish_item_id(&item.item_id).is_some_and(|value| value == item_id)
                    {
                        hits.push(ReferenceHit::new(
                            "map",
                            entry.definition.id.to_string(),
                            entry.relative_path.clone(),
                            format!(
                                "objects[{index}].props.container.initial_inventory[{item_index}].item_id"
                            ),
                        ));
                    }
                }
            }
        }
    }

    print_references(
        "item",
        &item_document.definition.id.to_string(),
        &item_document.relative_path,
        &hits,
    );
    Ok(0)
}

fn references_map(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let map_document = find_map_document(target_id, repo_root)?;
    let mut hits = Vec::new();

    for entry in scan_overworld_documents(repo_root)? {
        for (index, location) in entry.definition.locations.iter().enumerate() {
            if location.map_id.as_str() == target_id {
                hits.push(ReferenceHit::new(
                    "overworld",
                    entry.definition.id.to_string(),
                    entry.relative_path.clone(),
                    format!(
                        "locations[{index}] id={} entry_point_id={} kind={:?}",
                        location.id, location.entry_point_id, location.kind
                    ),
                ));
            }
        }
    }

    print_references(
        "map",
        map_document.definition.id.as_str(),
        &map_document.relative_path,
        &hits,
    );
    Ok(0)
}

fn parse_stringish_item_id(value: &str) -> Option<u32> {
    value.trim().parse::<u32>().ok()
}

fn print_references(kind: &str, target_id: &str, relative_path: &str, hits: &[ReferenceHit]) {
    println!("kind: {kind}");
    println!("id: {target_id}");
    println!("relative_path: {relative_path}");
    println!("reference_count: {}", hits.len());
    if hits.is_empty() {
        println!("status: no_references_found");
        return;
    }

    for hit in hits {
        println!(
            "- {} {} @ {} [{}]",
            hit.source_kind, hit.source_id, hit.relative_path, hit.detail
        );
    }
}

#[derive(Debug)]
struct ReferenceHit {
    source_kind: String,
    source_id: String,
    relative_path: String,
    detail: String,
}

impl ReferenceHit {
    fn new(
        source_kind: impl Into<String>,
        source_id: impl Into<String>,
        relative_path: impl Into<String>,
        detail: impl Into<String>,
    ) -> Self {
        Self {
            source_kind: source_kind.into(),
            source_id: source_id.into(),
            relative_path: relative_path.into(),
            detail: detail.into(),
        }
    }
}
