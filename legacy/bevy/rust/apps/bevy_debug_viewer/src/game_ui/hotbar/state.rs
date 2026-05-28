//! 快捷栏状态同步：负责玩家快捷栏快照、技能组切换和面板联动状态刷新。

use game_bevy::{
    player_actor_id, SkillDefinitions, SkillTreeDefinitions, UiHotbarState, UiMenuState,
};

use crate::game_ui::state_sync::{find_skill_tree_id, skills_snapshot_for_player};
use crate::state::ViewerRuntimeState;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AutoHotbarSlotTarget {
    AlreadyBound(usize),
    Slot(usize),
}

pub(crate) fn sync_skill_selection_state(
    menu_state: &mut UiMenuState,
    runtime_state: &ViewerRuntimeState,
    skills: &SkillDefinitions,
    trees: &SkillTreeDefinitions,
) {
    let Some(snapshot) = skills_snapshot_for_player(runtime_state, skills, trees) else {
        menu_state.selected_skill_tree_id = None;
        menu_state.selected_skill_id = None;
        return;
    };

    let tree_from_selected_skill = menu_state
        .selected_skill_id
        .as_deref()
        .and_then(|skill_id| find_skill_tree_id(&snapshot, skill_id));
    let selected_tree = tree_from_selected_skill
        .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        .or_else(|| {
            menu_state
                .selected_skill_tree_id
                .as_deref()
                .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        })
        .or_else(|| snapshot.trees.iter().find(|tree| !tree.entries.is_empty()))
        .or_else(|| snapshot.trees.first());

    let Some(selected_tree) = selected_tree else {
        menu_state.selected_skill_tree_id = None;
        menu_state.selected_skill_id = None;
        return;
    };

    menu_state.selected_skill_tree_id = Some(selected_tree.tree_id.clone());
    let selected_skill_is_in_tree = menu_state
        .selected_skill_id
        .as_deref()
        .and_then(|skill_id| {
            selected_tree
                .entries
                .iter()
                .find(|entry| entry.skill_id == skill_id)
        })
        .is_some();
    if !selected_skill_is_in_tree {
        menu_state.selected_skill_id = selected_tree
            .entries
            .first()
            .map(|entry| entry.skill_id.clone());
    }
}

pub(crate) fn validate_hotbar_skill_binding(
    runtime_state: &ViewerRuntimeState,
    skills: &SkillDefinitions,
    skill_id: &str,
) -> Result<(), String> {
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return Err("missing_player".to_string());
    };
    let Some(skill) = skills.0.get(skill_id) else {
        return Err(format!("未知技能 {skill_id}"));
    };
    let learned_level = runtime_state
        .runtime
        .economy()
        .actor(actor_id)
        .and_then(|actor| actor.learned_skills.get(skill_id))
        .copied()
        .unwrap_or(0);
    if learned_level <= 0 {
        return Err(format!("{} 尚未学习", skill.name));
    }
    let activation_mode = skill
        .activation
        .as_ref()
        .map(|activation| activation.mode.as_str())
        .unwrap_or("passive");
    if activation_mode == "passive" {
        return Err(format!("{} 为被动技能，无法绑定快捷栏", skill.name));
    }
    Ok(())
}

pub(crate) fn assign_skill_to_hotbar_slot(
    hotbar_state: &mut UiHotbarState,
    menu_state: &mut UiMenuState,
    skill_id: String,
    group: usize,
    slot: usize,
) -> bool {
    let Some(group_slots) = hotbar_state.groups.get_mut(group) else {
        menu_state.status_text = format!("快捷栏第 {} 组不存在", group.saturating_add(1));
        return false;
    };
    let Some(slot_state) = group_slots.get_mut(slot) else {
        menu_state.status_text = format!(
            "快捷栏第 {} 组不存在第 {} 槽",
            group.saturating_add(1),
            slot.saturating_add(1)
        );
        return false;
    };

    slot_state.skill_id = Some(skill_id.clone());
    slot_state.cooldown_remaining = 0.0;
    slot_state.toggled = false;
    menu_state.status_text = format!(
        "已将 {skill_id} 绑定到第 {} 组第 {} 槽",
        group.saturating_add(1),
        slot.saturating_add(1)
    );
    true
}

pub(crate) fn resolve_auto_hotbar_slot_target(
    hotbar_state: &UiHotbarState,
    group: usize,
    skill_id: &str,
) -> Result<AutoHotbarSlotTarget, String> {
    let Some(group_slots) = hotbar_state.groups.get(group) else {
        return Err(format!("快捷栏第 {} 组不存在", group.saturating_add(1)));
    };

    if let Some(slot) = group_slots
        .iter()
        .position(|slot| slot.skill_id.as_deref() == Some(skill_id))
    {
        return Ok(AutoHotbarSlotTarget::AlreadyBound(slot));
    }

    if let Some(slot) = group_slots.iter().position(|slot| slot.skill_id.is_none()) {
        return Ok(AutoHotbarSlotTarget::Slot(slot));
    }

    Ok(AutoHotbarSlotTarget::Slot(
        group_slots.len().saturating_sub(1),
    ))
}
