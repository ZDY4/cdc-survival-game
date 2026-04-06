//! UI 主更新链：负责按当前场景与菜单状态装配各类游戏 UI 浮层。

use super::*;

pub(crate) fn update_game_ui(
    mut commands: Commands,
    root: Single<(Entity, Option<&Children>), With<GameUiRoot>>,
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    palette: Res<ViewerPalette>,
    font: Res<ViewerUiFont>,
    ui: GameUiViewState,
    content: GameContentRefs,
) {
    let (entity, children) = root.into_inner();
    clear_ui_children(&mut commands, children);
    if ui.console_state.is_open {
        return;
    }
    let _ = palette;
    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
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
                render_active_panel(parent, &font, actor_id, &ui, &content);
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
                render_trade_page(
                    parent,
                    &font,
                    &trade_snapshot,
                    &inventory,
                    &ui.menu_state,
                    &ui.drag_state,
                );
            }

            let prompt_blocked = ui.input_block_state.blocked || ui.inventory_context_menu.visible;
            if !prompt_blocked {
                let prompt = overworld_location_prompt_snapshot(
                    &ui.runtime_state.runtime,
                    actor_id,
                    &content.overworld.0,
                );
                if prompt.visible {
                    render_overworld_location_prompt(
                        parent,
                        &font,
                        &window,
                        camera,
                        &camera_transform,
                        &ui.runtime_state.runtime,
                        &prompt,
                    );
                }
            }
        }

        let _ = &ui.viewer_state;

        if ui.hover_tooltip.visible {
            render_hover_tooltip(parent, &font, &window, player_actor, &ui, &content);
        }

        if ui.inventory_context_menu.visible {
            render_inventory_context_menu(parent, &font, &window, player_actor, &ui, &content);
        }

        if ui.drag_state.dragging {
            render_drag_preview(parent, &font, &ui.drag_state);
        }

        if let Some(item_modal) = ui.modal_state.item_quantity.as_ref() {
            render_item_quantity_modal(parent, &font, item_modal, &content.items);
        }
    });
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
