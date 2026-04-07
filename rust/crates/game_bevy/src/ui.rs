use std::collections::{BTreeMap, BTreeSet};

use bevy_app::{App, Plugin};
use bevy_ecs::prelude::*;
use game_core::SimulationRuntime;
use game_data::{
    ActorId, ActorSide, GridCoord, InteractionContextSnapshot, InteractionPrompt, ItemDefinition,
    ItemFragment, ItemLibrary, OverworldDefinition, OverworldLibrary, OverworldLocationDefinition,
    OverworldLocationKind, QuestLibrary, RecipeLibrary, ShopLibrary, SkillLibrary,
    SkillTreeLibrary, WorldMode,
};

const DEFAULT_EQUIPMENT_SLOT_ORDER: &[&str] = &[
    "main_hand",
    "off_hand",
    "head",
    "body",
    "legs",
    "feet",
    "accessory_1",
    "accessory_2",
];

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UiMenuRegion {
    Left,
    Center,
    Right,
    Overlay,
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
    pub left_panel: Option<UiMenuPanel>,
    pub center_panel: Option<UiMenuPanel>,
    pub right_panel: Option<UiMenuPanel>,
    pub overlay_panel: Option<UiMenuPanel>,
    pub selected_inventory_item: Option<u32>,
    pub selected_equipment_slot: Option<String>,
    pub selected_skill_tree_id: Option<String>,
    pub selected_skill_id: Option<String>,
    pub selected_recipe_id: Option<String>,
    pub selected_map_location_id: Option<String>,
    pub status_text: String,
}

impl UiMenuState {
    pub fn panel_region(panel: UiMenuPanel) -> UiMenuRegion {
        match panel {
            UiMenuPanel::Character | UiMenuPanel::Journal | UiMenuPanel::Skills => {
                UiMenuRegion::Left
            }
            UiMenuPanel::Map => UiMenuRegion::Center,
            UiMenuPanel::Inventory | UiMenuPanel::Crafting => UiMenuRegion::Right,
            UiMenuPanel::Settings => UiMenuRegion::Overlay,
        }
    }

    pub fn region_panel(&self, region: UiMenuRegion) -> Option<UiMenuPanel> {
        match region {
            UiMenuRegion::Left => self.left_panel,
            UiMenuRegion::Center => self.center_panel,
            UiMenuRegion::Right => self.right_panel,
            UiMenuRegion::Overlay => self.overlay_panel,
        }
    }

    pub fn is_panel_open(&self, panel: UiMenuPanel) -> bool {
        self.region_panel(Self::panel_region(panel)) == Some(panel)
    }

    pub fn any_stage_panel_open(&self) -> bool {
        self.left_panel.is_some() || self.center_panel.is_some() || self.right_panel.is_some()
    }

    pub fn any_panel_open(&self) -> bool {
        self.any_stage_panel_open() || self.overlay_panel.is_some()
    }

    pub fn is_settings_open(&self) -> bool {
        self.overlay_panel == Some(UiMenuPanel::Settings)
    }

    pub fn open_panel(&mut self, panel: UiMenuPanel) {
        match Self::panel_region(panel) {
            UiMenuRegion::Left => {
                self.left_panel = Some(panel);
                self.overlay_panel = None;
            }
            UiMenuRegion::Center => {
                self.center_panel = Some(panel);
                self.overlay_panel = None;
            }
            UiMenuRegion::Right => {
                self.right_panel = Some(panel);
                self.overlay_panel = None;
            }
            UiMenuRegion::Overlay => {
                self.close_stage_panels();
                self.overlay_panel = Some(panel);
            }
        }
    }

    pub fn close_panel(&mut self, panel: UiMenuPanel) {
        match Self::panel_region(panel) {
            UiMenuRegion::Left if self.left_panel == Some(panel) => self.left_panel = None,
            UiMenuRegion::Center if self.center_panel == Some(panel) => self.center_panel = None,
            UiMenuRegion::Right if self.right_panel == Some(panel) => self.right_panel = None,
            UiMenuRegion::Overlay if self.overlay_panel == Some(panel) => self.overlay_panel = None,
            _ => {}
        }
    }

    pub fn toggle_panel(&mut self, panel: UiMenuPanel) {
        if self.is_panel_open(panel) {
            self.close_panel(panel);
        } else {
            self.open_panel(panel);
        }
    }

    pub fn close_stage_panels(&mut self) {
        self.left_panel = None;
        self.center_panel = None;
        self.right_panel = None;
    }

    pub fn close_all_panels(&mut self) {
        self.close_stage_panels();
        self.overlay_panel = None;
    }
}

