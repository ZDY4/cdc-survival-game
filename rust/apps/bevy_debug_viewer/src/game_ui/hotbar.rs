use super::*;

pub(crate) fn tick_hotbar_cooldowns(
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut hotbar: ResMut<UiHotbarState>,
) {
    runtime_state
        .runtime
        .advance_skill_timers(time.delta_secs());
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return;
    };

    for group in &mut hotbar.groups {
        for slot in group {
            if let Some(skill_id) = slot.skill_id.as_deref() {
                slot.cooldown_remaining = runtime_state
                    .runtime
                    .skill_cooldown_remaining(actor_id, skill_id);
                slot.toggled = runtime_state
                    .runtime
                    .is_skill_toggled_active(actor_id, skill_id);
            } else {
                slot.cooldown_remaining = 0.0;
                slot.toggled = false;
            }
        }
    }
}

pub(super) fn sync_skill_selection_state(
    menu_state: &mut UiMenuState,
    runtime_state: &ViewerRuntimeState,
    skills: &SkillDefinitions,
    trees: &SkillTreeDefinitions,
) {
    let Some(snapshot) = skills_snapshot_for_player(runtime_state, skills, trees) else {
        menu_state.selected_skill_tree_id = None;
        menu_state.selected_skill_id = None;
        return;
    };

    let tree_from_selected_skill = menu_state
        .selected_skill_id
        .as_deref()
        .and_then(|skill_id| find_skill_tree_id(&snapshot, skill_id));
    let selected_tree = tree_from_selected_skill
        .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        .or_else(|| {
            menu_state
                .selected_skill_tree_id
                .as_deref()
                .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        })
        .or_else(|| snapshot.trees.iter().find(|tree| !tree.entries.is_empty()))
        .or_else(|| snapshot.trees.first());

    let Some(selected_tree) = selected_tree else {
        menu_state.selected_skill_tree_id = None;
        menu_state.selected_skill_id = None;
        return;
    };

    menu_state.selected_skill_tree_id = Some(selected_tree.tree_id.clone());
    let selected_skill_is_in_tree = menu_state
        .selected_skill_id
        .as_deref()
        .and_then(|skill_id| {
            selected_tree
                .entries
                .iter()
                .find(|entry| entry.skill_id == skill_id)
        })
        .is_some();
    if !selected_skill_is_in_tree {
        menu_state.selected_skill_id = selected_tree
            .entries
            .first()
            .map(|entry| entry.skill_id.clone());
    }
}

pub(super) fn validate_hotbar_skill_binding(
    runtime_state: &ViewerRuntimeState,
    skills: &SkillDefinitions,
    skill_id: &str,
) -> Result<(), String> {
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return Err("missing_player".to_string());
    };
    let Some(skill) = skills.0.get(skill_id) else {
        return Err(format!("未知技能 {skill_id}"));
    };
    let learned_level = runtime_state
        .runtime
        .economy()
        .actor(actor_id)
        .and_then(|actor| actor.learned_skills.get(skill_id))
        .copied()
        .unwrap_or(0);
    if learned_level <= 0 {
        return Err(format!("{} 尚未学习", skill.name));
    }
    let activation_mode = skill
        .activation
        .as_ref()
        .map(|activation| activation.mode.as_str())
        .unwrap_or("passive");
    if activation_mode == "passive" {
        return Err(format!("{} 为被动技能，无法绑定快捷栏", skill.name));
    }
    Ok(())
}

pub(super) fn assign_skill_to_hotbar_slot(
    hotbar_state: &mut UiHotbarState,
    menu_state: &mut UiMenuState,
    skill_id: String,
    group: usize,
    slot: usize,
) -> bool {
    let Some(group_slots) = hotbar_state.groups.get_mut(group) else {
        menu_state.status_text = format!("快捷栏第 {} 组不存在", group.saturating_add(1));
        return false;
    };
    let Some(slot_state) = group_slots.get_mut(slot) else {
        menu_state.status_text = format!(
            "快捷栏第 {} 组不存在第 {} 槽",
            group.saturating_add(1),
            slot.saturating_add(1)
        );
        return false;
    };

    slot_state.skill_id = Some(skill_id.clone());
    slot_state.cooldown_remaining = 0.0;
    slot_state.toggled = false;
    menu_state.status_text = format!(
        "已将 {skill_id} 绑定到第 {} 组第 {} 槽",
        group.saturating_add(1),
        slot.saturating_add(1)
    );
    true
}

