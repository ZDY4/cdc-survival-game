use super::*;

pub(crate) fn update_game_ui(
    mut commands: Commands,
    root: Single<(Entity, Option<&Children>), With<GameUiRoot>>,
    window: Single<&Window>,
    palette: Res<ViewerPalette>,
    font: Res<ViewerUiFont>,
    ui: GameUiViewState,
    content: GameContentRefs,
) {
    let (entity, children) = root.into_inner();
    clear_ui_children(&mut commands, children);
    let _ = palette;
    let player_actor = player_actor_id(&ui.runtime_state.runtime);
    let player_stats =
        player_actor.and_then(|actor_id| player_hud_stats(&ui.runtime_state, actor_id));
    let esc_menu_open = ui.menu_state.active_panel == Some(UiMenuPanel::Settings);

    commands.entity(entity).with_children(|parent| {
        let in_main_menu_scene = should_render_main_menu(*ui.scene_kind);
        let trade_state = if !esc_menu_open {
            ui.modal_state.trade.as_ref()
        } else {
            None
        };

        if in_main_menu_scene {
            render_main_menu(parent, &font, &ui.menu_state.status_text);
        } else if !esc_menu_open && trade_state.is_none() {
            render_top_center_badges(
                parent,
                &font,
                *ui.scene_kind,
                &ui.viewer_state,
                player_stats.as_ref(),
                &ui.menu_state,
            );
            render_hotbar(
                parent,
                &font,
                &ui.viewer_state,
                &ui.hotbar_state,
                &content.skills.0,
                &ui.menu_state,
                ui.menu_state.active_panel == Some(UiMenuPanel::Skills),
                ui.menu_state.selected_skill_id.as_deref(),
            );
        }

        if let Some(actor_id) = player_actor {
            if trade_state.is_none() {
                if let Some(panel) = ui.menu_state.active_panel {
                    match panel {
                        UiMenuPanel::Inventory => {
                            render_panel_shell(parent, &font, panel);
                            let snapshot = inventory_snapshot(
                                &ui.runtime_state.runtime,
                                actor_id,
                                &content.items.0,
                                ui.filter_state.filter,
                                ui.menu_state.selected_inventory_item,
                            );
                            render_inventory_panel(parent, &font, &snapshot, &ui.menu_state);
                        }
                        UiMenuPanel::Character => {
                            render_panel_shell(parent, &font, panel);
                            let snapshot = character_snapshot(&ui.runtime_state.runtime, actor_id);
                            render_character_panel(parent, &font, &snapshot);
                        }
                        UiMenuPanel::Journal => {
                            render_panel_shell(parent, &font, panel);
                            let snapshot = journal_snapshot(
                                &ui.runtime_state.runtime,
                                actor_id,
                                &content.quests.0,
                            );
                            render_journal_panel(parent, &font, &snapshot);
                        }
                        UiMenuPanel::Skills => {
                            render_panel_shell(parent, &font, panel);
                            let snapshot = skills_snapshot(
                                &ui.runtime_state.runtime,
                                actor_id,
                                &content.skills.0,
                                &content.skill_trees.0,
                            );
                            render_skills_panel(
                                parent,
                                &font,
                                &snapshot,
                                &ui.menu_state,
                                &ui.hotbar_state,
                            );
                        }
                        UiMenuPanel::Crafting => {
                            render_panel_shell(parent, &font, panel);
                            let snapshot = game_bevy::crafting_snapshot(
                                &ui.runtime_state.runtime,
                                actor_id,
                                &content.recipes.0,
                            );
                            render_crafting_panel(parent, &font, &snapshot);
                        }
                        UiMenuPanel::Map => {
                            render_panel_shell(parent, &font, panel);
                            let _ = actor_id;
                            render_map_panel(
                                parent,
                                &font,
                                &ui.runtime_state.runtime.current_overworld_state(),
                                &content.overworld.0,
                                &ui.menu_state,
                            );
                        }
                        UiMenuPanel::Settings => {
                            render_settings_panel(parent, &font, &ui.settings);
                        }
                    }
                }
            }

            if let Some(trade) = trade_state {
                let trade_snapshot = trade_snapshot(
                    &ui.runtime_state.runtime,
                    actor_id,
                    trade.target_actor_id,
                    &trade.shop_id,
                    &content.items.0,
                    &content.shops.0,
                );
                let inventory = inventory_snapshot(
                    &ui.runtime_state.runtime,
                    actor_id,
                    &content.items.0,
                    ui.filter_state.filter,
                    ui.menu_state.selected_inventory_item,
                );
                render_trade_page(parent, &font, &trade_snapshot, &inventory, &ui.menu_state);
            }
        }

        let _ = &ui.viewer_state;

        if ui.hover_tooltip.visible {
            render_hover_tooltip(parent, &font, &window, player_actor, &ui, &content);
        }

        if ui.inventory_context_menu.visible {
            render_inventory_context_menu(parent, &font, &window, player_actor, &ui, &content);
        }

        if let Some(discard_modal) = ui.modal_state.discard_quantity.as_ref() {
            render_discard_quantity_modal(parent, &font, discard_modal, &content.items);
        }
    });
}

