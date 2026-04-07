//! 屏幕叠加层模块：负责角色标签、伤害数字、交互菜单和对话面板等 2D 叠加内容。

use super::*;
use bevy::text::{Justify, LineBreak, TextLayout};

pub(crate) fn clear_actor_labels(
    mut commands: Commands,
    mut label_entities: ResMut<ActorLabelEntities>,
) {
    for entity in label_entities.by_actor.drain().map(|(_, entity)| entity) {
        commands.entity(entity).despawn();
    }
}

pub(crate) fn sync_actor_labels(
    mut commands: Commands,
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    viewer_state: Res<ViewerState>,
    palette: Res<ViewerPalette>,
    render_config: Res<ViewerRenderConfig>,
    viewer_font: Res<ViewerUiFont>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    mut label_entities: ResMut<ActorLabelEntities>,
    mut labels: Query<(
        Entity,
        &mut Text,
        &mut Node,
        &mut TextColor,
        &mut Visibility,
        Option<&InteractionLockedActorTag>,
        &ActorLabel,
    )>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let mut seen_actor_ids = HashSet::new();
    let hovered_actor_id = viewer_state
        .hovered_grid
        .and_then(|grid| {
            snapshot
                .actors
                .iter()
                .find(|actor| actor.grid_position == grid)
        })
        .map(|actor| actor.actor_id);

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        seen_actor_ids.insert(actor.actor_id);
        let interaction_locked =
            viewer_state.is_actor_interaction_locked(&runtime_state, actor.actor_id);
        let actor_visible = current_focus_actor_vision(&snapshot, &viewer_state)
            .map(|vision| vision.visible_cells.contains(&actor.grid_position))
            .unwrap_or(true);
        let should_show_label = should_show_actor_label(
            *render_config,
            &viewer_state,
            actor,
            interaction_locked,
            hovered_actor_id,
        ) && actor_visible;
        let label = if interaction_locked {
            format!("{} [交互中]", actor_label(actor))
        } else {
            actor_label(actor)
        };
        let color = actor_color(actor.side, &palette);
        let world_position = actor_label_world_position(
            actor_visual_world_position(&runtime_state, &motion_state, actor),
            snapshot.grid.grid_size,
            *render_config,
        );
        let viewport = camera.world_to_viewport(&camera_transform, world_position);

        if let Some(entity) = label_entities.by_actor.get(&actor.actor_id).copied() {
            if let Ok((
                label_entity,
                mut text,
                mut node,
                mut text_color,
                mut visibility,
                interaction_tag,
                label_actor,
            )) = labels.get_mut(entity)
            {
                if label_actor.actor_id == actor.actor_id {
                    *text = Text::new(label);
                    *text_color = TextColor(color);
                    if let Ok(viewport_position) = viewport {
                        node.left =
                            px(viewport_position.x + render_config.label_screen_offset_px.x);
                        node.top = px(viewport_position.y + render_config.label_screen_offset_px.y);
                        *visibility = if should_show_label {
                            Visibility::Visible
                        } else {
                            Visibility::Hidden
                        };
                    } else {
                        *visibility = Visibility::Hidden;
                    }
                    sync_interaction_lock_tag(
                        &mut commands,
                        label_entity,
                        interaction_tag.is_some(),
                        interaction_locked,
                    );
                    continue;
                }
            }
        }

        let mut node = Node {
            position_type: PositionType::Absolute,
            padding: UiRect::axes(px(8), px(3)),
            ..default()
        };
        let mut visibility = Visibility::Hidden;
        if should_show_label {
            if let Ok(viewport_position) = viewport {
                node.left = px(viewport_position.x + render_config.label_screen_offset_px.x);
                node.top = px(viewport_position.y + render_config.label_screen_offset_px.y);
                visibility = Visibility::Visible;
            }
        }
        let mut entity = commands.spawn((
            Text::new(label),
            TextFont::from_font_size(13.5).with_font(viewer_font.0.clone()),
            TextColor(color),
            node,
            BackgroundColor(palette.label_background),
            visibility,
            ActorLabel {
                actor_id: actor.actor_id,
            },
        ));
        if interaction_locked {
            entity.insert(InteractionLockedActorTag);
        }
        let entity = entity.id();
        label_entities.by_actor.insert(actor.actor_id, entity);
    }

    let stale_actor_ids: Vec<_> = label_entities
        .by_actor
        .keys()
        .copied()
        .filter(|actor_id| !seen_actor_ids.contains(actor_id))
        .collect();
    for actor_id in stale_actor_ids {
        if let Some(entity) = label_entities.by_actor.remove(&actor_id) {
            commands.entity(entity).despawn();
        }
    }
}

