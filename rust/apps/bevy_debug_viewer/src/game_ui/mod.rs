//! 游戏 UI 模块门面：统一组织状态同步、输入处理、面板、快捷栏、浮层和通用组件子模块，
//! 并对外暴露 viewer UI 更新链路所需的稳定入口与共享常量。

use std::fs;
use std::marker::PhantomData;

use bevy::ecs::system::SystemParam;
use bevy::prelude::*;
use bevy::ui::{ComputedNode, FocusPolicy, RelativeCursorPosition, UiGlobalTransform};
use bevy::window::{PresentMode, VideoModeSelection, WindowMode};
use game_bevy::{
    apply_gameplay_libraries, character_snapshot, container_snapshot, interaction_prompt_text,
    inventory_snapshot, journal_snapshot, overworld_location_prompt_snapshot, player_actor_id,
    skills_snapshot, trade_snapshot, world_status_snapshot, EffectDefinitions, ItemDefinitions,
    OverworldDefinitions, QuestDefinitions, RecipeDefinitions, ShopDefinitions, SkillDefinitions,
    SkillTreeDefinitions, UiHotbarState, UiInputBlockState, UiInventoryFilter,
    UiInventoryFilterState, UiMenuPanel, UiMenuState, UiModalState, UiStatusBannerState,
};
use game_core::RuntimeSnapshot;
use game_data::{ActorId, InteractionTargetId};

use crate::bootstrap::load_viewer_gameplay_bootstrap;
use crate::console::ViewerConsoleState;
use crate::controls::{cancel_targeting, enter_attack_targeting};
use crate::picking::ViewerPickingState;
use crate::simulation::{reset_viewer_runtime_transients, sync_viewer_runtime_basics};
use crate::state::{
    viewer_ui_passthrough_bundle, ActivePanelRoot, ContainerInventoryItemClickTarget,
    ContainerInventoryListDropZone, ContainerInventoryPanelBounds, ContainerRoot, DiscardModalRoot,
    DragPreviewRoot, EquipmentSlotClickTarget, GameUiButtonAction, GameUiRoot, GameUiScaffold,
    HotbarRoot, InventoryContextMenuLayerRoot, InventoryEntryScrollArea,
    InventoryEntryScrollbarThumb, InventoryEntryScrollbarTrack, InventoryItemClickTarget,
    InventoryItemHoverTarget, InventoryListDropZone, InventoryPanelBounds, MainMenuRoot,
    OverworldPromptRoot, SkillHoverTarget, TooltipRoot, TopBadgeRoot,
    TradeInventoryItemClickTarget, TradeInventoryListDropZone, TradeInventoryPanelBounds,
    TradeRoot, TradeSellZone, UiContextMenuRoot, UiContextMenuState, UiContextMenuTarget,
    UiHoverTooltipContent, UiHoverTooltipState, UiInventoryDragHoverTarget, UiInventoryDragSource,
    UiInventoryDragState, UiInventoryScrollbarDragState, UiMouseBlocker, UiMouseBlockerName,
    ViewerCamera, ViewerPalette, ViewerRenderConfig, ViewerRuntimeSavePath, ViewerRuntimeState,
    ViewerSceneKind, ViewerState, ViewerUiFont, ViewerUiSettings, ViewerUiSettingsPath,
    ViewerWindowResolution,
};
use crate::ui_context_menu::{context_menu_button_color, ContextMenuStyle, ContextMenuVariant};

