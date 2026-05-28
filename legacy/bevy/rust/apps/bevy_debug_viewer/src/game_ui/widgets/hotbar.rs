//! 技能树与快捷栏 helper：负责技能名称、快捷键和技能树选择辅助逻辑。

use super::*;

pub(in crate::game_ui) fn activation_mode_label(mode: &str) -> String {
    match mode {
        "passive" => "被动".to_string(),
        "toggle" => "开关".to_string(),
        "active" => "主动".to_string(),
        "instant" => "瞬发".to_string(),
        "channeled" => "引导".to_string(),
        other => other.to_string(),
    }
}

pub(in crate::game_ui) fn truncate_ui_text(text: &str, max_chars: usize) -> String {
    let trimmed = text.trim();
    let total_chars = trimmed.chars().count();
    if total_chars <= max_chars {
        return trimmed.to_string();
    }
    let visible = max_chars.saturating_sub(1);
    let prefix = trimmed.chars().take(visible).collect::<String>();
    format!("{prefix}…")
}

pub(in crate::game_ui) fn compact_skill_name(name: &str, max_chars: usize) -> String {
    truncate_ui_text(name, max_chars)
}

pub(in crate::game_ui) fn abbreviated_skill_name(name: &str) -> String {
    let initials = name
        .split(|ch: char| ch.is_whitespace() || ch == '_' || ch == '-')
        .filter(|part| !part.is_empty())
        .filter_map(|part| part.chars().next())
        .take(2)
        .collect::<String>()
        .to_uppercase();
    if !initials.is_empty() {
        return initials;
    }
    let fallback = name.trim();
    if fallback.is_empty() {
        "·".to_string()
    } else {
        fallback.chars().take(2).collect::<String>().to_uppercase()
    }
}

pub(in crate::game_ui) fn hotbar_key_label(slot_index: usize) -> &'static str {
    match slot_index {
        0 => "1",
        1 => "2",
        2 => "3",
        3 => "4",
        4 => "5",
        5 => "6",
        6 => "7",
        7 => "8",
        8 => "9",
        9 => "0",
        _ => "?",
    }
}

pub(in crate::game_ui) fn skill_tree_progress(tree: &game_bevy::UiSkillTreeView) -> (usize, usize) {
    let learned = tree
        .entries
        .iter()
        .filter(|entry| entry.learned_level > 0)
        .count();
    (learned, tree.entries.len())
}

pub(in crate::game_ui) fn selected_skill_tree<'a>(
    snapshot: &'a game_bevy::UiSkillsSnapshot,
    menu_state: &UiMenuState,
) -> Option<&'a game_bevy::UiSkillTreeView> {
    menu_state
        .selected_skill_tree_id
        .as_deref()
        .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        .or_else(|| {
            menu_state
                .selected_skill_id
                .as_deref()
                .and_then(|skill_id| find_skill_tree_id(snapshot, skill_id))
                .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        })
        .or_else(|| snapshot.trees.iter().find(|tree| !tree.entries.is_empty()))
        .or_else(|| snapshot.trees.first())
}

pub(in crate::game_ui) fn selected_skill_entry<'a>(
    tree: &'a game_bevy::UiSkillTreeView,
    selected_skill_id: Option<&str>,
) -> Option<&'a game_bevy::UiSkillEntryView> {
    selected_skill_id
        .and_then(|skill_id| tree.entries.iter().find(|entry| entry.skill_id == skill_id))
        .or_else(|| tree.entries.first())
}

pub(in crate::game_ui) fn current_group_skill_slot(
    hotbar_state: &UiHotbarState,
    skill_id: &str,
) -> Option<usize> {
    hotbar_state
        .groups
        .get(hotbar_state.active_group)
        .and_then(|group| {
            group
                .iter()
                .position(|slot| slot.skill_id.as_deref() == Some(skill_id))
        })
}

pub(in crate::game_ui) fn format_skill_prerequisites(
    entry: &game_bevy::UiSkillEntryView,
) -> String {
    if entry.prerequisite_names.is_empty() {
        "无".to_string()
    } else {
        entry.prerequisite_names.join(" · ")
    }
}

pub(in crate::game_ui) fn format_skill_attribute_requirements(
    entry: &game_bevy::UiSkillEntryView,
) -> String {
    if entry.attribute_requirements.is_empty() {
        "无".to_string()
    } else {
        entry
            .attribute_requirements
            .iter()
            .map(|(attribute, value)| format!("{attribute} {value}"))
            .collect::<Vec<_>>()
            .join(" · ")
    }
}
