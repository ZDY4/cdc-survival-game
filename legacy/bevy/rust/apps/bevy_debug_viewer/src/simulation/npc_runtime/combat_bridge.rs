//! 在线 NPC 战斗桥接模块。
//! 负责 viewer 侧 online NPC 与共享战斗 runtime 的状态同步，不定义新的战斗语义。

use bevy::prelude::*;
use game_bevy::{
    BehaviorProfile, NpcLifeState, NpcRuntimeAiMode, NpcRuntimeBridgeState, RuntimeActorLink,
};
use game_core::{
    resolve_combat_tactic_profile_id, select_combat_ai_intent_for_profile, CombatAiIntent,
    CombatAiSnapshot, SimulationCommand,
};

use crate::state::{ViewerRuntimeState, ViewerSceneKind};

pub(crate) fn advance_online_npc_combat(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
    mut query: Query<(
        &RuntimeActorLink,
        Option<&BehaviorProfile>,
        Option<&mut NpcLifeState>,
        &mut NpcRuntimeBridgeState,
    )>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        return;
    }

    let current_actor = runtime_state.runtime.current_actor();
    let in_combat = runtime_state.runtime.is_in_combat();

    for (runtime_link, behavior, life, mut runtime_bridge) in &mut query {
        let actor_in_combat =
            in_combat && runtime_state.runtime.actor_in_combat(runtime_link.actor_id);
        if !actor_in_combat {
            if runtime_bridge.ai_mode == NpcRuntimeAiMode::Combat {
                finalize_combat_exit(life, &mut runtime_bridge);
            } else {
                runtime_bridge.combat_target_actor_id = None;
                runtime_bridge.runtime_goal_grid = None;
            }
            continue;
        }

        if runtime_state.runtime.get_actor_side(runtime_link.actor_id)
            == Some(game_data::ActorSide::Player)
        {
            continue;
        }

        runtime_bridge.ai_mode = NpcRuntimeAiMode::Combat;
        runtime_bridge.combat_alert_active = true;
        if current_actor != Some(runtime_link.actor_id) {
            runtime_bridge.combat_target_actor_id = None;
            runtime_bridge.runtime_goal_grid = None;
            continue;
        }

        if !runtime_state.runtime.actor_turn_open(runtime_link.actor_id) {
            continue;
        }

        let tactical_profile_id = selected_profile_id(
            &runtime_state,
            runtime_link.actor_id,
            behavior.map(|behavior| behavior.0.as_str()),
        );

        let Some(snapshot) = runtime_state.runtime.query_combat_ai(runtime_link.actor_id) else {
            end_combat_turn_if_stuck(&mut runtime_state, runtime_link.actor_id);
            runtime_bridge.combat_target_actor_id = None;
            runtime_bridge.runtime_goal_grid = None;
            runtime_bridge.last_combat_outcome = Some("no_combat_snapshot".to_string());
            runtime_bridge.last_combat_intent =
                Some(format!("{tactical_profile_id}:no_combat_snapshot"));
            continue;
        };

        update_snapshot_metrics(&runtime_state, &snapshot, &mut runtime_bridge);
        runtime_bridge.combat_threat_actor_id = highest_threat_actor_id(&snapshot);
        if runtime_bridge.last_combat_outcome.is_none() {
            runtime_bridge.last_combat_outcome = Some("entered_combat".to_string());
        }

        let Some(intent) = select_combat_ai_intent_for_profile(tactical_profile_id, &snapshot)
        else {
            end_combat_turn_if_stuck(&mut runtime_state, runtime_link.actor_id);
            runtime_bridge.combat_target_actor_id = None;
            runtime_bridge.target_hp_ratio = None;
            runtime_bridge.approach_distance_steps = None;
            runtime_bridge.runtime_goal_grid = None;
            runtime_bridge.last_combat_outcome = Some("no_available_intent".to_string());
            runtime_bridge.last_combat_intent = Some(format!(
                "{tactical_profile_id}:end_turn:no_available_intent"
            ));
            continue;
        };

        let intent_target = intent_target_actor(&intent);
        let target_context = snapshot
            .target_options
            .iter()
            .find(|option| option.target_actor_id == intent_target);
        runtime_bridge.combat_target_actor_id = Some(intent_target);
        runtime_bridge.last_combat_target_actor_id = Some(intent_target);
        runtime_bridge.target_hp_ratio = target_context.map(|option| option.target_hp_ratio);
        runtime_bridge.approach_distance_steps =
            target_context.and_then(|option| option.approach_distance_steps);
        runtime_bridge.last_combat_intent = Some(format!(
            "{tactical_profile_id}:{}",
            format_combat_intent(&intent)
        ));
        runtime_bridge.runtime_goal_grid = intent_goal_grid(&intent);
        runtime_bridge.last_failure_reason = None;
        runtime_state
            .runtime
            .clear_actor_autonomous_movement_goal(runtime_link.actor_id);
        runtime_state
            .runtime
            .clear_actor_runtime_action_state(runtime_link.actor_id);

        let actor_hp_before = runtime_state
            .runtime
            .get_actor_hit_points(runtime_link.actor_id);
        let target_hp_before = runtime_state.runtime.get_actor_hit_points(intent_target);
        let result = runtime_state
            .runtime
            .execute_combat_ai_intent(runtime_link.actor_id, intent.clone());
        let actor_hp_after = runtime_state
            .runtime
            .get_actor_hit_points(runtime_link.actor_id);
        let target_hp_after = runtime_state.runtime.get_actor_hit_points(intent_target);

        if actor_hp_after < actor_hp_before {
            runtime_bridge.last_damage_taken = Some(actor_hp_before - actor_hp_after);
        }
        if target_hp_after < target_hp_before {
            runtime_bridge.last_damage_dealt = Some(target_hp_before - target_hp_after);
        }

        if !result.performed {
            end_combat_turn_if_stuck(&mut runtime_state, runtime_link.actor_id);
            runtime_bridge.last_failure_reason = Some("combat_intent_not_performed".to_string());
            runtime_bridge.last_combat_outcome = Some("combat_intent_not_performed".to_string());
            continue;
        }

        runtime_bridge.last_combat_outcome = Some(match intent {
            CombatAiIntent::UseSkill { .. } => "used_skill".to_string(),
            CombatAiIntent::Attack { .. } => "performed_attack".to_string(),
            CombatAiIntent::Approach { .. } => "approached_target".to_string(),
            CombatAiIntent::Retreat { .. } => "retreated_to_cover".to_string(),
        });
    }
}

