//! UI 浮层细节模块：负责 tooltip、背包/技能右键菜单及其通用浮动容器。

use super::*;
use crate::ui_context_menu::{
    context_menu_header_text_bundle, context_menu_muted_text_color, spawn_context_menu_button,
    spawn_context_menu_shell, ContextMenuItemVisual, ContextMenuStyle, ContextMenuVariant,
};

pub(super) fn render_hover_tooltip(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    player_actor: Option<ActorId>,
    ui: &GameUiViewState<'_, '_>,
    content: &GameContentRefs<'_, '_>,
) {
    let Some(tooltip_content) = ui.hover_tooltip.content.as_ref() else {
        return;
    };

    match tooltip_content {
        UiHoverTooltipContent::InventoryItem { item_id } => {
            let Some(player_actor) = player_actor else {
                return;
            };
            let snapshot = inventory_snapshot(
                &ui.runtime_state.runtime,
                player_actor,
                &content.items.0,
                ui.filter_state.filter,
                Some(*item_id),
            );
            let Some(detail) = snapshot.detail.as_ref() else {
                return;
            };
            let inventory_entry = snapshot
                .entries
                .iter()
                .find(|entry| entry.item_id == *item_id);
            let (fallback_detail, fallback_entry) = if inventory_entry.is_some() {
                (None, None)
            } else {
                let Some(definition) = content.items.0.get(*item_id) else {
                    return;
                };
                let ammo_ids = game_bevy::ammo_item_ids(&content.items.0);
                let item_type = game_bevy::classify_item(definition, &ammo_ids);
                (
                    Some(game_bevy::UiInventoryDetailView {
                        item_id: *item_id,
                        name: definition.name.clone(),
                        description: definition.description.clone(),
                        count: 1,
                        item_type,
                        weight: definition.weight,
                        attribute_bonuses: game_bevy::item_attribute_bonuses(definition),
                    }),
                    Some(game_bevy::UiInventoryEntryView {
                        item_id: *item_id,
                        display_index: 0,
                        name: definition.name.clone(),
                        count: 1,
                        item_type,
                        total_weight: definition.weight,
                        can_use: game_bevy::item_usable(definition),
                        can_equip: game_bevy::item_equippable(definition),
                    }),
                )
            };
            let detail = fallback_detail.as_ref().unwrap_or(detail);
            let entry = inventory_entry.or(fallback_entry.as_ref());
            let display = build_inventory_detail_display(detail, entry);
            render_tooltip_container(
                parent,
                window,
                ui.hover_tooltip.cursor_position,
                display.content.estimated_height(),
                |tooltip| render_inventory_detail_content(tooltip, font, &display, false),
            );
        }
        UiHoverTooltipContent::Skill { tree_id, skill_id } => {
            let Some(player_actor) = player_actor else {
                return;
            };
            let snapshot = skills_snapshot(
                &ui.runtime_state.runtime,
                player_actor,
                &content.skills.0,
                &content.skill_trees.0,
            );
            let Some(tree) = snapshot.trees.iter().find(|tree| tree.tree_id == *tree_id) else {
                return;
            };
            let Some(entry) = tree
                .entries
                .iter()
                .find(|entry| entry.skill_id == *skill_id)
            else {
                return;
            };
            let display = build_skill_detail_display(Some(tree), entry, &ui.hotbar_state);
            render_tooltip_container(
                parent,
                window,
                ui.hover_tooltip.cursor_position,
                display.content.estimated_height(),
                |tooltip| render_skill_detail_content(tooltip, font, &display, entry, false),
            );
        }
        UiHoverTooltipContent::SceneTransition { target_name } => {
            render_tooltip_container(
                parent,
                window,
                ui.hover_tooltip.cursor_position,
                56.0,
                |tooltip| {
                    tooltip.spawn(text_bundle(font, "前往", 10.0, ui_text_muted_color()));
                    tooltip.spawn(text_bundle(font, target_name, 14.0, Color::WHITE));
                },
            );
        }
    }
}

