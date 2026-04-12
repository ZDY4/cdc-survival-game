//! 容器浮窗渲染：只展示容器库存，并按物件世界位置锚定到屏幕。

use super::*;

pub(super) fn render_container_page(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    camera: &Camera,
    camera_transform: &GlobalTransform,
    runtime: &game_core::SimulationRuntime,
    container_state: &game_bevy::UiContainerSessionState,
    container_snapshot: &game_bevy::UiContainerSnapshot,
    drag_state: &UiInventoryDragState,
) {
    let (left, top) = container_window_screen_position(
        window,
        camera,
        camera_transform,
        runtime,
        container_state,
    );

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(left),
                top: px(top),
                width: px(CONTAINER_WINDOW_WIDTH),
                height: px(CONTAINER_WINDOW_HEIGHT),
                padding: UiRect::all(px(14)),
                flex_direction: FlexDirection::Column,
                row_gap: px(10),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(ui_border_strong_color()),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
            UiMouseBlockerName("容器浮窗".to_string()),
        ))
        .with_children(|panel| {
            panel
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        flex_direction: FlexDirection::Row,
                        justify_content: JustifyContent::SpaceBetween,
                        align_items: AlignItems::Center,
                        ..default()
                    },
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|header| {
                    header
                        .spawn(Node {
                            flex_direction: FlexDirection::Column,
                            row_gap: px(4),
                            ..default()
                        })
                        .with_children(|titles| {
                            titles.spawn(text_bundle(
                                font,
                                &format!("容器 · {}", container_snapshot.display_name),
                                14.4,
                                Color::WHITE,
                            ));
                            titles.spawn(text_bundle(
                                font,
                                &format!(
                                    "容器 ID {} · {} 种物品",
                                    container_snapshot.container_id,
                                    container_snapshot.item_kind_count
                                ),
                                10.0,
                                ui_text_secondary_color(),
                            ));
                        });
                    header.spawn(action_button(
                        font,
                        "关闭",
                        GameUiButtonAction::CloseContainer,
                    ));
                });

            panel.spawn(text_bundle(
                font,
                "背包面板保持正常显示；可从背包拖入这里，也可从这里拖回背包。",
                9.6,
                ui_text_muted_color(),
            ));

            render_container_stock_column(panel, font, container_snapshot, drag_state);
        });
}

