use std::collections::{BTreeMap, BTreeSet};

use bevy_app::{App, Plugin};
use bevy_ecs::prelude::*;
use game_core::SimulationRuntime;
use game_data::{
    ActorId, ActorSide, InteractionContextSnapshot, InteractionPrompt, ItemDefinition,
    ItemFragment, ItemLibrary, OverworldLibrary, OverworldLocationDefinition,
    OverworldLocationKind, QuestLibrary, RecipeLibrary, ShopLibrary, SkillLibrary,
    SkillTreeLibrary, WorldMode,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum UiMenuPanel {
    #[default]
    Inventory,
    Character,
    Map,
    Journal,
    Skills,
    Crafting,
    Settings,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum UiInventoryFilter {
    #[default]
    All,
    Weapon,
    Armor,
    Accessory,
    Consumable,
    Material,
    Ammo,
    Misc,
}

impl UiInventoryFilter {
    pub fn label(self) -> &'static str {
        match self {
            Self::All => "全部",
            Self::Weapon => "weapon",
            Self::Armor => "armor",
            Self::Accessory => "accessory",
            Self::Consumable => "consumable",
            Self::Material => "material",
            Self::Ammo => "ammo",
            Self::Misc => "misc",
        }
    }

    pub fn matches_type(self, item_type: UiItemType) -> bool {
        matches!(self, Self::All)
            || matches!(
                (self, item_type),
                (Self::Weapon, UiItemType::Weapon)
                    | (Self::Armor, UiItemType::Armor)
                    | (Self::Accessory, UiItemType::Accessory)
                    | (Self::Consumable, UiItemType::Consumable)
                    | (Self::Material, UiItemType::Material)
                    | (Self::Ammo, UiItemType::Ammo)
                    | (Self::Misc, UiItemType::Misc)
            )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum UiItemType {
    Weapon,
    Armor,
    Accessory,
    Consumable,
    Material,
    Ammo,
    #[default]
    Misc,
}

impl UiItemType {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Weapon => "weapon",
            Self::Armor => "armor",
            Self::Accessory => "accessory",
            Self::Consumable => "consumable",
            Self::Material => "material",
            Self::Ammo => "ammo",
            Self::Misc => "misc",
        }
    }
}

#[derive(Resource, Debug, Clone, Default)]
pub struct UiMenuState {
    pub main_menu_open: bool,
    pub active_panel: Option<UiMenuPanel>,
    pub selected_inventory_item: Option<u32>,
    pub selected_equipment_slot: Option<String>,
    pub selected_skill_tree_id: Option<String>,
    pub selected_skill_id: Option<String>,
    pub selected_recipe_id: Option<String>,
    pub selected_map_location_id: Option<String>,
    pub status_text: String,
}

#[derive(Debug, Clone, Default)]
pub struct UiTradeSessionState {
    pub shop_id: String,
    pub target_actor_id: Option<ActorId>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct UiDiscardQuantityModalState {
    pub item_id: u32,
    pub available_count: i32,
    pub selected_count: i32,
}

#[derive(Resource, Debug, Clone, Default)]
pub struct UiModalState {
    pub message: Option<String>,
    pub trade: Option<UiTradeSessionState>,
    pub discard_quantity: Option<UiDiscardQuantityModalState>,
}

#[derive(Resource, Debug, Clone, Default)]
pub struct UiStatusBannerState {
    pub visible: bool,
    pub title: String,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct UiHotbarSlotState {
    pub skill_id: Option<String>,
    pub cooldown_remaining: f32,
    pub toggled: bool,
}

impl Default for UiHotbarSlotState {
    fn default() -> Self {
        Self {
            skill_id: None,
            cooldown_remaining: 0.0,
            toggled: false,
        }
    }
}

#[derive(Resource, Debug, Clone)]
pub struct UiHotbarState {
    pub active_group: usize,
    pub groups: Vec<Vec<UiHotbarSlotState>>,
    pub last_activation_status: Option<String>,
}

impl Default for UiHotbarState {
    fn default() -> Self {
        Self {
            active_group: 0,
            groups: (0..5)
                .map(|_| (0..10).map(|_| UiHotbarSlotState::default()).collect())
                .collect(),
            last_activation_status: None,
        }
    }
}

#[derive(Resource, Debug, Clone, Default)]
pub struct UiInputBlockState {
    pub blocked: bool,
    pub reason: String,
}

#[derive(Resource, Debug, Clone, Default)]
pub struct UiInventoryFilterState {
    pub filter: UiInventoryFilter,
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub enum UiMenuCommand {
    Open(UiMenuPanel),
    CloseAll,
    Toggle(UiMenuPanel),
    SetStatus(String),
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub enum UiInventoryCommand {
    SetFilter(UiInventoryFilter),
    SelectItem(u32),
    UseSelected,
    EquipSelected,
    UnequipSlot(String),
    MoveEquippedItem { from_slot: String, to_slot: String },
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub enum UiCharacterCommand {
    AllocateAttribute(String),
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub enum UiSkillCommand {
    SelectSkill(String),
    AssignToHotbar {
        skill_id: String,
        group: usize,
        slot: usize,
    },
    MoveHotbarSkill {
        from_group: usize,
        from_slot: usize,
        to_group: usize,
        to_slot: usize,
    },
    ClearHotbarSlot {
        group: usize,
        slot: usize,
    },
    SetActiveGroup(usize),
    ActivateSlot(usize),
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub enum UiDialogueCommand {
    Continue,
    SelectChoice(usize),
    Close,
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub enum UiTradeCommand {
    Open {
        shop_id: String,
        target_actor_id: Option<ActorId>,
    },
    Buy {
        shop_id: String,
        item_id: u32,
        count: i32,
    },
    Sell {
        shop_id: String,
        item_id: u32,
        count: i32,
    },
    Close,
}

#[derive(Message, Debug, Clone, PartialEq)]
pub enum UiSettingsCommand {
    SetMasterVolume(f32),
    SetMusicVolume(f32),
    SetSfxVolume(f32),
    SetWindowMode(String),
    SetVsync(bool),
    SetUiScale(f32),
    RebindAction { action: String, key: String },
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub enum UiMainMenuCommand {
    NewGame,
    Continue,
    Exit,
}

pub struct GameUiPlugin;

impl Plugin for GameUiPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<UiMenuState>()
            .init_resource::<UiModalState>()
            .init_resource::<UiStatusBannerState>()
            .init_resource::<UiHotbarState>()
            .init_resource::<UiInputBlockState>()
            .init_resource::<UiInventoryFilterState>()
            .add_message::<UiMenuCommand>()
            .add_message::<UiInventoryCommand>()
            .add_message::<UiCharacterCommand>()
            .add_message::<UiSkillCommand>()
            .add_message::<UiDialogueCommand>()
            .add_message::<UiTradeCommand>()
            .add_message::<UiSettingsCommand>()
            .add_message::<UiMainMenuCommand>();
    }
}

#[derive(Debug, Clone, Default)]
pub struct UiMainMenuSnapshot {
    pub can_continue: bool,
}

#[derive(Debug, Clone, Default)]
pub struct UiWorldStatusSnapshot {
    pub visible: bool,
    pub title: String,
    pub detail: String,
    pub world_mode: WorldMode,
}

#[derive(Debug, Clone, Default)]
pub struct UiInventoryEntryView {
    pub item_id: u32,
    pub name: String,
    pub count: i32,
    pub item_type: UiItemType,
    pub total_weight: f32,
    pub can_use: bool,
    pub can_equip: bool,
}

#[derive(Debug, Clone, Default)]
pub struct UiEquipmentSlotView {
    pub slot_id: String,
    pub slot_label: String,
    pub item_id: Option<u32>,
    pub item_name: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct UiInventoryDetailView {
    pub item_id: u32,
    pub name: String,
    pub description: String,
    pub count: i32,
    pub item_type: UiItemType,
    pub weight: f32,
    pub attribute_bonuses: BTreeMap<String, f32>,
}

#[derive(Debug, Clone, Default)]
pub struct UiInventoryPanelSnapshot {
    pub entries: Vec<UiInventoryEntryView>,
    pub detail: Option<UiInventoryDetailView>,
    pub equipment: Vec<UiEquipmentSlotView>,
    pub total_weight: f32,
    pub max_weight: f32,
    pub filter: UiInventoryFilter,
}

#[derive(Debug, Clone, Default)]
pub struct UiCharacterSnapshot {
    pub available_points: i32,
    pub attributes: BTreeMap<String, i32>,
}

#[derive(Debug, Clone, Default)]
pub struct UiJournalSnapshot {
    pub quest_titles: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct UiSkillEntryView {
    pub skill_id: String,
    pub tree_id: String,
    pub name: String,
    pub description: String,
    pub learned_level: i32,
    pub max_level: i32,
    pub hotbar_eligible: bool,
    pub activation_mode: String,
    pub cooldown_seconds: f32,
    pub prerequisite_names: Vec<String>,
    pub attribute_requirements: BTreeMap<String, i32>,
}

#[derive(Debug, Clone, Default)]
pub struct UiSkillTreeView {
    pub tree_id: String,
    pub tree_name: String,
    pub tree_description: String,
    pub entries: Vec<UiSkillEntryView>,
}

#[derive(Debug, Clone, Default)]
pub struct UiSkillsSnapshot {
    pub trees: Vec<UiSkillTreeView>,
}

#[derive(Debug, Clone, Default)]
pub struct UiCraftingSnapshot {
    pub recipe_names: Vec<(String, String)>,
}

#[derive(Debug, Clone, Default)]
pub struct UiMapLocationView {
    pub location_id: String,
    pub name: String,
    pub kind: String,
    pub unlocked: bool,
    pub current: bool,
    pub travel_minutes: Option<u32>,
    pub food_cost: Option<i32>,
    pub risk_level: Option<f32>,
}

#[derive(Debug, Clone, Default)]
pub struct UiMapSnapshot {
    pub locations: Vec<UiMapLocationView>,
}

#[derive(Debug, Clone, Default)]
pub struct UiTradeEntryView {
    pub item_id: u32,
    pub name: String,
    pub count: i32,
    pub unit_price: i32,
    pub total_weight: f32,
}

#[derive(Debug, Clone, Default)]
pub struct UiTradeSnapshot {
    pub shop_id: String,
    pub relation_score: i32,
    pub player_money: i32,
    pub shop_money: i32,
    pub player_items: Vec<UiTradeEntryView>,
    pub shop_items: Vec<UiTradeEntryView>,
}

pub fn player_actor_id(runtime: &SimulationRuntime) -> Option<ActorId> {
    runtime
        .snapshot()
        .actors
        .iter()
        .find(|actor| actor.side == ActorSide::Player)
        .map(|actor| actor.actor_id)
}

pub fn world_status_snapshot(context: &InteractionContextSnapshot) -> UiWorldStatusSnapshot {
    let (title, detail, visible) = match context.world_mode {
        WorldMode::Overworld => (
            "大地图".to_string(),
            context
                .active_outdoor_location_id
                .clone()
                .unwrap_or_else(|| "当前处于大地图".to_string()),
            true,
        ),
        WorldMode::Traveling => (
            "切换中".to_string(),
            "正在切换到目标世界模式".to_string(),
            true,
        ),
        WorldMode::Outdoor | WorldMode::Interior | WorldMode::Dungeon => (
            "当前位置".to_string(),
            context
                .active_location_id
                .clone()
                .or(context.active_outdoor_location_id.clone())
                .or(context.current_subscene_location_id.clone())
                .unwrap_or_else(|| "未知地点".to_string()),
            true,
        ),
        WorldMode::Unknown => (String::new(), String::new(), false),
    };

    UiWorldStatusSnapshot {
        visible,
        title,
        detail,
        world_mode: context.world_mode,
    }
}

pub fn interaction_prompt_text(prompt: Option<&InteractionPrompt>) -> String {
    prompt
        .map(|prompt| format!("{} · {} 个选项", prompt.target_name, prompt.options.len()))
        .unwrap_or_default()
}

pub fn inventory_snapshot(
    runtime: &SimulationRuntime,
    actor_id: ActorId,
    items: &ItemLibrary,
    filter: UiInventoryFilter,
    selected_item_id: Option<u32>,
) -> UiInventoryPanelSnapshot {
    let actor = match runtime.economy().actor(actor_id) {
        Some(actor) => actor,
        None => {
            return UiInventoryPanelSnapshot {
                filter,
                ..UiInventoryPanelSnapshot::default()
            };
        }
    };

    let ammo_ids = ammo_item_ids(items);
    let entries = actor
        .inventory
        .iter()
        .filter_map(|(item_id, count)| {
            let definition = items.get(*item_id)?;
            let item_type = classify_item(definition, &ammo_ids);
            if !filter.matches_type(item_type) {
                return None;
            }
            Some(UiInventoryEntryView {
                item_id: *item_id,
                name: definition.name.clone(),
                count: *count,
                item_type,
                total_weight: definition.weight * (*count as f32),
                can_use: item_usable(definition),
                can_equip: item_equippable(definition),
            })
        })
        .collect::<Vec<_>>();

    let detail = selected_item_id.and_then(|item_id| {
        let definition = items.get(item_id)?;
        let count = actor.inventory.get(&item_id).copied().unwrap_or(0);
        Some(UiInventoryDetailView {
            item_id,
            name: definition.name.clone(),
            description: definition.description.clone(),
            count,
            item_type: classify_item(definition, &ammo_ids),
            weight: definition.weight,
            attribute_bonuses: item_attribute_bonuses(definition),
        })
    });

    let equipment = actor
        .equipped_slots
        .iter()
        .map(|(slot_id, equipped)| UiEquipmentSlotView {
            slot_id: slot_id.clone(),
            slot_label: slot_id.clone(),
            item_id: Some(equipped.item_id),
            item_name: items.get(equipped.item_id).map(|item| item.name.clone()),
        })
        .collect::<Vec<_>>();

    let total_weight = runtime
        .economy()
        .inventory_weight(actor_id, items)
        .unwrap_or_default();
    let max_weight = 50.0
        + runtime
            .economy()
            .equipment_carry_bonus(actor_id, items)
            .unwrap_or_default();

    UiInventoryPanelSnapshot {
        entries,
        detail,
        equipment,
        total_weight,
        max_weight,
        filter,
    }
}

pub fn character_snapshot(runtime: &SimulationRuntime, actor_id: ActorId) -> UiCharacterSnapshot {
    let snapshot = runtime.snapshot();
    let debug_actor = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == actor_id);
    let attributes = runtime
        .economy()
        .actor(actor_id)
        .map(|actor| {
            actor
                .attributes
                .iter()
                .filter(|(name, _)| {
                    matches!(name.as_str(), "strength" | "agility" | "constitution")
                })
                .map(|(name, value)| (name.clone(), *value))
                .collect::<BTreeMap<_, _>>()
        })
        .unwrap_or_default();

    UiCharacterSnapshot {
        available_points: debug_actor
            .map(|actor| actor.available_stat_points)
            .unwrap_or(0),
        attributes,
    }
}

pub fn journal_snapshot(
    runtime: &SimulationRuntime,
    actor_id: ActorId,
    quests: &QuestLibrary,
) -> UiJournalSnapshot {
    let quest_titles = runtime
        .active_quest_ids_for_actor(actor_id)
        .into_iter()
        .map(|quest_id| {
            quests
                .get(&quest_id)
                .map(|quest| quest.title.clone())
                .unwrap_or(quest_id)
        })
        .collect();
    UiJournalSnapshot { quest_titles }
}

pub fn skills_snapshot(
    runtime: &SimulationRuntime,
    actor_id: ActorId,
    skills: &SkillLibrary,
    trees: &SkillTreeLibrary,
) -> UiSkillsSnapshot {
    let learned = runtime
        .economy()
        .actor(actor_id)
        .map(|actor| actor.learned_skills.clone())
        .unwrap_or_default();
    let mut trees_by_id = trees
        .iter()
        .map(|(tree_id, definition)| {
            (
                tree_id.clone(),
                UiSkillTreeView {
                    tree_id: tree_id.clone(),
                    tree_name: definition.name.clone(),
                    tree_description: definition.description.clone(),
                    entries: Vec::new(),
                },
            )
        })
        .collect::<BTreeMap<_, _>>();

    for (skill_id, definition) in skills.iter() {
        let learned_level = learned.get(skill_id).copied().unwrap_or(0);
        let activation_mode = definition
            .activation
            .as_ref()
            .map(|activation| activation.mode.trim().to_string())
            .filter(|mode| !mode.is_empty())
            .unwrap_or_else(|| "passive".to_string());
        let prerequisite_names = definition
            .prerequisites
            .iter()
            .map(|prerequisite_id| {
                skills
                    .get(prerequisite_id)
                    .map(|skill| skill.name.clone())
                    .filter(|name| !name.trim().is_empty())
                    .unwrap_or_else(|| prerequisite_id.clone())
            })
            .collect::<Vec<_>>();

        let tree_entry = trees_by_id
            .entry(definition.tree_id.clone())
            .or_insert_with(|| UiSkillTreeView {
                tree_id: definition.tree_id.clone(),
                tree_name: definition.tree_id.clone(),
                tree_description: String::new(),
                entries: Vec::new(),
            });

        tree_entry.entries.push(UiSkillEntryView {
            skill_id: skill_id.clone(),
            tree_id: definition.tree_id.clone(),
            name: definition.name.clone(),
            description: definition.description.clone(),
            learned_level,
            max_level: definition.max_level,
            hotbar_eligible: learned_level > 0 && activation_mode != "passive",
            activation_mode,
            cooldown_seconds: definition
                .activation
                .as_ref()
                .map(|activation| activation.cooldown)
                .unwrap_or_default(),
            prerequisite_names,
            attribute_requirements: definition.attribute_requirements.clone(),
        });
    }

    let mut tree_views = trees_by_id.into_values().collect::<Vec<_>>();
    for tree in &mut tree_views {
        tree.entries.sort_by(|left, right| {
            right
                .learned_level
                .cmp(&left.learned_level)
                .then(left.name.cmp(&right.name))
        });
    }
    tree_views.sort_by(|left, right| left.tree_name.cmp(&right.tree_name));

    UiSkillsSnapshot { trees: tree_views }
}

pub fn crafting_snapshot(
    runtime: &SimulationRuntime,
    actor_id: ActorId,
    recipes: &RecipeLibrary,
) -> UiCraftingSnapshot {
    let recipe_names = runtime
        .economy()
        .actor(actor_id)
        .map(|actor| {
            let mut ids = actor.unlocked_recipes.iter().cloned().collect::<Vec<_>>();
            ids.sort();
            ids.into_iter()
                .filter_map(|recipe_id| {
                    recipes
                        .get(&recipe_id)
                        .map(|recipe| (recipe_id.clone(), recipe.name.clone()))
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    UiCraftingSnapshot { recipe_names }
}

pub fn map_snapshot(
    runtime: &mut SimulationRuntime,
    actor_id: ActorId,
    overworld: &OverworldLibrary,
) -> UiMapSnapshot {
    let current = runtime.current_overworld_state();
    let Some((_, definition)) = overworld.iter().next() else {
        return UiMapSnapshot::default();
    };

    let unlocked = current
        .unlocked_locations
        .iter()
        .cloned()
        .collect::<BTreeSet<_>>();

    let mut locations = definition
        .locations
        .iter()
        .map(|location| {
            map_location_view(
                runtime,
                actor_id,
                location,
                unlocked.contains(location.id.as_str()),
                &current.active_outdoor_location_id,
            )
        })
        .collect::<Vec<_>>();
    locations.sort_by(|left, right| left.name.cmp(&right.name));
    UiMapSnapshot { locations }
}

fn map_location_view(
    runtime: &mut SimulationRuntime,
    actor_id: ActorId,
    location: &OverworldLocationDefinition,
    unlocked: bool,
    active_outdoor_location_id: &Option<String>,
) -> UiMapLocationView {
    let preview = if unlocked {
        runtime
            .request_overworld_route(actor_id, location.id.as_str())
            .ok()
    } else {
        None
    };

    UiMapLocationView {
        location_id: location.id.as_str().to_string(),
        name: location.name.clone(),
        kind: match location.kind {
            OverworldLocationKind::Outdoor => "outdoor".to_string(),
            OverworldLocationKind::Interior => "interior".to_string(),
            OverworldLocationKind::Dungeon => "dungeon".to_string(),
        },
        unlocked,
        current: active_outdoor_location_id.as_deref() == Some(location.id.as_str()),
        travel_minutes: preview.as_ref().map(|route| route.travel_minutes),
        food_cost: preview.as_ref().map(|route| route.food_cost),
        risk_level: preview.as_ref().map(|route| route.risk_level),
    }
}

pub fn trade_snapshot(
    runtime: &SimulationRuntime,
    actor_id: ActorId,
    target_actor_id: Option<ActorId>,
    shop_id: &str,
    items: &ItemLibrary,
    shops: &ShopLibrary,
) -> UiTradeSnapshot {
    let player_items = runtime
        .economy()
        .actor(actor_id)
        .map(|actor| {
            actor
                .inventory
                .iter()
                .filter_map(|(item_id, count)| {
                    let definition = items.get(*item_id)?;
                    let unit_price = runtime
                        .economy()
                        .shop(shop_id)
                        .and_then(|shop| {
                            shop.inventory
                                .get(item_id)
                                .map(|entry| entry.price)
                                .or(Some(definition.value))
                        })
                        .unwrap_or(definition.value);
                    Some(UiTradeEntryView {
                        item_id: *item_id,
                        name: definition.name.clone(),
                        count: *count,
                        unit_price,
                        total_weight: definition.weight * (*count as f32),
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let shop_items = runtime
        .economy()
        .shop(shop_id)
        .map(|shop| {
            shop.inventory
                .values()
                .filter_map(|entry| {
                    let definition = items.get(entry.item_id)?;
                    Some(UiTradeEntryView {
                        item_id: entry.item_id,
                        name: definition.name.clone(),
                        count: entry.count,
                        unit_price: entry.price,
                        total_weight: definition.weight * (entry.count as f32),
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let relation_score = target_actor_id
        .map(|target_actor_id| runtime.get_relationship_score(actor_id, target_actor_id))
        .unwrap_or(0);
    let shop_money = runtime
        .economy()
        .shop(shop_id)
        .map(|shop| shop.money)
        .unwrap_or(0);

    let _ = shops;

    UiTradeSnapshot {
        shop_id: shop_id.to_string(),
        relation_score,
        player_money: runtime.economy().actor_money(actor_id).unwrap_or(0),
        shop_money,
        player_items,
        shop_items,
    }
}

pub fn classify_item(definition: &ItemDefinition, ammo_ids: &BTreeSet<u32>) -> UiItemType {
    if definition
        .fragments
        .iter()
        .any(|fragment| matches!(fragment, ItemFragment::Weapon { .. }))
    {
        return UiItemType::Weapon;
    }
    if definition
        .fragments
        .iter()
        .any(|fragment| matches!(fragment, ItemFragment::Usable { .. }))
    {
        return UiItemType::Consumable;
    }
    if ammo_ids.contains(&definition.id) {
        return UiItemType::Ammo;
    }
    if let Some(ItemFragment::Equip { slots, .. }) = definition
        .fragments
        .iter()
        .find(|fragment| matches!(fragment, ItemFragment::Equip { .. }))
    {
        if slots
            .iter()
            .any(|slot| matches!(slot.as_str(), "accessory" | "accessory_1" | "accessory_2"))
        {
            return UiItemType::Accessory;
        }
        return UiItemType::Armor;
    }
    if definition
        .fragments
        .iter()
        .any(|fragment| matches!(fragment, ItemFragment::Crafting { .. }))
        || definition
            .fragments
            .iter()
            .any(|fragment| matches!(fragment, ItemFragment::Stacking { .. }))
    {
        return UiItemType::Material;
    }
    UiItemType::Misc
}

pub fn ammo_item_ids(items: &ItemLibrary) -> BTreeSet<u32> {
    items
        .iter()
        .flat_map(|(_, definition)| {
            definition.fragments.iter().filter_map(|fragment| {
                if let ItemFragment::Weapon {
                    ammo_type: Some(ammo_type),
                    ..
                } = fragment
                {
                    Some(*ammo_type)
                } else {
                    None
                }
            })
        })
        .collect()
}

pub fn item_attribute_bonuses(definition: &ItemDefinition) -> BTreeMap<String, f32> {
    definition
        .fragments
        .iter()
        .find_map(|fragment| {
            if let ItemFragment::AttributeModifiers { attributes } = fragment {
                Some(attributes.clone())
            } else {
                None
            }
        })
        .unwrap_or_default()
}

pub fn item_equippable(definition: &ItemDefinition) -> bool {
    definition
        .fragments
        .iter()
        .any(|fragment| matches!(fragment, ItemFragment::Equip { .. }))
}

pub fn item_usable(definition: &ItemDefinition) -> bool {
    definition
        .fragments
        .iter()
        .any(|fragment| matches!(fragment, ItemFragment::Usable { .. }))
}
