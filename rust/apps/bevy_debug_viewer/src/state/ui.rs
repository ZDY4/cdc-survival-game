//! UI 状态：定义游戏 UI 资源、鼠标命中目标和按钮动作枚举。

use bevy::picking::prelude::Pickable;
use bevy::prelude::*;
use bevy::text::TextSpan;
use game_bevy::{UiInventoryFilter, UiMenuPanel};

use super::ViewerObserveSpeed;

#[derive(Component)]
pub(crate) struct GameUiRoot;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum UiHoverTooltipContent {
    InventoryItem { item_id: u32 },
    Skill { tree_id: String, skill_id: String },
    SceneTransition { target_name: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum UiContextMenuTarget {
    InventoryItem { item_id: u32 },
    EquipmentSlot { slot_id: String, item_id: u32 },
    SkillEntry { tree_id: String, skill_id: String },
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
pub(crate) struct UiContextMenuState {
    pub visible: bool,
    pub cursor_position: Vec2,
    pub target: Option<UiContextMenuTarget>,
}

impl Default for UiContextMenuState {
    fn default() -> Self {
        Self {
            visible: false,
            cursor_position: Vec2::ZERO,
            target: None,
        }
    }
}

impl UiContextMenuState {
    pub(crate) fn clear(&mut self) {
        self.visible = false;
        self.target = None;
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum UiInventoryDragSource {
    InventoryItem { item_id: u32 },
    EquipmentSlot { slot_id: String, item_id: u32 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum UiInventoryDragHoverTarget {
    InventoryItem { item_id: u32 },
    EquipmentSlot { slot_id: String },
    InventoryListEnd,
    TradeSellZone,
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct UiInventoryDragState {
    pub active_source: Option<UiInventoryDragSource>,
    pub hover_target: Option<UiInventoryDragHoverTarget>,
    pub press_cursor_position: Vec2,
    pub cursor_position: Vec2,
    pub dragging: bool,
    pub suppress_button_press_once: bool,
    pub preview_label: String,
}

impl Default for UiInventoryDragState {
    fn default() -> Self {
        Self {
            active_source: None,
            hover_target: None,
            press_cursor_position: Vec2::ZERO,
            cursor_position: Vec2::ZERO,
            dragging: false,
            suppress_button_press_once: false,
            preview_label: String::new(),
        }
    }
}

impl UiInventoryDragState {
    pub(crate) fn clear(&mut self) {
        self.active_source = None;
        self.hover_target = None;
        self.press_cursor_position = Vec2::ZERO;
        self.cursor_position = Vec2::ZERO;
        self.dragging = false;
        self.suppress_button_press_once = false;
        self.preview_label.clear();
    }

    pub(crate) fn is_active(&self) -> bool {
        self.active_source.is_some()
    }
}

#[derive(Component)]
pub(crate) struct UiMouseBlocker;

pub(crate) fn viewer_ui_passthrough_bundle() -> impl Bundle {
    (Pickable::IGNORE,)
}

pub(crate) fn sync_viewer_ui_pick_passthrough(
    mut commands: Commands,
    ui_entities: Query<
        Entity,
        (
            Or<(With<Node>, With<Text>, With<TextSpan>)>,
            Without<Pickable>,
        ),
    >,
) {
    for entity in &ui_entities {
        commands.entity(entity).try_insert(Pickable::IGNORE);
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

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct TradeInventoryItemClickTarget {
    pub item_id: u32,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub(crate) struct EquipmentSlotClickTarget {
    pub slot_id: String,
    pub item_id: Option<u32>,
}

#[derive(Component)]
pub(crate) struct InventoryPanelBounds;

#[derive(Component)]
pub(crate) struct InventoryListDropZone;

#[derive(Component)]
pub(crate) struct TradeInventoryPanelBounds;

#[derive(Component)]
pub(crate) struct TradeInventoryListDropZone;

#[derive(Component)]
pub(crate) struct TradeSellZone;

#[derive(Component)]
pub(crate) struct UiContextMenuRoot;

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
    DecreaseItemQuantity,
    IncreaseItemQuantity,
    SetItemQuantityToMax,
    ConfirmItemQuantity,
    CancelItemQuantity,
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
    ToggleObPlayback,
    SetObPlaybackSpeed(ViewerObserveSpeed),
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
    SellEquippedTradeItem {
        shop_id: String,
        slot_id: String,
    },
    SettingsSetMaster(f32),
    SettingsSetMusic(f32),
    SettingsSetSfx(f32),
    SettingsSetWindowMode(String),
    SettingsSetVsync(bool),
    SettingsSetUiScale(f32),
    SettingsCycleBinding(String),
}
