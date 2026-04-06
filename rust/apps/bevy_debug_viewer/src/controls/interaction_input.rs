//! 交互输入处理模块：负责点击目标、菜单按钮和对话选项的输入响应。

use super::*;

pub(super) fn resolve_primary_target_interaction(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &ViewerState,
    snapshot: &game_core::SimulationSnapshot,
    target_id: InteractionTargetId,
) -> Option<(ActorId, InteractionPrompt)> {
    let actor_id = viewer_state.command_actor_id(snapshot)?;
    let prompt = runtime_state
        .runtime
        .query_interaction_prompt(actor_id, target_id)?;
    Some((actor_id, prompt))
}

pub(super) fn handle_object_primary_click(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    snapshot: &game_core::SimulationSnapshot,
    object_id: &str,
    grid: game_data::GridCoord,
) {
    let target_id = InteractionTargetId::MapObject(object_id.to_string());
    if execute_primary_target_interaction(
        runtime_state,
        viewer_state,
        snapshot,
        target_id.clone(),
        format!("object {object_id}"),
        "mouse_primary",
    ) {
        return;
    }

    if let Some(actor_id) = viewer_state.command_actor_id(snapshot) {
        if runtime_state.runtime.grid_walkable(grid) {
            issue_move_to_grid(runtime_state, viewer_state, actor_id, grid);
            return;
        }
    }

    viewer_state.focused_target = Some(target_id);
    viewer_state.current_prompt = None;
    viewer_state.interaction_menu = None;
    if viewer_state.command_actor_id(snapshot).is_none() {
        viewer_state.status_line = format!("focused object {object_id}; select an actor first");
    } else {
        viewer_state.status_line = format!("focused object {object_id} with no executable options");
    }
}

pub(super) fn execute_primary_target_interaction(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    snapshot: &game_core::SimulationSnapshot,
    target_id: InteractionTargetId,
    target_summary: String,
    input_source: &'static str,
) -> bool {
    let Some((actor_id, prompt)) = resolve_primary_target_interaction(
        runtime_state,
        viewer_state,
        snapshot,
        target_id.clone(),
    ) else {
        viewer_state.interaction_menu = None;
        viewer_state.status_line =
            format!("focused {target_summary} with no available interactions");
        return false;
    };
    let Some(option_id) = prompt.primary_option_id.clone() else {
        viewer_state.focused_target = Some(target_id);
        viewer_state.current_prompt = Some(prompt.clone());
        viewer_state.interaction_menu = None;
        viewer_state.status_line = if prompt_has_locked_door_options(&prompt) {
            "interaction: door is locked".to_string()
        } else {
            format!("focused {target_summary} with no primary interaction")
        };
        return false;
    };
    viewer_state.focused_target = Some(target_id.clone());
    viewer_state.current_prompt = Some(prompt.clone());

    log_viewer_interaction(
        "primary",
        Some(actor_id),
        &target_id,
        &prompt.target_name,
        Some(&option_id),
        input_source,
    );
    execute_target_interaction_option(runtime_state, viewer_state, target_id, option_id);
    true
}

fn prompt_has_locked_door_options(prompt: &InteractionPrompt) -> bool {
    prompt.options.iter().any(|option| {
        matches!(
            option.kind,
            InteractionOptionKind::UnlockDoor | InteractionOptionKind::PickLockDoor
        )
    }) && prompt.primary_option_id.is_none()
}

pub(super) fn focus_target_and_query_prompt(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    target_id: InteractionTargetId,
) -> Option<InteractionPrompt> {
    viewer_state.focused_target = Some(target_id.clone());
    let snapshot = runtime_state.runtime.snapshot();
    let prompt = viewer_state
        .command_actor_id(&snapshot)
        .and_then(|actor_id| {
            runtime_state
                .runtime
                .query_interaction_prompt(actor_id, target_id)
        });
    viewer_state.current_prompt = prompt.clone();
    prompt
}

pub(super) fn cursor_interaction_target(
    command_actor_id: Option<ActorId>,
    actor: Option<&game_core::ActorDebugState>,
    map_object: Option<&game_core::MapObjectDebugState>,
) -> Option<InteractionTargetId> {
    if let Some(actor) = actor {
        if actor.side != ActorSide::Player || Some(actor.actor_id) == command_actor_id {
            return Some(InteractionTargetId::Actor(actor.actor_id));
        }
    }

    map_object.map(|object| InteractionTargetId::MapObject(object.object_id.clone()))
}

