//! 游戏内调试面板：提供可点击 console 命令和常用作弊入口。

use bevy::input::keyboard::{Key, KeyboardInput};
use bevy::input::ButtonState;
use bevy::log::{info, warn};
use bevy::prelude::*;
use bevy::ui::{FocusPolicy, RelativeCursorPosition};
use game_bevy::{
    player_actor_id, ItemDefinitions, MapAiSpawnRuntimeState, SettlementContext,
    SmartObjectReservations, WorldAlertState,
};

use crate::console::{execute_console_command, ConsoleFeedback, CONSOLE_COMMANDS};
use crate::state::{
    viewer_ui_passthrough_bundle, UiMouseBlocker, UiMouseBlockerName, ViewerActorFeedbackState,
    ViewerActorMotionState, ViewerCameraShakeState, ViewerDamageNumberState, ViewerInfoPanelState,
    ViewerPalette, ViewerRuntimeSavePath, ViewerRuntimeState, ViewerState, ViewerUiFont,
};

mod actions;
mod state;
mod ui;

pub(crate) use actions::{
    handle_debug_panel_buttons, handle_debug_panel_keyboard_input, toggle_debug_panel,
};
pub(crate) use state::ViewerDebugPanelState;
use state::{
    DebugPanelBodyRoot, DebugPanelButtonAction, DebugPanelFeedback, DebugPanelRoot, DebugPanelTab,
    DebugPanelTextFocus,
};
pub(crate) use ui::{spawn_debug_panel, update_debug_panel};

const PANEL_LEFT_PX: f32 = 14.0;
const PANEL_TOP_PX: f32 = 70.0;
const PANEL_BOTTOM_PX: f32 = 126.0;
const PANEL_WIDTH_PX: f32 = 390.0;
const PANEL_PADDING_PX: f32 = 12.0;
const PANEL_GAP_PX: f32 = 8.0;
const DEBUG_PANEL_MAX_ITEM_ROWS: usize = 12;