pub(crate) fn activate_hotbar_slot(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    skills: &SkillDefinitions,
    hotbar_state: &mut UiHotbarState,
    slot: usize,
) {
    let Some(group) = hotbar_state.groups.get_mut(hotbar_state.active_group) else {
        return;
    };
    let Some(slot_state) = group.get_mut(slot) else {
        return;
    };
    let Some(skill_id) = slot_state.skill_id.clone() else {
        hotbar_state.last_activation_status = Some(format!("槽位 {} 为空", slot + 1));
        return;
    };
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return;
    };
    let runtime_skill_state = runtime_state.runtime.skill_state(actor_id, &skill_id);
    if runtime_skill_state.cooldown_remaining > 0.0 {
        hotbar_state.last_activation_status = Some(format!(
            "{} 冷却中 {:.1}s",
            skill_id, runtime_skill_state.cooldown_remaining
        ));
        return;
    }
    let learned_level = runtime_state
        .runtime
        .economy()
        .actor(actor_id)
        .and_then(|actor| actor.learned_skills.get(&skill_id))
        .copied()
        .unwrap_or(0);
    if learned_level <= 0 {
        hotbar_state.last_activation_status = Some(format!("{skill_id} 尚未学习"));
        return;
    }
    if let Some(skill) = skills.0.get(&skill_id) {
        if let Some(activation) = skill.activation.as_ref() {
            if activation
                .targeting
                .as_ref()
                .is_some_and(|targeting| targeting.enabled)
            {
                match enter_skill_targeting(
                    runtime_state,
                    viewer_state,
                    skills,
                    &skill_id,
                    crate::state::ViewerTargetingSource::HotbarSlot(slot),
                ) {
                    Ok(()) => {
                        hotbar_state.last_activation_status =
                            Some(format!("{}: 选择目标", skill.name));
                    }
                    Err(error) => {
                        hotbar_state.last_activation_status = Some(error);
                    }
                }
            } else {
                let actor_grid = runtime_state
                    .runtime
                    .get_actor_grid_position(actor_id)
                    .unwrap_or_default();
                let result = runtime_state.runtime.activate_skill(
                    actor_id,
                    &skill_id,
                    game_data::SkillTargetRequest::Grid(actor_grid),
                );
                slot_state.cooldown_remaining = runtime_state
                    .runtime
                    .skill_cooldown_remaining(actor_id, &skill_id);
                slot_state.toggled = runtime_state
                    .runtime
                    .is_skill_toggled_active(actor_id, &skill_id);
                hotbar_state.last_activation_status = Some(if result.action_result.success {
                    format!(
                        "{}: {}",
                        skill.name,
                        game_core::runtime::action_result_status(&result.action_result)
                    )
                } else {
                    format!(
                        "{}: {}",
                        skill.name,
                        result
                            .failure_reason
                            .clone()
                            .or(result.action_result.reason.clone())
                            .unwrap_or_else(|| "failed".to_string())
                    )
                });
            }
        } else {
            hotbar_state.last_activation_status = Some(format!("{} 无主动效果", skill.name));
        }
    }
}

