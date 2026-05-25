//! 屏幕叠加层模块：负责角色标签、伤害数字、交互菜单和对话面板等 2D 叠加内容。

use super::*;
use bevy::log::{info, warn};
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
    info_panel_state: Res<ViewerInfoPanelState>,
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
    let current_actor_label_enabled =
        info_panel_state.active_page() == Some(ViewerHudPage::TurnSys);

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
        );
        let is_current_turn_actor = snapshot.combat.current_actor_id == Some(actor.actor_id);
        let show_current_turn_label = current_actor_label_enabled && is_current_turn_actor;
        let should_show_label = (should_show_label || show_current_turn_label) && actor_visible;
        let label = actor_overlay_label(actor, interaction_locked, show_current_turn_label);
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

fn actor_overlay_label(
    actor: &game_core::ActorDebugState,
    interaction_locked: bool,
    show_current_turn_label: bool,
) -> String {
    let mut label = if show_current_turn_label {
        format!("当前行动: {}", actor_label(actor))
    } else {
        actor_label(actor)
    };
    if interaction_locked {
        label.push_str(" [交互中]");
    }
    label
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
    options_root: Single<Entity, With<InteractionMenuOptionsRoot>>,
    target_label: Single<&mut Text, (With<InteractionMenuTargetLabel>, Without<Button>)>,
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
    mut last_diagnostic: Local<Option<String>>,
) {
    let (mut node, mut visibility) = menu_root.into_inner();
    let options_entity = options_root.into_inner();
    if scene_kind.is_main_menu() || console_state.is_open {
        log_interaction_menu_diagnostic(
            &mut last_diagnostic,
            "hidden_scene_or_console",
            scene_kind.as_ref(),
            console_state.is_open,
            viewer_state.interaction_menu.as_ref(),
            viewer_state.current_prompt.as_ref(),
        );
        *visibility = Visibility::Hidden;
        for (_, mut row_visibility, ..) in &mut rows {
            *row_visibility = Visibility::Hidden;
        }
        return;
    }
    let Some(menu_state) = viewer_state.interaction_menu.as_ref() else {
        log_interaction_menu_diagnostic(
            &mut last_diagnostic,
            "hidden_no_menu_state",
            scene_kind.as_ref(),
            console_state.is_open,
            None,
            viewer_state.current_prompt.as_ref(),
        );
        *visibility = Visibility::Hidden;
        for (_, mut row_visibility, ..) in &mut rows {
            *row_visibility = Visibility::Hidden;
        }
        return;
    };
    let Some(prompt) = viewer_state.current_prompt.as_ref() else {
        log_interaction_menu_diagnostic(
            &mut last_diagnostic,
            "hidden_no_prompt",
            scene_kind.as_ref(),
            console_state.is_open,
            Some(menu_state),
            None,
        );
        *visibility = Visibility::Hidden;
        for (_, mut row_visibility, ..) in &mut rows {
            *row_visibility = Visibility::Hidden;
        }
        return;
    };
    if prompt.target_id != menu_state.target_id || prompt.options.is_empty() {
        log_interaction_menu_diagnostic(
            &mut last_diagnostic,
            "hidden_prompt_mismatch_or_empty",
            scene_kind.as_ref(),
            console_state.is_open,
            Some(menu_state),
            Some(prompt),
        );
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
    let mut target_label = target_label.into_inner();
    *target_label = Text::new(prompt.target_name.clone());
    log_interaction_menu_diagnostic(
        &mut last_diagnostic,
        "visible",
        scene_kind.as_ref(),
        console_state.is_open,
        Some(menu_state),
        Some(prompt),
    );
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

fn log_interaction_menu_diagnostic(
    last_diagnostic: &mut Local<Option<String>>,
    reason: &str,
    scene_kind: &ViewerSceneKind,
    console_open: bool,
    menu_state: Option<&InteractionMenuState>,
    prompt: Option<&game_data::InteractionPrompt>,
) {
    let menu_target = menu_state.map(|menu| format!("{:?}", menu.target_id));
    let prompt_target = prompt.map(|prompt| format!("{:?}", prompt.target_id));
    let prompt_options = prompt
        .map(|prompt| prompt.options.len())
        .unwrap_or_default();
    let diagnostic = format!(
        "reason={reason};scene={scene_kind:?};console={console_open};menu_target={menu_target:?};prompt_target={prompt_target:?};prompt_options={prompt_options}"
    );
    if last_diagnostic.as_ref() == Some(&diagnostic) {
        return;
    }

    info!("viewer.interaction.menu_diagnostic {diagnostic}");
    **last_diagnostic = Some(diagnostic);
}

pub(crate) fn sync_dialogue_panel_diagnostics(
    viewer_state: Res<ViewerState>,
    scene_kind: Res<ViewerSceneKind>,
    console_state: Res<crate::console::ViewerConsoleState>,
    panel_roots: Query<&Visibility, With<DialoguePanelRoot>>,
    choices_roots: Query<&Visibility, With<DialoguePanelChoicesRoot>>,
    mut last_logged_state: Local<Option<String>>,
) {
    let active_dialogue = viewer_state
        .active_dialogue
        .as_ref()
        .map(|dialogue| {
            format!(
                "{:?}|{}|{}|target={:?}",
                dialogue.actor_id, dialogue.dialog_id, dialogue.current_node_id, dialogue.target_id
            )
        })
        .unwrap_or_else(|| "none".to_string());
    let panel_visibilities = panel_roots
        .iter()
        .map(|visibility| format!("{visibility:?}"))
        .collect::<Vec<_>>()
        .join(",");
    let choices_visibilities = choices_roots
        .iter()
        .map(|visibility| format!("{visibility:?}"))
        .collect::<Vec<_>>()
        .join(",");
    let state_key = format!(
        "active={active_dialogue};scene={:?};console={};panel_count={};panel_vis=[{}];choices_count={};choices_vis=[{}]",
        scene_kind.as_ref(),
        console_state.is_open,
        panel_roots.iter().len(),
        panel_visibilities,
        choices_roots.iter().len(),
        choices_visibilities,
    );
    if last_logged_state.as_ref() == Some(&state_key) {
        return;
    }

    info!("viewer.dialogue.panel_diagnostic {state_key}");
    *last_logged_state = Some(state_key);
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct DialogueChoiceLabel {
    index: usize,
}

pub(crate) fn update_dialogue_panel(
    mut commands: Commands,
    window: Single<&Window>,
    mut dialogue_roots: Query<
        (&mut Node, &mut Visibility),
        (With<DialoguePanelRoot>, Without<Button>),
    >,
    choices_roots: Query<Entity, With<DialoguePanelChoicesRoot>>,
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
            Without<DialogueChoiceLabel>,
        ),
    >,
    mut choices: Query<
        (
            &DialogueChoiceRow,
            &Interaction,
            &mut Visibility,
            &mut BackgroundColor,
            &mut DialogueChoiceButton,
        ),
        With<Button>,
    >,
    mut choice_texts: Query<(&DialogueChoiceLabel, &mut Text), With<DialogueChoiceLabel>>,
    mut body_scroll_positions: Query<&mut ScrollPosition, With<DialoguePanelBodyScrollArea>>,
    scene_kind: Res<ViewerSceneKind>,
    viewer_state: Res<ViewerState>,
    viewer_font: Res<ViewerUiFont>,
    console_state: Res<crate::console::ViewerConsoleState>,
    mut last_logged_dialogue: Local<Option<(game_data::ActorId, String, String)>>,
    mut last_logged_panel_error: Local<Option<String>>,
) {
    let mut dialogue_root_iter = dialogue_roots.iter_mut();
    let Some((mut node, mut visibility)) = dialogue_root_iter.next() else {
        log_dialogue_panel_setup_error(
            "missing_dialogue_root",
            viewer_state.active_dialogue.as_ref(),
            &mut last_logged_panel_error,
        );
        return;
    };
    if dialogue_root_iter.next().is_some() {
        log_dialogue_panel_setup_error(
            "duplicate_dialogue_roots",
            viewer_state.active_dialogue.as_ref(),
            &mut last_logged_panel_error,
        );
        return;
    }

    let mut choices_root_iter = choices_roots.iter();
    let Some(choices_entity) = choices_root_iter.next() else {
        log_dialogue_panel_setup_error(
            "missing_choices_root",
            viewer_state.active_dialogue.as_ref(),
            &mut last_logged_panel_error,
        );
        return;
    };
    if choices_root_iter.next().is_some() {
        log_dialogue_panel_setup_error(
            "duplicate_choices_roots",
            viewer_state.active_dialogue.as_ref(),
            &mut last_logged_panel_error,
        );
        return;
    }
    *last_logged_panel_error = None;

    if scene_kind.is_main_menu() || console_state.is_open {
        if let Some((actor_id, dialog_id, node_id)) = last_logged_dialogue.take() {
            info!(
                "viewer.dialogue.panel_hidden reason={} actor={:?} dialog_id={} node={}",
                if scene_kind.is_main_menu() {
                    "main_menu"
                } else {
                    "console_open"
                },
                actor_id,
                dialog_id,
                node_id,
            );
        }
        *visibility = Visibility::Hidden;
        for (_, _, mut choice_visibility, ..) in &mut choices {
            *choice_visibility = Visibility::Hidden;
        }
        return;
    }

    let Some(dialogue) = viewer_state.active_dialogue.as_ref() else {
        if let Some((actor_id, dialog_id, node_id)) = last_logged_dialogue.take() {
            info!(
                "viewer.dialogue.panel_hidden reason=no_active_dialogue actor={:?} dialog_id={} node={}",
                actor_id, dialog_id, node_id
            );
        }
        *visibility = Visibility::Hidden;
        for (_, _, mut choice_visibility, ..) in &mut choices {
            *choice_visibility = Visibility::Hidden;
        }
        return;
    };
    let width =
        (window.width() - 520.0).clamp(DIALOGUE_PANEL_MIN_WIDTH_PX, DIALOGUE_PANEL_MAX_WIDTH_PX);
    node.width = px(width);
    node.height = px(DIALOGUE_PANEL_HEIGHT_PX);
    node.left = Val::Percent(50.0);
    node.margin.left = px(-(width / 2.0));
    node.bottom = px(DIALOGUE_PANEL_BOTTOM_PX);
    *visibility = Visibility::Visible;

    let (speaker_text, body_text, choice_labels, hint_text) = dialogue_panel_content(dialogue);
    let dialogue_key = (
        dialogue.actor_id,
        dialogue.dialog_id.clone(),
        dialogue.current_node_id.clone(),
    );
    if last_logged_dialogue.as_ref() != Some(&dialogue_key) {
        for mut scroll_position in &mut body_scroll_positions {
            scroll_position.y = 0.0;
        }
        info!(
            "viewer.dialogue.panel_visible actor={:?} target={:?} dialog_id={} dialogue_key={} node={} target_name={} choices={} width={}",
            dialogue.actor_id,
            dialogue.target_id,
            dialogue.dialog_id,
            dialogue.dialogue_key,
            dialogue.current_node_id,
            dialogue.target_name,
            choice_labels.len(),
            width,
        );
        *last_logged_dialogue = Some(dialogue_key);
    }
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
        commands.entity(choices_entity).with_children(|parent| {
            for index in existing_rows..choice_labels.len() {
                parent
                    .spawn((
                        Button,
                        dialogue_choice_button_node(),
                        BackgroundColor(dialogue_choice_button_color(Interaction::None)),
                        Visibility::Hidden,
                        viewer_ui_passthrough_bundle(),
                        DialogueChoiceRow { index },
                        DialogueChoiceButton {
                            choice_index: index,
                        },
                    ))
                    .with_children(|button| {
                        button.spawn((
                            Node {
                                width: Val::Percent(100.0),
                                ..default()
                            },
                            Text::new(choice_labels.get(index).cloned().unwrap_or_default()),
                            TextFont::from_font_size(DIALOGUE_CHOICE_BUTTON_FONT_SIZE_PX)
                                .with_font(viewer_font.0.clone()),
                            TextColor(context_menu_text_color()),
                            TextLayout::new(Justify::Left, LineBreak::NoWrap),
                            viewer_ui_passthrough_bundle(),
                            DialogueChoiceLabel { index },
                        ));
                    });
            }
        });
    }

    for (row, interaction, mut row_visibility, mut background, mut button) in &mut choices {
        let Some(label) = choice_labels.get(row.index) else {
            *row_visibility = Visibility::Hidden;
            continue;
        };
        *row_visibility = Visibility::Visible;
        *background = BackgroundColor(dialogue_choice_button_color(*interaction));
        button.choice_index = row.index;

        for (choice_label, mut text) in &mut choice_texts {
            if choice_label.index == row.index {
                *text = Text::new(label.clone());
            }
        }
    }
}

#[derive(Debug, Clone, Copy)]
struct DialogueBodyScrollbarMetrics {
    max_scroll: f32,
    thumb_height: f32,
    travel: f32,
}

pub(crate) fn sync_dialogue_body_scrollbar(
    mut tracks: Query<
        (&ComputedNode, &mut Visibility),
        (
            With<DialoguePanelBodyScrollbarTrack>,
            Without<DialoguePanelBodyScrollbarThumb>,
        ),
    >,
    mut thumbs: Query<
        (&mut Node, &mut Visibility),
        (
            With<DialoguePanelBodyScrollbarThumb>,
            Without<DialoguePanelBodyScrollbarTrack>,
        ),
    >,
    scroll_areas: Query<&ComputedNode, With<DialoguePanelBodyScrollArea>>,
) {
    let Ok(scroll_area) = scroll_areas.single() else {
        return;
    };
    let Ok((track, mut track_visibility)) = tracks.single_mut() else {
        return;
    };
    let Ok((mut thumb_node, mut thumb_visibility)) = thumbs.single_mut() else {
        return;
    };

    let Some(metrics) = dialogue_body_scrollbar_metrics(scroll_area, track) else {
        *track_visibility = Visibility::Hidden;
        *thumb_visibility = Visibility::Hidden;
        return;
    };

    *track_visibility = Visibility::Visible;
    *thumb_visibility = Visibility::Visible;
    let thumb_top = if metrics.max_scroll <= f32::EPSILON {
        0.0
    } else {
        metrics.travel * (scroll_area.scroll_position.y / metrics.max_scroll).clamp(0.0, 1.0)
    };

    thumb_node.top = px(thumb_top);
    thumb_node.height = px(metrics.thumb_height);
}

fn dialogue_body_scrollbar_metrics(
    scroll_area: &ComputedNode,
    track: &ComputedNode,
) -> Option<DialogueBodyScrollbarMetrics> {
    let viewport_height = scroll_area.size.y.max(0.0);
    let content_height = scroll_area.content_size.y.max(0.0);
    let track_height = track.size.y.max(0.0);
    let max_scroll = (content_height - viewport_height + scroll_area.scrollbar_size.y).max(0.0);
    let can_scroll = max_scroll > 0.5 && track_height > 0.0 && content_height > f32::EPSILON;
    if !can_scroll {
        return None;
    }

    let visible_ratio = (viewport_height / content_height).clamp(0.0, 1.0);
    let thumb_height = (track_height * visible_ratio).clamp(24.0, track_height);
    let travel = (track_height - thumb_height).max(0.0);
    Some(DialogueBodyScrollbarMetrics {
        max_scroll,
        thumb_height,
        travel,
    })
}

fn log_dialogue_panel_setup_error(
    reason: &str,
    active_dialogue: Option<&crate::state::ActiveDialogueState>,
    last_logged_panel_error: &mut Option<String>,
) {
    let state_key = active_dialogue
        .map(|dialogue| {
            format!(
                "{}|actor={:?}|target={:?}|dialog_id={}|node={}",
                reason,
                dialogue.actor_id,
                dialogue.target_id,
                dialogue.dialog_id,
                dialogue.current_node_id
            )
        })
        .unwrap_or_else(|| format!("{reason}|active=none"));
    if last_logged_panel_error.as_ref() == Some(&state_key) {
        return;
    }

    warn!("viewer.dialogue.panel_setup_error {state_key}");
    *last_logged_panel_error = Some(state_key);
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
        justify_content: JustifyContent::FlexStart,
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
