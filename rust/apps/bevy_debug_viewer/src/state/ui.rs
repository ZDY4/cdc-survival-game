//! UI 状态：定义游戏 UI 资源、鼠标命中目标和按钮动作枚举。

use bevy::picking::prelude::Pickable;
use bevy::prelude::*;
use bevy::ui::{ComputedNode, RelativeCursorPosition, UiGlobalTransform};
use game_bevy::{UiInventoryFilter, UiMenuPanel};

use super::ViewerObserveSpeed;

#[derive(Component)]
pub(crate) struct GameUiRoot;

#[derive(Component)]
pub(crate) struct MainMenuRoot;

#[derive(Component)]
pub(crate) struct TopBadgeRoot;

#[derive(Component)]
pub(crate) struct HotbarRoot;

#[derive(Component)]
pub(crate) struct ActivePanelRoot;

#[derive(Component)]
pub(crate) struct TradeRoot;

#[derive(Component)]
pub(crate) struct ContainerRoot;

#[derive(Component)]
pub(crate) struct TooltipRoot;

#[derive(Component)]
pub(crate) struct InventoryContextMenuLayerRoot;

#[derive(Component)]
pub(crate) struct DragPreviewRoot;

#[derive(Component)]
pub(crate) struct DiscardModalRoot;

#[derive(Component)]
pub(crate) struct OverworldPromptRoot;

#[derive(Resource, Debug, Clone, Copy)]
pub(crate) struct GameUiScaffold {
    pub root: Entity,
    pub main_menu: Entity,
    pub top_badges: Entity,
    pub hotbar: Entity,
    pub active_panel: Entity,
    pub trade: Entity,
    pub container: Entity,
    pub tooltip: Entity,
    pub context_menu: Entity,
    pub drag_preview: Entity,
    pub discard_modal: Entity,
    pub overworld_prompt: Entity,
}

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
    ContainerItem { container_id: String, item_id: u32 },
    EquipmentSlot { slot_id: String, item_id: u32 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum UiInventoryDragHoverTarget {
    InventoryItem { item_id: u32 },
    ContainerItem { item_id: u32 },
    EquipmentSlot { slot_id: String },
    InventoryListEnd,
    ContainerListEnd,
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
    pub allowed_equipment_slots: Vec<String>,
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
            allowed_equipment_slots: Vec::new(),
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
        self.allowed_equipment_slots.clear();
    }

    pub(crate) fn is_active(&self) -> bool {
        self.active_source.is_some()
    }

    pub(crate) fn supports_equipment_slot(&self, slot_id: &str) -> bool {
        slot_supported(self.allowed_equipment_slots.as_slice(), slot_id)
    }

    pub(crate) fn is_source_equipment_slot(&self, slot_id: &str) -> bool {
        matches!(
            self.active_source.as_ref(),
            Some(UiInventoryDragSource::EquipmentSlot {
                slot_id: source_slot_id,
                ..
            }) if source_slot_id == slot_id
        )
    }
}

fn slot_supported(allowed_slots: &[String], requested_slot: &str) -> bool {
    allowed_slots.iter().any(|slot| {
        let normalized = slot.trim();
        normalized == requested_slot
            || (normalized == "main_hand" && requested_slot == "off_hand")
            || (normalized == "accessory" && requested_slot.starts_with("accessory"))
    })
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct UiInventoryScrollbarDragState {
    pub active: bool,
    pub grab_offset_y: f32,
}

impl Default for UiInventoryScrollbarDragState {
    fn default() -> Self {
        Self {
            active: false,
            grab_offset_y: 0.0,
        }
    }
}

impl UiInventoryScrollbarDragState {
    pub(crate) fn clear(&mut self) {
        self.active = false;
        self.grab_offset_y = 0.0;
    }

    pub(crate) fn is_active(&self) -> bool {
        self.active
    }
}

#[derive(Component)]
pub(crate) struct UiMouseBlocker;

#[derive(Component, Debug, Clone)]
pub(crate) struct UiMouseBlockerName(pub String);

// UiMouseBlocker only carries intent. Actual blocking depends on current inherited visibility.
pub(crate) fn visible_ui_blocker_contains_cursor(
    cursor_position: Vec2,
    computed_node: &ComputedNode,
    transform: &UiGlobalTransform,
    cursor: Option<&RelativeCursorPosition>,
    visibility: Option<&Visibility>,
    inherited_visibility: &InheritedVisibility,
) -> bool {
    if !inherited_visibility.get()
        || visibility.is_some_and(|visibility| *visibility == Visibility::Hidden)
    {
        return false;
    }

    cursor.is_some_and(RelativeCursorPosition::cursor_over)
        || computed_node.contains_point(*transform, cursor_position)
}

pub(crate) fn cursor_over_visible_ui_blocker(
    cursor_position: Option<Vec2>,
    ui_blockers: &Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
            &InheritedVisibility,
            Option<&UiMouseBlockerName>,
        ),
        With<UiMouseBlocker>,
    >,
) -> bool {
    let Some(cursor_position) = cursor_position else {
        return false;
    };

    ui_blockers.iter().any(
        |(computed_node, transform, cursor, visibility, inherited_visibility, _name)| {
            visible_ui_blocker_contains_cursor(
                cursor_position,
                computed_node,
                transform,
                cursor,
                visibility,
                inherited_visibility,
            )
        },
    )
}

pub(crate) fn hovered_visible_ui_blocker_name(
    cursor_position: Option<Vec2>,
    ui_blockers: &Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
            &InheritedVisibility,
            Option<&UiMouseBlockerName>,
        ),
        With<UiMouseBlocker>,
    >,
) -> Option<String> {
    let cursor_position = cursor_position?;
    ui_blockers
        .iter()
        .filter_map(
            |(computed_node, transform, cursor, visibility, inherited_visibility, name)| {
                visible_ui_blocker_contains_cursor(
                    cursor_position,
                    computed_node,
                    transform,
                    cursor,
                    visibility,
                    inherited_visibility,
                )
                .then(|| {
                    let area =
                        (computed_node.size.x.max(0.0) * computed_node.size.y.max(0.0)).max(0.0);
                    let label = name
                        .map(|name| name.0.clone())
                        .unwrap_or_else(|| "未命名界面".to_string());
                    (area, label)
                })
            },
        )
        .min_by(|(left_area, _), (right_area, _)| left_area.total_cmp(right_area))
        .map(|(_, label)| label)
}

pub(crate) fn viewer_ui_passthrough_bundle() -> impl Bundle {
    (Pickable::IGNORE,)
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

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct ContainerInventoryItemClickTarget {
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
pub(crate) struct InventoryEntryScrollArea;

#[derive(Component)]
pub(crate) struct InventoryEntryScrollbarTrack;

#[derive(Component)]
pub(crate) struct InventoryEntryScrollbarThumb;

#[derive(Component)]
pub(crate) struct TradeInventoryPanelBounds;

#[derive(Component)]
pub(crate) struct TradeInventoryListDropZone;

#[derive(Component)]
pub(crate) struct ContainerInventoryPanelBounds;

#[derive(Component)]
pub(crate) struct ContainerInventoryListDropZone;

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
    CloseTrade,
    CloseContainer,
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
    StoreContainerItem {
        container_id: String,
        item_id: u32,
    },
    TakeContainerItem {
        container_id: String,
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
    SettingsSetResolution {
        width: u32,
        height: u32,
    },
    SettingsSetVsync(bool),
    SettingsSetUiScale(f32),
    SettingsCycleBinding(String),
}
