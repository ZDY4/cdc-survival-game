use super::*;

pub(super) fn render_inventory_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
) {
    let body = panel_body(parent, UiMenuPanel::Inventory);
    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(
            font,
            &format!(
                "负重 {:.1}/{:.1} · 筛选 {}",
                snapshot.total_weight,
                snapshot.max_weight,
                snapshot.filter.label()
            ),
            10.8,
            Color::srgba(0.84, 0.88, 0.95, 1.0),
        ));
        body.spawn(Node {
            width: Val::Percent(100.0),
            flex_direction: FlexDirection::Column,
            row_gap: px(10),
            ..default()
        })
        .with_children(|layout| {
            layout
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        padding: UiRect::all(px(10)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(8),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.06, 0.07, 0.10, 0.96)),
                    BorderColor::all(Color::srgba(0.19, 0.23, 0.30, 1.0)),
                ))
                .with_children(|equipment| {
                    equipment.spawn(text_bundle(
                        font,
                        "装备区",
                        11.4,
                        Color::srgba(0.94, 0.96, 1.0, 1.0),
                    ));
                    equipment.spawn(text_bundle(
                        font,
                        "左键选择/交换装备槽，右键打开装备操作。",
                        9.8,
                        Color::srgba(0.72, 0.76, 0.82, 1.0),
                    ));
                    if snapshot.equipment.is_empty() {
                        equipment.spawn(text_bundle(
                            font,
                            "当前没有装备槽数据",
                            10.0,
                            Color::srgba(0.72, 0.76, 0.82, 1.0),
                        ));
                    }
                    equipment
                        .spawn(Node {
                            width: Val::Percent(100.0),
                            flex_wrap: FlexWrap::Wrap,
                            column_gap: px(8),
                            row_gap: px(8),
                            ..default()
                        })
                        .with_children(|slots| {
                            for slot in &snapshot.equipment {
                                let is_selected = menu_state.selected_equipment_slot.as_deref()
                                    == Some(slot.slot_id.as_str());
                                slots
                                    .spawn((
                                        Button,
                                        Node {
                                            width: px(164),
                                            min_height: px(62),
                                            padding: UiRect::all(px(8)),
                                            flex_direction: FlexDirection::Column,
                                            justify_content: JustifyContent::SpaceBetween,
                                            border: UiRect::all(px(if is_selected {
                                                2.0
                                            } else {
                                                1.0
                                            })),
                                            ..default()
                                        },
                                        BackgroundColor(if is_selected {
                                            Color::srgba(0.16, 0.18, 0.27, 0.98).into()
                                        } else {
                                            Color::srgba(0.08, 0.09, 0.13, 0.95).into()
                                        }),
                                        BorderColor::all(if is_selected {
                                            Color::srgba(0.72, 0.76, 0.92, 1.0)
                                        } else {
                                            Color::srgba(0.22, 0.25, 0.33, 1.0)
                                        }),
                                        EquipmentSlotClickTarget {
                                            slot_id: slot.slot_id.clone(),
                                            item_id: slot.item_id,
                                        },
                                        RelativeCursorPosition::default(),
                                    ))
                                    .with_children(|slot_button| {
                                        slot_button.spawn(text_bundle(
                                            font,
                                            &slot.slot_label,
                                            9.5,
                                            Color::srgba(0.74, 0.78, 0.86, 1.0),
                                        ));
                                        slot_button.spawn(text_bundle(
                                            font,
                                            slot.item_name.as_deref().unwrap_or("空"),
                                            10.6,
                                            Color::WHITE,
                                        ));
                                    });
                            }
                        });
                });

            layout
                .spawn(Node {
                    width: Val::Percent(100.0),
                    flex_wrap: FlexWrap::Wrap,
                    column_gap: px(6),
                    row_gap: px(6),
                    ..default()
                })
                .with_children(|filters| {
                    for filter in [
                        UiInventoryFilter::All,
                        UiInventoryFilter::Weapon,
                        UiInventoryFilter::Armor,
                        UiInventoryFilter::Accessory,
                        UiInventoryFilter::Consumable,
                        UiInventoryFilter::Material,
                        UiInventoryFilter::Ammo,
                        UiInventoryFilter::Misc,
                    ] {
                        filters.spawn(dock_tab_button(
                            font,
                            filter.label(),
                            snapshot.filter == filter,
                            GameUiButtonAction::InventoryFilter(filter),
                        ));
                    }
                });

            layout
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        padding: UiRect::all(px(10)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(4),
                        border: UiRect::all(px(1)),
                        overflow: Overflow::clip_y(),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.97)),
                    BorderColor::all(Color::srgba(0.19, 0.22, 0.30, 1.0)),
                ))
                .with_children(|entries| {
                    entries.spawn(text_bundle(
                        font,
                        "物品列表",
                        11.2,
                        Color::srgba(0.94, 0.96, 1.0, 1.0),
                    ));
                    entries.spawn(text_bundle(
                        font,
                        "左键选中物品，右键打开可执行操作。",
                        9.8,
                        Color::srgba(0.72, 0.76, 0.82, 1.0),
                    ));
                    if snapshot.entries.is_empty() {
                        entries.spawn(text_bundle(
                            font,
                            "当前筛选下没有物品",
                            10.4,
                            Color::srgba(0.72, 0.76, 0.82, 1.0),
                        ));
                    }
                    for entry in &snapshot.entries {
                        let is_selected = menu_state.selected_inventory_item == Some(entry.item_id);
                        entries.spawn((
                            Button,
                            Node {
                                width: Val::Percent(100.0),
                                padding: UiRect::axes(px(10), px(7)),
                                margin: UiRect::bottom(px(4)),
                                border: UiRect::all(px(if is_selected { 2.0 } else { 1.0 })),
                                align_items: AlignItems::Center,
                                ..default()
                            },
                            BackgroundColor(if is_selected {
                                Color::srgba(0.16, 0.22, 0.31, 0.98).into()
                            } else {
                                interaction_menu_button_color(false, Interaction::None).into()
                            }),
                            BorderColor::all(if is_selected {
                                Color::srgba(0.64, 0.76, 0.94, 1.0)
                            } else {
                                Color::srgba(0.19, 0.24, 0.32, 1.0)
                            }),
                            Text::new(format!(
                                "{} x{} · {} · {:.1}kg",
                                entry.name,
                                entry.count,
                                entry.item_type.as_str(),
                                entry.total_weight
                            )),
                            TextFont::from_font_size(11.0).with_font(font.0.clone()),
                            TextColor(Color::WHITE),
                            InventoryItemHoverTarget {
                                item_id: entry.item_id,
                            },
                            InventoryItemClickTarget {
                                item_id: entry.item_id,
                            },
                            RelativeCursorPosition::default(),
                        ));
                    }
                });
        });
    });
}