pub(super) fn render_inventory_context_menu(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    player_actor: Option<ActorId>,
    ui: &GameUiViewState<'_, '_>,
    content: &GameContentRefs<'_, '_>,
) {
    let trade_state = ui.modal_state.trade.as_ref();
    let trade_active = trade_state.is_some();
    let skills_panel_active = ui.menu_state.is_panel_open(UiMenuPanel::Skills);
    if !trade_active && !ui.menu_state.is_panel_open(UiMenuPanel::Inventory) && !skills_panel_active
    {
        return;
    }
    let Some(player_actor) = player_actor else {
        return;
    };
    let Some(target) = ui.inventory_context_menu.target.as_ref() else {
        return;
    };

    match target {
        UiContextMenuTarget::InventoryItem { item_id } => {
            let snapshot = inventory_snapshot(
                &ui.runtime_state.runtime,
                player_actor,
                &content.items.0,
                ui.filter_state.filter,
                Some(*item_id),
            );
            let Some(detail) = snapshot.detail.as_ref() else {
                return;
            };
            let Some(entry) = snapshot
                .entries
                .iter()
                .find(|entry| entry.item_id == *item_id)
            else {
                return;
            };
            let display = build_inventory_detail_display(detail, Some(entry));
            let actions = inventory_context_menu_actions(
                trade_state.map(|trade| trade.shop_id.as_str()),
                *item_id,
                display.can_use,
                display.can_equip,
                detail.count,
            );
            render_ui_context_menu_container(
                parent,
                font,
                window,
                ui.inventory_context_menu.cursor_position,
                context_menu_estimated_height(actions.len(), true),
                |menu| {
                    spawn_ui_context_menu_header(
                        menu,
                        font,
                        "操作",
                        &detail.name,
                        &format!("{} · x{}", detail.item_type.as_str(), detail.count),
                    );
                    for (label, action) in actions {
                        spawn_context_menu_button(
                            menu,
                            font,
                            ContextMenuStyle::for_variant(ContextMenuVariant::UiContext),
                            &ContextMenuItemVisual {
                                label: label.to_string(),
                                is_primary: false,
                                is_disabled: false,
                            },
                            action,
                        );
                    }
                },
            );
        }
        UiContextMenuTarget::EquipmentSlot { slot_id, item_id } => {
            let snapshot = inventory_snapshot(
                &ui.runtime_state.runtime,
                player_actor,
                &content.items.0,
                ui.filter_state.filter,
                None,
            );
            let slot_name = snapshot
                .equipment
                .iter()
                .find(|slot| slot.slot_id == *slot_id)
                .and_then(|slot| slot.item_name.clone())
                .unwrap_or_else(|| item_id.to_string());
            let actions = equipment_context_menu_actions(
                trade_state.map(|trade| trade.shop_id.as_str()),
                slot_id,
            );
            render_ui_context_menu_container(
                parent,
                font,
                window,
                ui.inventory_context_menu.cursor_position,
                context_menu_estimated_height(actions.len(), true),
                |menu| {
                    spawn_ui_context_menu_header(
                        menu,
                        font,
                        "操作",
                        &slot_name,
                        &format!("装备槽: {slot_id}"),
                    );
                    for (label, action) in actions {
                        spawn_context_menu_button(
                            menu,
                            font,
                            ContextMenuStyle::for_variant(ContextMenuVariant::UiContext),
                            &ContextMenuItemVisual {
                                label: label.to_string(),
                                is_primary: false,
                                is_disabled: false,
                            },
                            action,
                        );
                    }
                },
            );
        }
        UiContextMenuTarget::SkillEntry { tree_id, skill_id } => {
            let snapshot = skills_snapshot(
                &ui.runtime_state.runtime,
                player_actor,
                &content.skills.0,
                &content.skill_trees.0,
            );
            let Some(tree) = snapshot.trees.iter().find(|tree| tree.tree_id == *tree_id) else {
                return;
            };
            let Some(entry) = tree
                .entries
                .iter()
                .find(|entry| entry.skill_id == *skill_id)
            else {
                return;
            };
            let can_bind =
                validate_hotbar_skill_binding(&ui.runtime_state, &content.skills, skill_id).is_ok();
            let actions = skill_context_menu_actions(skill_id, can_bind);
            render_ui_context_menu_container(
                parent,
                font,
                window,
                ui.inventory_context_menu.cursor_position,
                context_menu_estimated_height(actions.len(), true),
                |menu| {
                    spawn_ui_context_menu_header(
                        menu,
                        font,
                        "操作",
                        &entry.name,
                        &format!(
                            "{} · Lv {}/{}",
                            activation_mode_label(&entry.activation_mode),
                            entry.learned_level,
                            entry.max_level
                        ),
                    );
                    for (item, action) in actions {
                        spawn_context_menu_button(
                            menu,
                            font,
                            ContextMenuStyle::for_variant(ContextMenuVariant::UiContext),
                            &item,
                            action,
                        );
                    }
                },
            );
        }
    }
}