fn finalize_combat_exit(
    life: Option<Mut<'_, NpcLifeState>>,
    runtime_bridge: &mut NpcRuntimeBridgeState,
) {
    runtime_bridge.ai_mode = NpcRuntimeAiMode::Life;
    runtime_bridge.combat_target_actor_id = None;
    runtime_bridge.runtime_goal_grid = None;
    runtime_bridge.combat_replan_required = true;
    runtime_bridge.combat_alert_active = true;
    runtime_bridge.last_combat_outcome = Some("combat_finished".to_string());
    if let Some(mut life) = life {
        life.replan_required = true;
    }
}

fn update_snapshot_metrics(
    runtime_state: &ViewerRuntimeState,
    snapshot: &CombatAiSnapshot,
    runtime_bridge: &mut NpcRuntimeBridgeState,
) {
    if let Some(previous_ratio) = runtime_bridge.actor_hp_ratio {
        if snapshot.actor_hp_ratio < previous_ratio {
            let max_hp = runtime_state
                .runtime
                .get_actor_max_hit_points(snapshot.actor_id);
            runtime_bridge.last_damage_taken =
                Some((previous_ratio - snapshot.actor_hp_ratio) * max_hp);
        }
    }
    runtime_bridge.actor_hp_ratio = Some(snapshot.actor_hp_ratio);
    runtime_bridge.attack_ap_cost = Some(snapshot.attack_ap_cost);
}

fn selected_profile_id(
    runtime_state: &ViewerRuntimeState,
    actor_id: game_data::ActorId,
    component_behavior: Option<&str>,
) -> &'static str {
    let behavior = component_behavior.or_else(|| {
        runtime_state
            .runtime
            .get_actor_combat_behavior_profile(actor_id)
    });
    resolve_combat_tactic_profile_id(behavior.unwrap_or(""))
}

fn highest_threat_actor_id(snapshot: &CombatAiSnapshot) -> Option<game_data::ActorId> {
    snapshot
        .target_options
        .iter()
        .max_by(|left, right| {
            left.threat_score
                .cmp(&right.threat_score)
                .then_with(|| right.distance_score.cmp(&left.distance_score))
        })
        .map(|option| option.target_actor_id)
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
        | CombatAiIntent::Approach { target_actor, .. }
        | CombatAiIntent::Retreat { target_actor, .. } => *target_actor,
    }
}

fn intent_goal_grid(intent: &CombatAiIntent) -> Option<game_data::GridCoord> {
    match intent {
        CombatAiIntent::Approach { goal, .. } | CombatAiIntent::Retreat { goal, .. } => Some(*goal),
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
        CombatAiIntent::Retreat { target_actor, goal } => format!(
            "retreat<-{}@({}, {}, {})",
            target_actor.0, goal.x, goal.y, goal.z
        ),
    }
}
