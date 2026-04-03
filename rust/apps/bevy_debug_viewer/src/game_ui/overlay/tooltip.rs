//! UI tooltip 渲染：负责将 tooltip 与上下文菜单状态实际挂载到 UI 树上。

use super::*;

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
                    tooltip.spawn(text_bundle(
                        font,
                        "前往",
                        10.0,
                        Color::srgba(0.70, 0.76, 0.86, 1.0),
                    ));
                    tooltip.spawn(text_bundle(font, target_name, 14.0, Color::WHITE));
                },
            );
        }
    }
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
