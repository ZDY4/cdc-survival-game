//! 相机输入子模块：负责拖拽平移、滚轮缩放和跟随相机时的手动偏移换算。

use super::*;

pub(crate) fn handle_mouse_wheel_zoom(
    mut mouse_wheel_events: MessageReader<MouseWheel>,
    mut viewer_state: ResMut<ViewerState>,
    mut render_config: ResMut<ViewerRenderConfig>,
    menu_state: Res<UiMenuState>,
    modal_state: Res<UiModalState>,
    console_state: Res<ViewerConsoleState>,
    debug_panel_state: Option<Res<crate::debug_panel::ViewerDebugPanelState>>,
    scene_kind: Res<ViewerSceneKind>,
) {
    if console_state.is_open {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    if debug_panel_state.is_some_and(|state| state.is_open) {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    if viewer_state.active_dialogue.is_some() {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    if viewer_state.is_interaction_menu_open() {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    if scene_kind.is_main_menu()
        || menu_state.blocks_gameplay_input()
        || modal_state.item_quantity.is_some()
        || modal_state.trade.is_some()
    {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    let mut scroll_delta = 0.0f32;
    for event in mouse_wheel_events.read() {
        let unit_scale = match event.unit {
            bevy::input::mouse::MouseScrollUnit::Line => 1.0,
            bevy::input::mouse::MouseScrollUnit::Pixel => 0.1,
        };
        scroll_delta += event.y * unit_scale;
    }

    if scroll_delta.abs() < f32::EPSILON {
        return;
    }

    let zoom_multiplier = (1.0 + scroll_delta * 0.12).clamp(0.5, 2.0);
    render_config.zoom_factor = (render_config.zoom_factor * zoom_multiplier).clamp(0.5, 4.0);
    viewer_state.status_line = format!("zoom: {:.0}%", render_config.zoom_factor * 100.0);
}

pub(crate) fn handle_dialogue_body_mouse_wheel(
    window: Single<&Window>,
    mut mouse_wheel_events: MessageReader<MouseWheel>,
    scene_kind: Res<ViewerSceneKind>,
    console_state: Res<ViewerConsoleState>,
    viewer_state: Res<ViewerState>,
    mut scroll_areas: Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
            &InheritedVisibility,
            &mut ScrollPosition,
        ),
        With<DialoguePanelBodyScrollArea>,
    >,
) {
    if scene_kind.is_main_menu() || console_state.is_open || viewer_state.active_dialogue.is_none()
    {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        for _ in mouse_wheel_events.read() {}
        return;
    };

    let Some((computed, _, _, _, _, mut scroll_position)) =
        scroll_areas.iter_mut().find(
            |(computed, transform, cursor, visibility, inherited_visibility, _)| {
                visible_node_contains_cursor(
                    cursor_position,
                    computed,
                    transform,
                    *cursor,
                    *visibility,
                    inherited_visibility,
                )
            },
        )
    else {
        for _ in mouse_wheel_events.read() {}
        return;
    };

    let max_scroll =
        (computed.content_size.y - computed.size.y + computed.scrollbar_size.y).max(0.0);
    if max_scroll <= f32::EPSILON {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    let mut scroll_delta = 0.0f32;
    for event in mouse_wheel_events.read() {
        scroll_delta += match event.unit {
            bevy::input::mouse::MouseScrollUnit::Line => event.y * 36.0,
            bevy::input::mouse::MouseScrollUnit::Pixel => event.y,
        };
    }
    if scroll_delta.abs() <= f32::EPSILON {
        return;
    }

    scroll_position.y = (scroll_position.y - scroll_delta).clamp(0.0, max_scroll);
}

fn visible_node_contains_cursor(
    cursor_position: Vec2,
    computed_node: &ComputedNode,
    transform: &UiGlobalTransform,
    cursor: Option<&RelativeCursorPosition>,
    visibility: Option<&Visibility>,
    inherited_visibility: &InheritedVisibility,
) -> bool {
    if !inherited_visibility.get()
        || visibility.is_some_and(|visibility| *visibility == Visibility::Hidden)
    {
        return false;
    }

    cursor.is_some_and(RelativeCursorPosition::cursor_over)
        || computed_node.contains_point(*transform, cursor_position)
}

pub(crate) fn handle_camera_pan(
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    buttons: Res<ButtonInput<MouseButton>>,
    ui_blockers: Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
            &InheritedVisibility,
            Option<&UiMouseBlockerName>,
        ),
        With<UiMouseBlocker>,
    >,
    runtime_state: Res<ViewerRuntimeState>,
    motion_state: Res<ViewerActorMotionState>,
    render_config: Res<ViewerRenderConfig>,
    mut viewer_state: ResMut<ViewerState>,
    menu_state: Res<UiMenuState>,
    modal_state: Res<UiModalState>,
    console_state: Res<ViewerConsoleState>,
    scene_kind: Res<ViewerSceneKind>,
) {
    if console_state.is_open {
        viewer_state.camera_drag_cursor = None;
        viewer_state.camera_drag_anchor_world = None;
        return;
    }

    if viewer_state.is_interaction_menu_open() {
        viewer_state.camera_drag_cursor = None;
        viewer_state.camera_drag_anchor_world = None;
        return;
    }

    if scene_kind.is_main_menu()
        || menu_state.blocks_gameplay_input()
        || modal_state.item_quantity.is_some()
        || modal_state.trade.is_some()
    {
        viewer_state.camera_drag_cursor = None;
        viewer_state.camera_drag_anchor_world = None;
        return;
    }

    if !buttons.pressed(MouseButton::Middle) {
        viewer_state.camera_drag_cursor = None;
        viewer_state.camera_drag_anchor_world = None;
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        viewer_state.camera_drag_cursor = None;
        viewer_state.camera_drag_anchor_world = None;
        return;
    };
    if cursor_over_visible_ui_blocker(Some(cursor_position), &ui_blockers)
        || cursor_over_hotbar_dock(&window, cursor_position)
    {
        viewer_state.camera_drag_cursor = None;
        viewer_state.camera_drag_anchor_world = None;
        return;
    }

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let plane_height = level_base_height(viewer_state.current_level, snapshot.grid.grid_size)
        + render_config.floor_thickness_world;
    let Ok(current_ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
        return;
    };
    let Some(current_point) = ray_point_on_horizontal_plane(current_ray, plane_height) else {
        return;
    };

    if buttons.just_pressed(MouseButton::Middle) || viewer_state.camera_drag_anchor_world.is_none()
    {
        if viewer_state.is_camera_following_selected_actor() {
            viewer_state.camera_pan_offset = manual_pan_offset_from_follow_focus(
                &runtime_state,
                &motion_state,
                &snapshot,
                &viewer_state,
                bounds,
                window.width(),
                window.height(),
                *render_config,
            );
        }
        viewer_state.disable_camera_follow();
        viewer_state.camera_drag_cursor = Some(cursor_position);
        viewer_state.camera_drag_anchor_world = Some(Vec2::new(current_point.x, current_point.z));
        return;
    }

    viewer_state.camera_drag_cursor = Some(cursor_position);
    let Some(anchor_world) = viewer_state.camera_drag_anchor_world else {
        return;
    };
    let pan_delta = anchor_world - Vec2::new(current_point.x, current_point.z);
    if pan_delta.length_squared() <= f32::EPSILON {
        return;
    }

    viewer_state.camera_pan_offset += pan_delta;
    viewer_state.camera_pan_offset = clamp_camera_pan_offset(
        bounds,
        snapshot.grid.grid_size,
        viewer_state.camera_pan_offset,
        window.width(),
        window.height(),
        *render_config,
    );
}

pub(super) fn manual_pan_offset_from_follow_focus(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    bounds: crate::geometry::GridBounds,
    viewport_width: f32,
    viewport_height: f32,
    render_config: ViewerRenderConfig,
) -> Vec2 {
    let grid_size = snapshot.grid.grid_size;
    let Some(actor) = selected_actor(snapshot, viewer_state) else {
        return Vec2::ZERO;
    };
    let actor_world = motion_state
        .current_world(actor.actor_id)
        .unwrap_or_else(|| runtime_state.runtime.grid_to_world(actor.grid_position));
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (bounds.min_z + bounds.max_z + 1) as f32 * grid_size * 0.5;
    let follow_offset = Vec2::new(actor_world.x - center_x, actor_world.z - center_z);

    clamp_camera_pan_offset(
        bounds,
        grid_size,
        follow_offset,
        viewport_width,
        viewport_height,
        render_config,
    )
}
