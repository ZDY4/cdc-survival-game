//! UI 模态与提示模块：负责丢弃数量弹窗与世界地点进入提示。

use super::*;

pub(super) fn render_item_quantity_modal(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    modal: &game_bevy::UiItemQuantityModalState,
    items: &ItemDefinitions,
) {
    let item_name = items
        .0
        .get(modal.item_id)
        .map(|item| item.name.as_str())
        .unwrap_or("未知物品");
    let (title, available_label, selected_label, confirm_label, max_label) = match &modal.intent {
        game_bevy::UiItemQuantityIntent::Discard => (
            "丢弃物品",
            format!("当前持有 x{}", modal.source_count),
            format!("待丢弃 x{}", modal.selected_count),
            "确认丢弃",
            None,
        ),
        game_bevy::UiItemQuantityIntent::TradeBuy { .. } => (
            "买入物品",
            format!("商店库存 x{}", modal.source_count),
            format!("待买入 x{}", modal.selected_count),
            "确认买入",
            Some(format!("当前最多可买 x{}", modal.available_count)),
        ),
        game_bevy::UiItemQuantityIntent::TradeSell { .. } => (
            "卖出物品",
            format!("当前持有 x{}", modal.source_count),
            format!("待卖出 x{}", modal.selected_count),
            "确认卖出",
            Some(format!("当前最多可卖 x{}", modal.available_count)),
        ),
    };
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
            BackgroundColor(Color::srgba(0.01, 0.01, 0.01, 0.66)),
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
                    BackgroundColor(ui_panel_background()),
                    BorderColor::all(ui_border_strong_color()),
                    UiMouseBlocker,
                ))
                .with_children(|panel| {
                    panel.spawn(text_bundle(font, title, 15.0, Color::WHITE));
                    panel.spawn(text_bundle(
                        font,
                        item_name,
                        12.0,
                        ui_text_heading_color(),
                    ));
                    panel.spawn(text_bundle(
                        font,
                        &available_label,
                        10.5,
                        ui_text_muted_color(),
                    ));
                    panel.spawn(text_bundle(
                        font,
                        &selected_label,
                        11.2,
                        Color::srgba(0.95, 0.85, 0.58, 1.0),
                    ));
                    if let Some(max_label) = max_label.as_ref() {
                        panel.spawn(text_bundle(font, max_label, 10.2, ui_text_muted_color()));
                    }
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
                                GameUiButtonAction::DecreaseItemQuantity,
                            ));
                            actions.spawn(action_button(
                                font,
                                "+1",
                                GameUiButtonAction::IncreaseItemQuantity,
                            ));
                            actions.spawn(action_button(
                                font,
                                "全部",
                                GameUiButtonAction::SetItemQuantityToMax,
                            ));
                        });
                    panel.spawn(action_button(
                        font,
                        confirm_label,
                        GameUiButtonAction::ConfirmItemQuantity,
                    ));
                    panel.spawn(action_button(
                        font,
                        "取消",
                        GameUiButtonAction::CancelItemQuantity,
                    ));
                });
        });
}

pub(super) fn render_overworld_location_prompt(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    camera: &Camera,
    camera_transform: &GlobalTransform,
    runtime: &game_core::SimulationRuntime,
    prompt: &game_bevy::UiOverworldLocationPromptSnapshot,
) {
    let world = runtime.grid_to_world(prompt.grid);
    let world_position = Vec3::new(world.x, world.y + 0.95, world.z);
    let Ok(viewport) = camera.world_to_viewport(camera_transform, world_position) else {
        return;
    };

    let width = 220.0;
    let height = 92.0;
    let left = (viewport.x - width * 0.5).clamp(12.0, (window.width() - width - 12.0).max(12.0));
    let top = (viewport.y - height - 26.0).clamp(12.0, (window.height() - height - 12.0).max(12.0));

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(left),
                top: px(top),
                width: px(width),
                padding: UiRect::all(px(12.0)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8.0),
                border: UiRect::all(px(1.0)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.05, 0.058, 0.076, 0.96)),
            BorderColor::all(Color::srgba(0.34, 0.42, 0.54, 1.0)),
            UiMouseBlocker,
        ))
        .with_children(|bubble| {
            bubble.spawn(text_bundle(font, &prompt.location_name, 13.0, Color::WHITE));
            bubble.spawn(action_button(
                font,
                &prompt.enter_label,
                GameUiButtonAction::EnterOverworldLocation(prompt.location_id.clone()),
            ));
        });
}
