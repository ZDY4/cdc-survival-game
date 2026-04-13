//! NPC 战斗桥接模块：负责把在线 life NPC 接入 runtime combat query/intent 执行链。

use bevy::prelude::*;
use game_bevy::{BehaviorProfile, NpcRuntimeAiMode, NpcRuntimeBridgeState, RuntimeActorLink};
use game_core::{
    resolve_combat_tactic_profile_id, select_combat_ai_intent_for_profile, CombatAiIntent,
    SimulationCommand,
};

use crate::state::{ViewerRuntimeState, ViewerSceneKind};

pub(crate) fn advance_online_npc_combat(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
    mut query: Query<(
        &RuntimeActorLink,
        Option<&BehaviorProfile>,
        &mut NpcRuntimeBridgeState,
    )>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        return;
    }

    let current_actor = runtime_state.runtime.current_actor();
    let in_combat = runtime_state.runtime.is_in_combat();

    for (runtime_link, behavior, mut runtime_bridge) in &mut query {
        if !in_combat || current_actor != Some(runtime_link.actor_id) {
            if runtime_bridge.ai_mode == NpcRuntimeAiMode::Combat {
                runtime_bridge.combat_target_actor_id = None;
                runtime_bridge.last_combat_intent = None;
                runtime_bridge.runtime_goal_grid = None;
            }
            continue;
        }

        if runtime_state.runtime.get_actor_side(runtime_link.actor_id)
            == Some(game_data::ActorSide::Player)
        {
            continue;
        }
        if !runtime_state.runtime.actor_in_combat(runtime_link.actor_id)
            || !runtime_state.runtime.actor_turn_open(runtime_link.actor_id)
        {
            continue;
        }

        runtime_bridge.ai_mode = NpcRuntimeAiMode::Combat;
        let tactical_profile_id =
            resolve_combat_tactic_profile_id(behavior.map(|behavior| behavior.0.as_str()).unwrap_or(""));

        let Some(snapshot) = runtime_state.runtime.query_combat_ai(runtime_link.actor_id) else {
            end_combat_turn_if_stuck(&mut runtime_state, runtime_link.actor_id);
            runtime_bridge.combat_target_actor_id = None;
            runtime_bridge.last_combat_intent =
                Some(format!("{tactical_profile_id}:no_combat_snapshot"));
            runtime_bridge.runtime_goal_grid = None;
            continue;
        };

        let Some(intent) = select_combat_ai_intent_for_profile(tactical_profile_id, &snapshot)
        else {
            end_combat_turn_if_stuck(&mut runtime_state, runtime_link.actor_id);
            runtime_bridge.combat_target_actor_id = None;
            runtime_bridge.last_combat_intent =
                Some(format!("{tactical_profile_id}:end_turn:no_available_intent"));
            runtime_bridge.runtime_goal_grid = None;
            continue;
        };

        runtime_bridge.combat_target_actor_id = Some(intent_target_actor(&intent));
        runtime_bridge.last_combat_intent =
            Some(format!("{tactical_profile_id}:{}", format_combat_intent(&intent)));
        runtime_bridge.runtime_goal_grid = intent_goal_grid(&intent);
        runtime_bridge.last_failure_reason = None;
        runtime_state
            .runtime
            .clear_actor_autonomous_movement_goal(runtime_link.actor_id);
        runtime_state
            .runtime
            .clear_actor_runtime_action_state(runtime_link.actor_id);

        let result = runtime_state
            .runtime
            .execute_combat_ai_intent(runtime_link.actor_id, intent);
        if !result.performed {
            end_combat_turn_if_stuck(&mut runtime_state, runtime_link.actor_id);
            runtime_bridge.last_failure_reason = Some("combat_intent_not_performed".to_string());
        }
    }
}

fn end_combat_turn_if_stuck(runtime_state: &mut ViewerRuntimeState, actor_id: game_data::ActorId) {
    let _ = runtime_state
        .runtime
        .submit_command(SimulationCommand::EndTurn { actor_id });
}

fn intent_target_actor(intent: &CombatAiIntent) -> game_data::ActorId {
    match intent {
        CombatAiIntent::UseSkill { target_actor, .. }
        | CombatAiIntent::Attack { target_actor }
        | CombatAiIntent::Approach { target_actor, .. } => *target_actor,
    }
}

fn intent_goal_grid(intent: &CombatAiIntent) -> Option<game_data::GridCoord> {
    match intent {
        CombatAiIntent::Approach { goal, .. } => Some(*goal),
        CombatAiIntent::UseSkill { .. } | CombatAiIntent::Attack { .. } => None,
    }
}

fn format_combat_intent(intent: &CombatAiIntent) -> String {
    match intent {
        CombatAiIntent::UseSkill {
            target_actor,
            skill_id,
        } => format!("skill:{skill_id}->{}", target_actor.0),
        CombatAiIntent::Attack { target_actor } => format!("attack->{}", target_actor.0),
        CombatAiIntent::Approach { target_actor, goal } => format!(
            "approach->{}@({}, {}, {})",
            target_actor.0, goal.x, goal.y, goal.z
        ),
    }
}
