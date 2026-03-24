use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct ShopInventoryEntry {
    pub item_id: u32,
    pub count: i32,
    pub price: i32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ShopDefinition {
    pub id: String,
    pub buy_price_modifier: f32,
    pub sell_price_modifier: f32,
    pub money: i32,
    pub inventory: Vec<ShopInventoryEntry>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct ShopLibrary {
    definitions: BTreeMap<String, ShopDefinition>,
}

impl From<BTreeMap<String, ShopDefinition>> for ShopLibrary {
    fn from(definitions: BTreeMap<String, ShopDefinition>) -> Self {
        Self { definitions }
    }
}

impl ShopLibrary {
    pub fn get(&self, id: &str) -> Option<&ShopDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &ShopDefinition)> {
        self.definitions.iter()
    }

    pub fn len(&self) -> usize {
        self.definitions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }

    pub fn ids(&self) -> BTreeSet<String> {
        self.definitions.keys().cloned().collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ShopValidationCatalog {
    pub item_ids: BTreeSet<u32>,
}

#[derive(Debug, Error, Clone, PartialEq)]
pub enum ShopDefinitionValidationError {
    #[error("shop id cannot be empty")]
    MissingId,
    #[error("shop {shop_id} buy_price_modifier must be >= 0")]
    NegativeBuyModifier { shop_id: String },
    #[error("shop {shop_id} sell_price_modifier must be >= 0")]
    NegativeSellModifier { shop_id: String },
    #[error("shop {shop_id} money must be >= 0")]
    NegativeMoney { shop_id: String },
    #[error("shop {shop_id} inventory entry {index} item_id must be > 0")]
    MissingItemId { shop_id: String, index: usize },
    #[error("shop {shop_id} inventory entry {index} count must be >= 0")]
    NegativeCount { shop_id: String, index: usize },
    #[error("shop {shop_id} inventory entry {index} price must be >= 0")]
    NegativePrice { shop_id: String, index: usize },
    #[error("shop {shop_id} inventory entry {index} references unknown item id {item_id}")]
    UnknownItemId {
        shop_id: String,
        index: usize,
        item_id: u32,
    },
}

#[derive(Debug, Error)]
pub enum ShopLoadError {
    #[error("failed to read shop definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read shop definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse shop definition file {path}: {message}")]
    ParseFile { path: PathBuf, message: String },
    #[error("shop definition file {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: ShopDefinitionValidationError,
    },
    #[error(
        "duplicate shop id {shop_id} found in {duplicate_path} (first declared in {first_path})"
    )]
    DuplicateId {
        shop_id: String,
        first_path: PathBuf,
        duplicate_path: PathBuf,
    },
}

pub fn validate_shop_definition(
    definition: &ShopDefinition,
    catalog: Option<&ShopValidationCatalog>,
) -> Result<(), ShopDefinitionValidationError> {
    let shop_id = definition.id.trim();
    if shop_id.is_empty() {
        return Err(ShopDefinitionValidationError::MissingId);
    }
    if definition.buy_price_modifier < 0.0 {
        return Err(ShopDefinitionValidationError::NegativeBuyModifier {
            shop_id: shop_id.to_string(),
        });
    }
    if definition.sell_price_modifier < 0.0 {
        return Err(ShopDefinitionValidationError::NegativeSellModifier {
            shop_id: shop_id.to_string(),
        });
    }
    if definition.money < 0 {
        return Err(ShopDefinitionValidationError::NegativeMoney {
            shop_id: shop_id.to_string(),
        });
    }

    for (index, entry) in definition.inventory.iter().enumerate() {
        if entry.item_id == 0 {
            return Err(ShopDefinitionValidationError::MissingItemId {
                shop_id: shop_id.to_string(),
                index,
            });
        }
        if entry.count < 0 {
            return Err(ShopDefinitionValidationError::NegativeCount {
                shop_id: shop_id.to_string(),
                index,
            });
        }
        if entry.price < 0 {
            return Err(ShopDefinitionValidationError::NegativePrice {
                shop_id: shop_id.to_string(),
                index,
            });
        }
        if let Some(catalog) = catalog {
            if !catalog.item_ids.is_empty() && !catalog.item_ids.contains(&entry.item_id) {
                return Err(ShopDefinitionValidationError::UnknownItemId {
                    shop_id: shop_id.to_string(),
                    index,
                    item_id: entry.item_id,
                });
            }
        }
    }

    Ok(())
}