pub(super) fn render_character_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCharacterSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Character);
    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(
            font,
            &format!("可用属性点 {}", snapshot.available_points),
            11.0,
            Color::WHITE,
        ));
        for attribute in ["strength", "agility", "constitution"] {
            let value = snapshot.attributes.get(attribute).copied().unwrap_or(0);
            body.spawn(text_bundle(
                font,
                &format!("{attribute}: {value}"),
                11.0,
                Color::WHITE,
            ));
            body.spawn(action_button(
                font,
                &format!("提升 {attribute}"),
                GameUiButtonAction::AllocateAttribute(attribute.to_string()),
            ));
        }
    });
}

pub(super) fn render_journal_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiJournalSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Journal);
    parent.commands().entity(body).with_children(|body| {
        if snapshot.quest_titles.is_empty() {
            body.spawn(text_bundle(
                font,
                "当前没有进行中的任务",
                11.0,
                Color::WHITE,
            ));
        } else {
            for title in &snapshot.quest_titles {
                body.spawn(text_bundle(font, title, 11.0, Color::WHITE));
            }
        }
    });
}

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
        right: px(SCREEN_EDGE_PADDING),
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
            "左侧切技能树，中列浏览当前树，右侧查看详情；选中技能后可加入当前组空槽，或直接点击底栏槽位精确绑定。",
            10.5,
            Color::srgba(0.78, 0.84, 0.92, 1.0),
        ));
        body.spawn(Node {
            width: Val::Percent(100.0),
            column_gap: px(12),
            flex_direction: FlexDirection::Row,
            align_items: AlignItems::Stretch,
            ..default()
        })
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
                    BackgroundColor(Color::srgba(0.05, 0.07, 0.10, 0.96)),
                    BorderColor::all(Color::srgba(0.18, 0.25, 0.33, 1.0)),
                ))
                .with_children(|tree_column| {
                    tree_column.spawn(text_bundle(
                        font,
                        "技能树",
                        11.5,
                        Color::srgba(0.92, 0.95, 1.0, 1.0),
                    ));
                    if snapshot.trees.is_empty() {
                        tree_column.spawn(text_bundle(
                            font,
                            "当前没有可显示的技能树",
                            10.5,
                            Color::srgba(0.72, 0.76, 0.82, 1.0),
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
                                    Color::srgba(0.16, 0.22, 0.31, 0.98).into()
                                } else {
                                    Color::srgba(0.08, 0.10, 0.15, 0.94).into()
                                }),
                                BorderColor::all(if is_selected {
                                    Color::srgba(0.56, 0.72, 0.92, 1.0)
                                } else {
                                    Color::srgba(0.18, 0.25, 0.33, 1.0)
                                }),
                                GameUiButtonAction::SelectSkillTree(tree.tree_id.clone()),
                            ))
                            .with_children(|button| {
                                button.spawn(text_bundle(
                                    font,
                                    &tree.tree_name,
                                    10.8,
                                    if is_selected {
                                        Color::WHITE
                                    } else {
                                        Color::srgba(0.86, 0.90, 0.96, 1.0)
                                    },
                                ));
                                button.spawn(text_bundle(
                                    font,
                                    &format!("{learned_count}/{total_count} 已学习"),
                                    9.2,
                                    Color::srgba(0.67, 0.73, 0.80, 1.0),
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
                    BackgroundColor(Color::srgba(0.05, 0.07, 0.10, 0.96)),
                    BorderColor::all(Color::srgba(0.18, 0.25, 0.33, 1.0)),
                ))
                .with_children(|list_column| {
                    let title = selected_tree
                        .map(|tree| format!("{} 技能", tree.tree_name))
                        .unwrap_or_else(|| "技能列表".to_string());
                    list_column.spawn(text_bundle(
                        font,
                        &title,
                        11.5,
                        Color::srgba(0.92, 0.95, 1.0, 1.0),
                    ));
                    if let Some(tree) = selected_tree {
                        if tree.entries.is_empty() {
                            list_column.spawn(text_bundle(
                                font,
                                "该技能树暂无技能条目",
                                10.5,
                                Color::srgba(0.72, 0.76, 0.82, 1.0),
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
                                        Color::srgba(0.16, 0.22, 0.31, 0.98).into()
                                    } else {
                                        Color::srgba(0.08, 0.10, 0.15, 0.94).into()
                                    }),
                                    BorderColor::all(if is_selected {
                                        Color::srgba(0.64, 0.76, 0.94, 1.0)
                                    } else {
                                        Color::srgba(0.18, 0.25, 0.33, 1.0)
                                    }),
                                    GameUiButtonAction::SelectSkill(entry.skill_id.clone()),
                                    SkillHoverTarget {
                                        tree_id: tree.tree_id.clone(),
                                        skill_id: entry.skill_id.clone(),
                                    },
                                    RelativeCursorPosition::default(),
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
                                            Color::srgba(0.78, 0.82, 0.88, 1.0)
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
                            Color::srgba(0.72, 0.76, 0.82, 1.0),
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
                    BackgroundColor(Color::srgba(0.05, 0.07, 0.10, 0.96)),
                    BorderColor::all(Color::srgba(0.18, 0.25, 0.33, 1.0)),
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
                                Color::srgba(0.82, 0.88, 0.96, 1.0),
                            ));
                            if !tree.tree_description.trim().is_empty() {
                                detail_column.spawn(text_bundle(
                                    font,
                                    &tree.tree_description,
                                    10.0,
                                    Color::srgba(0.70, 0.75, 0.82, 1.0),
                                ));
                            }
                        }
                        detail_column.spawn(text_bundle(
                            font,
                            "选择一个技能后，这里会显示完整描述、前置要求和快捷栏操作。",
                            10.5,
                            Color::srgba(0.72, 0.76, 0.82, 1.0),
                        ));
                    }
                });
        });
    });
}

