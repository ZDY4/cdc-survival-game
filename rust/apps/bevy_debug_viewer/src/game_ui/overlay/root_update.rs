//! UI 主更新链：负责按当前场景与菜单状态刷新 retained 游戏 UI 各分区。

use super::*;

#[derive(Default)]
pub(crate) struct GameUiRetainedCache {
    main_menu: Option<String>,
    top_badges: Option<String>,
    hotbar: Option<String>,
    active_panel: Option<String>,
    trade: Option<String>,
    tooltip: Option<String>,
    context_menu: Option<String>,
    drag_preview: Option<String>,
    item_quantity_modal: Option<String>,
    overworld_prompt: Option<String>,
}

pub(crate) fn update_game_ui(
    mut commands: Commands,
    scaffold: Res<GameUiScaffold>,
    ui_children: Query<Option<&Children>>,
    mut visibilities: Query<&mut Visibility>,
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    palette: Res<ViewerPalette>,
    font: Res<ViewerUiFont>,
    ui: GameUiViewState,
    content: GameContentRefs,
    mut cache: Local<GameUiRetainedCache>,
) {
    let _ = palette;
    if ui.console_state.is_open {
        hide_game_ui_sections(&mut visibilities, &scaffold);
        return;
    }

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let player_actor = player_actor_id(&ui.runtime_state.runtime);
    let player_stats =
        player_actor.and_then(|actor_id| player_hud_stats(&ui.runtime_state, actor_id));
    let esc_menu_open = ui.menu_state.active_panel == Some(UiMenuPanel::Settings);
    let in_main_menu_scene = should_render_main_menu(*ui.scene_kind);
    let trade_state = if !esc_menu_open {
        ui.modal_state.trade.as_ref()
    } else {
        None
    };

    let show_main_menu = in_main_menu_scene;
    refresh_section(
        &mut commands,
        &ui_children,
        &mut visibilities,
        scaffold.main_menu,
        show_main_menu,
        &mut cache.main_menu,
        show_main_menu.then(|| ui.menu_state.status_text.clone()),
        |commands, entity| {
            commands.entity(entity).with_children(|parent| {
                render_main_menu(parent, &font, &ui.menu_state.status_text);
            });
        },
    );

    let show_badges = !show_main_menu && !esc_menu_open && trade_state.is_none();
    let badge_key = show_badges.then(|| {
        format!(
            "{:?}|{:?}|{:?}|{:?}",
            ui.scene_kind.as_ref(),
            player_stats,
            ui.viewer_state.current_level,
            ui.menu_state.active_panel
        )
    });
    refresh_section(
        &mut commands,
        &ui_children,
        &mut visibilities,
        scaffold.top_badges,
        show_badges,
        &mut cache.top_badges,
        badge_key,
        |commands, entity| {
            commands.entity(entity).with_children(|parent| {
                render_top_center_badges(
                    parent,
                    &font,
                    *ui.scene_kind,
                    &ui.viewer_state,
                    player_stats.as_ref(),
                    &ui.menu_state,
                );
            });
        },
    );

    let show_hotbar = show_badges;
    let hotbar_key = show_hotbar.then(|| {
        format!(
            "{:?}|{:?}|{:?}|{:?}|{:?}|{:?}",
            ui.viewer_state.control_mode,
            ui.viewer_state.observe_speed,
            ui.viewer_state.auto_tick,
            ui.hotbar_state,
            ui.menu_state.active_panel,
            ui.menu_state.selected_skill_id
        )
    });
    refresh_section(
        &mut commands,
        &ui_children,
        &mut visibilities,
        scaffold.hotbar,
        show_hotbar,
        &mut cache.hotbar,
        hotbar_key,
        |commands, entity| {
            commands.entity(entity).with_children(|parent| {
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
            });
        },
    );

    if let Some(actor_id) = player_actor {
        let panel_key = active_panel_key(actor_id, &ui, &content);
        let show_active_panel = panel_key.is_some();
        refresh_section(
            &mut commands,
            &ui_children,
            &mut visibilities,
            scaffold.active_panel,
            show_active_panel,
            &mut cache.active_panel,
            panel_key,
            |commands, entity| {
                commands.entity(entity).with_children(|parent| {
                    render_active_panel(parent, &font, actor_id, &ui, &content);
                });
            },
        );

        let trade_key = trade_state.map(|trade| {
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
            format!(
                "{trade_snapshot:?}|{inventory:?}|{:?}|{:?}",
                ui.menu_state, ui.drag_state
            )
        });
        refresh_section(
            &mut commands,
            &ui_children,
            &mut visibilities,
            scaffold.trade,
            trade_key.is_some(),
            &mut cache.trade,
            trade_key,
            |commands, entity| {
                let Some(trade) = trade_state else {
                    return;
                };
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
                commands.entity(entity).with_children(|parent| {
                    render_trade_page(
                        parent,
                        &font,
                        &trade_snapshot,
                        &inventory,
                        &ui.menu_state,
                        &ui.drag_state,
                    );
                });
            },
        );

        let prompt_blocked = ui.input_block_state.blocked
            || ui.inventory_context_menu.visible
            || trade_state.is_some();
        let prompt_key = if prompt_blocked {
            None
        } else {
            let prompt = overworld_location_prompt_snapshot(
                &ui.runtime_state.runtime,
                actor_id,
                &content.overworld.0,
            );
            prompt.visible.then(|| {
                format!(
                    "{prompt:?}|{:?}|{:.1}|{:.1}",
                    camera_transform.translation(),
                    window.width(),
                    window.height()
                )
            })
        };
        refresh_section(
            &mut commands,
            &ui_children,
            &mut visibilities,
            scaffold.overworld_prompt,
            prompt_key.is_some(),
            &mut cache.overworld_prompt,
            prompt_key,
            |commands, entity| {
                let prompt = overworld_location_prompt_snapshot(
                    &ui.runtime_state.runtime,
                    actor_id,
                    &content.overworld.0,
                );
                if !prompt.visible {
                    return;
                }
                commands.entity(entity).with_children(|parent| {
                    render_overworld_location_prompt(
                        parent,
                        &font,
                        &window,
                        camera,
                        &camera_transform,
                        &ui.runtime_state.runtime,
                        &prompt,
                    );
                });
            },
        );
    } else {
        hide_section(&mut visibilities, scaffold.active_panel);
        hide_section(&mut visibilities, scaffold.trade);
        hide_section(&mut visibilities, scaffold.overworld_prompt);
    }

    let tooltip_key = ui
        .hover_tooltip
        .visible
        .then(|| format!("{:?}", ui.hover_tooltip.as_ref()));
    refresh_section(
        &mut commands,
        &ui_children,
        &mut visibilities,
        scaffold.tooltip,
        tooltip_key.is_some(),
        &mut cache.tooltip,
        tooltip_key,
        |commands, entity| {
            commands.entity(entity).with_children(|parent| {
                render_hover_tooltip(parent, &font, &window, player_actor, &ui, &content);
            });
        },
    );

    let context_menu_key = ui
        .inventory_context_menu
        .visible
        .then(|| format!("{:?}", ui.inventory_context_menu.as_ref()));
    refresh_section(
        &mut commands,
        &ui_children,
        &mut visibilities,
        scaffold.context_menu,
        context_menu_key.is_some(),
        &mut cache.context_menu,
        context_menu_key,
        |commands, entity| {
            commands.entity(entity).with_children(|parent| {
                render_inventory_context_menu(parent, &font, &window, player_actor, &ui, &content);
            });
        },
    );

    let drag_preview_key = ui
        .drag_state
        .dragging
        .then(|| format!("{:?}", ui.drag_state.as_ref()));
    refresh_section(
        &mut commands,
        &ui_children,
        &mut visibilities,
        scaffold.drag_preview,
        drag_preview_key.is_some(),
        &mut cache.drag_preview,
        drag_preview_key,
        |commands, entity| {
            commands.entity(entity).with_children(|parent| {
                render_drag_preview(parent, &font, &ui.drag_state);
            });
        },
    );

    let item_quantity_key = ui
        .modal_state
        .item_quantity
        .as_ref()
        .map(|modal| format!("{modal:?}"));
    refresh_section(
        &mut commands,
        &ui_children,
        &mut visibilities,
        scaffold.discard_modal,
        item_quantity_key.is_some(),
        &mut cache.item_quantity_modal,
        item_quantity_key,
        |commands, entity| {
            let Some(item_modal) = ui.modal_state.item_quantity.as_ref() else {
                return;
            };
            commands.entity(entity).with_children(|parent| {
                render_item_quantity_modal(parent, &font, item_modal, &content.items);
            });
        },
    );
}