#[allow(clippy::too_many_arguments)]

pub(super) fn render_main_menu(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    status_text: &str,
) {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                top: Val::Percent(50.0),
                margin: UiRect {
                    left: px(-220),
                    top: px(-150),
                    ..default()
                },
                width: px(440),
                padding: UiRect::all(px(18)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                ..default()
            },
            BackgroundColor(Color::srgba(0.02, 0.03, 0.05, 0.96)),
        ))
        .with_children(|menu| {
            menu.spawn(text_bundle(font, "CDC Survival Game", 20.0, Color::WHITE));
            menu.spawn(text_bundle(
                font,
                "Bevy 主流程界面",
                12.0,
                Color::srgba(0.82, 0.86, 0.93, 1.0),
            ));
            if !status_text.trim().is_empty() {
                menu.spawn(text_bundle(
                    font,
                    status_text,
                    11.5,
                    Color::srgba(0.92, 0.8, 0.56, 1.0),
                ));
            }
            menu.spawn(action_button(
                font,
                "开始新游戏",
                GameUiButtonAction::MainMenuNewGame,
            ));
            menu.spawn(action_button(
                font,
                "继续游戏",
                GameUiButtonAction::MainMenuContinue,
            ));
            menu.spawn(action_button(
                font,
                "退出游戏",
                GameUiButtonAction::MainMenuExit,
            ));
        });
}

pub(super) fn render_panel_shell(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    panel: UiMenuPanel,
) {
    let width = panel_width(panel);
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            top: px(RIGHT_PANEL_TOP),
            right: px(SCREEN_EDGE_PADDING),
            width: px(width),
            height: px(RIGHT_PANEL_HEADER_HEIGHT),
            padding: UiRect::axes(px(16), px(12)),
            justify_content: JustifyContent::SpaceBetween,
            align_items: AlignItems::Center,
            flex_direction: FlexDirection::Row,
            border: UiRect::all(px(1)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.98)),
        BorderColor::all(Color::srgba(0.26, 0.29, 0.38, 1.0)),
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        UiMouseBlocker,
        children![
            text_bundle(font, panel_title(panel), 15.0, Color::WHITE),
            text_bundle(
                font,
                panel_tab_label(panel),
                10.0,
                Color::srgba(0.76, 0.81, 0.88, 1.0)
            )
        ],
    ));
}