pub(super) fn is_command_actor_self_target(
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    actor: &game_core::ActorDebugState,
) -> bool {
    actor.side == ActorSide::Player
        && viewer_state.command_actor_id(snapshot) == Some(actor.actor_id)
}

fn execute_target_interaction_option(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    target_id: InteractionTargetId,
    option_id: game_data::InteractionOptionId,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let Some(actor_id) = viewer_state.command_actor_id(&snapshot) else {
        viewer_state.interaction_menu = None;
        viewer_state.status_line = "interaction: select an actor first".to_string();
        return;
    };

    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.interaction_menu = None;
    let result = runtime_state
        .runtime
        .issue_interaction(actor_id, target_id, option_id);
    apply_interaction_result(runtime_state, viewer_state, result);
}

pub(super) fn interaction_menu_contains_cursor(
    window: &Window,
    viewer_state: &ViewerState,
    cursor_position: Vec2,
) -> bool {
    let Some(menu_state) = viewer_state.interaction_menu.as_ref() else {
        return false;
    };
    let Some(prompt) = viewer_state.current_prompt.as_ref() else {
        return false;
    };
    if prompt.target_id != menu_state.target_id || prompt.options.is_empty() {
        return false;
    }

    interaction_menu_layout(window, menu_state, prompt).contains(cursor_position)
}

pub(crate) fn handle_interaction_menu_buttons(
    mut buttons: Query<
        (
            &Interaction,
            &mut BackgroundColor,
            &InteractionMenuButton,
            Option<&crate::ui_context_menu::ContextMenuItemDisabled>,
        ),
        (Changed<Interaction>, With<Button>),
    >,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    console_state: Res<ViewerConsoleState>,
) {
    if console_state.is_open {
        return;
    }

    let button_style = ContextMenuStyle::for_variant(ContextMenuVariant::WorldInteraction);
    for (interaction, mut background, menu_button, disabled) in &mut buttons {
        *background = BackgroundColor(context_menu_button_color(
            button_style,
            menu_button.is_primary,
            disabled.is_some(),
            *interaction,
        ));
        if disabled.is_some() {
            continue;
        }
        if *interaction != Interaction::Pressed {
            continue;
        }

        let target_name = interaction_target_name(&viewer_state, &menu_button.target_id);
        log_viewer_interaction(
            "option_selected",
            viewer_state.selected_actor,
            &menu_button.target_id,
            &target_name,
            Some(&menu_button.option_id),
            "mouse_menu",
        );
        execute_target_interaction_option(
            &mut runtime_state,
            &mut viewer_state,
            menu_button.target_id.clone(),
            menu_button.option_id.clone(),
        );
    }
}

pub(crate) fn handle_dialogue_choice_buttons(
    mut buttons: Query<
        (&Interaction, &mut BackgroundColor, &DialogueChoiceButton),
        (Changed<Interaction>, With<Button>),
    >,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    console_state: Res<ViewerConsoleState>,
) {
    if console_state.is_open {
        return;
    }

    let button_style = ContextMenuStyle::for_variant(ContextMenuVariant::WorldInteraction);
    for (interaction, mut background, choice_button) in &mut buttons {
        *background = BackgroundColor(context_menu_button_color(
            button_style,
            false,
            false,
            *interaction,
        ));
        if *interaction != Interaction::Pressed {
            continue;
        }

        log_dialogue_input(
            &viewer_state,
            "dialogue_choice_selected",
            "dialogue_click",
            Some(choice_button.choice_index),
        );
        advance_dialogue(
            &mut runtime_state,
            &mut viewer_state,
            Some(choice_button.choice_index),
        );
    }
}

fn interaction_target_name(viewer_state: &ViewerState, target_id: &InteractionTargetId) -> String {
    viewer_state
        .current_prompt
        .as_ref()
        .filter(|prompt| &prompt.target_id == target_id)
        .map(|prompt| prompt.target_name.clone())
        .unwrap_or_else(|| format!("{target_id:?}"))
}