fn spawn_ui_context_menu_header(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    kicker: &str,
    title: &str,
    subtitle: &str,
) {
    let style = ContextMenuStyle::for_variant(ContextMenuVariant::UiContext);
    parent.spawn(context_menu_header_text_bundle(
        font,
        kicker,
        style.title_font_size,
        ui_text_secondary_color(),
    ));
    parent.spawn(context_menu_header_text_bundle(
        font,
        title,
        11.5,
        Color::WHITE,
    ));
    parent.spawn(context_menu_header_text_bundle(
        font,
        subtitle,
        style.subtitle_font_size,
        context_menu_muted_text_color(),
    ));
}

pub(super) fn inventory_context_menu_actions(
    trade_shop_id: Option<&str>,
    item_id: u32,
    can_use: bool,
    can_equip: bool,
    count: i32,
) -> Vec<(&'static str, GameUiButtonAction)> {
    let mut actions = Vec::new();
    if let Some(shop_id) = trade_shop_id {
        if can_equip {
            actions.push(("装备", GameUiButtonAction::EquipInventoryItem));
        }
        if count > 0 {
            actions.push((
                "卖出",
                GameUiButtonAction::SellTradeItem {
                    shop_id: shop_id.to_string(),
                    item_id,
                },
            ));
        }
        return actions;
    }
    if can_use {
        actions.push(("使用", GameUiButtonAction::UseInventoryItem));
    }
    if can_equip {
        actions.push(("装备", GameUiButtonAction::EquipInventoryItem));
    }
    if count > 0 {
        actions.push(("丢弃", GameUiButtonAction::DropInventoryItem));
    }
    actions
}

pub(super) fn equipment_context_menu_actions(
    trade_shop_id: Option<&str>,
    slot_id: &str,
) -> Vec<(&'static str, GameUiButtonAction)> {
    let mut actions = vec![("卸下", GameUiButtonAction::UnequipSlot(slot_id.to_string()))];
    if let Some(shop_id) = trade_shop_id {
        actions.push((
            "卖出",
            GameUiButtonAction::SellEquippedTradeItem {
                shop_id: shop_id.to_string(),
                slot_id: slot_id.to_string(),
            },
        ));
    }
    actions
}

pub(super) fn skill_context_menu_actions(
    skill_id: &str,
    enabled: bool,
) -> Vec<(ContextMenuItemVisual, GameUiButtonAction)> {
    vec![(
        ContextMenuItemVisual {
            label: "添加到快捷栏".to_string(),
            is_primary: false,
            is_disabled: !enabled,
        },
        GameUiButtonAction::AssignSkillToFirstEmptyHotbarSlot(skill_id.to_string()),
    )]
}

pub(super) fn render_ui_context_menu_container(
    parent: &mut ChildSpawnerCommands,
    _font: &ViewerUiFont,
    window: &Window,
    cursor_position: Vec2,
    estimated_height: f32,
    content: impl FnOnce(&mut ChildSpawnerCommands),
) {
    let style = ContextMenuStyle::for_variant(ContextMenuVariant::UiContext);
    let position = floating_panel_position(window, cursor_position, style.width, estimated_height);
    spawn_context_menu_shell(
        parent,
        style,
        position,
        "UI 右键菜单",
        UiContextMenuRoot,
        content,
    );
}

pub(super) fn context_menu_estimated_height(action_count: usize, has_header: bool) -> f32 {
    let style = ContextMenuStyle::for_variant(ContextMenuVariant::UiContext);
    let header_rows = if has_header { 3.0 } else { 0.0 };
    style.border_width * 2.0
        + style.padding * 2.0
        + header_rows * 18.0
        + action_count as f32 * style.item_min_height
        + action_count.saturating_sub(1) as f32 * style.item_gap
}