fn refresh_section(
    commands: &mut Commands,
    children_query: &Query<Option<&Children>>,
    visibilities: &mut Query<&mut Visibility>,
    entity: Entity,
    visible: bool,
    cached_key: &mut Option<String>,
    next_key: Option<String>,
    render: impl FnOnce(&mut Commands, Entity),
) {
    if !visible {
        hide_section(visibilities, entity);
        return;
    }

    if let Ok(mut visibility) = visibilities.get_mut(entity) {
        *visibility = Visibility::Visible;
    }

    if *cached_key != next_key {
        let children = children_query.get(entity).ok().flatten();
        clear_ui_children(commands, children);
        render(commands, entity);
        *cached_key = next_key;
    }
}

fn hide_game_ui_sections(visibilities: &mut Query<&mut Visibility>, scaffold: &GameUiScaffold) {
    for entity in [
        scaffold.main_menu,
        scaffold.top_badges,
        scaffold.hotbar,
        scaffold.active_panel,
        scaffold.trade,
        scaffold.tooltip,
        scaffold.context_menu,
        scaffold.drag_preview,
        scaffold.discard_modal,
        scaffold.overworld_prompt,
    ] {
        hide_section(visibilities, entity);
    }
}

fn hide_section(visibilities: &mut Query<&mut Visibility>, entity: Entity) {
    if let Ok(mut visibility) = visibilities.get_mut(entity) {
        *visibility = Visibility::Hidden;
    }
}