pub fn load_shop_library(
    dir: impl AsRef<Path>,
    catalog: Option<&ShopValidationCatalog>,
) -> Result<ShopLibrary, ShopLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| ShopLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins = BTreeMap::<String, PathBuf>::new();

    for entry in entries {
        let entry = entry.map_err(|source| ShopLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if !path.is_file() || path.extension().and_then(|value| value.to_str()) != Some("tres") {
            continue;
        }

        let raw = fs::read_to_string(&path).map_err(|source| ShopLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let source_id = path
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string();
        let definition = parse_shop_definition(&source_id, &raw).map_err(|message| {
            ShopLoadError::ParseFile {
                path: path.clone(),
                message,
            }
        })?;

        validate_shop_definition(&definition, catalog).map_err(|source| {
            ShopLoadError::Validation {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = origins.insert(definition.id.clone(), path.clone()) {
            return Err(ShopLoadError::DuplicateId {
                shop_id: definition.id.clone(),
                first_path,
                duplicate_path: path,
            });
        }

        definitions.insert(definition.id.clone(), definition);
    }

    Ok(ShopLibrary { definitions })
}

fn parse_shop_definition(source_id: &str, raw: &str) -> Result<ShopDefinition, String> {
    let mut definition = ShopDefinition {
        id: source_id.to_string(),
        buy_price_modifier: 1.0,
        sell_price_modifier: 1.0,
        money: 0,
        inventory: Vec::new(),
    };

    let mut in_resource = false;
    let mut inventory_buffer = String::new();
    let mut collecting_inventory = false;
    let mut bracket_balance = 0i32;

    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed == "[resource]" {
            in_resource = true;
            continue;
        }
        if !in_resource || trimmed.is_empty() {
            continue;
        }

        if collecting_inventory {
            inventory_buffer.push_str(trimmed);
            inventory_buffer.push('\n');
            bracket_balance += bracket_delta(trimmed);
            if bracket_balance <= 0 {
                definition.inventory =
                    serde_json::from_str::<Vec<RawShopInventoryEntry>>(&inventory_buffer)
                        .map_err(|error| {
                            format!("failed to parse inventory JSON payload: {error}")
                        })?
                        .into_iter()
                        .map(|entry| {
                            Ok::<ShopInventoryEntry, String>(ShopInventoryEntry {
                                item_id: entry.id.parse::<u32>().map_err(|error| {
                                    format!("invalid shop inventory item id {}: {error}", entry.id)
                                })?,
                                count: entry.count,
                                price: entry.price,
                            })
                        })
                        .collect::<Result<Vec<_>, _>>()?;
                collecting_inventory = false;
                inventory_buffer.clear();
            }
            continue;
        }

        let Some((key, value)) = trimmed.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        match key {
            "buy_price_modifier" => {
                definition.buy_price_modifier = value
                    .parse::<f32>()
                    .map_err(|error| format!("invalid buy_price_modifier {value}: {error}"))?;
            }
            "sell_price_modifier" => {
                definition.sell_price_modifier = value
                    .parse::<f32>()
                    .map_err(|error| format!("invalid sell_price_modifier {value}: {error}"))?;
            }
            "money" => {
                definition.money = value
                    .parse::<i32>()
                    .map_err(|error| format!("invalid money {value}: {error}"))?;
            }
            "inventory" => {
                collecting_inventory = true;
                inventory_buffer.push_str(value);
                inventory_buffer.push('\n');
                bracket_balance = bracket_delta(value);
                if bracket_balance <= 0 {
                    definition.inventory =
                        serde_json::from_str::<Vec<RawShopInventoryEntry>>(&inventory_buffer)
                            .map_err(|error| {
                                format!("failed to parse inventory JSON payload: {error}")
                            })?
                            .into_iter()
                            .map(|entry| {
                                Ok::<ShopInventoryEntry, String>(ShopInventoryEntry {
                                    item_id: entry.id.parse::<u32>().map_err(|error| {
                                        format!(
                                            "invalid shop inventory item id {}: {error}",
                                            entry.id
                                        )
                                    })?,
                                    count: entry.count,
                                    price: entry.price,
                                })
                            })
                            .collect::<Result<Vec<_>, _>>()?;
                    collecting_inventory = false;
                    inventory_buffer.clear();
                }
            }
            _ => {}
        }
    }

    if collecting_inventory {
        return Err("unterminated inventory payload".to_string());
    }

    Ok(definition)
}

fn bracket_delta(line: &str) -> i32 {
    let open = line.chars().filter(|character| *character == '[').count() as i32;
    let close = line.chars().filter(|character| *character == ']').count() as i32;
    open - close
}

#[derive(Debug, Clone, Deserialize)]
struct RawShopInventoryEntry {
    id: String,
    count: i32,
    price: i32,
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::{load_shop_library, ShopValidationCatalog};
    use crate::load_item_library;

    #[test]
    fn load_shop_library_accepts_real_data() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..");
        let items = load_item_library(repo_root.join("data").join("items"), None)
            .expect("items should load");
        let shops = load_shop_library(
            repo_root.join("data").join("shops"),
            Some(&ShopValidationCatalog {
                item_ids: items.ids(),
            }),
        )
        .expect("shops should load");
        assert!(!shops.is_empty());
    }
}