fn render_container_stock_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiContainerSnapshot,
    drag_state: &UiInventoryDragState,
) {
    let list_hover = matches!(
        drag_state.hover_target,
        Some(UiInventoryDragHoverTarget::ContainerListEnd)
    );
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                flex_grow: 1.0,
                min_height: px(0),
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                border: UiRect::all(px(if list_hover { 2.0 } else { 1.0 })),
                overflow: Overflow::clip_y(),
                ..default()
            },
            BackgroundColor(ui_panel_background_alt()),
            BorderColor::all(if list_hover {
                Color::srgba(0.92, 0.80, 0.48, 1.0)
            } else {
                ui_border_color()
            }),
            ContainerInventoryPanelBounds,
            ContainerInventoryListDropZone,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|body| {
            body.spawn(text_bundle(font, "容器库存", 11.2, ui_text_heading_color()));
            body.spawn(text_bundle(
                font,
                "右键可移动到背包；也可直接拖回背包。",
                9.6,
                ui_text_muted_color(),
            ));

            body.spawn((
                Node {
                    width: Val::Percent(100.0),
                    flex_grow: 1.0,
                    min_height: px(0),
                    padding: UiRect::top(px(4)),
                    flex_direction: FlexDirection::Column,
                    row_gap: px(8),
                    overflow: Overflow::scroll_y(),
                    ..default()
                },
                RelativeCursorPosition::default(),
                viewer_ui_passthrough_bundle(),
            ))
            .with_children(|items| {
                if snapshot.entries.is_empty() {
                    items.spawn(text_bundle(font, "容器为空", 10.4, ui_text_muted_color()));
                }
                for entry in &snapshot.entries {
                    let is_drag_hover = matches!(
                        drag_state.hover_target.as_ref(),
                        Some(UiInventoryDragHoverTarget::ContainerItem { item_id })
                            if *item_id == entry.item_id
                    );
                    items
                        .spawn((
                            Node {
                                width: Val::Percent(100.0),
                                flex_direction: FlexDirection::Row,
                                ..default()
                            },
                            viewer_ui_passthrough_bundle(),
                        ))
                        .with_children(|row| {
                            row.spawn((
                                Button,
                                Node {
                                    flex_grow: 1.0,
                                    min_width: px(0),
                                    padding: UiRect::all(px(10)),
                                    flex_direction: FlexDirection::Column,
                                    row_gap: px(6),
                                    border: UiRect::all(px(if is_drag_hover { 2.0 } else { 1.0 })),
                                    ..default()
                                },
                                BackgroundColor(if is_drag_hover {
                                    Color::srgba(0.19, 0.18, 0.14, 0.98).into()
                                } else {
                                    ui_panel_background().into()
                                }),
                                BorderColor::all(if is_drag_hover {
                                    Color::srgba(0.92, 0.80, 0.48, 1.0)
                                } else {
                                    ui_border_color()
                                }),
                                InventoryItemHoverTarget {
                                    item_id: entry.item_id,
                                },
                                ContainerInventoryItemClickTarget {
                                    item_id: entry.item_id,
                                },
                                RelativeCursorPosition::default(),
                                viewer_ui_passthrough_bundle(),
                            ))
                            .with_children(|entry_button| {
                                entry_button.spawn(text_bundle(
                                    font,
                                    &entry.name,
                                    10.8,
                                    Color::WHITE,
                                ));
                                entry_button.spawn(text_bundle(
                                    font,
                                    &format!(
                                        "库存 x{} · 总重 {:.1}kg",
                                        entry.count, entry.total_weight
                                    ),
                                    9.4,
                                    ui_text_muted_color(),
                                ));
                            });
                        });
                }
            });
        });
}

fn container_window_screen_position(
    window: &Window,
    camera: &Camera,
    camera_transform: &GlobalTransform,
    runtime: &game_core::SimulationRuntime,
    container_state: &game_bevy::UiContainerSessionState,
) -> (f32, f32) {
    let default_left = (window.width() - CONTAINER_WINDOW_WIDTH - CONTAINER_WINDOW_MARGIN)
        .max(CONTAINER_WINDOW_MARGIN);
    let default_top = (window.height() * 0.22).clamp(
        CONTAINER_WINDOW_MARGIN,
        (window.height() - CONTAINER_WINDOW_HEIGHT).max(0.0),
    );

    let Some(object_id) = container_state.anchor_object_id.as_ref() else {
        return (default_left, default_top);
    };
    let snapshot = runtime.snapshot();
    let Some(object) = snapshot
        .grid
        .map_objects
        .iter()
        .find(|object| object.object_id == *object_id)
    else {
        return (default_left, default_top);
    };
    let world = runtime.grid_to_world(object.anchor);
    let world_position = Vec3::new(world.x, world.y + CONTAINER_WINDOW_ANCHOR_Y, world.z);
    let Ok(viewport) = camera.world_to_viewport(camera_transform, world_position) else {
        return (default_left, default_top);
    };

    let left = (viewport.x + CONTAINER_WINDOW_OFFSET_X).clamp(
        CONTAINER_WINDOW_MARGIN,
        (window.width() - CONTAINER_WINDOW_WIDTH - CONTAINER_WINDOW_MARGIN)
            .max(CONTAINER_WINDOW_MARGIN),
    );
    let top = (viewport.y - CONTAINER_WINDOW_HEIGHT * 0.5).clamp(
        CONTAINER_WINDOW_MARGIN,
        (window.height() - CONTAINER_WINDOW_HEIGHT - CONTAINER_WINDOW_MARGIN)
            .max(CONTAINER_WINDOW_MARGIN),
    );
    (left, top)
}