fn active_panel_key(
    actor_id: ActorId,
    ui: &GameUiViewState<'_, '_>,
    content: &GameContentRefs<'_, '_>,
) -> Option<String> {
    let panel = ui.menu_state.active_panel?;
    if panel == UiMenuPanel::Settings || ui.modal_state.trade.is_some() {
        return None;
    }

    Some(match panel {
        UiMenuPanel::Inventory => format!(
            "{panel:?}|{:?}|{:?}|{:?}",
            inventory_snapshot(
                &ui.runtime_state.runtime,
                actor_id,
                &content.items.0,
                ui.filter_state.filter,
                ui.menu_state.selected_inventory_item,
            ),
            ui.menu_state,
            ui.drag_state
        ),
        UiMenuPanel::Character => format!(
            "{panel:?}|{:?}",
            character_snapshot(&ui.runtime_state.runtime, actor_id)
        ),
        UiMenuPanel::Journal => format!(
            "{panel:?}|{:?}",
            journal_snapshot(&ui.runtime_state.runtime, actor_id, &content.quests.0)
        ),
        UiMenuPanel::Skills => format!(
            "{panel:?}|{:?}|{:?}|{:?}",
            skills_snapshot(
                &ui.runtime_state.runtime,
                actor_id,
                &content.skills.0,
                &content.skill_trees.0,
            ),
            ui.menu_state,
            ui.hotbar_state
        ),
        UiMenuPanel::Crafting => format!(
            "{panel:?}|{:?}",
            game_bevy::crafting_snapshot(&ui.runtime_state.runtime, actor_id, &content.recipes.0)
        ),
        UiMenuPanel::Map => format!(
            "{panel:?}|{:?}|{:?}|{:?}",
            ui.runtime_state.runtime.current_overworld_state(),
            ui.menu_state.selected_map_location_id,
            content.overworld.0
        ),
        UiMenuPanel::Settings => format!("{panel:?}|{:?}", ui.settings.as_ref()),
    })
}

fn render_active_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    actor_id: ActorId,
    ui: &GameUiViewState<'_, '_>,
    content: &GameContentRefs<'_, '_>,
) {
    let Some(panel) = ui.menu_state.active_panel else {
        return;
    };

    match panel {
        UiMenuPanel::Inventory => {
            render_panel_shell(parent, font, panel);
            let snapshot = inventory_snapshot(
                &ui.runtime_state.runtime,
                actor_id,
                &content.items.0,
                ui.filter_state.filter,
                ui.menu_state.selected_inventory_item,
            );
            render_inventory_panel(parent, font, &snapshot, &ui.menu_state, &ui.drag_state);
        }
        UiMenuPanel::Character => {
            render_panel_shell(parent, font, panel);
            let snapshot = character_snapshot(&ui.runtime_state.runtime, actor_id);
            render_character_panel(parent, font, &snapshot);
        }
        UiMenuPanel::Journal => {
            render_panel_shell(parent, font, panel);
            let snapshot = journal_snapshot(&ui.runtime_state.runtime, actor_id, &content.quests.0);
            render_journal_panel(parent, font, &snapshot);
        }
        UiMenuPanel::Skills => {
            render_panel_shell(parent, font, panel);
            let snapshot = skills_snapshot(
                &ui.runtime_state.runtime,
                actor_id,
                &content.skills.0,
                &content.skill_trees.0,
            );
            render_skills_panel(parent, font, &snapshot, &ui.menu_state, &ui.hotbar_state);
        }
        UiMenuPanel::Crafting => {
            render_panel_shell(parent, font, panel);
            let snapshot = game_bevy::crafting_snapshot(
                &ui.runtime_state.runtime,
                actor_id,
                &content.recipes.0,
            );
            render_crafting_panel(parent, font, &snapshot);
        }
        UiMenuPanel::Map => {
            render_panel_shell(parent, font, panel);
            render_map_panel(
                parent,
                font,
                &ui.runtime_state.runtime.current_overworld_state(),
                &content.overworld.0,
                &ui.menu_state,
            );
        }
        UiMenuPanel::Settings => {
            render_settings_panel(parent, font, &ui.settings);
        }
    }
}

fn render_drag_preview(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    drag_state: &UiInventoryDragState,
) {
    let label = if drag_state.preview_label.trim().is_empty() {
        "拖拽物品"
    } else {
        drag_state.preview_label.as_str()
    };
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(drag_state.cursor_position.x + 18.0),
                top: px(drag_state.cursor_position.y + 18.0),
                padding: UiRect::axes(px(10), px(7)),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.08, 0.10, 0.14, 0.96)),
            BorderColor::all(Color::srgba(0.92, 0.80, 0.48, 1.0)),
            FocusPolicy::Pass,
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|preview| {
            preview.spawn(text_bundle(font, label, 11.0, Color::WHITE));
        });
}
