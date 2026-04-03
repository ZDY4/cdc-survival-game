//! UI 浮层更新链：负责根据场景状态选择主菜单、面板、tooltip 和模态层渲染路径。

use super::*;
use super::{
    context_menu::render_inventory_context_menu,
    layout::{render_main_menu, render_panel_shell},
    modal::{render_discard_quantity_modal, render_overworld_location_prompt},
    tooltip::render_hover_tooltip,
};

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
                            let snapshot =
                                character_snapshot(&ui.runtime_state.runtime, actor_id);
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

        if let Some(discard_modal) = ui.modal_state.discard_quantity.as_ref() {
            render_discard_quantity_modal(parent, &font, discard_modal, &content.items);
        }
    });
}
