//! 快捷栏激活逻辑：负责数字键槽位触发、技能目标请求和快捷栏动作分发。

use bevy::prelude::*;
use game_bevy::{player_actor_id, SkillDefinitions, UiHotbarState};

use crate::controls::enter_skill_targeting;
use crate::state::{ViewerRuntimeState, ViewerState};

pub(crate) fn tick_hotbar_cooldowns(
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut hotbar: ResMut<UiHotbarState>,
) {
    runtime_state
        .runtime
        .advance_skill_timers(time.delta_secs());
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return;
    };

    for group in &mut hotbar.groups {
        for slot in group {
            if let Some(skill_id) = slot.skill_id.as_deref() {
                slot.cooldown_remaining = runtime_state
                    .runtime
                    .skill_cooldown_remaining(actor_id, skill_id);
                slot.toggled = runtime_state
                    .runtime
                    .is_skill_toggled_active(actor_id, skill_id);
            } else {
                slot.cooldown_remaining = 0.0;
                slot.toggled = false;
            }
        }
    }
}

pub(crate) fn activate_hotbar_slot(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    skills: &SkillDefinitions,
    hotbar_state: &mut UiHotbarState,
    slot: usize,
) {
    let Some(group) = hotbar_state.groups.get_mut(hotbar_state.active_group) else {
        return;
    };
    let Some(slot_state) = group.get_mut(slot) else {
        return;
    };
    let Some(skill_id) = slot_state.skill_id.clone() else {
        hotbar_state.last_activation_status = Some(format!("槽位 {} 为空", slot + 1));
        return;
    };
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return;
    };
    let runtime_skill_state = runtime_state.runtime.skill_state(actor_id, &skill_id);
    if runtime_skill_state.cooldown_remaining > 0.0 {
        hotbar_state.last_activation_status = Some(format!(
            "{} 冷却中 {:.1}s",
            skill_id, runtime_skill_state.cooldown_remaining
        ));
        return;
    }
    let learned_level = runtime_state
        .runtime
        .economy()
        .actor(actor_id)
        .and_then(|actor| actor.learned_skills.get(&skill_id))
        .copied()
        .unwrap_or(0);
    if learned_level <= 0 {
        hotbar_state.last_activation_status = Some(format!("{skill_id} 尚未学习"));
        return;
    }
    if let Some(skill) = skills.0.get(&skill_id) {
        if let Some(activation) = skill.activation.as_ref() {
            if activation
                .targeting
                .as_ref()
                .is_some_and(|targeting| targeting.enabled)
            {
                match enter_skill_targeting(
                    runtime_state,
                    viewer_state,
                    skills,
                    &skill_id,
                    crate::state::ViewerTargetingSource::HotbarSlot(slot),
                ) {
                    Ok(()) => {
                        hotbar_state.last_activation_status =
                            Some(format!("{}: 选择目标", skill.name));
                    }
                    Err(error) => {
                        hotbar_state.last_activation_status = Some(error);
                    }
                }
            } else {
                let actor_grid = runtime_state
                    .runtime
                    .get_actor_grid_position(actor_id)
                    .unwrap_or_default();
                let result = runtime_state.runtime.activate_skill(
                    actor_id,
                    &skill_id,
                    game_data::SkillTargetRequest::Grid(actor_grid),
                );
                slot_state.cooldown_remaining = runtime_state
                    .runtime
                    .skill_cooldown_remaining(actor_id, &skill_id);
                slot_state.toggled = runtime_state
                    .runtime
                    .is_skill_toggled_active(actor_id, &skill_id);
                hotbar_state.last_activation_status = Some(if result.action_result.success {
                    format!(
                        "{}: {}",
                        skill.name,
                        game_core::runtime::action_result_status(&result.action_result)
                    )
                } else {
                    format!(
                        "{}: {}",
                        skill.name,
                        result
                            .failure_reason
                            .clone()
                            .or(result.action_result.reason.clone())
                            .unwrap_or_else(|| "failed".to_string())
                    )
                });
            }
        } else {
            hotbar_state.last_activation_status = Some(format!("{} 无主动效果", skill.name));
        }
    }
}
