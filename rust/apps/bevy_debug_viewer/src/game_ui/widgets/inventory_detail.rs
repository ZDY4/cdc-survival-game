//! 物品详情展示：构建文本内容并根据交互能力提供按钮行为提示。

use super::*;

#[derive(Debug, Clone)]
pub(in crate::game_ui) struct InventoryDetailDisplay {
    pub(in crate::game_ui) content: DetailTextContent,
    pub(in crate::game_ui) can_use: bool,
    pub(in crate::game_ui) can_equip: bool,
}

pub(in crate::game_ui) fn build_inventory_detail_display(
    detail: &game_bevy::UiInventoryDetailView,
    entry: Option<&game_bevy::UiInventoryEntryView>,
) -> InventoryDetailDisplay {
    let can_use = entry.map(|entry| entry.can_use).unwrap_or(false);
    let can_equip = entry.map(|entry| entry.can_equip).unwrap_or(false);
    let mut content = DetailTextContent::default();

    content.push(
        format!(
            "{} · {} x{}",
            detail.name,
            detail.item_type.as_str(),
            detail.count
        ),
        11.3,
        Color::WHITE,
    );
    content.push(
        format!("重量 {:.1}kg", detail.weight),
        10.1,
        ui_text_secondary_color(),
    );
    if !detail.description.trim().is_empty() {
        content.push(
            detail.description.clone(),
            10.1,
            ui_text_secondary_color(),
        );
    }
    if detail.attribute_bonuses.is_empty() {
        content.push("属性加成: 无", 10.0, ui_text_muted_color());
    } else {
        content.push("属性加成", 10.0, ui_text_muted_color());
        for (attribute, bonus) in &detail.attribute_bonuses {
            content.push(
                format!("{attribute} {bonus:+.1}"),
                10.0,
                ui_text_secondary_color(),
            );
        }
    }
    content.push(
        format!("操作: {}", inventory_capability_label(can_use, can_equip)),
        10.0,
        ui_text_muted_color(),
    );

    InventoryDetailDisplay {
        content,
        can_use,
        can_equip,
    }
}

pub(in crate::game_ui) fn inventory_capability_label(
    can_use: bool,
    can_equip: bool,
) -> &'static str {
    match (can_use, can_equip) {
        (true, true) => "可使用 / 可装备",
        (true, false) => "可使用",
        (false, true) => "可装备",
        (false, false) => "无可执行操作",
    }
}

pub(in crate::game_ui) fn render_inventory_detail_content(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    display: &InventoryDetailDisplay,
    show_actions: bool,
) {
    spawn_detail_text_content(parent, font, &display.content);

    if !show_actions {
        return;
    }

    parent
        .spawn(Node {
            width: Val::Percent(100.0),
            flex_direction: FlexDirection::Row,
            flex_wrap: FlexWrap::Wrap,
            column_gap: px(8),
            ..default()
        })
        .with_children(|actions| {
            if display.can_use {
                actions.spawn(action_button(
                    font,
                    "使用",
                    GameUiButtonAction::UseInventoryItem,
                ));
            }
            if display.can_equip {
                actions.spawn(action_button(
                    font,
                    "装备",
                    GameUiButtonAction::EquipInventoryItem,
                ));
            }
        });
}
