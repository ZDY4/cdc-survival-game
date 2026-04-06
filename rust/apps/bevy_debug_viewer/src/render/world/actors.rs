//! 角色可视化 helper：负责角色实体同步、世界位置换算与颜色策略。

use super::*;

#[allow(clippy::too_many_arguments)]
pub(super) fn sync_actor_visuals(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    palette: &ViewerPalette,
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    feedback_state: &ViewerActorFeedbackState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    render_config: ViewerRenderConfig,
    actor_visual_state: &mut ActorVisualState,
    actor_visuals: &mut Query<
        (Entity, &mut Transform, &ActorBodyVisual),
        Without<GeneratedDoorPivot>,
    >,
) {
    let mut seen_actor_ids = HashSet::new();
    let grid_size = snapshot.grid.grid_size;

    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == viewer_state.current_level)
    {
        seen_actor_ids.insert(actor.actor_id);
        let translation = actor_visual_translation(
            runtime_state,
            motion_state,
            feedback_state,
            actor,
            grid_size,
            render_config,
        );
        let color = actor_color(actor.side, palette);
        let accent_color = actor_accent_color(actor.side, palette);

        if let Some(entity) = actor_visual_state.by_actor.get(&actor.actor_id).copied() {
            if let Ok((_, mut transform, body)) = actor_visuals.get_mut(entity) {
                if body.actor_id == actor.actor_id {
                    transform.translation = translation;
                    if let Some(material) = materials.get_mut(&body.body_material) {
                        material.base_color = color;
                    }
                    if let Some(material) = materials.get_mut(&body.head_material) {
                        material.base_color = actor_head_color(color);
                    }
                    if let Some(material) = materials.get_mut(&body.accent_material) {
                        material.base_color = accent_color;
                    }
                    continue;
                }
            }
        }

        let body_material = make_standard_material(materials, color, MaterialStyle::CharacterBody);
        let head_material = make_standard_material(
            materials,
            actor_head_color(color),
            MaterialStyle::CharacterHead,
        );
        let accent_material =
            make_standard_material(materials, accent_color, MaterialStyle::CharacterAccent);
        let shadow_material = make_standard_material(
            materials,
            Color::srgba(
                0.02,
                0.025,
                0.032,
                render_config.shadow_opacity_scale * 0.62,
            ),
            MaterialStyle::Shadow,
        );
        let body_height = render_config.actor_body_length_world;
        let body_width = (render_config.actor_radius_world * 1.65).max(0.18);
        let body_depth = (render_config.actor_radius_world * 1.2).max(0.16);
        let head_radius = (render_config.actor_radius_world * 0.92).max(0.12);
        let shadow_width = body_width * 1.55;
        let shadow_depth = body_depth * 1.7;
        let pick_binding = ViewerPickBindingSpec::actor(actor.actor_id);
        let outline_member = HoverOutlineMember::new(ViewerPickTarget::Actor(actor.actor_id));

        let actor_transform =
            Transform::from_translation(translation).with_scale(Vec3::splat(grid_size));
        let entity = commands
            .spawn((
                actor_transform,
                GlobalTransform::from(actor_transform),
                Visibility::Visible,
                InheritedVisibility::VISIBLE,
                ActorBodyVisual {
                    actor_id: actor.actor_id,
                    body_material: body_material.clone(),
                    head_material: head_material.clone(),
                    accent_material: accent_material.clone(),
                },
            ))
            .with_children(|parent| {
                parent.spawn((
                    Mesh3d(meshes.add(Cuboid::new(shadow_width, 0.018, shadow_depth))),
                    MeshMaterial3d(shadow_material),
                    Transform::from_xyz(
                        0.0,
                        -(render_config.actor_radius_world + body_height * 0.5) + 0.01,
                        0.0,
                    ),
                ));
                parent.spawn((
                    Mesh3d(meshes.add(Cuboid::new(body_width, body_height, body_depth))),
                    MeshMaterial3d(body_material.clone()),
                    Transform::from_xyz(0.0, -render_config.actor_radius_world, 0.0),
                    pickable_target(pick_binding.clone().into()),
                    outline_member.clone(),
                ));
                parent.spawn((
                    Mesh3d(meshes.add(Sphere::new(head_radius))),
                    MeshMaterial3d(head_material),
                    Transform::from_xyz(0.0, body_height * 0.5, 0.0),
                    pickable_target(pick_binding.clone().into()),
                    outline_member.clone(),
                ));
            })
            .id();
        actor_visual_state.by_actor.insert(actor.actor_id, entity);
    }

    let stale_actor_ids: Vec<_> = actor_visual_state
        .by_actor
        .keys()
        .copied()
        .filter(|actor_id| !seen_actor_ids.contains(actor_id))
        .collect();
    for actor_id in stale_actor_ids {
        if let Some(entity) = actor_visual_state.by_actor.remove(&actor_id) {
            commands.entity(entity).despawn();
        }
    }
}