pub(super) fn render_hotbar_slots(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    let Some(active_group) = hotbar_state.groups.get(hotbar_state.active_group) else {
        return;
    };

    parent
        .spawn(Node {
            width: Val::Percent(100.0),
            flex_direction: FlexDirection::Row,
            column_gap: px(4),
            justify_content: JustifyContent::Center,
            ..default()
        })
        .with_children(|slots| {
            for (slot_index, slot) in active_group.iter().enumerate() {
                let skill_name = slot
                    .skill_id
                    .as_deref()
                    .and_then(|skill_id| skills.get(skill_id))
                    .map(|skill| skill.name.as_str());
                let short_name = skill_name
                    .map(|name| compact_skill_name(name, 8))
                    .unwrap_or_else(|| "空槽".to_string());
                let skill_abbreviation = skill_name
                    .map(abbreviated_skill_name)
                    .unwrap_or_else(|| "·".to_string());
                let footer_label = if slot.cooldown_remaining > 0.0 {
                    format!("{:.1}s", slot.cooldown_remaining)
                } else {
                    short_name.clone()
                };
                let is_selected_skill = selected_skill_id
                    .map(|skill_id| slot.skill_id.as_deref() == Some(skill_id))
                    .unwrap_or(false);
                let primary_action = if let Some(skill_id) = selected_skill_id {
                    GameUiButtonAction::AssignSkillToHotbar {
                        skill_id: skill_id.to_string(),
                        group: hotbar_state.active_group,
                        slot: slot_index,
                    }
                } else {
                    GameUiButtonAction::ActivateHotbarSlot(slot_index)
                };
                let border_color = if slot.toggled {
                    Color::srgba(0.42, 0.78, 0.56, 1.0)
                } else if is_selected_skill {
                    Color::srgba(0.92, 0.74, 0.38, 1.0)
                } else if slot.skill_id.is_some() {
                    Color::srgba(0.22, 0.32, 0.44, 1.0)
                } else {
                    Color::srgba(0.14, 0.18, 0.24, 1.0)
                };
                let background = if slot.skill_id.is_none() {
                    Color::srgba(0.05, 0.06, 0.09, 0.94)
                } else if slot.cooldown_remaining > 0.0 {
                    Color::srgba(0.08, 0.10, 0.16, 0.96)
                } else {
                    Color::srgba(0.08, 0.11, 0.17, 0.98)
                };
                slots
                    .spawn(Node {
                        width: px(HOTBAR_SLOT_SIZE),
                        min_height: px(HOTBAR_SLOT_SIZE),
                        position_type: PositionType::Relative,
                        ..default()
                    })
                    .with_children(|slot_wrapper| {
                        slot_wrapper
                            .spawn((
                                Button,
                                Node {
                                    width: px(HOTBAR_SLOT_SIZE),
                                    min_height: px(HOTBAR_SLOT_SIZE),
                                    padding: UiRect::all(px(6)),
                                    flex_direction: FlexDirection::Column,
                                    justify_content: JustifyContent::SpaceBetween,
                                    border: UiRect::all(px(if slot.toggled || is_selected_skill {
                                        2.0
                                    } else {
                                        1.0
                                    })),
                                    ..default()
                                },
                                BackgroundColor(background.into()),
                                BorderColor::all(border_color),
                                primary_action,
                            ))
                            .with_children(|button| {
                                button
                                    .spawn(Node {
                                        width: Val::Percent(100.0),
                                        flex_direction: FlexDirection::Row,
                                        justify_content: JustifyContent::SpaceBetween,
                                        ..default()
                                    })
                                    .with_children(|top_row| {
                                        top_row.spawn(text_bundle(
                                            font,
                                            hotbar_key_label(slot_index),
                                            8.2,
                                            if slot.skill_id.is_some() {
                                                Color::srgba(0.82, 0.86, 0.94, 1.0)
                                            } else {
                                                Color::srgba(0.52, 0.57, 0.66, 1.0)
                                            },
                                        ));
                                        if slot.toggled {
                                            top_row.spawn(text_bundle(
                                                font,
                                                "ON",
                                                7.8,
                                                Color::srgba(0.56, 0.88, 0.62, 1.0),
                                            ));
                                        }
                                    });
                                button.spawn(text_bundle(
                                    font,
                                    &skill_abbreviation,
                                    13.0,
                                    if slot.skill_id.is_some() {
                                        Color::WHITE
                                    } else {
                                        Color::srgba(0.46, 0.50, 0.58, 1.0)
                                    },
                                ));
                                button.spawn(text_bundle(
                                    font,
                                    &footer_label,
                                    8.0,
                                    if slot.skill_id.is_some() {
                                        Color::srgba(0.80, 0.84, 0.92, 1.0)
                                    } else {
                                        Color::srgba(0.44, 0.48, 0.56, 1.0)
                                    },
                                ));
                                if slot.cooldown_remaining > 0.0 {
                                    button
                                        .spawn((
                                            Node {
                                                position_type: PositionType::Absolute,
                                                left: px(0),
                                                top: px(0),
                                                width: Val::Percent(100.0),
                                                height: Val::Percent(100.0),
                                                justify_content: JustifyContent::FlexEnd,
                                                align_items: AlignItems::FlexEnd,
                                                padding: UiRect::all(px(6)),
                                                ..default()
                                            },
                                            BackgroundColor(Color::srgba(0.01, 0.02, 0.04, 0.55)),
                                        ))
                                        .with_children(|overlay| {
                                            overlay.spawn(text_bundle(
                                                font,
                                                &format!("{:.1}s", slot.cooldown_remaining),
                                                8.2,
                                                Color::WHITE,
                                            ));
                                        });
                                }
                            });

                        if show_clear_controls && slot.skill_id.is_some() {
                            slot_wrapper
                                .spawn((
                                    Button,
                                    Node {
                                        position_type: PositionType::Absolute,
                                        top: px(-4),
                                        right: px(-4),
                                        width: px(18),
                                        height: px(18),
                                        justify_content: JustifyContent::Center,
                                        align_items: AlignItems::Center,
                                        border: UiRect::all(px(1)),
                                        ..default()
                                    },
                                    BackgroundColor(Color::srgba(0.22, 0.08, 0.08, 0.94).into()),
                                    BorderColor::all(Color::srgba(0.74, 0.40, 0.40, 1.0)),
                                    GameUiButtonAction::ClearHotbarSlot {
                                        group: hotbar_state.active_group,
                                        slot: slot_index,
                                    },
                                ))
                                .with_children(|clear| {
                                    clear.spawn(text_bundle(font, "×", 8.8, Color::WHITE));
                                });
                        }
                    });
            }
        });
}

