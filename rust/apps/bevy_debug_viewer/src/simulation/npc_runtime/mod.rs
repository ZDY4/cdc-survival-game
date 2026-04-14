//! 在线 NPC runtime 适配模块。
//! 负责汇总 presence、life action 与 combat bridge 适配层，不定义新的 AI 规则语义。

mod background_state;
mod combat_bridge;
mod helpers;
mod life_actions;
mod presence_sync;

pub(super) use background_state::{build_background_state, quantize_need};
pub(crate) use combat_bridge::advance_online_npc_combat;
pub(super) use helpers::{resolve_anchor_grid, resolve_reachable_runtime_grid};
pub(crate) use life_actions::advance_online_npc_actions;
pub(crate) use presence_sync::sync_npc_runtime_presence;