pub(crate) fn clear_damage_numbers(
    mut commands: Commands,
    mut damage_numbers: ResMut<ViewerDamageNumberState>,
    mut visual_state: ResMut<DamageNumberVisualState>,
) {
    damage_numbers.entries.clear();
    for entity in visual_state.by_id.drain().map(|(_, entity)| entity) {
        commands.entity(entity).despawn();
    }
}

pub(crate) fn sync_damage_numbers(
    mut commands: Commands,
    time: Res<Time>,
    viewer_font: Res<ViewerUiFont>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    mut damage_numbers: ResMut<ViewerDamageNumberState>,
    mut visual_state: ResMut<DamageNumberVisualState>,
    mut labels: Query<(
        Entity,
        &mut Text,
        &mut TextFont,
        &mut TextColor,
        &mut Node,
        &mut Visibility,
        &DamageNumberLabel,
    )>,
) {
    damage_numbers.advance(time.delta_secs());

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let mut seen_ids = HashSet::new();

    for (id, entry) in &damage_numbers.entries {
        seen_ids.insert(*id);
        let viewport = camera.world_to_viewport(&camera_transform, entry.current_world_position());

        if let Some(entity) = visual_state.by_id.get(id).copied() {
            if let Ok((
                _,
                mut text,
                mut text_font,
                mut text_color,
                mut node,
                mut visibility,
                damage_label,
            )) = labels.get_mut(entity)
            {
                if damage_label.id == *id {
                    *text = Text::new(entry.text());
                    text_font.font_size = entry.current_font_size();
                    *text_color = TextColor(entry.color());
                    if let Ok(viewport_position) = viewport {
                        node.left = px(viewport_position.x);
                        node.top = px(viewport_position.y);
                        *visibility = Visibility::Visible;
                    } else {
                        *visibility = Visibility::Hidden;
                    }
                    continue;
                }
            }
        }

        let mut node = Node {
            position_type: PositionType::Absolute,
            ..default()
        };
        let mut visibility = Visibility::Hidden;
        if let Ok(viewport_position) = viewport {
            node.left = px(viewport_position.x);
            node.top = px(viewport_position.y);
            visibility = Visibility::Visible;
        }
        let entity = commands
            .spawn((
                Text::new(entry.text()),
                TextFont::from_font_size(entry.current_font_size())
                    .with_font(viewer_font.0.clone()),
                TextColor(entry.color()),
                node,
                visibility,
                DamageNumberLabel { id: *id },
            ))
            .id();
        visual_state.by_id.insert(*id, entity);
    }

    let stale_ids: Vec<_> = visual_state
        .by_id
        .keys()
        .copied()
        .filter(|id| !seen_ids.contains(id))
        .collect();
    for id in stale_ids {
        if let Some(entity) = visual_state.by_id.remove(&id) {
            commands.entity(entity).despawn();
        }
    }
}