const UI_PANEL_WIDTH: f32 = 448.0;
const INVENTORY_PANEL_WIDTH: f32 = 300.0;
const SKILLS_PANEL_WIDTH: f32 = 940.0;
const SCREEN_EDGE_PADDING: f32 = 18.0;
const LEFT_STAGE_PANEL_X: f32 = SCREEN_EDGE_PADDING;
const TOP_BADGE_WIDTH: f32 = 348.0;
const RIGHT_PANEL_TOP: f32 = 74.0;
const RIGHT_PANEL_BOTTOM: f32 = 174.0;
const RIGHT_PANEL_HEADER_HEIGHT: f32 = 44.0;
pub(crate) const HOTBAR_DOCK_WIDTH: f32 = 1088.0;
pub(crate) const HOTBAR_DOCK_HEIGHT: f32 = 76.0;
const HOTBAR_SLOT_SIZE: f32 = 45.0;
const BOTTOM_TAB_HEIGHT: f32 = 22.0;
const HOVER_TOOLTIP_MAX_WIDTH: f32 = 320.0;
const HOVER_TOOLTIP_CURSOR_OFFSET_X: f32 = 16.0;
const HOVER_TOOLTIP_CURSOR_OFFSET_Y: f32 = 16.0;
const HOVER_TOOLTIP_VIEWPORT_MARGIN: f32 = 8.0;

#[derive(Debug, Clone)]
struct PlayerHudStats {
    hp: f32,
    max_hp: f32,
    ap: f32,
    available_steps: i32,
}

#[derive(SystemParam)]
pub(crate) struct GameUiViewState<'w, 's> {
    runtime_state: Res<'w, ViewerRuntimeState>,
    scene_kind: Res<'w, ViewerSceneKind>,
    viewer_state: Res<'w, ViewerState>,
    menu_state: Res<'w, UiMenuState>,
    modal_state: Res<'w, UiModalState>,
    input_block_state: Res<'w, UiInputBlockState>,
    filter_state: Res<'w, UiInventoryFilterState>,
    hotbar_state: Res<'w, UiHotbarState>,
    settings: Res<'w, ViewerUiSettings>,
    hover_tooltip: Res<'w, UiHoverTooltipState>,
    inventory_context_menu: Res<'w, UiContextMenuState>,
    drag_state: Res<'w, UiInventoryDragState>,
    console_state: Res<'w, ViewerConsoleState>,
    marker: PhantomData<&'s ()>,
}

#[derive(SystemParam)]
pub(crate) struct GameUiCommandState<'w, 's> {
    runtime_state: ResMut<'w, ViewerRuntimeState>,
    scene_kind: ResMut<'w, ViewerSceneKind>,
    viewer_state: ResMut<'w, ViewerState>,
    menu_state: ResMut<'w, UiMenuState>,
    modal_state: ResMut<'w, UiModalState>,
    filter_state: ResMut<'w, UiInventoryFilterState>,
    hotbar_state: ResMut<'w, UiHotbarState>,
    settings: ResMut<'w, ViewerUiSettings>,
    inventory_context_menu: ResMut<'w, UiContextMenuState>,
    drag_state: ResMut<'w, UiInventoryDragState>,
    scrollbar_drag_state: ResMut<'w, UiInventoryScrollbarDragState>,
    hover_tooltip: ResMut<'w, UiHoverTooltipState>,
    picking_state: ResMut<'w, ViewerPickingState>,
    key_buttons: ResMut<'w, ButtonInput<KeyCode>>,
    mouse_buttons: ResMut<'w, ButtonInput<MouseButton>>,
    marker: PhantomData<&'s ()>,
}

#[derive(SystemParam)]
pub(crate) struct GameContentRefs<'w, 's> {
    items: Res<'w, ItemDefinitions>,
    effects: Res<'w, EffectDefinitions>,
    skills: Res<'w, SkillDefinitions>,
    skill_trees: Res<'w, SkillTreeDefinitions>,
    quests: Res<'w, QuestDefinitions>,
    recipes: Res<'w, RecipeDefinitions>,
    shops: Res<'w, ShopDefinitions>,
    overworld: Res<'w, OverworldDefinitions>,
    marker: PhantomData<&'s ()>,
}

mod container_ui;
mod hotbar;
mod input;
mod overlay;
mod panels;
mod settings;
mod state_sync;
#[cfg(test)]
mod tests;
mod trade_ui;
mod widgets;

use container_ui::*;
pub(super) use hotbar::*;
pub(super) use input::*;
pub(crate) use overlay::GameUiRetainedCache;
pub(super) use overlay::*;
use panels::*;
pub(super) use settings::*;
pub(super) use state_sync::*;
use trade_ui::*;
use widgets::*;
