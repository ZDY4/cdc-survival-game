//! NPC life 战斗状态同步系统。
//! 负责在共享 life 域中归一化 combat bridge 状态，不负责执行具体战斗 AI。

use bevy_ecs::prelude::*;
use game_core::NpcExecutionMode;

use super::super::components::{NpcLifeState, NpcRuntimeAiMode, NpcRuntimeBridgeState};

pub(super) fn refresh_npc_runtime_bridge_state_system(
    mut query: Query<(&NpcLifeState, &mut NpcRuntimeBridgeState)>,
) {
    for (life, mut runtime_bridge) in &mut query {
        if !life.online || runtime_bridge.execution_mode == NpcExecutionMode::Background {
            runtime_bridge.ai_mode = NpcRuntimeAiMode::Life;
            runtime_bridge.combat_alert_active = false;
            runtime_bridge.combat_replan_required = false;
            runtime_bridge.combat_threat_actor_id = None;
            runtime_bridge.combat_target_actor_id = None;
            runtime_bridge.last_combat_target_actor_id = None;
            runtime_bridge.last_combat_intent = None;
            runtime_bridge.last_combat_outcome = None;
            runtime_bridge.runtime_goal_grid = None;
            runtime_bridge.actor_hp_ratio = None;
            runtime_bridge.attack_ap_cost = None;
            runtime_bridge.target_hp_ratio = None;
            runtime_bridge.approach_distance_steps = None;
            runtime_bridge.last_damage_taken = None;
            runtime_bridge.last_damage_dealt = None;
            runtime_bridge.last_failure_reason = None;
        }
    }
}