pub(crate) fn update_interaction_menu(
    mut commands: Commands,
    window: Single<&Window>,
    menu_root: Single<(&mut Node, &mut Visibility), (With<InteractionMenuRoot>, Without<Button>)>,
    options_root: Single<(Entity, &Children), With<InteractionMenuOptionsRoot>>,
    mut rows: Query<
        (
            &InteractionMenuOptionRow,
            &mut Visibility,
            &mut BackgroundColor,
            &mut Text,
            &mut TextFont,
            &mut TextColor,
            &mut InteractionMenuButton,
        ),
        With<Button>,
    >,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    viewer_font: Res<ViewerUiFont>,
    console_state: Res<crate::console::ViewerConsoleState>,
) {
    let (mut node, mut visibility) = menu_root.into_inner();
    let (options_entity, _) = options_root.into_inner();
    if scene_kind.is_main_menu() || console_state.is_open {
        *visibility = Visibility::Hidden;
        for (_, mut row_visibility, ..) in &mut rows {
            *row_visibility = Visibility::Hidden;
        }
        return;
    }
    let Some(menu_state) = viewer_state.interaction_menu.as_ref() else {
        *visibility = Visibility::Hidden;
        for (_, mut row_visibility, ..) in &mut rows {
            *row_visibility = Visibility::Hidden;
        }
        return;
    };
    let Some(prompt) = viewer_state.current_prompt.as_ref() else {
        *visibility = Visibility::Hidden;
        for (_, mut row_visibility, ..) in &mut rows {
            *row_visibility = Visibility::Hidden;
        }
        return;
    };
    if prompt.target_id != menu_state.target_id || prompt.options.is_empty() {
        *visibility = Visibility::Hidden;
        for (_, mut row_visibility, ..) in &mut rows {
            *row_visibility = Visibility::Hidden;
        }
        return;
    }

    let layout = interaction_menu_layout(&window, menu_state, prompt);
    node.left = px(layout.left);
    node.top = px(layout.top);
    *visibility = Visibility::Visible;
    let menu_style = ContextMenuStyle::for_variant(ContextMenuVariant::WorldInteraction);
    let existing_rows = rows.iter().count();
    if existing_rows < prompt.options.len() {
        commands.entity(options_entity).with_children(|parent| {
            for index in existing_rows..prompt.options.len() {
                parent.spawn((
                    Button,
                    context_menu_button_node(menu_style),
                    BackgroundColor(context_menu_button_color(
                        menu_style,
                        false,
                        false,
                        Interaction::None,
                    )),
                    Text::new(""),
                    TextFont::from_font_size(menu_style.item_font_size)
                        .with_font(viewer_font.0.clone()),
                    TextColor(context_menu_text_color()),
                    TextLayout::new(Justify::Left, LineBreak::NoWrap),
                    Visibility::Hidden,
                    viewer_ui_passthrough_bundle(),
                    InteractionMenuOptionRow { index },
                    InteractionMenuButton {
                        target_id: prompt.target_id.clone(),
                        option_id: game_data::InteractionOptionId(String::new()),
                        is_primary: false,
                    },
                ));
            }
        });
    }

    for (
        row,
        mut row_visibility,
        mut background,
        mut text,
        mut text_font,
        mut text_color,
        mut button,
    ) in &mut rows
    {
        let Some(option) = prompt.options.get(row.index) else {
            *row_visibility = Visibility::Hidden;
            continue;
        };
        let is_primary = prompt.primary_option_id.as_ref() == Some(&option.id);
        *row_visibility = Visibility::Visible;
        *background = BackgroundColor(context_menu_button_color(
            menu_style,
            is_primary,
            false,
            Interaction::None,
        ));
        *text = Text::new(format_interaction_button_label(
            row.index,
            option.display_name.as_str(),
        ));
        text_font.font_size =
            interaction_menu_button_font_size_for_label(option.display_name.as_str());
        *text_color = TextColor(context_menu_text_color());
        button.target_id = prompt.target_id.clone();
        button.option_id = option.id.clone();
        button.is_primary = is_primary;
    }
}

