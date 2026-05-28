//! 快捷栏门面：统一组织激活逻辑、冷却推进、状态同步与多种底栏渲染入口。

use super::*;

mod activation;
mod rendering;
mod state;

pub(crate) use activation::{activate_hotbar_slot, tick_hotbar_cooldowns};
pub(crate) use rendering::render_hotbar;
pub(crate) use state::{
    assign_skill_to_hotbar_slot, resolve_auto_hotbar_slot_target, sync_skill_selection_state,
    validate_hotbar_skill_binding, AutoHotbarSlotTarget,
};