pub(super) fn panel_body(parent: &mut ChildSpawnerCommands, panel: UiMenuPanel) -> Entity {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(RIGHT_PANEL_TOP + RIGHT_PANEL_HEADER_HEIGHT - 1.0),
                right: px(SCREEN_EDGE_PADDING),
                width: px(panel_width(panel)),
                bottom: px(RIGHT_PANEL_BOTTOM),
                padding: UiRect::all(px(14)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                overflow: Overflow::clip_y(),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.97)),
            BorderColor::all(Color::srgba(0.22, 0.25, 0.33, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .id()
}

pub(super) fn render_hover_tooltip(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    player_actor: Option<ActorId>,
    ui: &GameUiViewState<'_, '_>,
    content: &GameContentRefs<'_, '_>,
) {
    let Some(player_actor) = player_actor else {
        return;
    };
    let Some(tooltip_content) = ui.hover_tooltip.content.as_ref() else {
        return;
    };

    match tooltip_content {
        UiHoverTooltipContent::InventoryItem { item_id } => {
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
            render_tooltip_container(
                parent,
                window,
                ui.hover_tooltip.cursor_position,
                display.content.estimated_height(),
                |tooltip| render_inventory_detail_content(tooltip, font, &display, false),
            );
        }
        UiHoverTooltipContent::Skill { tree_id, skill_id } => {
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
    if ui.menu_state.active_panel != Some(UiMenuPanel::Inventory) {
        return;
    }
    let Some(player_actor) = player_actor else {
        return;
    };
    let Some(target) = ui.inventory_context_menu.target.as_ref() else {
        return;
    };

    match target {
        UiInventoryContextMenuTarget::InventoryItem { item_id } => {
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
            render_inventory_context_menu_container(
                parent,
                font,
                window,
                ui.inventory_context_menu.cursor_position,
                152.0,
                |menu| {
                    menu.spawn(text_bundle(font, &detail.name, 11.5, Color::WHITE));
                    menu.spawn(text_bundle(
                        font,
                        &format!("{} · x{}", detail.item_type.as_str(), detail.count),
                        9.8,
                        Color::srgba(0.74, 0.79, 0.88, 1.0),
                    ));
                    for (label, action) in inventory_context_menu_actions(
                        display.can_use,
                        display.can_equip,
                        detail.count,
                    ) {
                        menu.spawn(action_button(font, label, action));
                    }
                },
            );
        }
        UiInventoryContextMenuTarget::EquipmentSlot { slot_id, item_id } => {
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
            render_inventory_context_menu_container(
                parent,
                font,
                window,
                ui.inventory_context_menu.cursor_position,
                118.0,
                |menu| {
                    menu.spawn(text_bundle(font, &slot_name, 11.5, Color::WHITE));
                    menu.spawn(text_bundle(
                        font,
                        &format!("装备槽: {slot_id}"),
                        9.8,
                        Color::srgba(0.74, 0.79, 0.88, 1.0),
                    ));
                    menu.spawn(action_button(
                        font,
                        "卸下",
                        GameUiButtonAction::UnequipSlot(slot_id.clone()),
                    ));
                },
            );
        }
    }
}

pub(super) fn inventory_context_menu_actions(
    can_use: bool,
    can_equip: bool,
    count: i32,
) -> Vec<(&'static str, GameUiButtonAction)> {
    let mut actions = Vec::new();
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

pub(super) fn render_discard_quantity_modal(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    modal: &game_bevy::UiDiscardQuantityModalState,
    items: &ItemDefinitions,
) {
    let item_name = items
        .0
        .get(modal.item_id)
        .map(|item| item.name.as_str())
        .unwrap_or("未知物品");
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(0),
                top: px(0),
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                align_items: AlignItems::Center,
                justify_content: JustifyContent::Center,
                ..default()
            },
            BackgroundColor(Color::srgba(0.01, 0.02, 0.03, 0.66)),
            UiMouseBlocker,
        ))
        .with_children(|overlay| {
            overlay
                .spawn((
                    Node {
                        width: px(360.0),
                        padding: UiRect::all(px(18.0)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(10.0),
                        border: UiRect::all(px(1.0)),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.05, 0.058, 0.076, 0.98)),
                    BorderColor::all(Color::srgba(0.34, 0.42, 0.54, 1.0)),
                    UiMouseBlocker,
                ))
                .with_children(|panel| {
                    panel.spawn(text_bundle(font, "丢弃物品", 15.0, Color::WHITE));
                    panel.spawn(text_bundle(
                        font,
                        item_name,
                        12.0,
                        Color::srgba(0.9, 0.94, 1.0, 1.0),
                    ));
                    panel.spawn(text_bundle(
                        font,
                        &format!("当前持有 x{}", modal.available_count),
                        10.5,
                        Color::srgba(0.74, 0.79, 0.88, 1.0),
                    ));
                    panel.spawn(text_bundle(
                        font,
                        &format!("待丢弃 x{}", modal.selected_count),
                        11.2,
                        Color::srgba(0.95, 0.85, 0.58, 1.0),
                    ));
                    panel
                        .spawn(Node {
                            width: Val::Percent(100.0),
                            flex_direction: FlexDirection::Row,
                            column_gap: px(8.0),
                            ..default()
                        })
                        .with_children(|actions| {
                            actions.spawn(action_button(
                                font,
                                "-1",
                                GameUiButtonAction::DecreaseDiscardQuantity,
                            ));
                            actions.spawn(action_button(
                                font,
                                "+1",
                                GameUiButtonAction::IncreaseDiscardQuantity,
                            ));
                            actions.spawn(action_button(
                                font,
                                "全部",
                                GameUiButtonAction::SetDiscardQuantityToMax,
                            ));
                        });
                    panel.spawn(action_button(
                        font,
                        "确认丢弃",
                        GameUiButtonAction::ConfirmDiscardQuantity,
                    ));
                    panel.spawn(action_button(
                        font,
                        "取消",
                        GameUiButtonAction::CancelDiscardQuantity,
                    ));
                });
        });
}

pub(super) fn render_inventory_context_menu_container(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    cursor_position: Vec2,
    estimated_height: f32,
    content: impl FnOnce(&mut ChildSpawnerCommands),
) {
    let position = floating_panel_position(window, cursor_position, 220.0, estimated_height);
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(position.x),
                top: px(position.y),
                width: px(220),
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(6),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.05, 0.058, 0.076, 0.985)),
            BorderColor::all(Color::srgba(0.34, 0.42, 0.54, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            InventoryContextMenuRoot,
            UiMouseBlocker,
        ))
        .with_children(|menu| {
            menu.spawn(text_bundle(
                font,
                "操作",
                10.2,
                Color::srgba(0.84, 0.89, 0.96, 1.0),
            ));
            content(menu);
        });
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
            BackgroundColor(Color::srgba(0.045, 0.052, 0.068, 0.96)),
            BorderColor::all(Color::srgba(0.28, 0.34, 0.44, 1.0)),
            FocusPolicy::Pass,
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

    let mut left = cursor_position.x + HOVER_TOOLTIP_CURSOR_OFFSET_X;
    let mut top = cursor_position.y + HOVER_TOOLTIP_CURSOR_OFFSET_Y;

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
    use super::inventory_context_menu_actions;

    #[test]
    fn inventory_context_menu_shows_drop_even_without_use_or_equip() {
        let labels: Vec<_> = inventory_context_menu_actions(false, false, 3)
            .into_iter()
            .map(|(label, _)| label)
            .collect();

        assert_eq!(labels, vec!["丢弃"]);
    }
}