pub(crate) fn update_dialogue_panel(
    mut commands: Commands,
    window: Single<&Window>,
    dialogue_root: Single<(&mut Node, &mut Visibility), (With<DialoguePanelRoot>, Without<Button>)>,
    choices_root: Single<(Entity, &Children), With<DialoguePanelChoicesRoot>>,
    mut labels: Query<
        (
            &mut Text,
            Option<&DialoguePanelTitleLabel>,
            Option<&DialoguePanelSpeakerLabel>,
            Option<&DialoguePanelBodyLabel>,
            Option<&DialoguePanelHintLabel>,
        ),
        (
            Or<(
                With<DialoguePanelTitleLabel>,
                With<DialoguePanelSpeakerLabel>,
                With<DialoguePanelBodyLabel>,
                With<DialoguePanelHintLabel>,
            )>,
            Without<Button>,
        ),
    >,
    mut choices: Query<
        (
            &DialogueChoiceRow,
            &mut Visibility,
            &mut BackgroundColor,
            &mut Text,
            &mut DialogueChoiceButton,
        ),
        With<Button>,
    >,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    viewer_font: Res<ViewerUiFont>,
    console_state: Res<crate::console::ViewerConsoleState>,
) {
    let (mut node, mut visibility) = dialogue_root.into_inner();
    let (choices_entity, _) = choices_root.into_inner();

    if scene_kind.is_main_menu() || console_state.is_open {
        *visibility = Visibility::Hidden;
        for (_, mut choice_visibility, ..) in &mut choices {
            *choice_visibility = Visibility::Hidden;
        }
        return;
    }

    let Some(dialogue) = viewer_state.active_dialogue.as_ref() else {
        *visibility = Visibility::Hidden;
        for (_, mut choice_visibility, ..) in &mut choices {
            *choice_visibility = Visibility::Hidden;
        }
        return;
    };
    let width =
        (window.width() - 520.0).clamp(DIALOGUE_PANEL_MIN_WIDTH_PX, DIALOGUE_PANEL_MAX_WIDTH_PX);
    node.width = px(width);
    node.bottom = px(DIALOGUE_PANEL_BOTTOM_PX);
    *visibility = Visibility::Visible;

    let (speaker_text, body_text, choice_labels, hint_text) = dialogue_panel_content(dialogue);
    for (mut text, title, speaker, body, hint) in &mut labels {
        if title.is_some() {
            *text = Text::new(format!("对话 · {}", dialogue.target_name));
        } else if speaker.is_some() {
            *text = Text::new(speaker_text.clone());
        } else if body.is_some() {
            *text = Text::new(body_text.clone());
        } else if hint.is_some() {
            *text = Text::new(hint_text.clone());
        }
    }

    let existing_rows = choices.iter().count();
    if existing_rows < choice_labels.len() {
        let button_style = ContextMenuStyle::for_variant(ContextMenuVariant::WorldInteraction);
        commands.entity(choices_entity).with_children(|parent| {
            for index in existing_rows..choice_labels.len() {
                parent.spawn((
                    Button,
                    dialogue_choice_button_node(),
                    BackgroundColor(context_menu_button_color(
                        button_style,
                        false,
                        false,
                        Interaction::None,
                    )),
                    Text::new(""),
                    TextFont::from_font_size(DIALOGUE_CHOICE_BUTTON_FONT_SIZE_PX)
                        .with_font(viewer_font.0.clone()),
                    TextColor(context_menu_text_color()),
                    Visibility::Hidden,
                    viewer_ui_passthrough_bundle(),
                    DialogueChoiceRow { index },
                    DialogueChoiceButton {
                        choice_index: index,
                    },
                ));
            }
        });
    }

    let button_style = ContextMenuStyle::for_variant(ContextMenuVariant::WorldInteraction);
    for (row, mut row_visibility, mut background, mut text, mut button) in &mut choices {
        let Some(label) = choice_labels.get(row.index) else {
            *row_visibility = Visibility::Hidden;
            continue;
        };
        *row_visibility = Visibility::Visible;
        *background = BackgroundColor(context_menu_button_color(
            button_style,
            false,
            false,
            Interaction::None,
        ));
        *text = Text::new(label.clone());
        button.choice_index = row.index;
    }
}