pub(super) fn render_crafting_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCraftingSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Crafting);
    parent.commands().entity(body).with_children(|body| {
        if snapshot.recipe_names.is_empty() {
            body.spawn(text_bundle(font, "当前没有可制造配方", 11.0, Color::WHITE));
        } else {
            for (recipe_id, recipe_name) in &snapshot.recipe_names {
                body.spawn(action_button(
                    font,
                    recipe_name,
                    GameUiButtonAction::CraftRecipe(recipe_id.clone()),
                ));
            }
        }
    });
}

pub(super) fn render_map_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    current: &game_core::OverworldStateSnapshot,
    overworld: &game_data::OverworldLibrary,
    menu_state: &UiMenuState,
) {
    let body = panel_body(parent, UiMenuPanel::Map);
    parent.commands().entity(body).with_children(|body| {
        let Some((_, definition)) = overworld.iter().next() else {
            return;
        };
        for location in &definition.locations {
            let is_unlocked = current
                .unlocked_locations
                .iter()
                .any(|id| id == location.id.as_str());
            let is_current =
                current.active_outdoor_location_id.as_deref() == Some(location.id.as_str());
            body.spawn(action_button(
                font,
                &format!(
                    "{} · {} · {}{}",
                    location.name,
                    match location.kind {
                        game_data::OverworldLocationKind::Outdoor => "outdoor",
                        game_data::OverworldLocationKind::Interior => "interior",
                        game_data::OverworldLocationKind::Dungeon => "dungeon",
                    },
                    if is_unlocked {
                        "已解锁"
                    } else {
                        "未解锁"
                    },
                    if is_current { " · 当前位置" } else { "" }
                ),
                GameUiButtonAction::SelectMapLocation(location.id.as_str().to_string()),
            ));
            if menu_state.selected_map_location_id.as_deref() == Some(location.id.as_str()) {
                body.spawn(text_bundle(
                    font,
                    "地图面板仅提供地点信息；世界大地图上的实际移动改为直接点格子逐格前进。",
                    10.5,
                    Color::WHITE,
                ));
                body.spawn(text_bundle(
                    font,
                    "到达对应 overworld 格子后，会通过地图触发器进入 outdoor / interior / dungeon。",
                    10.5,
                    Color::WHITE,
                ));
            }
        }
    });
}