#[allow(dead_code)]
pub(super) fn render_hotbar_legacy(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    viewer_state: &ViewerState,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    menu_state: &UiMenuState,
    player_stats: Option<&PlayerHudStats>,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    let binding_hint = selected_skill_id
        .and_then(|skill_id| skills.get(skill_id).map(|skill| skill.name.as_str()))
        .map(|skill_name| {
            format!(
                "绑定模式 · 已选 {}，点击底栏槽位可精确放入当前组",
                skill_name
            )
        })
        .unwrap_or_else(|| "数字键 1-0 激活当前组槽位".to_string());
    let status_hint = hotbar_state
        .last_activation_status
        .as_deref()
        .map(|status| truncate_ui_text(status, 36))
        .unwrap_or_else(|| "上次激活状态会显示在这里".to_string());
    let attack_targeting_active = viewer_state
        .targeting_state
        .as_ref()
        .is_some_and(|targeting| targeting.is_attack());
    let attack_enabled = !viewer_state.is_free_observe() && viewer_state.selected_actor.is_some();
    let hp_text = player_stats
        .map(|stats| format!("{:.0} / {:.0}", stats.hp, stats.max_hp))
        .unwrap_or_else(|| "-- / --".to_string());
    let hp_ratio = player_stats
        .map(|stats| {
            if stats.max_hp <= 0.0 {
                0.0
            } else {
                (stats.hp / stats.max_hp).clamp(0.0, 1.0)
            }
        })
        .unwrap_or(0.0);
    let action_text = player_stats
        .map(|stats| format!("{:.1} AP · {}步", stats.ap, stats.available_steps))
        .unwrap_or_else(|| "--".to_string());
    let action_ratio = player_stats.map(action_meter_ratio).unwrap_or(0.0);

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                bottom: px(SCREEN_EDGE_PADDING),
                margin: UiRect {
                    left: px(-(HOTBAR_DOCK_WIDTH / 2.0)),
                    ..default()
                },
                width: px(HOTBAR_DOCK_WIDTH),
                min_height: px(HOTBAR_DOCK_HEIGHT),
                padding: UiRect::all(px(12)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.03, 0.035, 0.05, 0.93)),
            BorderColor::all(Color::srgba(0.24, 0.28, 0.37, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn(Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                justify_content: JustifyContent::SpaceBetween,
                align_items: AlignItems::Center,
                ..default()
            })
            .with_children(|header| {
                header
                    .spawn(Node {
                        flex_direction: FlexDirection::Row,
                        column_gap: px(8),
                        align_items: AlignItems::Center,
                        ..default()
                    })
                    .with_children(|left| {
                        left.spawn((
                            Node {
                                padding: UiRect::axes(px(10), px(4)),
                                border: UiRect::all(px(1)),
                                ..default()
                            },
                            BackgroundColor(Color::srgba(0.10, 0.13, 0.18, 1.0)),
                            BorderColor::all(Color::srgba(0.34, 0.46, 0.62, 1.0)),
                            children![text_bundle(
                                font,
                                &format!("组 {}", hotbar_state.active_group + 1),
                                9.8,
                                Color::WHITE
                            )],
                        ));
                        left.spawn((
                            Button,
                            Node {
                                padding: UiRect::axes(px(10), px(5)),
                                border: UiRect::all(px(if attack_targeting_active {
                                    2.0
                                } else {
                                    1.0
                                })),
                                ..default()
                            },
                            BackgroundColor(if attack_targeting_active {
                                Color::srgba(0.28, 0.12, 0.10, 0.98).into()
                            } else if attack_enabled {
                                Color::srgba(0.12, 0.09, 0.08, 0.96).into()
                            } else {
                                Color::srgba(0.07, 0.07, 0.08, 0.94).into()
                            }),
                            BorderColor::all(if attack_targeting_active {
                                Color::srgba(0.96, 0.54, 0.44, 1.0)
                            } else if attack_enabled {
                                Color::srgba(0.56, 0.32, 0.28, 1.0)
                            } else {
                                Color::srgba(0.20, 0.20, 0.22, 1.0)
                            }),
                            GameUiButtonAction::EnterAttackTargeting,
                        ))
                        .with_children(|button| {
                            button.spawn(text_bundle(
                                font,
                                if attack_targeting_active {
                                    "攻击中"
                                } else {
                                    "普通攻击"
                                },
                                9.6,
                                if attack_enabled {
                                    Color::WHITE
                                } else {
                                    Color::srgba(0.52, 0.54, 0.58, 1.0)
                                },
                            ));
                        });
                    });
                header.spawn(text_bundle(
                    font,
                    &status_hint,
                    9.8,
                    Color::srgba(0.78, 0.83, 0.92, 1.0),
                ));
            });
            body.spawn(Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                column_gap: px(10),
                align_items: AlignItems::FlexStart,
                ..default()
            })
            .with_children(|content| {
                content
                    .spawn((
                        Node {
                            width: px(214),
                            padding: UiRect::all(px(10)),
                            flex_direction: FlexDirection::Column,
                            row_gap: px(8),
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.98)),
                        BorderColor::all(Color::srgba(0.18, 0.21, 0.29, 1.0)),
                    ))
                    .with_children(|left| {
                        left.spawn(text_bundle(
                            font,
                            &binding_hint,
                            9.4,
                            Color::srgba(0.70, 0.75, 0.84, 1.0),
                        ));
                        left.spawn(Node {
                            width: Val::Percent(100.0),
                            flex_direction: FlexDirection::Row,
                            column_gap: px(6),
                            flex_wrap: FlexWrap::Wrap,
                            ..default()
                        })
                        .with_children(|groups| {
                            for group_index in 0..hotbar_state.groups.len() {
                                let is_selected = group_index == hotbar_state.active_group;
                                groups
                                    .spawn((
                                        Button,
                                        Node {
                                            width: px(34),
                                            height: px(28),
                                            justify_content: JustifyContent::Center,
                                            align_items: AlignItems::Center,
                                            border: UiRect::all(px(if is_selected {
                                                2.0
                                            } else {
                                                1.0
                                            })),
                                            ..default()
                                        },
                                        BackgroundColor(if is_selected {
                                            Color::srgba(0.16, 0.22, 0.31, 1.0).into()
                                        } else {
                                            Color::srgba(0.08, 0.10, 0.15, 0.94).into()
                                        }),
                                        BorderColor::all(if is_selected {
                                            Color::srgba(0.64, 0.76, 0.94, 1.0)
                                        } else {
                                            Color::srgba(0.18, 0.25, 0.33, 1.0)
                                        }),
                                        GameUiButtonAction::SelectHotbarGroup(group_index),
                                    ))
                                    .with_children(|button| {
                                        button.spawn(text_bundle(
                                            font,
                                            &(group_index + 1).to_string(),
                                            9.2,
                                            if is_selected {
                                                Color::WHITE
                                            } else {
                                                Color::srgba(0.76, 0.80, 0.88, 1.0)
                                            },
                                        ));
                                    });
                            }
                        });
                        render_stat_meter(
                            left,
                            font,
                            "生命",
                            &hp_text,
                            hp_ratio,
                            Color::srgba(0.68, 0.16, 0.18, 1.0),
                            Color::srgba(0.54, 0.20, 0.22, 1.0),
                        );
                        render_stat_meter(
                            left,
                            font,
                            "行动",
                            &action_text,
                            action_ratio,
                            Color::srgba(0.18, 0.44, 0.70, 1.0),
                            Color::srgba(0.24, 0.40, 0.58, 1.0),
                        );
                    });

                content
                    .spawn(Node {
                        flex_grow: 1.0,
                        flex_direction: FlexDirection::Column,
                        row_gap: px(8),
                        ..default()
                    })
                    .with_children(|main| {
                        render_hotbar_slots(
                            main,
                            font,
                            hotbar_state,
                            skills,
                            show_clear_controls,
                            selected_skill_id,
                        );
                        main.spawn(Node {
                            width: Val::Percent(100.0),
                            flex_direction: FlexDirection::Row,
                            justify_content: JustifyContent::SpaceBetween,
                            align_items: AlignItems::Center,
                            column_gap: px(8),
                            ..default()
                        })
                        .with_children(|footer| {
                            footer
                                .spawn(Node {
                                    flex_direction: FlexDirection::Row,
                                    column_gap: px(6),
                                    flex_wrap: FlexWrap::Wrap,
                                    ..default()
                                })
                                .with_children(|tabs| {
                                    for panel in [
                                        UiMenuPanel::Inventory,
                                        UiMenuPanel::Journal,
                                        UiMenuPanel::Character,
                                        UiMenuPanel::Skills,
                                        UiMenuPanel::Crafting,
                                        UiMenuPanel::Map,
                                        UiMenuPanel::Settings,
                                    ] {
                                        tabs.spawn(dock_tab_button(
                                            font,
                                            panel_tab_label(panel),
                                            menu_state.active_panel == Some(panel),
                                            GameUiButtonAction::TogglePanel(panel),
                                        ));
                                    }
                                });
                            footer.spawn(dock_tab_button(
                                font,
                                "关闭",
                                menu_state.active_panel.is_none(),
                                GameUiButtonAction::ClosePanels,
                            ));
                        });
                    });
            });
        });
}