#[allow(clippy::too_many_arguments)]

pub(super) fn sync_interaction_lock_tag(
    commands: &mut Commands,
    entity: Entity,
    has_tag: bool,
    should_have_tag: bool,
) {
    match (has_tag, should_have_tag) {
        (false, true) => {
            commands.entity(entity).insert(InteractionLockedActorTag);
        }
        (true, false) => {
            commands
                .entity(entity)
                .remove::<InteractionLockedActorTag>();
        }
        _ => {}
    }
}

pub(super) fn format_interaction_button_label(index: usize, display_name: &str) -> String {
    let _ = index;
    display_name.to_string()
}

pub(super) fn interaction_menu_button_font_size_for_label(display_name: &str) -> f32 {
    let style = ContextMenuStyle::for_variant(ContextMenuVariant::WorldInteraction);
    let available_width = (style.width - style.padding * 2.0 - style.item_padding_x * 2.0).max(1.0);
    let estimated_width =
        interaction_menu_estimated_label_width(display_name, style.item_font_size);
    if estimated_width <= available_width {
        return style.item_font_size;
    }

    let scaled_size = style.item_font_size * (available_width / estimated_width);
    scaled_size.clamp(INTERACTION_MENU_ITEM_MIN_FONT_SIZE_PX, style.item_font_size)
}

fn interaction_menu_estimated_label_width(display_name: &str, font_size: f32) -> f32 {
    let units = display_name
        .chars()
        .map(interaction_menu_label_char_width_units)
        .sum::<f32>();
    units * font_size
}

fn interaction_menu_label_char_width_units(ch: char) -> f32 {
    if ch.is_ascii_whitespace() {
        0.34
    } else if ch.is_ascii_punctuation() || ch.is_ascii_digit() {
        0.52
    } else if ch.is_ascii_alphabetic() {
        0.58
    } else {
        1.0
    }
}

pub(super) fn dialogue_choice_button_node() -> Node {
    Node {
        width: Val::Percent(100.0),
        min_height: px(DIALOGUE_CHOICE_BUTTON_HEIGHT_PX),
        padding: UiRect::axes(
            px(DIALOGUE_CHOICE_BUTTON_PADDING_X_PX),
            px(DIALOGUE_CHOICE_BUTTON_PADDING_Y_PX),
        ),
        margin: UiRect::bottom(px(DIALOGUE_CHOICE_BUTTON_GAP_PX)),
        align_items: AlignItems::Center,
        ..default()
    }
}

pub(super) fn dialogue_panel_content(
    dialogue: &crate::state::ActiveDialogueState,
) -> (String, String, Vec<String>, String) {
    let Some(node) = current_dialogue_node(dialogue) else {
        return (
            "对话数据错误".to_string(),
            format!(
                "dialog_id={} node_id={} 无法找到对应节点",
                dialogue.dialog_id, dialogue.current_node_id
            ),
            Vec::new(),
            "Esc 关闭对话".to_string(),
        );
    };

    let speaker = if node.speaker.trim().is_empty() {
        dialogue.target_name.clone()
    } else {
        node.speaker.clone()
    };

    let choice_labels = node
        .options
        .iter()
        .enumerate()
        .map(|(index, option)| format!("{}. {}", index + 1, option.text))
        .collect();

    let hint = if current_dialogue_has_options(dialogue) {
        "点击选项 / 按 1-9 选择分支，Esc 关闭对话".to_string()
    } else {
        "左键 / Space / Enter 下一句，Esc 关闭对话".to_string()
    };

    (speaker, node.text.clone(), choice_labels, hint)
}
