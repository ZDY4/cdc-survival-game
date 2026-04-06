//! 技能详情展示：负责技能详情内容拼装与详情区按钮渲染。

use super::*;

#[derive(Debug, Clone)]
pub(in crate::game_ui) struct SkillDetailDisplay {
    pub(in crate::game_ui) content: DetailTextContent,
    pub(in crate::game_ui) hotbar_eligible: bool,
}

pub(in crate::game_ui) fn build_skill_detail_display(
    tree: Option<&game_bevy::UiSkillTreeView>,
    entry: &game_bevy::UiSkillEntryView,
    hotbar_state: &UiHotbarState,
) -> SkillDetailDisplay {
    let current_group_fill = hotbar_state
        .groups
        .get(hotbar_state.active_group)
        .map(|group| group.iter().filter(|slot| slot.skill_id.is_some()).count())
        .unwrap_or(0);
    let mut content = DetailTextContent::default();

    if let Some(tree) = tree {
        content.push(
            tree.tree_name.clone(),
            12.0,
            ui_text_secondary_color(),
        );
        if !tree.tree_description.trim().is_empty() {
            content.push(
                tree.tree_description.clone(),
                10.0,
                ui_text_muted_color(),
            );
        }
    }

    content.push(entry.name.clone(), 14.0, Color::WHITE);
    content.push(
        format!(
            "等级 {}/{} · {} · 冷却 {:.1}s",
            entry.learned_level,
            entry.max_level,
            activation_mode_label(&entry.activation_mode),
            entry.cooldown_seconds
        ),
        10.8,
        ui_text_secondary_color(),
    );
    if !entry.description.trim().is_empty() {
        content.push(entry.description.clone(), 10.5, Color::WHITE);
    }
    content.push(
        format!("前置需求: {}", format_skill_prerequisites(entry)),
        10.0,
        ui_text_secondary_color(),
    );
    content.push(
        format!("属性需求: {}", format_skill_attribute_requirements(entry)),
        10.0,
        ui_text_secondary_color(),
    );
    content.push(
        format!(
            "当前快捷栏组 {} · 已占用 {}/10",
            hotbar_state.active_group + 1,
            current_group_fill
        ),
        10.0,
        ui_text_muted_color(),
    );
    if let Some(slot_index) = current_group_skill_slot(hotbar_state, &entry.skill_id) {
        content.push(
            format!("当前组已绑定到第 {} 槽", slot_index + 1),
            10.0,
            Color::srgba(0.90, 0.80, 0.58, 1.0),
        );
    }
    content.push(
        if entry.hotbar_eligible {
            "快捷栏: 可加入当前组，满时替换最后槽"
        } else if entry.learned_level > 0 {
            "快捷栏: 该技能当前不进入快捷栏"
        } else {
            "快捷栏: 尚未学习，暂时不能加入快捷栏"
        },
        10.0,
        ui_text_muted_color(),
    );

    SkillDetailDisplay {
        content,
        hotbar_eligible: entry.hotbar_eligible,
    }
}

pub(in crate::game_ui) fn render_skill_detail_content(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    display: &SkillDetailDisplay,
    entry: &game_bevy::UiSkillEntryView,
    show_actions: bool,
) {
    spawn_detail_text_content(parent, font, &display.content);

    if show_actions && display.hotbar_eligible {
        parent.spawn(action_button(
            font,
            "加入当前组",
            GameUiButtonAction::AssignSkillToFirstEmptyHotbarSlot(entry.skill_id.clone()),
        ));
    }
}
