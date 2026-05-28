// Temporary survival-domain compatibility scaffold.
// The current headless actor economy authority lives in `economy.rs`;
// this module gives the broader survival runtime a concrete home so
// `game_core` no longer exports a missing module while we continue to
// fold more legacy gameplay domains into Rust.
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::error::Error;
use std::fmt;

use game_data::{
    ActorId, ItemDefinition, ItemLibrary, RecipeDefinition, RecipeLibrary, ShopLibrary,
};

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ActorSurvivalState {
    pub money: i32,
    pub inventory: BTreeMap<String, i32>,
    pub unlocked_recipes: BTreeSet<String>,
    pub skill_levels: BTreeMap<String, i32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ShopInventoryState {
    pub item_id: String,
    pub count: i32,
    pub price: i32,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct ShopRuntimeState {
    pub id: String,
    pub buy_price_modifier: f32,
    pub sell_price_modifier: f32,
    pub money: i32,
    pub inventory: BTreeMap<String, ShopInventoryState>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MissingInventoryEntry {
    pub item_id: String,
    pub required: i32,
    pub current: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MissingSkillRequirement {
    pub skill_id: String,
    pub required: i32,
    pub current: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CraftingCheck {
    pub can_craft: bool,
    pub recipe_unlocked: bool,
    pub missing_materials: Vec<MissingInventoryEntry>,
    pub missing_tools: Vec<String>,
    pub missing_skills: Vec<MissingSkillRequirement>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CraftingResult {
    pub recipe_id: String,
    pub output_item_id: String,
    pub output_count: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TradeQuote {
    pub item_id: String,
    pub count: i32,
    pub unit_price: i32,
    pub total_price: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TradeResult {
    pub quote: TradeQuote,
    pub actor_money_after: i32,
    pub shop_money_after: i32,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct SurvivalRuntime {
    actors: HashMap<ActorId, ActorSurvivalState>,
    shops: BTreeMap<String, ShopRuntimeState>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SurvivalRuntimeError {
    UnknownActor {
        actor_id: ActorId,
    },
    UnknownShop {
        shop_id: String,
    },
    UnknownRecipe {
        recipe_id: String,
    },
    UnknownItem {
        item_id: String,
    },
    InvalidCount {
        count: i32,
    },
    InsufficientItem {
        owner: String,
        item_id: String,
        required: i32,
        current: i32,
    },
    InsufficientMoney {
        owner: String,
        required: i32,
        current: i32,
    },
    RecipeLocked {
        actor_id: ActorId,
        recipe_id: String,
    },
    MissingTools {
        recipe_id: String,
        tools: Vec<String>,
    },
    MissingSkills {
        recipe_id: String,
        missing: Vec<MissingSkillRequirement>,
    },
}

impl fmt::Display for SurvivalRuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnknownActor { actor_id } => write!(f, "unknown actor: {:?}", actor_id),
            Self::UnknownShop { shop_id } => write!(f, "unknown shop: {shop_id}"),
            Self::UnknownRecipe { recipe_id } => write!(f, "unknown recipe: {recipe_id}"),
            Self::UnknownItem { item_id } => write!(f, "unknown item: {item_id}"),
            Self::InvalidCount { count } => write!(f, "invalid count: {count}"),
            Self::InsufficientItem {
                owner,
                item_id,
                required,
                current,
            } => write!(
                f,
                "{owner} does not have enough item {item_id}: required {required}, current {current}"
            ),
            Self::InsufficientMoney {
                owner,
                required,
                current,
            } => write!(
                f,
                "{owner} does not have enough money: required {required}, current {current}"
            ),
            Self::RecipeLocked { actor_id, recipe_id } => {
                write!(f, "actor {:?} has not unlocked recipe {recipe_id}", actor_id)
            }
            Self::MissingTools { recipe_id, tools } => {
                write!(f, "recipe {recipe_id} is missing required tools {}", tools.join(","))
            }
            Self::MissingSkills { recipe_id, missing } => write!(
                f,
                "recipe {recipe_id} is missing required skills {}",
                missing
                    .iter()
                    .map(|entry| format!("{}:{}/{}", entry.skill_id, entry.current, entry.required))
                    .collect::<Vec<_>>()
                    .join(",")
            ),
        }
    }
}

impl Error for SurvivalRuntimeError {}

impl SurvivalRuntime {
    pub fn register_actor(&mut self, actor_id: ActorId) {
        self.actors.entry(actor_id).or_default();
    }

    pub fn unregister_actor(&mut self, actor_id: ActorId) {
        self.actors.remove(&actor_id);
    }

    pub fn actor(&self, actor_id: ActorId) -> Option<&ActorSurvivalState> {
        self.actors.get(&actor_id)
    }

    pub fn actor_money(&self, actor_id: ActorId) -> Option<i32> {
        self.actor(actor_id).map(|state| state.money)
    }

    pub fn set_actor_money(
        &mut self,
        actor_id: ActorId,
        money: i32,
    ) -> Result<(), SurvivalRuntimeError> {
        let actor = self.actor_state_mut(actor_id)?;
        actor.money = money.max(0);
        Ok(())
    }

    pub fn inventory(&self, actor_id: ActorId) -> Option<&BTreeMap<String, i32>> {
        self.actor(actor_id).map(|state| &state.inventory)
    }

    pub fn item_count(&self, actor_id: ActorId, item_id: &str) -> i32 {
        self.actor(actor_id)
            .and_then(|state| state.inventory.get(item_id))
            .copied()
            .unwrap_or(0)
    }

    pub fn has_item(&self, actor_id: ActorId, item_id: &str, count: i32) -> bool {
        if count <= 0 {
            return false;
        }
        self.item_count(actor_id, item_id) >= count
    }

    pub fn add_item(
        &mut self,
        actor_id: ActorId,
        item_id: impl Into<String>,
        count: i32,
    ) -> Result<i32, SurvivalRuntimeError> {
        if count <= 0 {
            return Err(SurvivalRuntimeError::InvalidCount { count });
        }

        let item_id = item_id.into();
        let actor = self.actor_state_mut(actor_id)?;
        let next_total = actor.inventory.get(&item_id).copied().unwrap_or(0) + count;
        actor.inventory.insert(item_id, next_total);
        Ok(next_total)
    }

    pub fn remove_item(
        &mut self,
        actor_id: ActorId,
        item_id: &str,
        count: i32,
    ) -> Result<i32, SurvivalRuntimeError> {
        if count <= 0 {
            return Err(SurvivalRuntimeError::InvalidCount { count });
        }

        let actor = self.actor_state_mut(actor_id)?;
        let current = actor.inventory.get(item_id).copied().unwrap_or(0);
        if current < count {
            return Err(SurvivalRuntimeError::InsufficientItem {
                owner: format!("actor:{:?}", actor_id),
                item_id: item_id.to_string(),
                required: count,
                current,
            });
        }

        let remaining = current - count;
        if remaining == 0 {
            actor.inventory.remove(item_id);
        } else {
            actor.inventory.insert(item_id.to_string(), remaining);
        }
        Ok(remaining)
    }

    pub fn inventory_weight(
        &self,
        actor_id: ActorId,
        items: &ItemLibrary,
    ) -> Result<f32, SurvivalRuntimeError> {
        let actor = self.actor_state(actor_id)?;
        let mut total = 0.0;

        for (item_id, count) in &actor.inventory {
            let definition = lookup_item_definition(item_id, items)?;
            total += definition.weight * (*count as f32);
        }

        Ok(total)
    }

    pub fn set_skill_level(
        &mut self,
        actor_id: ActorId,
        skill_id: impl Into<String>,
        level: i32,
    ) -> Result<(), SurvivalRuntimeError> {
        let actor = self.actor_state_mut(actor_id)?;
        let skill_id = skill_id.into();
        let normalized_level = level.max(0);
        if normalized_level == 0 {
            actor.skill_levels.remove(&skill_id);
        } else {
            actor.skill_levels.insert(skill_id, normalized_level);
        }
        Ok(())
    }

    pub fn skill_level(&self, actor_id: ActorId, skill_id: &str) -> i32 {
        self.actor(actor_id)
            .and_then(|state| state.skill_levels.get(skill_id))
            .copied()
            .unwrap_or(0)
    }

    pub fn unlock_recipe(
        &mut self,
        actor_id: ActorId,
        recipe_id: impl Into<String>,
    ) -> Result<(), SurvivalRuntimeError> {
        let actor = self.actor_state_mut(actor_id)?;
        actor.unlocked_recipes.insert(recipe_id.into());
        Ok(())
    }

    pub fn unlock_default_recipes(
        &mut self,
        actor_id: ActorId,
        recipes: &RecipeLibrary,
    ) -> Result<usize, SurvivalRuntimeError> {
        let actor = self.actor_state_mut(actor_id)?;
        let mut unlocked = 0usize;
        for (recipe_id, definition) in recipes.iter() {
            if definition.is_default_unlocked && actor.unlocked_recipes.insert(recipe_id.clone()) {
                unlocked += 1;
            }
        }
        Ok(unlocked)
    }

    pub fn is_recipe_unlocked(&self, actor_id: ActorId, recipe: &RecipeDefinition) -> bool {
        recipe.is_default_unlocked
            || self
                .actor(actor_id)
                .map(|state| state.unlocked_recipes.contains(&recipe.id))
                .unwrap_or(false)
    }

    pub fn can_craft(
        &self,
        actor_id: ActorId,
        recipe_id: &str,
        recipes: &RecipeLibrary,
    ) -> Result<CraftingCheck, SurvivalRuntimeError> {
        let actor = self.actor_state(actor_id)?;
        let recipe = recipes
            .get(recipe_id)
            .ok_or_else(|| SurvivalRuntimeError::UnknownRecipe {
                recipe_id: recipe_id.to_string(),
            })?;

        let recipe_unlocked = self.is_recipe_unlocked(actor_id, recipe);
        let mut check = CraftingCheck {
            can_craft: recipe_unlocked,
            recipe_unlocked,
            missing_materials: Vec::new(),
            missing_tools: Vec::new(),
            missing_skills: Vec::new(),
        };

        for material in &recipe.materials {
            let item_id = material.item_id.to_string();
            let current = actor.inventory.get(&item_id).copied().unwrap_or(0);
            if current < material.count {
                check.missing_materials.push(MissingInventoryEntry {
                    item_id,
                    required: material.count,
                    current,
                });
            }
        }

        for tool_id in &recipe.required_tools {
            let normalized = tool_id.trim();
            if normalized.is_empty() {
                continue;
            }
            if actor.inventory.get(normalized).copied().unwrap_or(0) < 1 {
                check.missing_tools.push(normalized.to_string());
            }
        }

        for (skill_id, required_level) in &recipe.skill_requirements {
            let current = actor.skill_levels.get(skill_id).copied().unwrap_or(0);
            if current < *required_level {
                check.missing_skills.push(MissingSkillRequirement {
                    skill_id: skill_id.clone(),
                    required: *required_level,
                    current,
                });
            }
        }

        check.can_craft = check.recipe_unlocked
            && check.missing_materials.is_empty()
            && check.missing_tools.is_empty()
            && check.missing_skills.is_empty();

        Ok(check)
    }

    pub fn craft(
        &mut self,
        actor_id: ActorId,
        recipe_id: &str,
        recipes: &RecipeLibrary,
    ) -> Result<CraftingResult, SurvivalRuntimeError> {
        let recipe = recipes
            .get(recipe_id)
            .ok_or_else(|| SurvivalRuntimeError::UnknownRecipe {
                recipe_id: recipe_id.to_string(),
            })?
            .clone();

        let check = self.can_craft(actor_id, recipe_id, recipes)?;
        if !check.recipe_unlocked {
            return Err(SurvivalRuntimeError::RecipeLocked {
                actor_id,
                recipe_id: recipe_id.to_string(),
            });
        }
        if !check.missing_tools.is_empty() {
            return Err(SurvivalRuntimeError::MissingTools {
                recipe_id: recipe_id.to_string(),
                tools: check.missing_tools,
            });
        }
        if !check.missing_skills.is_empty() {
            return Err(SurvivalRuntimeError::MissingSkills {
                recipe_id: recipe_id.to_string(),
                missing: check.missing_skills,
            });
        }
        if let Some(missing) = check.missing_materials.first() {
            return Err(SurvivalRuntimeError::InsufficientItem {
                owner: format!("actor:{:?}", actor_id),
                item_id: missing.item_id.clone(),
                required: missing.required,
                current: missing.current,
            });
        }

        for material in &recipe.materials {
            self.remove_item(actor_id, &material.item_id.to_string(), material.count)?;
        }
        self.add_item(
            actor_id,
            recipe.output.item_id.to_string(),
            recipe.output.count,
        )?;

        Ok(CraftingResult {
            recipe_id: recipe.id,
            output_item_id: recipe.output.item_id.to_string(),
            output_count: recipe.output.count,
        })
    }

    pub fn load_shops(&mut self, shops: &ShopLibrary) {
        self.shops.clear();
        for (shop_id, definition) in shops.iter() {
            self.shops.insert(
                shop_id.clone(),
                build_shop_runtime_state(shop_id, definition),
            );
        }
    }

    pub fn shop(&self, shop_id: &str) -> Option<&ShopRuntimeState> {
        self.shops.get(shop_id)
    }

    pub fn shop_count(&self) -> usize {
        self.shops.len()
    }

    pub fn buy_from_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        item_id: &str,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<TradeResult, SurvivalRuntimeError> {
        if count <= 0 {
            return Err(SurvivalRuntimeError::InvalidCount { count });
        }

        let entry = self
            .shops
            .get(shop_id)
            .and_then(|shop| shop.inventory.get(item_id))
            .cloned()
            .ok_or_else(|| SurvivalRuntimeError::UnknownItem {
                item_id: item_id.to_string(),
            })?;
        if entry.count < count {
            return Err(SurvivalRuntimeError::InsufficientItem {
                owner: format!("shop:{shop_id}"),
                item_id: item_id.to_string(),
                required: count,
                current: entry.count,
            });
        }

        let unit_price = {
            let shop =
                self.shops
                    .get(shop_id)
                    .ok_or_else(|| SurvivalRuntimeError::UnknownShop {
                        shop_id: shop_id.to_string(),
                    })?;
            calculate_buy_price(shop, &entry, items)?
        };
        let total_price = unit_price.saturating_mul(count);

        let actor_money = self.actor_state(actor_id)?.money;
        if actor_money < total_price {
            return Err(SurvivalRuntimeError::InsufficientMoney {
                owner: format!("actor:{:?}", actor_id),
                required: total_price,
                current: actor_money,
            });
        }

        {
            let actor = self.actor_state_mut(actor_id)?;
            actor.money -= total_price;
            let total = actor.inventory.get(item_id).copied().unwrap_or(0) + count;
            actor.inventory.insert(item_id.to_string(), total);
        }
        {
            let shop = self.shop_state_mut(shop_id)?;
            shop.money += total_price;
            if let Some(item) = shop.inventory.get_mut(item_id) {
                item.count -= count;
                if item.count <= 0 {
                    shop.inventory.remove(item_id);
                }
            }
        }

        Ok(TradeResult {
            quote: TradeQuote {
                item_id: item_id.to_string(),
                count,
                unit_price,
                total_price,
            },
            actor_money_after: self.actor_money(actor_id).unwrap_or(0),
            shop_money_after: self.shop(shop_id).map(|shop| shop.money).unwrap_or(0),
        })
    }

    pub fn sell_to_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        item_id: &str,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<TradeResult, SurvivalRuntimeError> {
        if count <= 0 {
            return Err(SurvivalRuntimeError::InvalidCount { count });
        }
        if self.item_count(actor_id, item_id) < count {
            return Err(SurvivalRuntimeError::InsufficientItem {
                owner: format!("actor:{:?}", actor_id),
                item_id: item_id.to_string(),
                required: count,
                current: self.item_count(actor_id, item_id),
            });
        }

        let unit_price = {
            let shop = self.shop_state(shop_id)?;
            calculate_sell_price(shop, item_id, items)?
        };
        let total_price = unit_price.saturating_mul(count);

        let shop_money = self.shop_state(shop_id)?.money;
        if shop_money < total_price {
            return Err(SurvivalRuntimeError::InsufficientMoney {
                owner: format!("shop:{shop_id}"),
                required: total_price,
                current: shop_money,
            });
        }

        self.remove_item(actor_id, item_id, count)?;
        {
            let actor = self.actor_state_mut(actor_id)?;
            actor.money += total_price;
        }
        {
            let shop = self.shop_state_mut(shop_id)?;
            shop.money -= total_price;
            let entry = shop
                .inventory
                .entry(item_id.to_string())
                .or_insert_with(|| ShopInventoryState {
                    item_id: item_id.to_string(),
                    count: 0,
                    price: unit_price,
                });
            entry.count += count;
            entry.price = unit_price;
        }

        Ok(TradeResult {
            quote: TradeQuote {
                item_id: item_id.to_string(),
                count,
                unit_price,
                total_price,
            },
            actor_money_after: self.actor_money(actor_id).unwrap_or(0),
            shop_money_after: self.shop(shop_id).map(|shop| shop.money).unwrap_or(0),
        })
    }

    fn actor_state(&self, actor_id: ActorId) -> Result<&ActorSurvivalState, SurvivalRuntimeError> {
        self.actors
            .get(&actor_id)
            .ok_or(SurvivalRuntimeError::UnknownActor { actor_id })
    }

    fn actor_state_mut(
        &mut self,
        actor_id: ActorId,
    ) -> Result<&mut ActorSurvivalState, SurvivalRuntimeError> {
        self.actors
            .get_mut(&actor_id)
            .ok_or(SurvivalRuntimeError::UnknownActor { actor_id })
    }

    fn shop_state(&self, shop_id: &str) -> Result<&ShopRuntimeState, SurvivalRuntimeError> {
        self.shops
            .get(shop_id)
            .ok_or_else(|| SurvivalRuntimeError::UnknownShop {
                shop_id: shop_id.to_string(),
            })
    }

    fn shop_state_mut(
        &mut self,
        shop_id: &str,
    ) -> Result<&mut ShopRuntimeState, SurvivalRuntimeError> {
        self.shops
            .get_mut(shop_id)
            .ok_or_else(|| SurvivalRuntimeError::UnknownShop {
                shop_id: shop_id.to_string(),
            })
    }
}

fn build_shop_runtime_state(
    shop_id: &str,
    definition: &game_data::ShopDefinition,
) -> ShopRuntimeState {
    let mut inventory = BTreeMap::new();
    for entry in &definition.inventory {
        inventory.insert(
            entry.item_id.to_string(),
            ShopInventoryState {
                item_id: entry.item_id.to_string(),
                count: entry.count,
                price: entry.price,
            },
        );
    }

    ShopRuntimeState {
        id: shop_id.to_string(),
        buy_price_modifier: definition.buy_price_modifier,
        sell_price_modifier: definition.sell_price_modifier,
        money: definition.money,
        inventory,
    }
}

fn calculate_buy_price(
    shop: &ShopRuntimeState,
    entry: &ShopInventoryState,
    items: &ItemLibrary,
) -> Result<i32, SurvivalRuntimeError> {
    let base_price = if entry.price > 0 {
        entry.price
    } else {
        item_base_value(&entry.item_id, items)?
    };
    Ok(((base_price as f32) * shop.buy_price_modifier).round() as i32)
}

fn calculate_sell_price(
    shop: &ShopRuntimeState,
    item_id: &str,
    items: &ItemLibrary,
) -> Result<i32, SurvivalRuntimeError> {
    let base_price = item_base_value(item_id, items)?;
    Ok(((base_price as f32) * shop.sell_price_modifier).round() as i32)
}

fn item_base_value(item_id: &str, items: &ItemLibrary) -> Result<i32, SurvivalRuntimeError> {
    Ok(lookup_item_definition(item_id, items)?.value)
}

fn lookup_item_definition<'a>(
    item_id: &str,
    items: &'a ItemLibrary,
) -> Result<&'a ItemDefinition, SurvivalRuntimeError> {
    let parsed = item_id
        .parse::<u32>()
        .map_err(|_| SurvivalRuntimeError::UnknownItem {
            item_id: item_id.to_string(),
        })?;
    items
        .get(parsed)
        .ok_or_else(|| SurvivalRuntimeError::UnknownItem {
            item_id: item_id.to_string(),
        })
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use game_data::{
        ActorId, ItemDefinition, ItemLibrary, RecipeDefinition, RecipeLibrary, RecipeMaterial,
        RecipeOutput, ShopDefinition, ShopInventoryEntry, ShopLibrary,
    };

    use super::{CraftingResult, SurvivalRuntime, TradeResult};

    #[test]
    fn inventory_weight_uses_loaded_item_definitions() {
        let mut runtime = SurvivalRuntime::default();
        let actor = ActorId(1);
        runtime.register_actor(actor);
        runtime
            .add_item(actor, "1005", 2)
            .expect("items should add");
        runtime
            .add_item(actor, "1010", 1)
            .expect("items should add");

        let weight = runtime
            .inventory_weight(actor, &sample_item_library())
            .expect("weight should resolve");

        assert!((weight - 2.5).abs() < f32::EPSILON);
    }

    #[test]
    fn crafting_consumes_materials_and_produces_output() {
        let mut runtime = SurvivalRuntime::default();
        let actor = ActorId(1);
        runtime.register_actor(actor);
        runtime
            .add_item(actor, "1105", 1)
            .expect("powder should add");
        runtime
            .add_item(actor, "1010", 1)
            .expect("metal should add");
        runtime.add_item(actor, "2000", 1).expect("tool should add");
        runtime
            .set_skill_level(actor, "crafting", 1)
            .expect("skill should set");
        runtime
            .unlock_recipe(actor, "recipe_ammo_pistol")
            .expect("recipe should unlock");

        let result = runtime
            .craft(actor, "recipe_ammo_pistol", &sample_recipe_library())
            .expect("craft should succeed");

        assert_eq!(
            result,
            CraftingResult {
                recipe_id: "recipe_ammo_pistol".to_string(),
                output_item_id: "1009".to_string(),
                output_count: 10,
            }
        );
        assert_eq!(runtime.item_count(actor, "1105"), 0);
        assert_eq!(runtime.item_count(actor, "1010"), 0);
        assert_eq!(runtime.item_count(actor, "2000"), 1);
        assert_eq!(runtime.item_count(actor, "1009"), 10);
    }

    #[test]
    fn shop_buy_and_sell_updates_money_and_inventory() {
        let mut runtime = SurvivalRuntime::default();
        let actor = ActorId(1);
        runtime.register_actor(actor);
        runtime
            .set_actor_money(actor, 200)
            .expect("money should set");
        runtime.load_shops(&sample_shop_library());

        let purchase = runtime
            .buy_from_shop(
                actor,
                "trader_lao_wang_shop",
                "1005",
                2,
                &sample_item_library(),
            )
            .expect("purchase should succeed");
        assert_eq!(
            purchase,
            TradeResult {
                quote: super::TradeQuote {
                    item_id: "1005".to_string(),
                    count: 2,
                    unit_price: 60,
                    total_price: 120,
                },
                actor_money_after: 80,
                shop_money_after: 620,
            }
        );
        assert_eq!(runtime.item_count(actor, "1005"), 2);

        let sale = runtime
            .sell_to_shop(
                actor,
                "trader_lao_wang_shop",
                "1005",
                1,
                &sample_item_library(),
            )
            .expect("sale should succeed");
        assert_eq!(sale.quote.total_price, 40);
        assert_eq!(sale.actor_money_after, 120);
        assert_eq!(runtime.item_count(actor, "1005"), 1);
        assert_eq!(
            runtime
                .shop("trader_lao_wang_shop")
                .and_then(|shop| shop.inventory.get("1005"))
                .map(|entry| entry.count),
            Some(2)
        );
    }

    fn sample_item_library() -> ItemLibrary {
        ItemLibrary::from(BTreeMap::from([
            (
                1005,
                ItemDefinition {
                    id: 1005,
                    name: "罐头".to_string(),
                    value: 50,
                    weight: 1.0,
                    ..ItemDefinition::default()
                },
            ),
            (
                1009,
                ItemDefinition {
                    id: 1009,
                    name: "手枪弹药".to_string(),
                    value: 5,
                    weight: 0.1,
                    ..ItemDefinition::default()
                },
            ),
            (
                1010,
                ItemDefinition {
                    id: 1010,
                    name: "废铁".to_string(),
                    value: 20,
                    weight: 0.5,
                    ..ItemDefinition::default()
                },
            ),
            (
                1105,
                ItemDefinition {
                    id: 1105,
                    name: "火药".to_string(),
                    value: 5,
                    weight: 0.5,
                    ..ItemDefinition::default()
                },
            ),
            (
                2000,
                ItemDefinition {
                    id: 2000,
                    name: "工具箱".to_string(),
                    value: 80,
                    weight: 2.0,
                    ..ItemDefinition::default()
                },
            ),
        ]))
    }

    fn sample_recipe_library() -> RecipeLibrary {
        RecipeLibrary::from(BTreeMap::from([(
            "recipe_ammo_pistol".to_string(),
            RecipeDefinition {
                id: "recipe_ammo_pistol".to_string(),
                name: "手枪弹药".to_string(),
                output: RecipeOutput {
                    item_id: 1009,
                    count: 10,
                    ..RecipeOutput::default()
                },
                materials: vec![
                    RecipeMaterial {
                        item_id: 1105,
                        count: 1,
                        ..RecipeMaterial::default()
                    },
                    RecipeMaterial {
                        item_id: 1010,
                        count: 1,
                        ..RecipeMaterial::default()
                    },
                ],
                required_tools: vec!["2000".to_string()],
                skill_requirements: BTreeMap::from([("crafting".to_string(), 1)]),
                ..RecipeDefinition::default()
            },
        )]))
    }

    fn sample_shop_library() -> ShopLibrary {
        ShopLibrary::from(BTreeMap::from([(
            "trader_lao_wang_shop".to_string(),
            ShopDefinition {
                id: "trader_lao_wang_shop".to_string(),
                buy_price_modifier: 1.2,
                sell_price_modifier: 0.8,
                money: 500,
                inventory: vec![ShopInventoryEntry {
                    item_id: 1005,
                    count: 3,
                    price: 50,
                }],
            },
        )]))
    }
}
