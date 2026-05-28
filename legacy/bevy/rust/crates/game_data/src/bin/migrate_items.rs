use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

use game_data::{
    migrate_legacy_item_value, EffectDefinition, GameplayEffectData, ItemDefinition, ItemFragment,
};
use serde_json::Value;

fn main() -> Result<(), String> {
    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("..")
        .canonicalize()
        .map_err(|error| format!("failed to resolve repo root: {error}"))?;
    let items_dir = repo_root.join("data").join("items");
    let effects_dir = repo_root.join("data").join("json").join("effects");

    fs::create_dir_all(&effects_dir)
        .map_err(|error| format!("failed to ensure effect directory exists: {error}"))?;

    let mut generated_effects: BTreeMap<String, EffectDefinition> = BTreeMap::new();
    let entries = fs::read_dir(&items_dir).map_err(|error| {
        format!(
            "failed to read item directory {}: {error}",
            items_dir.display()
        )
    })?;

    for entry in entries {
        let entry =
            entry.map_err(|error| format!("failed to enumerate item directory: {error}"))?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let value: Value = serde_json::from_str(&raw)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
        let artifact = migrate_legacy_item_value(value)
            .map_err(|error| format!("failed to migrate {}: {error}", path.display()))?;

        write_json(&path, &artifact.item)?;
        for effect in artifact.generated_effects {
            generated_effects.insert(effect.id.clone(), effect);
        }
    }

    for effect in generated_effects.into_values() {
        let path = effects_dir.join(format!("{}.json", effect.id));
        write_json(&path, &effect)?;
    }

    let mut effect_ids_on_disk = fs::read_dir(&effects_dir)
        .map_err(|error| {
            format!(
                "failed to read effect directory {}: {error}",
                effects_dir.display()
            )
        })?
        .filter_map(|entry| entry.ok())
        .filter_map(|entry| {
            let path = entry.path();
            (path.extension().and_then(|value| value.to_str()) == Some("json")).then_some(path)
        })
        .filter_map(|path| {
            path.file_stem()
                .and_then(|value| value.to_str())
                .map(|value| value.to_string())
        })
        .collect::<std::collections::BTreeSet<_>>();

    let entries = fs::read_dir(&items_dir).map_err(|error| {
        format!(
            "failed to re-read item directory {}: {error}",
            items_dir.display()
        )
    })?;
    for entry in entries {
        let entry =
            entry.map_err(|error| format!("failed to enumerate migrated items: {error}"))?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read migrated item {}: {error}", path.display()))?;
        let item: ItemDefinition = serde_json::from_str(&raw).map_err(|error| {
            format!("failed to parse migrated item {}: {error}", path.display())
        })?;

        for effect_id in referenced_effect_ids(&item) {
            if effect_ids_on_disk.contains(&effect_id) {
                continue;
            }
            let effect = if effect_id.starts_with("consume_") {
                generated_effect_from_id(&effect_id)?
            } else {
                placeholder_effect_from_id(&effect_id)
            };
            let path = effects_dir.join(format!("{effect_id}.json"));
            write_json(&path, &effect)?;
            effect_ids_on_disk.insert(effect_id);
        }
    }

    Ok(())
}

fn referenced_effect_ids(item: &ItemDefinition) -> Vec<String> {
    let mut ids = Vec::new();
    for fragment in &item.fragments {
        match fragment {
            ItemFragment::Equip {
                equip_effect_ids,
                unequip_effect_ids,
                ..
            } => {
                ids.extend(equip_effect_ids.iter().cloned());
                ids.extend(unequip_effect_ids.iter().cloned());
            }
            ItemFragment::Weapon {
                on_hit_effect_ids, ..
            } => {
                ids.extend(on_hit_effect_ids.iter().cloned());
            }
            ItemFragment::Usable { effect_ids, .. }
            | ItemFragment::PassiveEffects { effect_ids } => {
                ids.extend(effect_ids.iter().cloned());
            }
            _ => {}
        }
    }
    ids.sort();
    ids.dedup();
    ids
}

fn placeholder_effect_from_id(effect_id: &str) -> EffectDefinition {
    EffectDefinition {
        id: effect_id.to_string(),
        name: format!("Placeholder {effect_id}"),
        description: "Auto-generated placeholder effect for migrated item references.".to_string(),
        category: "neutral".to_string(),
        icon_path: String::new(),
        color_tint: String::new(),
        duration: 0.0,
        tick_interval: 0.0,
        is_infinite: false,
        is_stackable: false,
        max_stacks: 1,
        stack_mode: "refresh".to_string(),
        stat_modifiers: BTreeMap::new(),
        special_effects: vec![effect_id.to_string()],
        visual_effect: String::new(),
        gameplay_effect: None,
        extra: BTreeMap::new(),
    }
}

fn generated_effect_from_id(effect_id: &str) -> Result<EffectDefinition, String> {
    let parts = effect_id
        .strip_prefix("consume_")
        .ok_or_else(|| format!("generated effect id must start with consume_: {effect_id}"))?
        .split('_')
        .collect::<Vec<_>>();
    if parts.len() < 2 || parts.len() % 2 != 0 {
        return Err(format!(
            "unsupported generated effect id format: {effect_id}"
        ));
    }

    let mut resource_deltas = BTreeMap::new();
    for pair in parts.chunks(2) {
        let amount = pair[1]
            .parse::<f32>()
            .map_err(|error| format!("invalid generated effect amount in {effect_id}: {error}"))?;
        resource_deltas.insert(pair[0].to_string(), amount);
    }

    Ok(EffectDefinition {
        id: effect_id.to_string(),
        name: format!("Generated {effect_id}"),
        description: "Generated from migrated consumable item data.".to_string(),
        category: "neutral".to_string(),
        icon_path: String::new(),
        color_tint: String::new(),
        duration: 0.0,
        tick_interval: 0.0,
        is_infinite: false,
        is_stackable: false,
        max_stacks: 1,
        stack_mode: "refresh".to_string(),
        stat_modifiers: BTreeMap::new(),
        special_effects: Vec::new(),
        visual_effect: String::new(),
        gameplay_effect: Some(GameplayEffectData {
            resource_deltas,
            extra: BTreeMap::new(),
        }),
        extra: BTreeMap::new(),
    })
}
fn write_json(path: &PathBuf, value: &impl serde::Serialize) -> Result<(), String> {
    let json = serde_json::to_string_pretty(value)
        .map_err(|error| format!("failed to serialize {}: {error}", path.display()))?;
    fs::write(path, json).map_err(|error| format!("failed to write {}: {error}", path.display()))
}
