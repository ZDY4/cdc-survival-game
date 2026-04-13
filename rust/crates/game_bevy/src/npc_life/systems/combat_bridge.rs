use bevy_ecs::prelude::*;
use game_core::NpcExecutionMode;

use super::super::{NpcLifeState, NpcRuntimeAiMode, NpcRuntimeBridgeState};

pub(super) fn refresh_npc_runtime_bridge_state_system(
    mut query: Query<(&NpcLifeState, &mut NpcRuntimeBridgeState)>,
) {
    for (life, mut runtime_bridge) in &mut query {
        // The executable combat bridge lives in app/runtime integration layers that own
        // SimulationRuntime. Shared npc_life only normalizes bridge state for debug/UI.
        if !life.online || runtime_bridge.execution_mode == NpcExecutionMode::Background {
            runtime_bridge.ai_mode = NpcRuntimeAiMode::Life;
            runtime_bridge.combat_target_actor_id = None;
            runtime_bridge.last_combat_intent = None;
        }
    }
}