pub(super) fn render_settings_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    settings: &ViewerUiSettings,
) {
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: px(0),
            top: px(0),
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            ..default()
        },
        BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.58)),
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        UiMouseBlocker,
    ));

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                top: Val::Percent(50.0),
                margin: UiRect {
                    left: px(-250),
                    top: px(-210),
                    ..default()
                },
                width: px(500),
                min_height: px(420),
                padding: UiRect::all(px(18)),
                flex_direction: FlexDirection::Column,
                row_gap: px(10),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.985)),
            BorderColor::all(Color::srgba(0.28, 0.31, 0.40, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn(text_bundle(font, "游戏菜单", 18.0, Color::WHITE));
            body.spawn(text_bundle(
                font,
                "按 Esc 关闭菜单并返回游戏",
                10.4,
                Color::srgba(0.80, 0.84, 0.91, 1.0),
            ));
            body.spawn(action_button(
                font,
                &format!("Master {:.0}%", settings.master_volume * 100.0),
                GameUiButtonAction::SettingsSetMaster(if settings.master_volume > 0.0 {
                    0.0
                } else {
                    1.0
                }),
            ));
            body.spawn(action_button(
                font,
                &format!("Music {:.0}%", settings.music_volume * 100.0),
                GameUiButtonAction::SettingsSetMusic(if settings.music_volume > 0.0 {
                    0.0
                } else {
                    1.0
                }),
            ));
            body.spawn(action_button(
                font,
                &format!("SFX {:.0}%", settings.sfx_volume * 100.0),
                GameUiButtonAction::SettingsSetSfx(if settings.sfx_volume > 0.0 {
                    0.0
                } else {
                    1.0
                }),
            ));
            body.spawn(action_button(
                font,
                &format!("窗口模式 {}", settings.window_mode),
                GameUiButtonAction::SettingsSetWindowMode(match settings.window_mode.as_str() {
                    "windowed" => "borderless_fullscreen".to_string(),
                    "borderless_fullscreen" => "fullscreen".to_string(),
                    _ => "windowed".to_string(),
                }),
            ));
            body.spawn(action_button(
                font,
                &format!("VSync {}", if settings.vsync { "On" } else { "Off" }),
                GameUiButtonAction::SettingsSetVsync(!settings.vsync),
            ));
            body.spawn(action_button(
                font,
                &format!("UI Scale {:.1}", settings.ui_scale),
                GameUiButtonAction::SettingsSetUiScale(if settings.ui_scale < 1.0 {
                    1.0
                } else {
                    0.85
                }),
            ));
            for action_name in [
                "menu_inventory",
                "menu_character",
                "menu_map",
                "menu_journal",
                "menu_skills",
                "menu_crafting",
            ] {
                let current = settings
                    .action_bindings
                    .get(action_name)
                    .cloned()
                    .unwrap_or_else(|| "Unbound".to_string());
                body.spawn(action_button(
                    font,
                    &format!("{action_name}: {current}"),
                    GameUiButtonAction::SettingsCycleBinding(action_name.to_string()),
                ));
            }
        });
}
