use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

use crate::{
    load_character_library, load_dialogue_library, load_dialogue_rule_library, load_effect_library,
    load_item_library, load_map_library, load_overworld_library_with_catalog, load_quest_library,
    load_recipe_library, load_settlement_library, load_shop_library, load_skill_library,
    load_skill_tree_library, CharacterDefinition, DialogueRuleDefinition,
    DialogueRuleValidationCatalog, ItemDefinition, ItemFragment, MapDefinition, MapObjectKind,
    OverworldDefinition, OverworldValidationCatalog, QuestDefinition, RecipeDefinition,
    RecipeValidationCatalog, SettlementDefinition, ShopDefinition, ShopValidationCatalog,
    SkillDefinition, SkillTreeDefinition, SkillTreeValidationCatalog, SkillValidationCatalog,
};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ContentAuthorityKind {
    RustSchema,
    LegacyJson,
    GodotResource,
    GodotConfig,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContentDomainSummary {
    pub domain: String,
    pub authority: ContentAuthorityKind,
    pub relative_path: String,
    pub format: String,
    pub record_count: usize,
    pub ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContentReference {
    pub source_domain: String,
    pub source_id: String,
    pub target_domain: String,
    pub target_id: String,
    pub path: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SharedContentRegistry {
    pub domains: Vec<ContentDomainSummary>,
    pub references: Vec<ContentReference>,
}

#[derive(Debug, Error)]
pub enum ContentRegistryLoadError {
    #[error("failed to resolve content registry root {path}: {source}")]
    CanonicalizeRoot {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to load {domain} domain from {path}: {message}")]
    DomainLoad {
        domain: &'static str,
        path: PathBuf,
        message: String,
    },
    #[error("failed to read raw content directory {path}: {source}")]
    ReadRawDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read raw content file {path}: {source}")]
    ReadRawFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse raw content file {path}: {source}")]
    ParseRawFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
}

pub fn load_shared_content_registry(
    repo_root: impl AsRef<Path>,
) -> Result<SharedContentRegistry, ContentRegistryLoadError> {
    let requested_root = repo_root.as_ref().to_path_buf();
    let repo_root = requested_root.canonicalize().map_err(|source| {
        ContentRegistryLoadError::CanonicalizeRoot {
            path: requested_root,
            source,
        }
    })?;

    let data_root = repo_root.join("data");
    let effects_dir = data_root.join("json").join("effects");
    let items_dir = data_root.join("items");
    let dialogues_dir = data_root.join("dialogues");
    let dialogue_rules_dir = data_root.join("dialogue_rules");
    let quests_dir = data_root.join("quests");
    let maps_dir = data_root.join("maps");
    let overworld_dir = data_root.join("overworld");
    let characters_dir = data_root.join("characters");
    let settlements_dir = data_root.join("settlements");
    let skills_dir = data_root.join("skills");
    let skill_trees_dir = data_root.join("skill_trees");
    let recipes_dir = data_root.join("recipes");
    let shops_dir = data_root.join("shops");

    let effect_library = load_effect_library(&effects_dir).map_err(|error| {
        ContentRegistryLoadError::DomainLoad {
            domain: "effects",
            path: effects_dir.clone(),
            message: error.to_string(),
        }
    })?;
    let item_library = load_item_library(&items_dir, Some(&effect_library)).map_err(|error| {
        ContentRegistryLoadError::DomainLoad {
            domain: "items",
            path: items_dir.clone(),
            message: error.to_string(),
        }
    })?;
    let character_library = load_character_library(&characters_dir).map_err(|error| {
        ContentRegistryLoadError::DomainLoad {
            domain: "characters",
            path: characters_dir.clone(),
            message: error.to_string(),
        }
    })?;
    let dialogue_library = load_dialogue_library(&dialogues_dir).map_err(|error| {
        ContentRegistryLoadError::DomainLoad {
            domain: "dialogues",
            path: dialogues_dir.clone(),
            message: error.to_string(),
        }
    })?;
    let dialogue_rule_library = load_dialogue_rule_library(
        &dialogue_rules_dir,
        Some(&DialogueRuleValidationCatalog {
            dialogue_ids: dialogue_library.ids(),
        }),
    )
    .map_err(|error| ContentRegistryLoadError::DomainLoad {
        domain: "dialogue_rules",
        path: dialogue_rules_dir.clone(),
        message: error.to_string(),
    })?;
    let map_library =
        load_map_library(&maps_dir).map_err(|error| ContentRegistryLoadError::DomainLoad {
            domain: "maps",
            path: maps_dir.clone(),
            message: error.to_string(),
        })?;
    let overworld_library = load_overworld_library_with_catalog(
        &overworld_dir,
        Some(&OverworldValidationCatalog {
            map_ids: map_library
                .iter()
                .map(|(map_id, _)| map_id.as_str().to_string())
                .collect(),
            map_entry_points_by_map: map_library
                .iter()
                .map(|(map_id, definition)| {
                    (
                        map_id.as_str().to_string(),
                        definition
                            .entry_points
                            .iter()
                            .map(|entry| entry.id.clone())
                            .collect(),
                    )
                })
                .collect(),
        }),
    )
    .map_err(|error| ContentRegistryLoadError::DomainLoad {
        domain: "overworld",
        path: overworld_dir.clone(),
        message: error.to_string(),
    })?;
    let settlement_library = load_settlement_library(&settlements_dir).map_err(|error| {
        ContentRegistryLoadError::DomainLoad {
            domain: "settlements",
            path: settlements_dir.clone(),
            message: error.to_string(),
        }
    })?;
    let skill_tree_library = load_skill_tree_library(
        &skill_trees_dir,
        Some(&SkillTreeValidationCatalog::default()),
    )
    .map_err(|error| ContentRegistryLoadError::DomainLoad {
        domain: "skill_trees",
        path: skill_trees_dir.clone(),
        message: error.to_string(),
    })?;
    let skill_library = load_skill_library(
        &skills_dir,
        Some(&SkillValidationCatalog {
            skill_ids: BTreeSet::new(),
            tree_ids: skill_tree_library.ids(),
        }),
    )
    .map_err(|error| ContentRegistryLoadError::DomainLoad {
        domain: "skills",
        path: skills_dir.clone(),
        message: error.to_string(),
    })?;
    let recipe_library = load_recipe_library(
        &recipes_dir,
        Some(&RecipeValidationCatalog {
            item_ids: item_library.ids(),
            skill_ids: skill_library.ids(),
            recipe_ids: BTreeSet::new(),
        }),
    )
    .map_err(|error| ContentRegistryLoadError::DomainLoad {
        domain: "recipes",
        path: recipes_dir.clone(),
        message: error.to_string(),
    })?;
    let shop_library = load_shop_library(
        &shops_dir,
        Some(&ShopValidationCatalog {
            item_ids: item_library.ids(),
        }),
    )
    .map_err(|error| ContentRegistryLoadError::DomainLoad {
        domain: "shops",
        path: shops_dir.clone(),
        message: error.to_string(),
    })?;
    let quest_library = load_quest_library(&quests_dir, None).map_err(|error| {
        ContentRegistryLoadError::DomainLoad {
            domain: "quests",
            path: quests_dir.clone(),
            message: error.to_string(),
        }
    })?;

    let mut domains = vec![
        build_domain_summary(
            "effects",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/json/effects"),
            "json",
            effect_library
                .iter()
                .map(|(id, _)| id.clone())
                .collect::<Vec<_>>(),
        ),
        build_domain_summary(
            "items",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/items"),
            "json",
            item_library
                .iter()
                .map(|(id, _)| id.to_string())
                .collect::<Vec<_>>(),
        ),
        build_domain_summary(
            "dialogues",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/dialogues"),
            "json",
            dialogue_library.ids().into_iter().collect(),
        ),
        build_domain_summary(
            "dialogue_rules",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/dialogue_rules"),
            "json",
            dialogue_rule_library.ids().into_iter().collect(),
        ),
        build_domain_summary(
            "quests",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/quests"),
            "json",
            quest_library.ids().into_iter().collect(),
        ),
        build_domain_summary(
            "maps",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/maps"),
            "json",
            map_library
                .iter()
                .map(|(id, _)| id.as_str().to_string())
                .collect::<Vec<_>>(),
        ),
        build_domain_summary(
            "overworld",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/overworld"),
            "json",
            overworld_library.ids().into_iter().collect(),
        ),
        build_domain_summary(
            "characters",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/characters"),
            "json",
            character_library
                .iter()
                .map(|(id, _)| id.as_str().to_string())
                .collect::<Vec<_>>(),
        ),
        build_domain_summary(
            "settlements",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/settlements"),
            "json",
            settlement_library
                .iter()
                .map(|(id, _)| id.as_str().to_string())
                .collect::<Vec<_>>(),
        ),
        build_domain_summary(
            "skills",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/skills"),
            "json",
            skill_library.ids().into_iter().collect(),
        ),
        build_domain_summary(
            "skill_trees",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/skill_trees"),
            "json",
            skill_tree_library.ids().into_iter().collect(),
        ),
        build_domain_summary(
            "recipes",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/recipes"),
            "json",
            recipe_library.ids().into_iter().collect(),
        ),
        build_domain_summary(
            "shops",
            ContentAuthorityKind::RustSchema,
            PathBuf::from("data/shops"),
            "godot_tres",
            shop_library.ids().into_iter().collect(),
        ),
        build_domain_summary(
            "map_locations",
            ContentAuthorityKind::LegacyJson,
            PathBuf::from("data/json/map_locations.json"),
            "json",
            scan_json_file_ids(&data_root.join("json").join("map_locations.json"))?,
        ),
        build_domain_summary(
            "structures",
            ContentAuthorityKind::LegacyJson,
            PathBuf::from("data/json/structures.json"),
            "json",
            scan_json_file_ids(&data_root.join("json").join("structures.json"))?,
        ),
        build_domain_summary(
            "story_chapters",
            ContentAuthorityKind::LegacyJson,
            PathBuf::from("data/json/story_chapters.json"),
            "json",
            scan_json_file_ids(&data_root.join("json").join("story_chapters.json"))?,
        ),
        build_domain_summary(
            "clues",
            ContentAuthorityKind::LegacyJson,
            PathBuf::from("data/json/clues.json"),
            "json",
            scan_json_file_ids(&data_root.join("json").join("clues.json"))?,
        ),
        build_domain_summary(
            "gameplay_tags",
            ContentAuthorityKind::GodotConfig,
            PathBuf::from("config/gameplay_tags.ini"),
            "ini",
            scan_single_file_marker(
                &repo_root.join("config").join("gameplay_tags.ini"),
                "registry",
            )?,
        ),
    ];
    domains.sort_by(|left, right| left.domain.cmp(&right.domain));

    let mut references = Vec::new();
    for (item_id, item) in item_library.iter() {
        collect_item_references(*item_id, item, &mut references);
    }
    for (character_id, definition) in character_library.iter() {
        collect_character_references(character_id.as_str(), definition, &mut references);
    }
    for (dialogue_key, definition) in dialogue_rule_library.iter() {
        collect_dialogue_rule_references(dialogue_key, definition, &mut references);
    }
    for (skill_id, definition) in skill_library.iter() {
        collect_skill_references(skill_id, definition, &mut references);
    }
    for (tree_id, definition) in skill_tree_library.iter() {
        collect_skill_tree_references(tree_id, definition, &mut references);
    }
    for (map_id, definition) in map_library.iter() {
        collect_map_references(map_id.as_str(), definition, &mut references);
    }
    for (overworld_id, definition) in overworld_library.iter() {
        collect_overworld_references(overworld_id.as_str(), definition, &mut references);
    }
    for (quest_id, definition) in quest_library.iter() {
        collect_quest_references(quest_id, definition, &mut references);
    }
    for (recipe_id, definition) in recipe_library.iter() {
        collect_recipe_references(recipe_id, definition, &mut references);
    }
    for (settlement_id, definition) in settlement_library.iter() {
        collect_settlement_references(settlement_id.as_str(), definition, &mut references);
    }
    for (shop_id, definition) in shop_library.iter() {
        collect_shop_references(shop_id, definition, &mut references);
    }
    references.sort_by(|left, right| {
        (
            &left.source_domain,
            &left.source_id,
            &left.target_domain,
            &left.target_id,
            &left.path,
        )
            .cmp(&(
                &right.source_domain,
                &right.source_id,
                &right.target_domain,
                &right.target_id,
                &right.path,
            ))
    });

    Ok(SharedContentRegistry {
        domains,
        references,
    })
}

fn build_domain_summary(
    domain: &str,
    authority: ContentAuthorityKind,
    relative_path: PathBuf,
    format: &str,
    mut ids: Vec<String>,
) -> ContentDomainSummary {
    ids.sort();
    ids.dedup();
    ContentDomainSummary {
        domain: domain.to_string(),
        authority,
        relative_path: relative_path.to_string_lossy().replace('\\', "/"),
        format: format.to_string(),
        record_count: ids.len(),
        ids,
    }
}

fn collect_item_references(
    item_id: u32,
    item: &ItemDefinition,
    references: &mut Vec<ContentReference>,
) {
    let source_id = item_id.to_string();
    for fragment in &item.fragments {
        match fragment {
            ItemFragment::Equip {
                equip_effect_ids,
                unequip_effect_ids,
                ..
            } => {
                for effect_id in equip_effect_ids {
                    push_reference(
                        references,
                        "items",
                        &source_id,
                        "effects",
                        effect_id,
                        "fragments.equip.equip_effect_ids",
                    );
                }
                for effect_id in unequip_effect_ids {
                    push_reference(
                        references,
                        "items",
                        &source_id,
                        "effects",
                        effect_id,
                        "fragments.equip.unequip_effect_ids",
                    );
                }
            }
            ItemFragment::Durability {
                repair_materials, ..
            } => {
                for entry in repair_materials {
                    push_reference(
                        references,
                        "items",
                        &source_id,
                        "items",
                        &entry.item_id.to_string(),
                        "fragments.durability.repair_materials",
                    );
                }
            }
            ItemFragment::Weapon {
                ammo_type,
                on_hit_effect_ids,
                ..
            } => {
                if let Some(ammo_type) = ammo_type {
                    push_reference(
                        references,
                        "items",
                        &source_id,
                        "items",
                        &ammo_type.to_string(),
                        "fragments.weapon.ammo_type",
                    );
                }
                for effect_id in on_hit_effect_ids {
                    push_reference(
                        references,
                        "items",
                        &source_id,
                        "effects",
                        effect_id,
                        "fragments.weapon.on_hit_effect_ids",
                    );
                }
            }
            ItemFragment::Usable { effect_ids, .. }
            | ItemFragment::PassiveEffects { effect_ids } => {
                let path = if matches!(fragment, ItemFragment::Usable { .. }) {
                    "fragments.usable.effect_ids"
                } else {
                    "fragments.passive_effects.effect_ids"
                };
                for effect_id in effect_ids {
                    push_reference(references, "items", &source_id, "effects", effect_id, path);
                }
            }
            ItemFragment::Crafting {
                crafting_recipe,
                deconstruct_yield,
            } => {
                if let Some(recipe) = crafting_recipe {
                    for material in &recipe.materials {
                        push_reference(
                            references,
                            "items",
                            &source_id,
                            "items",
                            &material.item_id.to_string(),
                            "fragments.crafting.crafting_recipe.materials",
                        );
                    }
                }
                for entry in deconstruct_yield {
                    push_reference(
                        references,
                        "items",
                        &source_id,
                        "items",
                        &entry.item_id.to_string(),
                        "fragments.crafting.deconstruct_yield",
                    );
                }
            }
            ItemFragment::Economy { .. }
            | ItemFragment::Stacking { .. }
            | ItemFragment::AttributeModifiers { .. } => {}
        }
    }
}

fn collect_character_references(
    character_id: &str,
    definition: &CharacterDefinition,
    references: &mut Vec<ContentReference>,
) {
    if let Some(life) = definition.life.as_ref() {
        push_reference(
            references,
            "characters",
            character_id,
            "settlements",
            &life.settlement_id,
            "life.settlement_id",
        );
    }

    if let Some(interaction) = definition.interaction.as_ref() {
        for option in &interaction.options {
            push_reference(
                references,
                "characters",
                character_id,
                "dialogues",
                &option.dialogue_id,
                "interaction.options.dialogue_id",
            );
            push_reference(
                references,
                "characters",
                character_id,
                "maps",
                &option.target_map_id,
                "interaction.options.target_map_id",
            );
        }
    }
}

fn collect_dialogue_rule_references(
    dialogue_key: &str,
    definition: &DialogueRuleDefinition,
    references: &mut Vec<ContentReference>,
) {
    push_reference(
        references,
        "dialogue_rules",
        dialogue_key,
        "dialogues",
        &definition.default_dialogue_id,
        "default_dialogue_id",
    );
    for (index, variant) in definition.variants.iter().enumerate() {
        push_reference(
            references,
            "dialogue_rules",
            dialogue_key,
            "dialogues",
            &variant.dialogue_id,
            &format!("variants[{index}].dialogue_id"),
        );
    }
}

fn collect_skill_references(
    skill_id: &str,
    definition: &SkillDefinition,
    references: &mut Vec<ContentReference>,
) {
    push_reference(
        references,
        "skills",
        skill_id,
        "skill_trees",
        &definition.tree_id,
        "tree_id",
    );
    for prerequisite_id in &definition.prerequisites {
        push_reference(
            references,
            "skills",
            skill_id,
            "skills",
            prerequisite_id,
            "prerequisites",
        );
    }
}

fn collect_skill_tree_references(
    tree_id: &str,
    definition: &SkillTreeDefinition,
    references: &mut Vec<ContentReference>,
) {
    for skill_id in &definition.skills {
        push_reference(
            references,
            "skill_trees",
            tree_id,
            "skills",
            skill_id,
            "skills",
        );
    }
}

fn collect_map_references(
    map_id: &str,
    definition: &MapDefinition,
    references: &mut Vec<ContentReference>,
) {
    for object in &definition.objects {
        match object.kind {
            MapObjectKind::Pickup => {
                if let Some(pickup) = object.props.pickup.as_ref() {
                    push_reference(
                        references,
                        "maps",
                        map_id,
                        "items",
                        &pickup.item_id,
                        "objects.props.pickup.item_id",
                    );
                }
            }
            MapObjectKind::AiSpawn => {
                if let Some(ai_spawn) = object.props.ai_spawn.as_ref() {
                    push_reference(
                        references,
                        "maps",
                        map_id,
                        "characters",
                        &ai_spawn.character_id,
                        "objects.props.ai_spawn.character_id",
                    );
                }
            }
            MapObjectKind::Interactive => {
                if let Some(interactive) = object.props.interactive.as_ref() {
                    for option in interactive.resolved_options() {
                        push_reference(
                            references,
                            "maps",
                            map_id,
                            "dialogues",
                            &option.dialogue_id,
                            "objects.props.interactive.options.dialogue_id",
                        );
                        push_reference(
                            references,
                            "maps",
                            map_id,
                            "maps",
                            &option.target_map_id,
                            "objects.props.interactive.options.target_map_id",
                        );
                    }
                }
            }
            MapObjectKind::Trigger => {
                if let Some(trigger) = object.props.trigger.as_ref() {
                    for option in trigger.resolved_options() {
                        push_reference(
                            references,
                            "maps",
                            map_id,
                            "dialogues",
                            &option.dialogue_id,
                            "objects.props.trigger.options.dialogue_id",
                        );
                        push_reference(
                            references,
                            "maps",
                            map_id,
                            "maps",
                            &option.target_map_id,
                            "objects.props.trigger.options.target_map_id",
                        );
                    }
                }
            }
            MapObjectKind::Building => {}
        }
    }
}

fn collect_overworld_references(
    overworld_id: &str,
    definition: &OverworldDefinition,
    references: &mut Vec<ContentReference>,
) {
    for location in &definition.locations {
        push_reference(
            references,
            "overworld",
            overworld_id,
            "maps",
            location.map_id.as_str(),
            "locations.map_id",
        );
        if let Some(parent_id) = location.parent_outdoor_location_id.as_ref() {
            push_reference(
                references,
                "overworld",
                overworld_id,
                "overworld_locations",
                parent_id.as_str(),
                "locations.parent_outdoor_location_id",
            );
        }
    }
}

fn collect_quest_references(
    quest_id: &str,
    definition: &QuestDefinition,
    references: &mut Vec<ContentReference>,
) {
    for prerequisite_id in &definition.prerequisites {
        push_reference(
            references,
            "quests",
            quest_id,
            "quests",
            prerequisite_id,
            "prerequisites",
        );
    }

    for node in definition.flow.nodes.values() {
        if let Some(item_id) = node.item_id {
            push_reference(
                references,
                "quests",
                quest_id,
                "items",
                &item_id.to_string(),
                "flow.nodes.item_id",
            );
        }
        push_reference(
            references,
            "quests",
            quest_id,
            "dialogues",
            &node.dialog_id,
            "flow.nodes.dialog_id",
        );
        for reward_item in &node.rewards.items {
            push_reference(
                references,
                "quests",
                quest_id,
                "items",
                &reward_item.id.to_string(),
                "flow.nodes.rewards.items",
            );
        }
        push_reference(
            references,
            "quests",
            quest_id,
            "map_locations",
            &node.rewards.unlock_location,
            "flow.nodes.rewards.unlock_location",
        );
        for recipe_id in &node.rewards.unlock_recipes {
            push_reference(
                references,
                "quests",
                quest_id,
                "recipes",
                recipe_id,
                "flow.nodes.rewards.unlock_recipes",
            );
        }
    }
}

fn collect_recipe_references(
    recipe_id: &str,
    definition: &RecipeDefinition,
    references: &mut Vec<ContentReference>,
) {
    push_reference(
        references,
        "recipes",
        recipe_id,
        "items",
        &definition.output.item_id.to_string(),
        "output.item_id",
    );
    for material in &definition.materials {
        push_reference(
            references,
            "recipes",
            recipe_id,
            "items",
            &material.item_id.to_string(),
            "materials.item_id",
        );
    }
    for tool in definition
        .required_tools
        .iter()
        .chain(definition.optional_tools.iter())
    {
        if let Ok(item_id) = tool.parse::<u32>() {
            push_reference(
                references,
                "recipes",
                recipe_id,
                "items",
                &item_id.to_string(),
                "tools",
            );
        }
    }
    for skill_id in definition.skill_requirements.keys() {
        push_reference(
            references,
            "recipes",
            recipe_id,
            "skills",
            skill_id,
            "skill_requirements",
        );
    }
    for condition in &definition.unlock_conditions {
        if condition.condition_type == "recipe" {
            push_reference(
                references,
                "recipes",
                recipe_id,
                "recipes",
                &condition.id,
                "unlock_conditions",
            );
        }
    }
}

fn collect_settlement_references(
    settlement_id: &str,
    definition: &SettlementDefinition,
    references: &mut Vec<ContentReference>,
) {
    push_reference(
        references,
        "settlements",
        settlement_id,
        "maps",
        definition.map_id.as_str(),
        "map_id",
    );
}

fn collect_shop_references(
    shop_id: &str,
    definition: &ShopDefinition,
    references: &mut Vec<ContentReference>,
) {
    for entry in &definition.inventory {
        push_reference(
            references,
            "shops",
            shop_id,
            "items",
            &entry.item_id.to_string(),
            "inventory.item_id",
        );
    }
}

fn push_reference(
    references: &mut Vec<ContentReference>,
    source_domain: &str,
    source_id: &str,
    target_domain: &str,
    target_id: &str,
    path: &str,
) {
    let normalized_target_id = target_id.trim();
    if normalized_target_id.is_empty() {
        return;
    }

    references.push(ContentReference {
        source_domain: source_domain.to_string(),
        source_id: source_id.to_string(),
        target_domain: target_domain.to_string(),
        target_id: normalized_target_id.to_string(),
        path: path.to_string(),
    });
}

fn scan_json_file_ids(path: &Path) -> Result<Vec<String>, ContentRegistryLoadError> {
    if !path.exists() {
        return Ok(Vec::new());
    }

    let raw = fs::read_to_string(path).map_err(|source| ContentRegistryLoadError::ReadRawFile {
        path: path.to_path_buf(),
        source,
    })?;
    let parsed: Value =
        serde_json::from_str(&raw).map_err(|source| ContentRegistryLoadError::ParseRawFile {
            path: path.to_path_buf(),
            source,
        })?;

    let mut ids = Vec::new();
    match parsed {
        Value::Object(map) => {
            ids.extend(map.into_iter().map(|(key, _)| key));
        }
        Value::Array(values) => {
            for value in values {
                if let Some(id) = value
                    .as_object()
                    .and_then(|object| {
                        object
                            .get("id")
                            .or_else(|| object.get("quest_id"))
                            .or_else(|| object.get("dialog_id"))
                            .or_else(|| object.get("title"))
                    })
                    .and_then(value_to_string)
                {
                    ids.push(id);
                }
            }
        }
        _ => {}
    }

    Ok(ids)
}

fn scan_single_file_marker(
    path: &Path,
    marker_id: &str,
) -> Result<Vec<String>, ContentRegistryLoadError> {
    if !path.exists() {
        return Ok(Vec::new());
    }

    fs::metadata(path).map_err(|source| ContentRegistryLoadError::ReadRawFile {
        path: path.to_path_buf(),
        source,
    })?;
    Ok(vec![marker_id.to_string()])
}

fn value_to_string(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => Some(text.trim().to_string()),
        Value::Number(number) => Some(number.to_string()),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::{load_shared_content_registry, ContentAuthorityKind};

    #[test]
    fn shared_content_registry_loads_real_project_data() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..");
        let registry = load_shared_content_registry(&repo_root)
            .expect("real project content registry should load");

        assert!(!registry.domains.is_empty());
        assert!(registry
            .domains
            .iter()
            .any(|domain| domain.domain == "items"
                && domain.authority == ContentAuthorityKind::RustSchema
                && domain.record_count > 0));
        assert!(registry
            .references
            .iter()
            .any(|reference| reference.source_domain == "items"));
    }
}
