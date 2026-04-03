//! UI 状态：定义游戏 UI 资源、鼠标命中目标和按钮动作枚举。

use bevy::picking::prelude::Pickable;
use bevy::prelude::*;
use bevy::text::TextSpan;
use game_bevy::{UiInventoryFilter, UiMenuPanel};

#[derive(Component)]
pub(crate) struct GameUiRoot;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum UiHoverTooltipContent {
    InventoryItem { item_id: u32 },
    Skill { tree_id: String, skill_id: String },
    SceneTransition { target_name: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum UiInventoryContextMenuTarget {
    InventoryItem { item_id: u32 },
    EquipmentSlot { slot_id: String, item_id: u32 },
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct UiHoverTooltipState {
    pub visible: bool,
    pub cursor_position: Vec2,
    pub content: Option<UiHoverTooltipContent>,
}

impl Default for UiHoverTooltipState {
    fn default() -> Self {
        Self {
            visible: false,
            cursor_position: Vec2::ZERO,
            content: None,
        }
    }
}

impl UiHoverTooltipState {
    pub(crate) fn clear(&mut self) {
        self.visible = false;
        self.content = None;
    }
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct UiInventoryContextMenuState {
    pub visible: bool,
    pub cursor_position: Vec2,
    pub target: Option<UiInventoryContextMenuTarget>,
}

impl Default for UiInventoryContextMenuState {
    fn default() -> Self {
        Self {
            visible: false,
            cursor_position: Vec2::ZERO,
            target: None,
        }
    }
}

impl UiInventoryContextMenuState {
    pub(crate) fn clear(&mut self) {
        self.visible = false;
        self.target = None;
    }
}

#[derive(Component)]
pub(crate) struct UiMouseBlocker;

pub(crate) fn viewer_ui_passthrough_bundle() -> impl Bundle {
    (Pickable::IGNORE,)
}

pub(crate) fn sync_viewer_ui_pick_passthrough(
    mut commands: Commands,
    ui_entities: Query<Entity, (Or<(With<Node>, With<Text>, With<TextSpan>)>, Without<Pickable>)>,
) {
    for entity in &ui_entities {
        commands.entity(entity).insert(Pickable::IGNORE);
    }
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct InventoryItemHoverTarget {
    pub item_id: u32,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub(crate) struct SkillHoverTarget {
    pub tree_id: String,
    pub skill_id: String,
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct InventoryItemClickTarget {
    pub item_id: u32,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub(crate) struct EquipmentSlotClickTarget {
    pub slot_id: String,
    pub item_id: Option<u32>,
}

#[derive(Component)]
pub(crate) struct InventoryContextMenuRoot;

#[derive(Component, Debug, Clone)]
pub(crate) enum GameUiButtonAction {
    MainMenuNewGame,
    MainMenuContinue,
    MainMenuExit,
    TogglePanel(UiMenuPanel),
    ClosePanels,
    CloseTrade,
    InventoryFilter(UiInventoryFilter),
    UseInventoryItem,
    EquipInventoryItem,
    DropInventoryItem,
    DecreaseDiscardQuantity,
    IncreaseDiscardQuantity,
    SetDiscardQuantityToMax,
    ConfirmDiscardQuantity,
    CancelDiscardQuantity,
    UnequipSlot(String),
    AllocateAttribute(String),
    SelectSkillTree(String),
    SelectSkill(String),
    AssignSkillToFirstEmptyHotbarSlot(String),
    AssignSkillToHotbar {
        skill_id: String,
        group: usize,
        slot: usize,
    },
    EnterAttackTargeting,
    ActivateHotbarSlot(usize),
    SelectHotbarGroup(usize),
    ClearHotbarSlot {
        group: usize,
        slot: usize,
    },
    CraftRecipe(String),
    SelectMapLocation(String),
    EnterOverworldLocation(String),
    BuyTradeItem {
        shop_id: String,
        item_id: u32,
    },
    SellTradeItem {
        shop_id: String,
        item_id: u32,
    },
    SettingsSetMaster(f32),
    SettingsSetMusic(f32),
    SettingsSetSfx(f32),
    SettingsSetWindowMode(String),
    SettingsSetVsync(bool),
    SettingsSetUiScale(f32),
    SettingsCycleBinding(String),
}
