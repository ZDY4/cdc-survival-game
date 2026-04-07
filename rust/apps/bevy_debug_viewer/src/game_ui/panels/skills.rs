//! 集中构建技能页面的树/列表/详情三列展示。
use super::*;

pub(super) fn render_skills_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiSkillsSnapshot,
    menu_state: &UiMenuState,
    hotbar_state: &UiHotbarState,
) {
    let body = panel_body(parent, UiMenuPanel::Skills);
    parent.commands().entity(body).insert(Node {
        position_type: PositionType::Absolute,
        top: px(RIGHT_PANEL_TOP + RIGHT_PANEL_HEADER_HEIGHT - 1.0),
        left: px(LEFT_STAGE_PANEL_X),
        right: Val::Auto,
        width: px(SKILLS_PANEL_WIDTH),
        bottom: px(RIGHT_PANEL_BOTTOM),
        padding: UiRect::all(px(14)),
        flex_direction: FlexDirection::Column,
        row_gap: px(10),
        overflow: Overflow::clip_y(),
        border: UiRect::all(px(1)),
        ..default()
    });
    let selected_tree = selected_skill_tree(snapshot, menu_state);
    let selected_entry = selected_tree
        .and_then(|tree| selected_skill_entry(tree, menu_state.selected_skill_id.as_deref()));

    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(
            font,
            "左侧切技能树，中列浏览当前树，右侧查看详情；选中技能后可加入当前组，右键技能可直接加到快捷栏，或直接点击底栏槽位精确绑定。",
            10.5,
            ui_text_secondary_color(),
        ));
        body.spawn((
            Node {
                width: Val::Percent(100.0),
                column_gap: px(12),
                flex_direction: FlexDirection::Row,
                align_items: AlignItems::Stretch,
                ..default()
            },
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|columns| {
            columns
                .spawn((
                    Node {
                        width: px(190),
                        padding: UiRect::all(px(10)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(6),
                        overflow: Overflow::clip_y(),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(ui_panel_background()),
                    BorderColor::all(ui_border_color()),
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|tree_column| {
                    tree_column.spawn(text_bundle(
                        font,
                        "技能树",
                        11.5,
                        ui_text_heading_color(),
                    ));
                    if snapshot.trees.is_empty() {
                        tree_column.spawn(text_bundle(
                            font,
                            "当前没有可显示的技能树",
                            10.5,
                            ui_text_muted_color(),
                        ));
                    }
                    for tree in &snapshot.trees {
                        let (learned_count, total_count) = skill_tree_progress(tree);
                        let is_selected = selected_tree
                            .map(|selected| selected.tree_id == tree.tree_id)
                            .unwrap_or(false);
                        tree_column
                            .spawn((
                                Button,
                                Node {
                                    width: Val::Percent(100.0),
                                    padding: UiRect::all(px(9)),
                                    margin: UiRect::bottom(px(2)),
                                    flex_direction: FlexDirection::Column,
                                    row_gap: px(2),
                                    border: UiRect::all(px(if is_selected { 2.0 } else { 1.0 })),
                                    ..default()
                                },
                                BackgroundColor(if is_selected {
                                    ui_panel_background_selected().into()
                                } else {
                                    ui_panel_background_alt().into()
                                }),
                                BorderColor::all(if is_selected {
                                    ui_border_selected_color()
                                } else {
                                    ui_border_color()
                                }),
                                GameUiButtonAction::SelectSkillTree(tree.tree_id.clone()),
                                viewer_ui_passthrough_bundle(),
                            ))
                            .with_children(|button| {
                                button.spawn(text_bundle(
                                    font,
                                    &tree.tree_name,
                                    10.8,
                                    if is_selected {
                                        Color::WHITE
                                    } else {
                                        ui_text_secondary_color()
                                    },
                                ));
                                button.spawn(text_bundle(
                                    font,
                                    &format!("{learned_count}/{total_count} 已学习"),
                                    9.2,
                                    ui_text_muted_color(),
                                ));
                            });
                    }
                });

            columns
                .spawn((
                    Node {
                        width: px(300),
                        padding: UiRect::all(px(10)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(6),
                        overflow: Overflow::clip_y(),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(ui_panel_background()),
                    BorderColor::all(ui_border_color()),
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|list_column| {
                    let title = selected_tree
                        .map(|tree| format!("{} 技能", tree.tree_name))
                        .unwrap_or_else(|| "技能列表".to_string());
                    list_column.spawn(text_bundle(
                        font,
                        &title,
                        11.5,
                        ui_text_heading_color(),
                    ));
                    if let Some(tree) = selected_tree {
                        if tree.entries.is_empty() {
                            list_column.spawn(text_bundle(
                                font,
                                "该技能树暂无技能条目",
                                10.5,
                                ui_text_muted_color(),
                            ));
                        }
                        for entry in &tree.entries {
                            let is_selected = selected_entry
                                .map(|selected| selected.skill_id == entry.skill_id)
                                .unwrap_or(false);
                            let state_label = if entry.learned_level > 0 {
                                if entry.hotbar_eligible {
                                    "可绑定"
                                } else {
                                    "已学习"
                                }
                            } else {
                                "未学习"
                            };
                            let state_color = if entry.learned_level > 0 {
                                Color::srgba(0.72, 0.92, 0.72, 1.0)
                            } else {
                                Color::srgba(0.58, 0.63, 0.70, 1.0)
                            };
                            list_column
                                .spawn((
                                    Button,
                                    Node {
                                        width: Val::Percent(100.0),
                                        padding: UiRect::all(px(9)),
                                        margin: UiRect::bottom(px(2)),
                                        flex_direction: FlexDirection::Column,
                                        row_gap: px(3),
                                        border: UiRect::all(px(if is_selected { 2.0 } else { 1.0 })),
                                        ..default()
                                    },
                                    BackgroundColor(if is_selected {
                                        ui_panel_background_selected().into()
                                    } else {
                                        ui_panel_background_alt().into()
                                    }),
                                    BorderColor::all(if is_selected {
                                        ui_border_selected_color()
                                    } else {
                                        ui_border_color()
                                    }),
                                    GameUiButtonAction::SelectSkill(entry.skill_id.clone()),
                                    SkillHoverTarget {
                                        tree_id: tree.tree_id.clone(),
                                        skill_id: entry.skill_id.clone(),
                                    },
                                    RelativeCursorPosition::default(),
                                    viewer_ui_passthrough_bundle(),
                                ))
                                .with_children(|button| {
                                    button.spawn(text_bundle(
                                        font,
                                        &format!(
                                            "{} · Lv {}/{}",
                                            entry.name, entry.learned_level, entry.max_level
                                        ),
                                        10.6,
                                        if entry.learned_level > 0 {
                                            Color::WHITE
                                        } else {
                                            ui_text_secondary_color()
                                        },
                                    ));
                                    button.spawn(text_bundle(
                                        font,
                                        &format!(
                                            "{} · {}",
                                            activation_mode_label(&entry.activation_mode),
                                            state_label
                                        ),
                                        9.2,
                                        state_color,
                                    ));
                                });
                        }
                    } else {
                        list_column.spawn(text_bundle(
                            font,
                            "没有可供选择的技能",
                            10.5,
                            ui_text_muted_color(),
                        ));
                    }
                });

            columns
                .spawn((
                    Node {
                        flex_grow: 1.0,
                        padding: UiRect::all(px(12)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(6),
                        overflow: Overflow::clip_y(),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(ui_panel_background()),
                    BorderColor::all(ui_border_color()),
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|detail_column| {
                    if let Some(entry) = selected_entry {
                        let display =
                            build_skill_detail_display(selected_tree, entry, hotbar_state);
                        render_skill_detail_content(detail_column, font, &display, entry, true);
                    } else {
                        if let Some(tree) = selected_tree {
                            detail_column.spawn(text_bundle(
                                font,
                                &tree.tree_name,
                                12.0,
                                ui_text_secondary_color(),
                            ));
                            if !tree.tree_description.trim().is_empty() {
                                detail_column.spawn(text_bundle(
                                    font,
                                    &tree.tree_description,
                                    10.0,
                                    ui_text_muted_color(),
                                ));
                            }
                        }
                        detail_column.spawn(text_bundle(
                            font,
                            "选择一个技能后，这里会显示完整描述、前置要求和快捷栏操作。",
                            10.5,
                            ui_text_muted_color(),
                        ));
                    }
                });
        });
    });
}
