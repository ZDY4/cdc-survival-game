use std::collections::{BTreeMap, BTreeSet};

use game_data::{
    ActorId, ItemDefinition, ItemFragment, ItemLibrary, RecipeDefinition, RecipeLibrary,
    ShopDefinition, ShopInventoryEntry, ShopLibrary, SkillDefinition, SkillLibrary,
};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct ActorEconomyState {
    pub money: i32,
    pub level: i32,
    pub inventory: BTreeMap<u32, i32>,
    #[serde(default)]
    pub inventory_order: Vec<u32>,
    pub skill_points: i32,
    pub learned_skills: BTreeMap<String, i32>,
    pub unlocked_recipes: BTreeSet<String>,
    pub attributes: BTreeMap<String, i32>,
    pub tool_tags: BTreeSet<String>,
    pub station_tags: BTreeSet<String>,
    pub equipped_slots: BTreeMap<String, EquippedItemState>,
    pub ammo_reserves: BTreeMap<u32, i32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EquippedItemState {
    pub item_id: u32,
    pub current_durability: Option<i32>,
    pub ammo_loaded: i32,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct EquippedWeaponProfile {
    pub item_id: u32,
    pub slot: String,
    pub subtype: String,
    pub damage: i32,
    pub attack_speed: f32,
    pub range: i32,
    pub stamina_cost: i32,
    pub crit_chance: f32,
    pub crit_multiplier: f32,
    pub accuracy: Option<i32>,
    pub ammo_type: Option<u32>,
    pub max_ammo: Option<i32>,
    pub ammo_loaded: i32,
    pub reload_time: Option<f32>,
    pub current_durability: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShopRuntimeEntry {
    pub item_id: u32,
    pub count: i32,
    pub price: i32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShopRuntimeState {
    pub id: String,
    pub buy_price_modifier: f32,
    pub sell_price_modifier: f32,
    pub money: i32,
    pub inventory: BTreeMap<u32, ShopRuntimeEntry>,
}

impl From<(&String, &ShopDefinition)> for ShopRuntimeState {
    fn from((shop_id, definition): (&String, &ShopDefinition)) -> Self {
        let inventory = definition
            .inventory
            .iter()
            .map(|entry| {
                (
                    entry.item_id,
                    ShopRuntimeEntry {
                        item_id: entry.item_id,
                        count: entry.count,
                        price: entry.price,
                    },
                )
            })
            .collect();
        Self {
            id: shop_id.clone(),
            buy_price_modifier: definition.buy_price_modifier,
            sell_price_modifier: definition.sell_price_modifier,
            money: definition.money,
            inventory,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TradeOutcome {
    pub shop_id: String,
    pub item_id: u32,
    pub count: i32,
    pub total_price: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CraftOutcome {
    pub recipe_id: String,
    pub output_item_id: u32,
    pub output_count: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MissingMaterial {
    pub item_id: u32,
    pub required: i32,
    pub current: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MissingSkill {
    pub skill_id: String,
    pub required_level: i32,
    pub current_level: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RecipeCraftCheck {
    pub missing_materials: Vec<MissingMaterial>,
    pub missing_tools: Vec<String>,
    pub missing_skills: Vec<MissingSkill>,
    pub missing_station: Option<String>,
    pub missing_unlock_recipes: Vec<String>,
}

impl RecipeCraftCheck {
    pub fn can_craft(&self) -> bool {
        self.missing_materials.is_empty()
            && self.missing_tools.is_empty()
            && self.missing_skills.is_empty()
            && self.missing_station.is_none()
            && self.missing_unlock_recipes.is_empty()
    }
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum EconomyRuntimeError {
    #[error("unknown actor {actor_id:?}")]
    UnknownActor { actor_id: ActorId },
    #[error("action rejected: {reason}")]
    ActionRejected { reason: String },
    #[error("unknown item {item_id}")]
    UnknownItem { item_id: u32 },
    #[error("unknown skill {skill_id}")]
    UnknownSkill { skill_id: String },
    #[error("unknown recipe {recipe_id}")]
    UnknownRecipe { recipe_id: String },
    #[error("unknown shop {shop_id}")]
    UnknownShop { shop_id: String },
    #[error("count must be positive, got {count}")]
    InvalidCount { count: i32 },
    #[error("not enough item {item_id}: required {required}, current {current}")]
    NotEnoughItems {
        item_id: u32,
        required: i32,
        current: i32,
    },
    #[error("not enough money: required {required}, current {current}")]
    NotEnoughMoney { required: i32, current: i32 },
    #[error(
        "shop {shop_id} is out of stock for item {item_id}: required {required}, current {current}"
    )]
    ShopInventoryInsufficient {
        shop_id: String,
        item_id: u32,
        required: i32,
        current: i32,
    },
    #[error("shop {shop_id} does not have enough money: required {required}, current {current}")]
    ShopOutOfMoney {
        shop_id: String,
        required: i32,
        current: i32,
    },
    #[error("skill {skill_id} has missing prerequisite {prerequisite_id}")]
    SkillPrerequisiteMissing {
        skill_id: String,
        prerequisite_id: String,
    },
    #[error("skill {skill_id} needs attribute {attribute} >= {required}, current {current}")]
    SkillAttributeRequirementMissing {
        skill_id: String,
        attribute: String,
        required: i32,
        current: i32,
    },
    #[error("no skill points available for {skill_id}")]
    MissingSkillPoints { skill_id: String },
    #[error("skill {skill_id} is already at max level")]
    SkillAlreadyMaxed { skill_id: String },
    #[error("item {item_id} is not equippable")]
    ItemNotEquippable { item_id: u32 },
    #[error("item {item_id} cannot be equipped into slot {slot}")]
    InvalidEquipmentSlot { item_id: u32, slot: String },
    #[error("item {item_id} requires level {required}, current {current}")]
    ItemLevelRequirementMissing {
        item_id: u32,
        required: i32,
        current: i32,
    },
    #[error("actor {actor_id:?} has no equipped item in slot {slot}")]
    EmptyEquipmentSlot { actor_id: ActorId, slot: String },
    #[error("item {item_id} is not a weapon")]
    ItemNotWeapon { item_id: u32 },
    #[error("weapon {item_id} does not consume ammo")]
    WeaponDoesNotUseAmmo { item_id: u32 },
    #[error("not enough ammo {item_id}: required {required}, current {current}")]
    NotEnoughAmmo {
        item_id: u32,
        required: i32,
        current: i32,
    },
    #[error("recipe {recipe_id} is locked")]
    RecipeLocked { recipe_id: String },
    #[error("recipe {recipe_id} is missing materials")]
    MissingRecipeMaterials { recipe_id: String },
    #[error("recipe {recipe_id} is missing tools")]
    MissingRecipeTools { recipe_id: String },
    #[error("recipe {recipe_id} is missing skills")]
    MissingRecipeSkills { recipe_id: String },
    #[error("recipe {recipe_id} requires station {station_id}")]
    MissingRecipeStation {
        recipe_id: String,
        station_id: String,
    },
    #[error("recipe {recipe_id} requires unlocked recipe {unlock_recipe_id}")]
    MissingRecipeUnlock {
        recipe_id: String,
        unlock_recipe_id: String,
    },
    #[error("recipe {recipe_id} is a repair recipe and needs a dedicated repair runtime")]
    UnsupportedRepairRecipe { recipe_id: String },
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct HeadlessEconomyRuntime {
    actors: BTreeMap<ActorId, ActorEconomyState>,
    shops: BTreeMap<String, ShopRuntimeState>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct HeadlessEconomyActorSnapshot {
    pub actor_id: ActorId,
    pub state: ActorEconomyState,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub(crate) struct HeadlessEconomyRuntimeSnapshot {
    pub actors: Vec<HeadlessEconomyActorSnapshot>,
    pub shops: Vec<ShopRuntimeState>,
}

impl HeadlessEconomyRuntime {
    fn normalize_actor_inventory_order(actor: &mut ActorEconomyState) {
        let mut normalized = Vec::with_capacity(actor.inventory.len());
        let mut seen = BTreeSet::new();

        for item_id in actor.inventory_order.iter().copied() {
            if actor.inventory.get(&item_id).copied().unwrap_or(0) <= 0 || !seen.insert(item_id) {
                continue;
            }
            normalized.push(item_id);
        }

        for (&item_id, &count) in &actor.inventory {
            if count > 0 && seen.insert(item_id) {
                normalized.push(item_id);
            }
        }

        actor.inventory_order = normalized;
    }

    fn append_inventory_order(actor: &mut ActorEconomyState, item_id: u32) {
        if actor.inventory.get(&item_id).copied().unwrap_or(0) > 0
            && !actor.inventory_order.contains(&item_id)
        {
            actor.inventory_order.push(item_id);
        }
    }

    fn remove_inventory_order(actor: &mut ActorEconomyState, item_id: u32) {
        actor
            .inventory_order
            .retain(|existing| *existing != item_id);
    }

    pub fn from_shop_library(shops: &ShopLibrary) -> Self {
        let mut runtime = Self::default();
        runtime.seed_shops_from_library(shops);
        runtime
    }

    pub fn seed_shops_from_library(&mut self, shops: &ShopLibrary) {
        self.shops = shops
            .iter()
            .map(|entry| {
                let state = ShopRuntimeState::from(entry);
                (state.id.clone(), state)
            })
            .collect();
    }

    pub fn ensure_actor(&mut self, actor_id: ActorId) -> &mut ActorEconomyState {
        let actor = self.actors.entry(actor_id).or_default();
        Self::normalize_actor_inventory_order(actor);
        actor
    }

    pub fn actor(&self, actor_id: ActorId) -> Option<&ActorEconomyState> {
        self.actors.get(&actor_id)
    }

    pub fn actor_mut(&mut self, actor_id: ActorId) -> Option<&mut ActorEconomyState> {
        self.actors.get_mut(&actor_id)
    }

    pub fn remove_actor(&mut self, actor_id: ActorId) -> Option<ActorEconomyState> {
        self.actors.remove(&actor_id)
    }

    pub fn shop(&self, shop_id: &str) -> Option<&ShopRuntimeState> {
        self.shops.get(shop_id)
    }

    pub fn actor_count(&self) -> usize {
        self.actors.len()
    }

    pub fn shop_count(&self) -> usize {
        self.shops.len()
    }

    pub(crate) fn save_snapshot(&self) -> HeadlessEconomyRuntimeSnapshot {
        HeadlessEconomyRuntimeSnapshot {
            actors: self
                .actors
                .iter()
                .map(|(actor_id, state)| HeadlessEconomyActorSnapshot {
                    actor_id: *actor_id,
                    state: {
                        let mut state = state.clone();
                        Self::normalize_actor_inventory_order(&mut state);
                        state
                    },
                })
                .collect(),
            shops: self.shops.values().cloned().collect(),
        }
    }

    pub(crate) fn load_snapshot(&mut self, snapshot: HeadlessEconomyRuntimeSnapshot) {
        self.actors = snapshot
            .actors
            .into_iter()
            .map(|entry| {
                let mut state = entry.state;
                Self::normalize_actor_inventory_order(&mut state);
                (entry.actor_id, state)
            })
            .collect();
        self.shops = snapshot
            .shops
            .into_iter()
            .map(|shop| (shop.id.clone(), shop))
            .collect();
    }

    pub fn initialize_actor_defaults(
        &mut self,
        actor_id: ActorId,
        recipes: &RecipeLibrary,
    ) -> &mut ActorEconomyState {
        let actor = self.ensure_actor(actor_id);
        for (recipe_id, definition) in recipes.iter() {
            if definition.is_default_unlocked {
                actor.unlocked_recipes.insert(recipe_id.clone());
            }
        }
        actor
    }

    pub fn set_actor_level(&mut self, actor_id: ActorId, level: i32) -> &mut ActorEconomyState {
        let actor = self.ensure_actor(actor_id);
        actor.level = level.max(0);
        actor
    }

    pub fn set_actor_attribute(
        &mut self,
        actor_id: ActorId,
        attribute: impl Into<String>,
        value: i32,
    ) -> &mut ActorEconomyState {
        let actor = self.ensure_actor(actor_id);
        actor.attributes.insert(attribute.into(), value.max(0));
        actor
    }

    pub fn add_skill_points(
        &mut self,
        actor_id: ActorId,
        amount: i32,
    ) -> Result<i32, EconomyRuntimeError> {
        if amount < 0 {
            return Err(EconomyRuntimeError::InvalidCount { count: amount });
        }
        let actor = self.ensure_actor(actor_id);
        actor.skill_points += amount;
        Ok(actor.skill_points)
    }

    pub fn grant_tool_tag(
        &mut self,
        actor_id: ActorId,
        tool_tag: impl Into<String>,
    ) -> Result<(), EconomyRuntimeError> {
        let normalized = tool_tag.into().trim().to_string();
        if normalized.is_empty() {
            return Ok(());
        }
        let actor = self.ensure_actor(actor_id);
        actor.tool_tags.insert(normalized);
        Ok(())
    }

    pub fn grant_station_tag(
        &mut self,
        actor_id: ActorId,
        station_tag: impl Into<String>,
    ) -> Result<(), EconomyRuntimeError> {
        let normalized = station_tag.into().trim().to_string();
        if normalized.is_empty() {
            return Ok(());
        }
        let actor = self.ensure_actor(actor_id);
        actor.station_tags.insert(normalized);
        Ok(())
    }

    pub fn grant_money(
        &mut self,
        actor_id: ActorId,
        amount: i32,
    ) -> Result<i32, EconomyRuntimeError> {
        if amount < 0 {
            return Err(EconomyRuntimeError::InvalidCount { count: amount });
        }
        let actor = self.ensure_actor(actor_id);
        actor.money += amount;
        Ok(actor.money)
    }

    pub fn actor_money(&self, actor_id: ActorId) -> Option<i32> {
        self.actor(actor_id).map(|actor| actor.money)
    }

    pub fn inventory_count(&self, actor_id: ActorId, item_id: u32) -> Option<i32> {
        self.actor(actor_id)
            .map(|actor| actor.inventory.get(&item_id).copied().unwrap_or(0))
    }

    pub fn inventory_display_order(&self, actor_id: ActorId) -> Option<Vec<u32>> {
        let actor = self.actor(actor_id)?;
        let mut normalized = actor.clone();
        Self::normalize_actor_inventory_order(&mut normalized);
        Some(normalized.inventory_order)
    }

    pub fn inventory_weight(
        &self,
        actor_id: ActorId,
        items: &ItemLibrary,
    ) -> Result<f32, EconomyRuntimeError> {
        let actor = self
            .actor(actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let mut total = 0.0;
        for (item_id, count) in &actor.inventory {
            let definition = items
                .get(*item_id)
                .ok_or(EconomyRuntimeError::UnknownItem { item_id: *item_id })?;
            total += definition.weight * (*count as f32);
        }
        Ok(total)
    }

    pub fn add_ammo(
        &mut self,
        actor_id: ActorId,
        ammo_item_id: u32,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<i32, EconomyRuntimeError> {
        if count <= 0 {
            return Err(EconomyRuntimeError::InvalidCount { count });
        }
        ensure_item_exists(items, ammo_item_id)?;
        let actor = self.ensure_actor(actor_id);
        let entry = actor.ammo_reserves.entry(ammo_item_id).or_insert(0);
        *entry += count;
        Ok(*entry)
    }

    pub fn ammo_count(&self, actor_id: ActorId, ammo_item_id: u32) -> Option<i32> {
        self.actor(actor_id)
            .map(|actor| actor.ammo_reserves.get(&ammo_item_id).copied().unwrap_or(0))
    }

    pub fn add_item(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<i32, EconomyRuntimeError> {
        if count <= 0 {
            return Err(EconomyRuntimeError::InvalidCount { count });
        }
        ensure_item_exists(items, item_id)?;
        let actor = self.ensure_actor(actor_id);
        let next = {
            let entry = actor.inventory.entry(item_id).or_insert(0);
            *entry += count;
            *entry
        };
        Self::append_inventory_order(actor, item_id);
        Ok(next)
    }

    pub fn add_item_unchecked(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        count: i32,
    ) -> Result<i32, EconomyRuntimeError> {
        if count <= 0 {
            return Err(EconomyRuntimeError::InvalidCount { count });
        }
        let actor = self.ensure_actor(actor_id);
        let next = {
            let entry = actor.inventory.entry(item_id).or_insert(0);
            *entry += count;
            *entry
        };
        Self::append_inventory_order(actor, item_id);
        Ok(next)
    }

    pub fn remove_item(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        count: i32,
    ) -> Result<i32, EconomyRuntimeError> {
        if count <= 0 {
            return Err(EconomyRuntimeError::InvalidCount { count });
        }
        let actor = self
            .actors
            .get_mut(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let current = actor.inventory.get(&item_id).copied().unwrap_or(0);
        if current < count {
            return Err(EconomyRuntimeError::NotEnoughItems {
                item_id,
                required: count,
                current,
            });
        }

        let next = current - count;
        if next == 0 {
            actor.inventory.remove(&item_id);
            Self::remove_inventory_order(actor, item_id);
        } else {
            actor.inventory.insert(item_id, next);
        }
        Ok(next)
    }

    pub fn equip_item(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        target_slot: Option<&str>,
        items: &ItemLibrary,
    ) -> Result<Option<u32>, EconomyRuntimeError> {
        let definition = ensure_item_exists(items, item_id)?;
        let Some(ItemFragment::Equip {
            slots,
            level_requirement,
            ..
        }) = item_equip_fragment(definition)
        else {
            return Err(EconomyRuntimeError::ItemNotEquippable { item_id });
        };
        let slot = resolve_equipment_slot(item_id, slots.as_slice(), target_slot)?;

        let actor = self
            .actors
            .get(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        if actor.inventory.get(&item_id).copied().unwrap_or(0) <= 0 {
            return Err(EconomyRuntimeError::NotEnoughItems {
                item_id,
                required: 1,
                current: actor.inventory.get(&item_id).copied().unwrap_or(0),
            });
        }
        if actor.level < *level_requirement {
            return Err(EconomyRuntimeError::ItemLevelRequirementMissing {
                item_id,
                required: *level_requirement,
                current: actor.level,
            });
        }

        let previous_item = actor.equipped_slots.get(&slot).map(|state| state.item_id);
        let durability = match item_durability_fragment(definition) {
            Some(ItemFragment::Durability {
                durability,
                max_durability,
                ..
            }) => resolve_initial_durability(*durability, *max_durability),
            _ => None,
        };
        let ammo_loaded = 0;

        self.remove_item(actor_id, item_id, 1)?;
        if let Some(previous_item_id) = previous_item {
            self.add_item_unchecked(actor_id, previous_item_id, 1)?;
        }

        let actor = self.ensure_actor(actor_id);
        actor.equipped_slots.insert(
            slot,
            EquippedItemState {
                item_id,
                current_durability: durability,
                ammo_loaded,
            },
        );
        Ok(previous_item)
    }

    pub fn unequip_item(
        &mut self,
        actor_id: ActorId,
        slot: &str,
    ) -> Result<u32, EconomyRuntimeError> {
        let normalized = slot.trim().to_string();
        let actor = self
            .actors
            .get_mut(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let equipped = actor.equipped_slots.remove(&normalized).ok_or_else(|| {
            EconomyRuntimeError::EmptyEquipmentSlot {
                actor_id,
                slot: normalized.clone(),
            }
        })?;
        *actor.inventory.entry(equipped.item_id).or_insert(0) += 1;
        Self::append_inventory_order(actor, equipped.item_id);
        Ok(equipped.item_id)
    }

    pub fn move_equipped_item(
        &mut self,
        actor_id: ActorId,
        from_slot: &str,
        to_slot: &str,
        items: &ItemLibrary,
    ) -> Result<(), EconomyRuntimeError> {
        let from_slot = from_slot.trim().to_string();
        let to_slot = to_slot.trim().to_string();
        if from_slot == to_slot {
            return Ok(());
        }

        let actor = self
            .actors
            .get(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let moving = actor
            .equipped_slots
            .get(&from_slot)
            .cloned()
            .ok_or_else(|| EconomyRuntimeError::EmptyEquipmentSlot {
                actor_id,
                slot: from_slot.clone(),
            })?;
        let target = actor.equipped_slots.get(&to_slot).cloned();

        let moving_definition = ensure_item_exists(items, moving.item_id)?;
        let Some(ItemFragment::Equip {
            slots: moving_slots,
            ..
        }) = item_equip_fragment(moving_definition)
        else {
            return Err(EconomyRuntimeError::ItemNotEquippable {
                item_id: moving.item_id,
            });
        };
        if !slot_supported(moving_slots.as_slice(), &to_slot) {
            return Err(EconomyRuntimeError::InvalidEquipmentSlot {
                item_id: moving.item_id,
                slot: to_slot,
            });
        }

        if let Some(target) = target.as_ref() {
            let target_definition = ensure_item_exists(items, target.item_id)?;
            let Some(ItemFragment::Equip {
                slots: target_slots,
                ..
            }) = item_equip_fragment(target_definition)
            else {
                return Err(EconomyRuntimeError::ItemNotEquippable {
                    item_id: target.item_id,
                });
            };
            if !slot_supported(target_slots.as_slice(), &from_slot) {
                return Err(EconomyRuntimeError::InvalidEquipmentSlot {
                    item_id: target.item_id,
                    slot: from_slot,
                });
            }
        }

        let actor = self
            .actors
            .get_mut(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        actor.equipped_slots.remove(&from_slot);
        if let Some(target) = target {
            actor.equipped_slots.insert(from_slot, target);
        }
        actor.equipped_slots.insert(to_slot, moving);
        Ok(())
    }

    pub fn move_inventory_item_before(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        before_item_id: Option<u32>,
    ) -> Result<(), EconomyRuntimeError> {
        let actor = self
            .actors
            .get_mut(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        Self::normalize_actor_inventory_order(actor);

        if actor.inventory.get(&item_id).copied().unwrap_or(0) <= 0 {
            return Err(EconomyRuntimeError::NotEnoughItems {
                item_id,
                required: 1,
                current: 0,
            });
        }

        if before_item_id == Some(item_id) {
            return Ok(());
        }

        if let Some(before_item_id) = before_item_id {
            let current = actor.inventory.get(&before_item_id).copied().unwrap_or(0);
            if current <= 0 {
                return Err(EconomyRuntimeError::NotEnoughItems {
                    item_id: before_item_id,
                    required: 1,
                    current,
                });
            }
        }

        actor
            .inventory_order
            .retain(|existing| *existing != item_id);
        match before_item_id {
            Some(before_item_id) => {
                if let Some(index) = actor
                    .inventory_order
                    .iter()
                    .position(|existing| *existing == before_item_id)
                {
                    actor.inventory_order.insert(index, item_id);
                } else {
                    actor.inventory_order.push(item_id);
                }
            }
            None => actor.inventory_order.push(item_id),
        }

        Ok(())
    }

    pub fn clear_actor_loadout(&mut self, actor_id: ActorId) -> Result<(), EconomyRuntimeError> {
        let actor = self
            .actors
            .get_mut(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        actor.inventory.clear();
        actor.inventory_order.clear();
        actor.equipped_slots.clear();
        actor.ammo_reserves.clear();
        Ok(())
    }

    pub fn equipped_item(&self, actor_id: ActorId, slot: &str) -> Option<&EquippedItemState> {
        self.actor(actor_id)
            .and_then(|actor| actor.equipped_slots.get(slot.trim()))
    }

    pub fn equipment_attribute_totals(
        &self,
        actor_id: ActorId,
        items: &ItemLibrary,
    ) -> Result<BTreeMap<String, f32>, EconomyRuntimeError> {
        let actor = self
            .actor(actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let mut totals = BTreeMap::new();
        for equipped in actor.equipped_slots.values() {
            let definition = ensure_item_exists(items, equipped.item_id)?;
            if let Some(ItemFragment::AttributeModifiers { attributes }) =
                item_attribute_fragment(definition)
            {
                for (attribute, value) in attributes {
                    *totals.entry(attribute.clone()).or_insert(0.0) += *value;
                }
            }
        }
        Ok(totals)
    }

    pub fn equipment_carry_bonus(
        &self,
        actor_id: ActorId,
        items: &ItemLibrary,
    ) -> Result<f32, EconomyRuntimeError> {
        Ok(self
            .equipment_attribute_totals(actor_id, items)?
            .get("carry_bonus")
            .copied()
            .unwrap_or(0.0))
    }

    pub fn equipped_weapon(
        &self,
        actor_id: ActorId,
        slot: &str,
        items: &ItemLibrary,
    ) -> Result<Option<EquippedWeaponProfile>, EconomyRuntimeError> {
        let Some(equipped) = self.equipped_item(actor_id, slot) else {
            return Ok(None);
        };
        let definition = ensure_item_exists(items, equipped.item_id)?;
        let Some(ItemFragment::Weapon {
            subtype,
            damage,
            attack_speed,
            range,
            stamina_cost,
            crit_chance,
            crit_multiplier,
            accuracy,
            ammo_type,
            max_ammo,
            reload_time,
            ..
        }) = item_weapon_fragment(definition)
        else {
            return Err(EconomyRuntimeError::ItemNotWeapon {
                item_id: equipped.item_id,
            });
        };

        Ok(Some(EquippedWeaponProfile {
            item_id: equipped.item_id,
            slot: slot.trim().to_string(),
            subtype: subtype.clone(),
            damage: *damage,
            attack_speed: *attack_speed,
            range: *range,
            stamina_cost: *stamina_cost,
            crit_chance: *crit_chance,
            crit_multiplier: *crit_multiplier,
            accuracy: *accuracy,
            ammo_type: *ammo_type,
            max_ammo: *max_ammo,
            ammo_loaded: equipped.ammo_loaded,
            reload_time: *reload_time,
            current_durability: equipped.current_durability,
        }))
    }

    pub fn reload_equipped_weapon(
        &mut self,
        actor_id: ActorId,
        slot: &str,
        items: &ItemLibrary,
    ) -> Result<i32, EconomyRuntimeError> {
        let normalized_slot = slot.trim().to_string();
        let (weapon_item_id, ammo_type, max_ammo, current_loaded) = {
            let equipped = self
                .equipped_item(actor_id, &normalized_slot)
                .ok_or_else(|| EconomyRuntimeError::EmptyEquipmentSlot {
                    actor_id,
                    slot: normalized_slot.clone(),
                })?;
            let definition = ensure_item_exists(items, equipped.item_id)?;
            match item_weapon_fragment(definition) {
                Some(ItemFragment::Weapon {
                    ammo_type,
                    max_ammo,
                    ..
                }) => (
                    equipped.item_id,
                    *ammo_type,
                    *max_ammo,
                    equipped.ammo_loaded,
                ),
                _ => {
                    return Err(EconomyRuntimeError::ItemNotWeapon {
                        item_id: equipped.item_id,
                    });
                }
            }
        };

        let ammo_type = ammo_type.ok_or(EconomyRuntimeError::WeaponDoesNotUseAmmo {
            item_id: weapon_item_id,
        })?;
        let max_ammo = max_ammo.unwrap_or(0).max(0);
        if max_ammo == 0 {
            return Err(EconomyRuntimeError::WeaponDoesNotUseAmmo {
                item_id: weapon_item_id,
            });
        }
        let ammo_needed = max_ammo.saturating_sub(current_loaded);
        if ammo_needed <= 0 {
            return Ok(0);
        }

        let reserve = self.ammo_count(actor_id, ammo_type).unwrap_or(0);
        if reserve <= 0 {
            return Err(EconomyRuntimeError::NotEnoughAmmo {
                item_id: ammo_type,
                required: ammo_needed,
                current: reserve,
            });
        }

        let to_load = ammo_needed.min(reserve);
        let actor = self
            .actors
            .get_mut(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let reserve_after = actor.ammo_reserves.get(&ammo_type).copied().unwrap_or(0) - to_load;
        if reserve_after <= 0 {
            actor.ammo_reserves.remove(&ammo_type);
        } else {
            actor.ammo_reserves.insert(ammo_type, reserve_after);
        }
        let equipped = actor
            .equipped_slots
            .get_mut(&normalized_slot)
            .ok_or_else(|| EconomyRuntimeError::EmptyEquipmentSlot {
                actor_id,
                slot: normalized_slot.clone(),
            })?;
        equipped.ammo_loaded += to_load;
        Ok(to_load)
    }

    pub fn consume_equipped_ammo(
        &mut self,
        actor_id: ActorId,
        slot: &str,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<i32, EconomyRuntimeError> {
        if count <= 0 {
            return Err(EconomyRuntimeError::InvalidCount { count });
        }

        let normalized_slot = slot.trim().to_string();
        let (weapon_item_id, ammo_type, current_loaded) = {
            let equipped = self
                .equipped_item(actor_id, &normalized_slot)
                .ok_or_else(|| EconomyRuntimeError::EmptyEquipmentSlot {
                    actor_id,
                    slot: normalized_slot.clone(),
                })?;
            let definition = ensure_item_exists(items, equipped.item_id)?;
            match item_weapon_fragment(definition) {
                Some(ItemFragment::Weapon { ammo_type, .. }) => {
                    (equipped.item_id, *ammo_type, equipped.ammo_loaded)
                }
                _ => {
                    return Err(EconomyRuntimeError::ItemNotWeapon {
                        item_id: equipped.item_id,
                    });
                }
            }
        };

        let ammo_type = ammo_type.ok_or(EconomyRuntimeError::WeaponDoesNotUseAmmo {
            item_id: weapon_item_id,
        })?;
        if current_loaded < count {
            return Err(EconomyRuntimeError::NotEnoughAmmo {
                item_id: ammo_type,
                required: count,
                current: current_loaded,
            });
        }

        let actor = self
            .actors
            .get_mut(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let equipped = actor
            .equipped_slots
            .get_mut(&normalized_slot)
            .ok_or_else(|| EconomyRuntimeError::EmptyEquipmentSlot {
                actor_id,
                slot: normalized_slot.clone(),
            })?;
        equipped.ammo_loaded -= count;
        Ok(equipped.ammo_loaded)
    }

    pub fn consume_equipped_durability(
        &mut self,
        actor_id: ActorId,
        slot: &str,
        amount: i32,
    ) -> Result<bool, EconomyRuntimeError> {
        if amount <= 0 {
            return Err(EconomyRuntimeError::InvalidCount { count: amount });
        }
        let normalized = slot.trim().to_string();
        let actor = self
            .actors
            .get_mut(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let Some(equipped) = actor.equipped_slots.get_mut(&normalized) else {
            return Err(EconomyRuntimeError::EmptyEquipmentSlot {
                actor_id,
                slot: normalized,
            });
        };
        let Some(current) = equipped.current_durability.as_mut() else {
            return Ok(false);
        };
        *current = (*current - amount).max(0);
        let broken = *current == 0;
        let broken_item_id = equipped.item_id;
        let slot_name = slot.trim().to_string();
        let _ = equipped;
        if broken {
            actor.equipped_slots.remove(&slot_name);
            *actor.inventory.entry(broken_item_id).or_insert(0) += 1;
            Self::append_inventory_order(actor, broken_item_id);
        }
        Ok(broken)
    }

    pub fn unlock_recipe(
        &mut self,
        actor_id: ActorId,
        recipe_id: impl Into<String>,
        recipes: &RecipeLibrary,
    ) -> Result<bool, EconomyRuntimeError> {
        let recipe_id = recipe_id.into();
        if recipes.get(&recipe_id).is_none() {
            return Err(EconomyRuntimeError::UnknownRecipe { recipe_id });
        }
        let actor = self.ensure_actor(actor_id);
        Ok(actor.unlocked_recipes.insert(recipe_id))
    }

    pub fn actor_knows_recipe(
        &self,
        actor_id: ActorId,
        recipe_id: &str,
        recipes: &RecipeLibrary,
    ) -> Result<bool, EconomyRuntimeError> {
        let actor = self
            .actor(actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let recipe = recipes
            .get(recipe_id)
            .ok_or_else(|| EconomyRuntimeError::UnknownRecipe {
                recipe_id: recipe_id.to_string(),
            })?;
        Ok(recipe.is_default_unlocked || actor.unlocked_recipes.contains(recipe_id))
    }

    pub fn learn_skill(
        &mut self,
        actor_id: ActorId,
        skill_id: &str,
        skills: &SkillLibrary,
    ) -> Result<i32, EconomyRuntimeError> {
        let definition = skills
            .get(skill_id)
            .ok_or_else(|| EconomyRuntimeError::UnknownSkill {
                skill_id: skill_id.to_string(),
            })?;
        let actor = self.ensure_actor(actor_id);
        if actor.skill_points <= 0 {
            return Err(EconomyRuntimeError::MissingSkillPoints {
                skill_id: skill_id.to_string(),
            });
        }

        let current_level = actor.learned_skills.get(skill_id).copied().unwrap_or(0);
        if current_level >= definition.max_level {
            return Err(EconomyRuntimeError::SkillAlreadyMaxed {
                skill_id: skill_id.to_string(),
            });
        }

        for prerequisite_id in &definition.prerequisites {
            if actor
                .learned_skills
                .get(prerequisite_id)
                .copied()
                .unwrap_or(0)
                <= 0
            {
                return Err(EconomyRuntimeError::SkillPrerequisiteMissing {
                    skill_id: skill_id.to_string(),
                    prerequisite_id: prerequisite_id.clone(),
                });
            }
        }

        for (attribute, required) in &definition.attribute_requirements {
            let current = actor.attributes.get(attribute).copied().unwrap_or(0);
            if current < *required {
                return Err(EconomyRuntimeError::SkillAttributeRequirementMissing {
                    skill_id: skill_id.to_string(),
                    attribute: attribute.clone(),
                    required: *required,
                    current,
                });
            }
        }

        actor.skill_points -= 1;
        let new_level = current_level + 1;
        actor.learned_skills.insert(skill_id.to_string(), new_level);
        Ok(new_level)
    }

    pub fn check_recipe(
        &self,
        actor_id: ActorId,
        recipe_id: &str,
        recipes: &RecipeLibrary,
    ) -> Result<RecipeCraftCheck, EconomyRuntimeError> {
        let actor = self
            .actor(actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        let recipe = recipes
            .get(recipe_id)
            .ok_or_else(|| EconomyRuntimeError::UnknownRecipe {
                recipe_id: recipe_id.to_string(),
            })?;
        if !recipe.is_default_unlocked && !actor.unlocked_recipes.contains(recipe_id) {
            return Err(EconomyRuntimeError::RecipeLocked {
                recipe_id: recipe_id.to_string(),
            });
        }

        let mut check = RecipeCraftCheck::default();
        for material in &recipe.materials {
            let current = actor.inventory.get(&material.item_id).copied().unwrap_or(0);
            if current < material.count {
                check.missing_materials.push(MissingMaterial {
                    item_id: material.item_id,
                    required: material.count,
                    current,
                });
            }
        }

        for tool in &recipe.required_tools {
            let normalized = tool.trim();
            if normalized.is_empty() {
                continue;
            }
            if let Ok(tool_item_id) = normalized.parse::<u32>() {
                if actor.inventory.get(&tool_item_id).copied().unwrap_or(0) <= 0 {
                    check.missing_tools.push(normalized.to_string());
                }
            } else if !actor.tool_tags.contains(normalized) {
                check.missing_tools.push(normalized.to_string());
            }
        }

        for (skill_id, required_level) in &recipe.skill_requirements {
            let current_level = actor.learned_skills.get(skill_id).copied().unwrap_or(0);
            if current_level < *required_level {
                check.missing_skills.push(MissingSkill {
                    skill_id: skill_id.clone(),
                    required_level: *required_level,
                    current_level,
                });
            }
        }

        if recipe.required_station.trim() != "none"
            && !recipe.required_station.trim().is_empty()
            && !actor.station_tags.contains(recipe.required_station.trim())
        {
            check.missing_station = Some(recipe.required_station.clone());
        }

        for condition in &recipe.unlock_conditions {
            if condition.condition_type == "recipe"
                && !condition.id.trim().is_empty()
                && !actor.unlocked_recipes.contains(condition.id.trim())
            {
                check.missing_unlock_recipes.push(condition.id.clone());
            }
        }

        Ok(check)
    }

    pub fn craft_recipe(
        &mut self,
        actor_id: ActorId,
        recipe_id: &str,
        recipes: &RecipeLibrary,
        items: &ItemLibrary,
    ) -> Result<CraftOutcome, EconomyRuntimeError> {
        let recipe = recipes
            .get(recipe_id)
            .ok_or_else(|| EconomyRuntimeError::UnknownRecipe {
                recipe_id: recipe_id.to_string(),
            })?;
        ensure_item_exists(items, recipe.output.item_id)?;

        if recipe.is_repair {
            return Err(EconomyRuntimeError::UnsupportedRepairRecipe {
                recipe_id: recipe_id.to_string(),
            });
        }

        let check = self.check_recipe(actor_id, recipe_id, recipes)?;
        if !check.missing_materials.is_empty() {
            return Err(EconomyRuntimeError::MissingRecipeMaterials {
                recipe_id: recipe_id.to_string(),
            });
        }
        if !check.missing_tools.is_empty() {
            return Err(EconomyRuntimeError::MissingRecipeTools {
                recipe_id: recipe_id.to_string(),
            });
        }
        if !check.missing_skills.is_empty() {
            return Err(EconomyRuntimeError::MissingRecipeSkills {
                recipe_id: recipe_id.to_string(),
            });
        }
        if let Some(station_id) = check.missing_station.as_ref() {
            return Err(EconomyRuntimeError::MissingRecipeStation {
                recipe_id: recipe_id.to_string(),
                station_id: station_id.clone(),
            });
        }
        if let Some(unlock_recipe_id) = check.missing_unlock_recipes.first() {
            return Err(EconomyRuntimeError::MissingRecipeUnlock {
                recipe_id: recipe_id.to_string(),
                unlock_recipe_id: unlock_recipe_id.clone(),
            });
        }

        for material in &recipe.materials {
            self.remove_item(actor_id, material.item_id, material.count)?;
        }
        self.add_item(actor_id, recipe.output.item_id, recipe.output.count, items)?;

        Ok(CraftOutcome {
            recipe_id: recipe_id.to_string(),
            output_item_id: recipe.output.item_id,
            output_count: recipe.output.count,
        })
    }

    pub fn buy_item_from_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        item_id: u32,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<TradeOutcome, EconomyRuntimeError> {
        if count <= 0 {
            return Err(EconomyRuntimeError::InvalidCount { count });
        }
        let base_price = item_base_value(items, item_id)?;
        let (shop_buy_modifier, shop_entry_count) = {
            let shop = self
                .shops
                .get(shop_id)
                .ok_or_else(|| EconomyRuntimeError::UnknownShop {
                    shop_id: shop_id.to_string(),
                })?;
            let count_in_shop = shop
                .inventory
                .get(&item_id)
                .map(|entry| entry.count)
                .unwrap_or(0);
            (shop.buy_price_modifier, count_in_shop)
        };
        if shop_entry_count < count {
            return Err(EconomyRuntimeError::ShopInventoryInsufficient {
                shop_id: shop_id.to_string(),
                item_id,
                required: count,
                current: shop_entry_count,
            });
        }

        let price_each = adjusted_price(base_price, shop_buy_modifier);
        let total_price = price_each * count;
        let actor_money = self.actor_money(actor_id).unwrap_or(0);
        if actor_money < total_price {
            return Err(EconomyRuntimeError::NotEnoughMoney {
                required: total_price,
                current: actor_money,
            });
        }

        {
            let actor = self.ensure_actor(actor_id);
            actor.money -= total_price;
        }
        self.add_item_unchecked(actor_id, item_id, count)?;

        let shop = self
            .shops
            .get_mut(shop_id)
            .ok_or_else(|| EconomyRuntimeError::UnknownShop {
                shop_id: shop_id.to_string(),
            })?;
        shop.money += total_price;
        if let Some(entry) = shop.inventory.get_mut(&item_id) {
            entry.count -= count;
            if entry.count <= 0 {
                shop.inventory.remove(&item_id);
            }
        }

        Ok(TradeOutcome {
            shop_id: shop_id.to_string(),
            item_id,
            count,
            total_price,
        })
    }

    pub fn sell_item_to_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        item_id: u32,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<TradeOutcome, EconomyRuntimeError> {
        if count <= 0 {
            return Err(EconomyRuntimeError::InvalidCount { count });
        }
        let base_price = item_base_value(items, item_id)?;
        let sell_price_modifier = self
            .shops
            .get(shop_id)
            .ok_or_else(|| EconomyRuntimeError::UnknownShop {
                shop_id: shop_id.to_string(),
            })?
            .sell_price_modifier;
        let price_each = adjusted_price(base_price, sell_price_modifier);
        let total_price = price_each * count;

        let shop_money = self.shops.get(shop_id).map(|shop| shop.money).unwrap_or(0);
        if shop_money < total_price {
            return Err(EconomyRuntimeError::ShopOutOfMoney {
                shop_id: shop_id.to_string(),
                required: total_price,
                current: shop_money,
            });
        }

        self.remove_item(actor_id, item_id, count)?;
        let actor = self.ensure_actor(actor_id);
        actor.money += total_price;

        let shop = self
            .shops
            .get_mut(shop_id)
            .ok_or_else(|| EconomyRuntimeError::UnknownShop {
                shop_id: shop_id.to_string(),
            })?;
        shop.money -= total_price;
        let entry = shop.inventory.entry(item_id).or_insert(ShopRuntimeEntry {
            item_id,
            count: 0,
            price: price_each,
        });
        entry.count += count;
        entry.price = price_each;

        Ok(TradeOutcome {
            shop_id: shop_id.to_string(),
            item_id,
            count,
            total_price,
        })
    }

    pub fn sell_equipped_item_to_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        slot_id: &str,
        items: &ItemLibrary,
    ) -> Result<TradeOutcome, EconomyRuntimeError> {
        let slot_id = slot_id.trim().to_string();
        let item_id = self
            .actor(actor_id)
            .and_then(|actor| actor.equipped_slots.get(&slot_id))
            .map(|equipped| equipped.item_id)
            .ok_or_else(|| EconomyRuntimeError::EmptyEquipmentSlot {
                actor_id,
                slot: slot_id.clone(),
            })?;
        let base_price = item_base_value(items, item_id)?;
        let sell_price_modifier = self
            .shops
            .get(shop_id)
            .ok_or_else(|| EconomyRuntimeError::UnknownShop {
                shop_id: shop_id.to_string(),
            })?
            .sell_price_modifier;
        let total_price = adjusted_price(base_price, sell_price_modifier);
        let shop_money = self.shops.get(shop_id).map(|shop| shop.money).unwrap_or(0);
        if shop_money < total_price {
            return Err(EconomyRuntimeError::ShopOutOfMoney {
                shop_id: shop_id.to_string(),
                required: total_price,
                current: shop_money,
            });
        }

        let actor = self
            .actors
            .get_mut(&actor_id)
            .ok_or(EconomyRuntimeError::UnknownActor { actor_id })?;
        actor.equipped_slots.remove(&slot_id).ok_or_else(|| {
            EconomyRuntimeError::EmptyEquipmentSlot {
                actor_id,
                slot: slot_id.clone(),
            }
        })?;
        actor.money += total_price;

        let shop = self
            .shops
            .get_mut(shop_id)
            .ok_or_else(|| EconomyRuntimeError::UnknownShop {
                shop_id: shop_id.to_string(),
            })?;
        shop.money -= total_price;
        let entry = shop.inventory.entry(item_id).or_insert(ShopRuntimeEntry {
            item_id,
            count: 0,
            price: total_price,
        });
        entry.count += 1;
        entry.price = total_price;

        Ok(TradeOutcome {
            shop_id: shop_id.to_string(),
            item_id,
            count: 1,
            total_price,
        })
    }
}

fn ensure_item_exists(
    items: &ItemLibrary,
    item_id: u32,
) -> Result<&ItemDefinition, EconomyRuntimeError> {
    items
        .get(item_id)
        .ok_or(EconomyRuntimeError::UnknownItem { item_id })
}

fn item_base_value(items: &ItemLibrary, item_id: u32) -> Result<i32, EconomyRuntimeError> {
    Ok(ensure_item_exists(items, item_id)?.value.max(0))
}

fn adjusted_price(base_price: i32, modifier: f32) -> i32 {
    ((base_price as f32) * modifier.max(0.0)).round().max(1.0) as i32
}

fn item_equip_fragment(definition: &ItemDefinition) -> Option<&ItemFragment> {
    definition
        .fragments
        .iter()
        .find(|fragment| matches!(fragment, ItemFragment::Equip { .. }))
}

fn item_durability_fragment(definition: &ItemDefinition) -> Option<&ItemFragment> {
    definition
        .fragments
        .iter()
        .find(|fragment| matches!(fragment, ItemFragment::Durability { .. }))
}

fn item_attribute_fragment(definition: &ItemDefinition) -> Option<&ItemFragment> {
    definition
        .fragments
        .iter()
        .find(|fragment| matches!(fragment, ItemFragment::AttributeModifiers { .. }))
}

fn item_weapon_fragment(definition: &ItemDefinition) -> Option<&ItemFragment> {
    definition
        .fragments
        .iter()
        .find(|fragment| matches!(fragment, ItemFragment::Weapon { .. }))
}

fn resolve_initial_durability(durability: i32, max_durability: i32) -> Option<i32> {
    let resolved = max_durability.max(durability);
    (resolved > 0).then_some(resolved)
}

fn resolve_equipment_slot(
    item_id: u32,
    allowed_slots: &[String],
    requested_slot: Option<&str>,
) -> Result<String, EconomyRuntimeError> {
    if let Some(requested_slot) = requested_slot {
        let normalized = requested_slot.trim();
        if slot_supported(allowed_slots, normalized) {
            return Ok(normalized.to_string());
        }
        return Err(EconomyRuntimeError::InvalidEquipmentSlot {
            item_id,
            slot: normalized.to_string(),
        });
    }

    allowed_slots
        .first()
        .cloned()
        .ok_or(EconomyRuntimeError::ItemNotEquippable { item_id })
}

fn slot_supported(allowed_slots: &[String], requested_slot: &str) -> bool {
    allowed_slots.iter().any(|slot| {
        let normalized = slot.trim();
        normalized == requested_slot
            || (normalized == "main_hand" && requested_slot == "off_hand")
            || (normalized == "accessory"
                && matches!(requested_slot, "accessory_1" | "accessory_2"))
    })
}

#[allow(dead_code)]
fn item_has_fragment(definition: &ItemDefinition, kind: &str) -> bool {
    definition
        .fragments
        .iter()
        .any(|fragment| fragment.kind() == kind)
}

#[allow(dead_code)]
fn item_required_tools(definition: &RecipeDefinition) -> Vec<u32> {
    definition
        .required_tools
        .iter()
        .filter_map(|tool| tool.parse::<u32>().ok())
        .collect()
}

#[allow(dead_code)]
fn item_is_equipable(definition: &ItemDefinition) -> bool {
    definition
        .fragments
        .iter()
        .any(|fragment| matches!(fragment, ItemFragment::Equip { .. }))
}

#[allow(dead_code)]
fn skill_max_level(definition: &SkillDefinition) -> i32 {
    definition.max_level
}

#[allow(dead_code)]
fn shop_entry_from_definition(entry: &ShopInventoryEntry) -> ShopRuntimeEntry {
    ShopRuntimeEntry {
        item_id: entry.item_id,
        count: entry.count,
        price: entry.price,
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use game_data::{
        ActorId, ItemDefinition, ItemFragment, ItemLibrary, RecipeDefinition, RecipeLibrary,
        RecipeMaterial, RecipeOutput, ShopDefinition, ShopInventoryEntry, ShopLibrary,
        SkillDefinition, SkillLibrary,
    };

    use super::{
        EconomyRuntimeError, HeadlessEconomyRuntime, MissingMaterial, MissingSkill,
        RecipeCraftCheck,
    };

    #[test]
    fn learning_skill_and_crafting_recipe_updates_actor_state() {
        let items = sample_item_library();
        let skills = sample_skill_library();
        let recipes = sample_recipe_library();
        let mut runtime = HeadlessEconomyRuntime::default();
        let actor_id = ActorId(7);

        runtime.initialize_actor_defaults(actor_id, &recipes);
        runtime
            .grant_station_tag(actor_id, "workbench")
            .expect("station tag should be granted");
        runtime.set_actor_attribute(actor_id, "intelligence", 3);
        runtime
            .add_skill_points(actor_id, 1)
            .expect("skill points should be granted");
        runtime
            .add_item(actor_id, 1001, 2, &items)
            .expect("materials should be added");
        runtime
            .add_item(actor_id, 1002, 1, &items)
            .expect("tool should be added");

        let learned_level = runtime
            .learn_skill(actor_id, "crafting_basics", &skills)
            .expect("crafting skill should be learnable");
        assert_eq!(learned_level, 1);

        let outcome = runtime
            .craft_recipe(actor_id, "bandage_recipe", &recipes, &items)
            .expect("recipe should craft");
        assert_eq!(outcome.output_item_id, 1003);
        assert_eq!(outcome.output_count, 1);
        assert_eq!(runtime.inventory_count(actor_id, 1001), Some(0));
        assert_eq!(runtime.inventory_count(actor_id, 1003), Some(1));
    }

    #[test]
    fn recipe_check_reports_missing_materials_tools_and_skills() {
        let recipes = sample_recipe_library();
        let mut runtime = HeadlessEconomyRuntime::default();
        let actor_id = ActorId(8);
        runtime.initialize_actor_defaults(actor_id, &recipes);

        let check = runtime
            .check_recipe(actor_id, "bandage_recipe", &recipes)
            .expect("recipe should exist");

        assert_eq!(
            check,
            RecipeCraftCheck {
                missing_materials: vec![MissingMaterial {
                    item_id: 1001,
                    required: 2,
                    current: 0,
                }],
                missing_tools: vec!["1002".to_string()],
                missing_skills: vec![MissingSkill {
                    skill_id: "crafting_basics".to_string(),
                    required_level: 1,
                    current_level: 0,
                }],
                missing_station: Some("workbench".to_string()),
                missing_unlock_recipes: Vec::new(),
            }
        );
        assert!(!check.can_craft());
    }

    #[test]
    fn buying_and_selling_items_updates_actor_and_shop_balances() {
        let items = sample_item_library();
        let shops = sample_shop_library();
        let mut runtime = HeadlessEconomyRuntime::from_shop_library(&shops);
        let actor_id = ActorId(9);
        runtime
            .grant_money(actor_id, 100)
            .expect("money should be granted");

        let buy = runtime
            .buy_item_from_shop(actor_id, "survivor_outpost_01_shop", 1031, 2, &items)
            .expect("buy should succeed");
        assert_eq!(buy.total_price, 30);
        assert_eq!(runtime.actor_money(actor_id), Some(70));
        assert_eq!(runtime.inventory_count(actor_id, 1031), Some(2));
        assert_eq!(
            runtime
                .shop("survivor_outpost_01_shop")
                .map(|shop| shop.money),
            Some(130)
        );
        assert_eq!(
            runtime
                .shop("survivor_outpost_01_shop")
                .and_then(|shop| shop.inventory.get(&1031))
                .map(|entry| entry.count),
            Some(1)
        );

        let sell = runtime
            .sell_item_to_shop(actor_id, "survivor_outpost_01_shop", 1031, 1, &items)
            .expect("sell should succeed");
        assert_eq!(sell.total_price, 5);
        assert_eq!(runtime.actor_money(actor_id), Some(75));
        assert_eq!(runtime.inventory_count(actor_id, 1031), Some(1));
        assert_eq!(
            runtime
                .shop("survivor_outpost_01_shop")
                .map(|shop| shop.money),
            Some(125)
        );
        assert_eq!(
            runtime
                .shop("survivor_outpost_01_shop")
                .and_then(|shop| shop.inventory.get(&1031))
                .map(|entry| entry.count),
            Some(2)
        );
    }

    #[test]
    fn learning_skill_enforces_attribute_requirement() {
        let skills = sample_skill_library();
        let mut runtime = HeadlessEconomyRuntime::default();
        let actor_id = ActorId(10);
        runtime
            .add_skill_points(actor_id, 1)
            .expect("skill points should be granted");

        let error = runtime
            .learn_skill(actor_id, "crafting_basics", &skills)
            .expect_err("attribute gate should fail");

        assert_eq!(
            error,
            EconomyRuntimeError::SkillAttributeRequirementMissing {
                skill_id: "crafting_basics".to_string(),
                attribute: "intelligence".to_string(),
                required: 3,
                current: 0,
            }
        );
    }

    #[test]
    fn equip_and_unequip_item_moves_state_between_inventory_and_slots() {
        let items = sample_item_library();
        let mut runtime = HeadlessEconomyRuntime::default();
        let actor_id = ActorId(11);
        runtime.set_actor_level(actor_id, 2);
        runtime
            .add_item(actor_id, 1002, 1, &items)
            .expect("knife should be added");

        let previous = runtime
            .equip_item(actor_id, 1002, Some("main_hand"), &items)
            .expect("knife should equip");

        assert_eq!(previous, None);
        assert_eq!(runtime.inventory_count(actor_id, 1002), Some(0));
        assert_eq!(
            runtime
                .equipped_item(actor_id, "main_hand")
                .map(|entry| entry.item_id),
            Some(1002)
        );

        let unequipped = runtime
            .unequip_item(actor_id, "main_hand")
            .expect("knife should unequip");

        assert_eq!(unequipped, 1002);
        assert_eq!(runtime.inventory_count(actor_id, 1002), Some(1));
        assert!(runtime.equipped_item(actor_id, "main_hand").is_none());
    }

    #[test]
    fn equipped_attributes_and_reload_follow_headless_equipment_state() {
        let items = sample_item_library();
        let mut runtime = HeadlessEconomyRuntime::default();
        let actor_id = ActorId(12);
        runtime.set_actor_level(actor_id, 8);
        runtime
            .add_item(actor_id, 2018, 1, &items)
            .expect("backpack should be added");
        runtime
            .add_item(actor_id, 1004, 1, &items)
            .expect("pistol should be added");
        runtime
            .add_ammo(actor_id, 1009, 12, &items)
            .expect("ammo should be added");

        runtime
            .equip_item(actor_id, 2018, Some("back"), &items)
            .expect("backpack should equip");
        runtime
            .equip_item(actor_id, 1004, Some("main_hand"), &items)
            .expect("pistol should equip");

        assert_eq!(
            runtime
                .equipment_carry_bonus(actor_id, &items)
                .expect("carry bonus should resolve"),
            5.0
        );

        let loaded = runtime
            .reload_equipped_weapon(actor_id, "main_hand", &items)
            .expect("reload should succeed");
        assert_eq!(loaded, 6);
        assert_eq!(runtime.ammo_count(actor_id, 1009), Some(6));

        let weapon = runtime
            .equipped_weapon(actor_id, "main_hand", &items)
            .expect("weapon should resolve")
            .expect("weapon should exist");
        assert_eq!(weapon.ammo_type, Some(1009));
        assert_eq!(weapon.ammo_loaded, 6);
    }

    #[test]
    fn consuming_durability_to_zero_breaks_and_unequips_item() {
        let items = sample_item_library();
        let mut runtime = HeadlessEconomyRuntime::default();
        let actor_id = ActorId(13);
        runtime.set_actor_level(actor_id, 2);
        runtime
            .add_item(actor_id, 1002, 1, &items)
            .expect("knife should be added");
        runtime
            .equip_item(actor_id, 1002, Some("main_hand"), &items)
            .expect("knife should equip");

        let broken = runtime
            .consume_equipped_durability(actor_id, "main_hand", 50)
            .expect("durability should consume");

        assert!(broken);
        assert!(runtime.equipped_item(actor_id, "main_hand").is_none());
        assert_eq!(runtime.inventory_count(actor_id, 1002), Some(1));
    }

    #[test]
    fn consuming_equipped_ammo_updates_loaded_rounds() {
        let items = sample_item_library();
        let mut runtime = HeadlessEconomyRuntime::default();
        let actor_id = ActorId(14);
        runtime.set_actor_level(actor_id, 8);
        runtime
            .add_item(actor_id, 1004, 1, &items)
            .expect("pistol should be added");
        runtime
            .add_ammo(actor_id, 1009, 6, &items)
            .expect("ammo should be added");
        runtime
            .equip_item(actor_id, 1004, Some("main_hand"), &items)
            .expect("pistol should equip");
        runtime
            .reload_equipped_weapon(actor_id, "main_hand", &items)
            .expect("reload should succeed");

        let remaining = runtime
            .consume_equipped_ammo(actor_id, "main_hand", 1, &items)
            .expect("loaded ammo should decrease");

        assert_eq!(remaining, 5);
        assert_eq!(
            runtime
                .equipped_weapon(actor_id, "main_hand", &items)
                .expect("weapon should resolve")
                .expect("weapon should still exist")
                .ammo_loaded,
            5
        );
    }

    fn sample_item_library() -> ItemLibrary {
        ItemLibrary::from(BTreeMap::from([
            (
                1001,
                ItemDefinition {
                    id: 1001,
                    name: "布料碎片".to_string(),
                    value: 2,
                    weight: 0.1,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 99,
                    }],
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
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 50,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1031,
                ItemDefinition {
                    id: 1031,
                    name: "抗生素".to_string(),
                    value: 10,
                    weight: 0.2,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 10,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1002,
                ItemDefinition {
                    id: 1002,
                    name: "小刀".to_string(),
                    value: 8,
                    weight: 0.5,
                    fragments: vec![
                        ItemFragment::Stacking {
                            stackable: false,
                            max_stack: 1,
                        },
                        ItemFragment::Equip {
                            slots: vec!["main_hand".to_string()],
                            level_requirement: 1,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                        ItemFragment::Durability {
                            durability: 50,
                            max_durability: 50,
                            repairable: true,
                            repair_materials: Vec::new(),
                        },
                        ItemFragment::Weapon {
                            subtype: "dagger".to_string(),
                            damage: 12,
                            attack_speed: 1.2,
                            range: 1,
                            stamina_cost: 3,
                            crit_chance: 0.15,
                            crit_multiplier: 2.0,
                            accuracy: None,
                            ammo_type: None,
                            max_ammo: None,
                            reload_time: None,
                            on_hit_effect_ids: Vec::new(),
                        },
                    ],
                    ..ItemDefinition::default()
                },
            ),
            (
                1003,
                ItemDefinition {
                    id: 1003,
                    name: "绷带".to_string(),
                    value: 12,
                    weight: 0.2,
                    fragments: vec![ItemFragment::Stacking {
                        stackable: true,
                        max_stack: 20,
                    }],
                    ..ItemDefinition::default()
                },
            ),
            (
                1004,
                ItemDefinition {
                    id: 1004,
                    name: "手枪".to_string(),
                    value: 120,
                    weight: 1.2,
                    fragments: vec![
                        ItemFragment::Equip {
                            slots: vec!["main_hand".to_string()],
                            level_requirement: 2,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                        ItemFragment::Durability {
                            durability: 80,
                            max_durability: 80,
                            repairable: true,
                            repair_materials: Vec::new(),
                        },
                        ItemFragment::Weapon {
                            subtype: "pistol".to_string(),
                            damage: 18,
                            attack_speed: 1.0,
                            range: 12,
                            stamina_cost: 2,
                            crit_chance: 0.1,
                            crit_multiplier: 1.8,
                            accuracy: Some(70),
                            ammo_type: Some(1009),
                            max_ammo: Some(6),
                            reload_time: Some(1.5),
                            on_hit_effect_ids: Vec::new(),
                        },
                    ],
                    ..ItemDefinition::default()
                },
            ),
            (
                2018,
                ItemDefinition {
                    id: 2018,
                    name: "小背包".to_string(),
                    value: 60,
                    weight: 0.8,
                    fragments: vec![
                        ItemFragment::Equip {
                            slots: vec!["back".to_string()],
                            level_requirement: 0,
                            equip_effect_ids: Vec::new(),
                            unequip_effect_ids: Vec::new(),
                        },
                        ItemFragment::AttributeModifiers {
                            attributes: BTreeMap::from([
                                ("carry_bonus".to_string(), 5.0),
                                ("inventory_slots".to_string(), 2.0),
                            ]),
                        },
                    ],
                    ..ItemDefinition::default()
                },
            ),
        ]))
    }

    fn sample_skill_library() -> SkillLibrary {
        SkillLibrary::from(BTreeMap::from([(
            "crafting_basics".to_string(),
            SkillDefinition {
                id: "crafting_basics".to_string(),
                name: "制作基础".to_string(),
                tree_id: "survival".to_string(),
                max_level: 3,
                prerequisites: Vec::new(),
                attribute_requirements: BTreeMap::from([("intelligence".to_string(), 3)]),
                ..SkillDefinition::default()
            },
        )]))
    }

    fn sample_recipe_library() -> RecipeLibrary {
        RecipeLibrary::from(BTreeMap::from([(
            "bandage_recipe".to_string(),
            RecipeDefinition {
                id: "bandage_recipe".to_string(),
                name: "制作绷带".to_string(),
                output: RecipeOutput {
                    item_id: 1003,
                    count: 1,
                    quality_bonus: 0,
                    extra: BTreeMap::new(),
                },
                materials: vec![RecipeMaterial {
                    item_id: 1001,
                    count: 2,
                    extra: BTreeMap::new(),
                }],
                required_tools: vec!["1002".to_string()],
                required_station: "workbench".to_string(),
                skill_requirements: BTreeMap::from([("crafting_basics".to_string(), 1)]),
                is_default_unlocked: true,
                ..RecipeDefinition::default()
            },
        )]))
    }

    fn sample_shop_library() -> ShopLibrary {
        ShopLibrary::from(BTreeMap::from([(
            "survivor_outpost_01_shop".to_string(),
            ShopDefinition {
                id: "survivor_outpost_01_shop".to_string(),
                buy_price_modifier: 1.5,
                sell_price_modifier: 0.5,
                money: 100,
                inventory: vec![ShopInventoryEntry {
                    item_id: 1031,
                    count: 3,
                    price: 15,
                }],
            },
        )]))
    }
}