pub(super) fn render_tooltip_container(
    parent: &mut ChildSpawnerCommands,
    window: &Window,
    cursor_position: Vec2,
    estimated_height: f32,
    content: impl FnOnce(&mut ChildSpawnerCommands),
) {
    let position = floating_panel_position(
        window,
        cursor_position,
        HOVER_TOOLTIP_MAX_WIDTH,
        estimated_height,
    );
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(position.x),
                top: px(position.y),
                width: px(HOVER_TOOLTIP_MAX_WIDTH),
                max_width: px(HOVER_TOOLTIP_MAX_WIDTH),
                padding: UiRect::all(px(12)),
                flex_direction: FlexDirection::Column,
                row_gap: px(6),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(ui_border_color()),
            FocusPolicy::Pass,
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(content);
}

pub(super) fn floating_panel_position(
    window: &Window,
    cursor_position: Vec2,
    width: f32,
    estimated_height: f32,
) -> Vec2 {
    let max_left =
        (window.width() - width - HOVER_TOOLTIP_VIEWPORT_MARGIN).max(HOVER_TOOLTIP_VIEWPORT_MARGIN);
    let max_top = (window.height() - estimated_height - HOVER_TOOLTIP_VIEWPORT_MARGIN)
        .max(HOVER_TOOLTIP_VIEWPORT_MARGIN);

    let mut left = cursor_position.x;
    let mut top = cursor_position.y;

    if left + width > window.width() - HOVER_TOOLTIP_VIEWPORT_MARGIN {
        left = cursor_position.x - width - HOVER_TOOLTIP_CURSOR_OFFSET_X;
    }
    if top + estimated_height > window.height() - HOVER_TOOLTIP_VIEWPORT_MARGIN {
        top = cursor_position.y - estimated_height - HOVER_TOOLTIP_CURSOR_OFFSET_Y;
    }

    Vec2::new(
        left.clamp(HOVER_TOOLTIP_VIEWPORT_MARGIN, max_left),
        top.clamp(HOVER_TOOLTIP_VIEWPORT_MARGIN, max_top),
    )
}

#[cfg(test)]
mod tests {
    use super::{
        equipment_context_menu_actions, floating_panel_position, inventory_context_menu_actions,
        skill_context_menu_actions,
    };
    use bevy::prelude::Vec2;
    use bevy::window::{Window, WindowResolution};
    use crate::game_ui::HOVER_TOOLTIP_CURSOR_OFFSET_X;

    #[test]
    fn inventory_context_menu_shows_drop_even_without_use_or_equip() {
        let labels: Vec<_> = inventory_context_menu_actions(None, 1001, false, false, 3)
            .into_iter()
            .map(|(label, _)| label)
            .collect();

        assert_eq!(labels, vec!["丢弃"]);
    }

    #[test]
    fn trade_inventory_context_menu_hides_use_and_drop() {
        let labels: Vec<_> = inventory_context_menu_actions(Some("npc_shop"), 1001, true, true, 3)
            .into_iter()
            .map(|(label, _)| label)
            .collect();

        assert_eq!(labels, vec!["装备", "卖出"]);
    }

    #[test]
    fn trade_equipment_context_menu_includes_sell() {
        let labels: Vec<_> = equipment_context_menu_actions(Some("npc_shop"), "weapon")
            .into_iter()
            .map(|(label, _)| label)
            .collect();

        assert_eq!(labels, vec!["卸下", "卖出"]);
    }

    #[test]
    fn skill_context_menu_only_shows_add_to_hotbar() {
        let labels: Vec<_> = skill_context_menu_actions("fireball", true)
            .into_iter()
            .map(|(item, _)| item.label)
            .collect();

        assert_eq!(labels, vec!["添加到快捷栏"]);
    }

    #[test]
    fn tooltip_sticks_to_cursor_when_space_is_available() {
        let position = floating_panel_position(
            &window_with_size(1280.0, 720.0),
            Vec2::new(320.0, 180.0),
            240.0,
            120.0,
        );

        assert_eq!(position, Vec2::new(320.0, 180.0));
    }

    #[test]
    fn tooltip_flips_left_when_right_side_lacks_space() {
        let position = floating_panel_position(
            &window_with_size(1280.0, 720.0),
            Vec2::new(1200.0, 180.0),
            240.0,
            120.0,
        );

        assert_eq!(position.x, 1200.0 - 240.0 - HOVER_TOOLTIP_CURSOR_OFFSET_X);
    }

    fn window_with_size(width: f32, height: f32) -> Window {
        Window {
            resolution: WindowResolution::new(width as u32, height as u32),
            ..Default::default()
        }
    }
}