#[derive(Debug, Clone, Default)]
pub struct UiTradeSessionState {
    pub shop_id: String,
    pub target_actor_id: Option<ActorId>,
}

#[derive(Debug, Clone, Default)]
pub struct UiContainerSessionState {
    pub container_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum UiItemQuantityIntent {
    #[default]
    Discard,
    TradeBuy {
        shop_id: String,
        unit_price: i32,
    },
    TradeSell {
        shop_id: String,
        unit_price: i32,
    },
    ContainerStore {
        container_id: String,
    },
    ContainerTake {
        container_id: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct UiItemQuantityModalState {
    pub item_id: u32,
    pub source_count: i32,
    pub available_count: i32,
    pub selected_count: i32,
    pub intent: UiItemQuantityIntent,
}

#[derive(Resource, Debug, Clone, Default)]
pub struct UiModalState {
    pub message: Option<String>,
    pub trade: Option<UiTradeSessionState>,
    pub container: Option<UiContainerSessionState>,
    pub item_quantity: Option<UiItemQuantityModalState>,
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
    pub display_index: usize,
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
}

#[derive(Debug, Clone, Default)]
pub struct UiMapSnapshot {
    pub locations: Vec<UiMapLocationView>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct UiOverworldLocationPromptSnapshot {
    pub visible: bool,
    pub location_id: String,
    pub location_name: String,
    pub grid: GridCoord,
    pub enter_label: String,
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
pub struct UiContainerEntryView {
    pub item_id: u32,
    pub name: String,
    pub count: i32,
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

#[derive(Debug, Clone, Default)]
pub struct UiContainerSnapshot {
    pub container_id: String,
    pub display_name: String,
    pub item_kind_count: usize,
    pub entries: Vec<UiContainerEntryView>,
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
            "无效状态".to_string(),
            "旧版 traveling 状态已不再支持".to_string(),
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
    let entries = runtime
        .economy()
        .inventory_display_order(actor_id)
        .unwrap_or_default()
        .into_iter()
        .enumerate()
        .filter_map(|(display_index, item_id)| {
            let count = actor.inventory.get(&item_id).copied().unwrap_or(0);
            if count <= 0 {
                return None;
            }
            let definition = items.get(item_id)?;
            let item_type = classify_item(definition, &ammo_ids);
            if !filter.matches_type(item_type) {
                return None;
            }
            Some(UiInventoryEntryView {
                item_id,
                display_index,
                name: definition.name.clone(),
                count,
                item_type,
                total_weight: definition.weight * (count as f32),
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

    let mut equipment_slot_ids = DEFAULT_EQUIPMENT_SLOT_ORDER
        .iter()
        .map(|slot| (*slot).to_string())
        .collect::<Vec<_>>();
    for slot_id in actor.equipped_slots.keys() {
        if !equipment_slot_ids
            .iter()
            .any(|existing| existing == slot_id)
        {
            equipment_slot_ids.push(slot_id.clone());
        }
    }
    let equipment = equipment_slot_ids
        .into_iter()
        .map(|slot_id| {
            let equipped = actor.equipped_slots.get(&slot_id);
            UiEquipmentSlotView {
                slot_id: slot_id.clone(),
                slot_label: equipment_slot_label(&slot_id),
                item_id: equipped.map(|equipped| equipped.item_id),
                item_name: equipped
                    .and_then(|equipped| items.get(equipped.item_id).map(|item| item.name.clone())),
            }
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

fn equipment_slot_label(slot_id: &str) -> String {
    match slot_id {
        "main_hand" => "主手".to_string(),
        "off_hand" => "副手".to_string(),
        "head" => "头部".to_string(),
        "body" => "身体".to_string(),
        "legs" => "腿部".to_string(),
        "feet" => "脚部".to_string(),
        "accessory" => "饰品".to_string(),
        "accessory_1" => "饰品 1".to_string(),
        "accessory_2" => "饰品 2".to_string(),
        other => other.to_string(),
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
    runtime: &SimulationRuntime,
    _actor_id: ActorId,
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
                location,
                unlocked.contains(location.id.as_str()),
                &current.active_outdoor_location_id,
            )
        })
        .collect::<Vec<_>>();
    locations.sort_by(|left, right| left.name.cmp(&right.name));
    UiMapSnapshot { locations }
}

pub fn overworld_location_prompt_snapshot(
    runtime: &SimulationRuntime,
    actor_id: ActorId,
    overworld: &OverworldLibrary,
) -> UiOverworldLocationPromptSnapshot {
    let hidden = UiOverworldLocationPromptSnapshot {
        enter_label: "进入".to_string(),
        ..UiOverworldLocationPromptSnapshot::default()
    };
    if runtime.current_interaction_context().world_mode != WorldMode::Overworld {
        return hidden;
    }
    if runtime.pending_movement().is_some() {
        return hidden;
    }

    let Some(actor_grid) = runtime.get_actor_grid_position(actor_id) else {
        return hidden;
    };
    let Some(arrival) = runtime.recent_overworld_arrival() else {
        return hidden;
    };
    if arrival.actor_id != actor_id
        || !arrival.arrived_exactly
        || arrival.requested_goal != actor_grid
        || arrival.final_position != actor_grid
    {
        return hidden;
    }

    let Some(location_id) = runtime.overworld_outdoor_location_id_at(actor_grid) else {
        return hidden;
    };
    let Some(definition) = active_overworld_definition(runtime, overworld) else {
        return hidden;
    };
    let Some(location) = definition.locations.iter().find(|location| {
        location.kind == OverworldLocationKind::Outdoor
            && location.id.as_str() == location_id.as_str()
    }) else {
        return hidden;
    };

    UiOverworldLocationPromptSnapshot {
        visible: true,
        location_id,
        location_name: location.name.clone(),
        grid: actor_grid,
        enter_label: "进入".to_string(),
    }
}

fn map_location_view(
    location: &OverworldLocationDefinition,
    unlocked: bool,
    active_outdoor_location_id: &Option<String>,
) -> UiMapLocationView {
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
    }
}

fn active_overworld_definition<'a>(
    runtime: &SimulationRuntime,
    overworld: &'a OverworldLibrary,
) -> Option<&'a OverworldDefinition> {
    let current = runtime.current_overworld_state();
    if let Some(overworld_id) = current.overworld_id.as_deref() {
        overworld
            .iter()
            .find(|(id, _)| id.as_str() == overworld_id)
            .map(|(_, definition)| definition)
    } else {
        overworld.iter().next().map(|(_, definition)| definition)
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
        .inventory_display_order(actor_id)
        .map(|order| {
            order
                .into_iter()
                .filter_map(|item_id| {
                    let count = runtime
                        .economy()
                        .inventory_count(actor_id, item_id)
                        .unwrap_or(0);
                    if count <= 0 {
                        return None;
                    }
                    let definition = items.get(item_id)?;
                    let unit_price = runtime
                        .economy()
                        .shop(shop_id)
                        .and_then(|shop| {
                            shop.inventory
                                .get(&item_id)
                                .map(|entry| entry.price)
                                .or(Some(definition.value))
                        })
                        .unwrap_or(definition.value);
                    Some(UiTradeEntryView {
                        item_id,
                        name: definition.name.clone(),
                        count,
                        unit_price,
                        total_weight: definition.weight * (count as f32),
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

pub fn container_snapshot(
    runtime: &SimulationRuntime,
    container_id: &str,
    items: &ItemLibrary,
) -> UiContainerSnapshot {
    let Some(container) = runtime.economy().container(container_id) else {
        return UiContainerSnapshot::default();
    };

    let entries = runtime
        .economy()
        .container_inventory_display_order(container_id)
        .unwrap_or_default()
        .into_iter()
        .filter_map(|item_id| {
            let count = runtime
                .economy()
                .container_inventory_count(container_id, item_id)
                .unwrap_or(0);
            if count <= 0 {
                return None;
            }
            let definition = items.get(item_id)?;
            Some(UiContainerEntryView {
                item_id,
                name: definition.name.clone(),
                count,
                total_weight: definition.weight * (count as f32),
            })
        })
        .collect::<Vec<_>>();

    UiContainerSnapshot {
        container_id: container.id.clone(),
        display_name: container.display_name.clone(),
        item_kind_count: entries.len(),
        entries,
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

#[cfg(test)]
mod tests {
    use super::{overworld_location_prompt_snapshot, UiOverworldLocationPromptSnapshot};
    use game_core::SimulationRuntime;
    use game_data::{
        ActorId, ActorSide, CharacterId, GridCoord, MapDefinition, MapEntryPointDefinition, MapId,
        MapLevelDefinition, MapSize, OverworldCellDefinition, OverworldDefinition, OverworldId,
        OverworldLibrary, OverworldLocationDefinition, OverworldLocationId, OverworldLocationKind,
        OverworldTravelRuleSet, WorldMode,
    };
    use std::collections::BTreeMap;

    #[test]
    fn overworld_prompt_snapshot_is_visible_after_exact_trigger_arrival() {
        let (mut runtime, player, overworld) = sample_overworld_prompt_runtime();
        runtime
            .issue_actor_move(player, GridCoord::new(1, 0, 0))
            .expect("move should succeed");

        let snapshot = overworld_location_prompt_snapshot(&runtime, player, &overworld);

        assert_eq!(
            snapshot,
            UiOverworldLocationPromptSnapshot {
                visible: true,
                location_id: "prompt_outpost".to_string(),
                location_name: "Prompt Outpost".to_string(),
                grid: GridCoord::new(1, 0, 0),
                enter_label: "进入".to_string(),
            }
        );
    }

    #[test]
    fn overworld_prompt_snapshot_stays_hidden_while_pending_movement_crosses_trigger() {
        let (mut runtime, player, overworld) = sample_overworld_prompt_runtime();
        runtime.submit_command(game_core::SimulationCommand::SetActorAp {
            actor_id: player,
            ap: 1.0,
        });
        runtime
            .issue_actor_move(player, GridCoord::new(2, 0, 0))
            .expect("move should start");

        assert_eq!(
            runtime.get_actor_grid_position(player),
            Some(GridCoord::new(1, 0, 0))
        );
        assert!(runtime.pending_movement().is_some());
        assert_eq!(
            overworld_location_prompt_snapshot(&runtime, player, &overworld),
            UiOverworldLocationPromptSnapshot {
                enter_label: "进入".to_string(),
                ..UiOverworldLocationPromptSnapshot::default()
            }
        );
    }

    #[test]
    fn overworld_prompt_snapshot_hides_after_entering_location() {
        let (mut runtime, player, overworld) = sample_overworld_prompt_runtime();
        runtime
            .issue_actor_move(player, GridCoord::new(1, 0, 0))
            .expect("move should succeed");
        runtime.submit_command(game_core::SimulationCommand::SetActorAp {
            actor_id: player,
            ap: 1.0,
        });
        runtime
            .enter_location(player, "prompt_outpost", None)
            .expect("enter should succeed");

        let snapshot = overworld_location_prompt_snapshot(&runtime, player, &overworld);

        assert!(!snapshot.visible);
    }

    fn sample_overworld_prompt_runtime() -> (SimulationRuntime, ActorId, OverworldLibrary) {
        let overworld = sample_overworld_prompt_library();
        let mut runtime = SimulationRuntime::new();
        runtime.set_map_library(sample_overworld_prompt_map_library());
        runtime.set_overworld_library(overworld.clone());
        runtime
            .seed_overworld_state(
                WorldMode::Overworld,
                Some("prompt_outpost".into()),
                None,
                ["prompt_outpost".into()],
            )
            .expect("overworld state should seed");
        let actor_id = runtime.register_actor(game_core::RegisterActor {
            definition_id: Some(CharacterId("player".into())),
            display_name: "Player".into(),
            kind: game_data::ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 0),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        runtime.submit_command(game_core::SimulationCommand::SetActorAp { actor_id, ap: 3.0 });
        (runtime, actor_id, overworld)
    }

    fn sample_overworld_prompt_map_library() -> game_data::MapLibrary {
        game_data::MapLibrary::from(BTreeMap::from([(
            MapId("prompt_outpost_map".into()),
            MapDefinition {
                id: MapId("prompt_outpost_map".into()),
                name: "Prompt Outpost".into(),
                size: MapSize {
                    width: 8,
                    height: 8,
                },
                default_level: 0,
                levels: vec![MapLevelDefinition {
                    y: 0,
                    cells: Vec::new(),
                }],
                entry_points: vec![MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(1, 0, 1),
                    facing: None,
                    extra: BTreeMap::new(),
                }],
                objects: Vec::new(),
            },
        )]))
    }

    fn sample_overworld_prompt_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("prompt_world".into()),
            OverworldDefinition {
                id: OverworldId("prompt_world".into()),
                size: MapSize {
                    width: 3,
                    height: 1,
                },
                locations: vec![OverworldLocationDefinition {
                    id: OverworldLocationId("prompt_outpost".into()),
                    name: "Prompt Outpost".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("prompt_outpost_map".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(1, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                }],
                cells: vec![
                    OverworldCellDefinition {
                        grid: GridCoord::new(0, 0, 0),
                        terrain: "road".into(),
                        blocked: false,
                        extra: BTreeMap::new(),
                    },
                    OverworldCellDefinition {
                        grid: GridCoord::new(1, 0, 0),
                        terrain: "road".into(),
                        blocked: false,
                        extra: BTreeMap::new(),
                    },
                    OverworldCellDefinition {
                        grid: GridCoord::new(2, 0, 0),
                        terrain: "road".into(),
                        blocked: false,
                        extra: BTreeMap::new(),
                    },
                ],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
    }
}