pub(crate) fn actor_visual_world_position(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    actor: &game_core::ActorDebugState,
) -> game_data::WorldCoord {
    motion_state
        .current_world(actor.actor_id)
        .unwrap_or_else(|| runtime_state.runtime.grid_to_world(actor.grid_position))
}

pub(crate) fn actor_visual_translation(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    feedback_state: &ViewerActorFeedbackState,
    actor: &game_core::ActorDebugState,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> Vec3 {
    actor_body_translation(
        actor_visual_world_position(runtime_state, motion_state, actor),
        grid_size,
        render_config,
    ) + feedback_state.visual_offset(actor.actor_id)
}

pub(crate) fn should_hide_building_roofs(
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    current_level: i32,
) -> bool {
    let focused_actor_id = if viewer_state.is_free_observe() {
        viewer_state.selected_actor
    } else {
        viewer_state.command_actor_id(snapshot)
    };
    focused_actor_id
        .and_then(|actor_id| {
            snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == actor_id)
        })
        .is_some_and(|actor| actor.grid_position.y == current_level)
}

pub(crate) fn should_show_actor_label(
    render_config: ViewerRenderConfig,
    viewer_state: &ViewerState,
    actor: &game_core::ActorDebugState,
    interaction_locked: bool,
    hovered_actor_id: Option<ActorId>,
) -> bool {
    let focused_actor_id = if viewer_state.is_free_observe() {
        viewer_state.selected_actor
    } else {
        viewer_state.controlled_player_actor
    };
    match render_config.overlay_mode {
        ViewerOverlayMode::Minimal => {
            Some(actor.actor_id) == focused_actor_id
                || Some(actor.actor_id) == hovered_actor_id
                || interaction_locked
        }
        ViewerOverlayMode::Gameplay => {
            Some(actor.actor_id) == focused_actor_id
                || Some(actor.actor_id) == hovered_actor_id
                || actor.side == ActorSide::Player
                || interaction_locked
        }
        ViewerOverlayMode::AiDebug => true,
    }
}

pub(crate) fn actor_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    match side {
        ActorSide::Player => palette.player,
        ActorSide::Friendly => palette.friendly,
        ActorSide::Hostile => palette.hostile,
        ActorSide::Neutral => palette.neutral,
    }
}

pub(super) fn actor_head_color(body_color: Color) -> Color {
    let mut color = body_color.to_srgba();
    color.red = (color.red * 1.08).min(1.0);
    color.green = (color.green * 1.08).min(1.0);
    color.blue = (color.blue * 1.08).min(1.0);
    color.into()
}

pub(super) fn actor_accent_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    match side {
        ActorSide::Player => lighten_color(palette.player, 0.2),
        ActorSide::Friendly => lighten_color(palette.friendly, 0.16),
        ActorSide::Hostile => lighten_color(palette.hostile, 0.12),
        ActorSide::Neutral => lighten_color(palette.neutral, 0.12),
    }
}

pub(crate) fn actor_selection_ring_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    let mut color = lerp_color(actor_color(side, palette), palette.selection, 0.35).to_srgba();
    color.red = (color.red * 1.15).min(1.0);
    color.green = (color.green * 1.15).min(1.0);
    color.blue = (color.blue * 1.15).min(1.0);
    color.into()
}