pub(super) fn render_hotbar(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    viewer_state: &ViewerState,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    menu_state: &UiMenuState,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    let binding_hint = selected_skill_id
        .and_then(|skill_id| skills.get(skill_id).map(|skill| skill.name.as_str()))
        .map(|skill_name| {
            format!(
                "绑定模式 · 已选 {}，点击底栏槽位可精确放入当前组",
                skill_name
            )
        })
        .unwrap_or_else(|| "数字键 1-0 激活当前组槽位".to_string());
    let attack_targeting_active = viewer_state
        .targeting_state
        .as_ref()
        .is_some_and(|targeting| targeting.is_attack());
    let attack_enabled = !viewer_state.is_free_observe() && viewer_state.selected_actor.is_some();
    let left_tabs = [
        UiMenuPanel::Character,
        UiMenuPanel::Journal,
        UiMenuPanel::Skills,
    ];
    let right_tabs = [
        UiMenuPanel::Inventory,
        UiMenuPanel::Crafting,
        UiMenuPanel::Map,
        UiMenuPanel::Settings,
    ];

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                bottom: px(0),
                margin: UiRect {
                    left: px(-(HOTBAR_DOCK_WIDTH / 2.0)),
                    ..default()
                },
                width: px(HOTBAR_DOCK_WIDTH),
                min_height: px(HOTBAR_DOCK_HEIGHT),
                padding: UiRect {
                    left: px(12),
                    right: px(12),
                    top: px(10),
                    bottom: px(8),
                },
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.03, 0.035, 0.05, 0.93)),
            BorderColor::all(Color::srgba(0.24, 0.28, 0.37, 1.0)),
        ))
        .with_children(|body| {
            body.spawn(Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                column_gap: px(10),
                align_items: AlignItems::Center,
                ..default()
            })
            .with_children(|header| {
                header
                    .spawn(Node {
                        width: px(HOTBAR_ACTION_WIDTH),
                        flex_direction: FlexDirection::Row,
                        justify_content: JustifyContent::FlexStart,
                        align_items: AlignItems::Center,
                        ..default()
                    })
                    .with_children(|left| {
                        left.spawn((
                            Button,
                            Node {
                                padding: UiRect::axes(px(10), px(5)),
                                border: UiRect::all(px(if attack_targeting_active {
                                    2.0
                                } else {
                                    1.0
                                })),
                                ..default()
                            },
                            BackgroundColor(if attack_targeting_active {
                                Color::srgba(0.28, 0.12, 0.10, 0.98).into()
                            } else if attack_enabled {
                                Color::srgba(0.12, 0.09, 0.08, 0.96).into()
                            } else {
                                Color::srgba(0.07, 0.07, 0.08, 0.94).into()
                            }),
                            BorderColor::all(if attack_targeting_active {
                                Color::srgba(0.96, 0.54, 0.44, 1.0)
                            } else if attack_enabled {
                                Color::srgba(0.56, 0.32, 0.28, 1.0)
                            } else {
                                Color::srgba(0.20, 0.20, 0.22, 1.0)
                            }),
                            GameUiButtonAction::EnterAttackTargeting,
                        ))
                        .with_children(|button| {
                            button.spawn(text_bundle(
                                font,
                                if attack_targeting_active {
                                    "攻击中"
                                } else {
                                    "普通攻击"
                                },
                                9.2,
                                if attack_enabled {
                                    Color::WHITE
                                } else {
                                    Color::srgba(0.52, 0.54, 0.58, 1.0)
                                },
                            ));
                        });
                    });

                header
                    .spawn((
                        Node {
                            flex_grow: 1.0,
                            padding: UiRect::axes(px(12), px(10)),
                            flex_direction: FlexDirection::Column,
                            justify_content: JustifyContent::Center,
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.98)),
                        BorderColor::all(Color::srgba(0.18, 0.21, 0.29, 1.0)),
                    ))
                    .with_children(|stats_panel| {
                        stats_panel.spawn(text_bundle(
                            font,
                            &binding_hint,
                            9.0,
                            Color::srgba(0.70, 0.75, 0.84, 1.0),
                        ));
                    });
            });

            body.spawn(Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                align_items: AlignItems::Center,
                column_gap: px(8),
                ..default()
            })
            .with_children(|row| {
                row.spawn(Node {
                    width: px(HOTBAR_LEFT_TABS_WIDTH),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(6),
                    justify_content: JustifyContent::FlexStart,
                    align_items: AlignItems::Center,
                    ..default()
                })
                .with_children(|tabs| {
                    for panel in left_tabs {
                        tabs.spawn(dock_tab_button(
                            font,
                            panel_tab_label(panel),
                            menu_state.active_panel == Some(panel),
                            GameUiButtonAction::TogglePanel(panel),
                        ));
                    }
                });

                row.spawn(Node {
                    flex_grow: 1.0,
                    ..default()
                })
                .with_children(|slots_wrap| {
                    render_hotbar_slots(
                        slots_wrap,
                        font,
                        hotbar_state,
                        skills,
                        show_clear_controls,
                        selected_skill_id,
                    );
                });

                row.spawn(Node {
                    width: px(HOTBAR_RIGHT_TABS_WIDTH),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(6),
                    justify_content: JustifyContent::FlexEnd,
                    align_items: AlignItems::Center,
                    ..default()
                })
                .with_children(|tabs| {
                    for panel in right_tabs {
                        tabs.spawn(dock_tab_button(
                            font,
                            panel_tab_label(panel),
                            menu_state.active_panel == Some(panel),
                            GameUiButtonAction::TogglePanel(panel),
                        ));
                    }
                    tabs.spawn(dock_tab_button(
                        font,
                        "关闭",
                        menu_state.active_panel.is_none(),
                        GameUiButtonAction::ClosePanels,
                    ));
                });
            });
        });
}
