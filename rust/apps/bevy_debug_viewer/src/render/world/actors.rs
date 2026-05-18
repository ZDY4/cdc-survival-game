//! 角色可视化 helper：负责角色实体同步、世界位置换算与颜色策略。

use super::*;
use crate::state::ActorMotionTrack;

const ACTOR_STEP_BOB_HEIGHT: f32 = 0.035;
const ACTOR_STEP_LEAN_RADIANS: f32 = 0.055;

#[allow(clippy::too_many_arguments)]
pub(super) fn sync_actor_visuals(
    commands: &mut Commands,
    asset_server: &AssetServer,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    character_definitions: Option<&game_bevy::CharacterDefinitions>,
    item_definitions: Option<&game_bevy::ItemDefinitions>,
    character_appearance_definitions: Option<&game_bevy::CharacterAppearanceDefinitions>,
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    feedback_state: &ViewerActorFeedbackState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    render_config: ViewerRenderConfig,
    palette: &ViewerPalette,
    actor_visual_state: &mut ActorVisualState,
    actor_visuals: &mut Query<
        (Entity, &mut Transform, &ActorBodyVisual),
        Without<GeneratedDoorPivot>,
    >,
    actor_motion_anchors: &mut Query<
        &mut Transform,
        (
            With<ActorMotionVisualAnchor>,
            Without<ActorBodyVisual>,
            Without<GeneratedDoorPivot>,
        ),
    >,
    mesh_pick_index: &mut crate::picking::ViewerMeshPickIndex,
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
        let appearance_key = game_bevy::runtime_character_appearance_key(
            &runtime_state.runtime,
            actor.actor_id,
            actor.definition_id.as_ref().map(|id| id.as_str()),
        );
        let motion_track = motion_state.tracks.get(&actor.actor_id);
        let previous_yaw = actor_visual_state
            .by_actor
            .get(&actor.actor_id)
            .map(|entry| entry.facing_yaw)
            .unwrap_or(0.0);
        let facing_yaw = actor_facing_yaw(motion_track, previous_yaw);
        let root_rotation = Quat::from_rotation_y(facing_yaw);
        let anchor_transform = actor_motion_anchor_transform(motion_track);

        if let Some(existing) = actor_visual_state.by_actor.get(&actor.actor_id).cloned() {
            if existing.appearance_key == appearance_key {
                if let Ok((_, mut transform, body)) = actor_visuals.get_mut(existing.root_entity) {
                    if body.actor_id == actor.actor_id {
                        transform.translation = translation;
                        transform.rotation = root_rotation;
                        if let Ok(mut anchor) =
                            actor_motion_anchors.get_mut(existing.motion_anchor_entity)
                        {
                            *anchor = anchor_transform;
                        }
                        if let Some(entry) = actor_visual_state.by_actor.get_mut(&actor.actor_id) {
                            entry.facing_yaw = facing_yaw;
                        }
                        register_actor_pick_mesh(
                            mesh_pick_index,
                            existing.root_entity,
                            actor,
                            translation,
                            grid_size,
                            render_config,
                        );
                        continue;
                    }
                }
            }
            mesh_pick_index.clear_entity(existing.root_entity);
            commands.entity(existing.root_entity).despawn();
            actor_visual_state.by_actor.remove(&actor.actor_id);
        }

        let (root_entity, motion_anchor_entity) = spawn_actor_visual_root(
            commands,
            asset_server,
            meshes,
            materials,
            palette,
            render_config,
            grid_size,
            actor,
            translation,
            root_rotation,
            anchor_transform,
            character_definitions,
            item_definitions,
            character_appearance_definitions,
            runtime_state,
        );
        register_actor_pick_mesh(
            mesh_pick_index,
            root_entity,
            actor,
            translation,
            grid_size,
            render_config,
        );
        actor_visual_state.by_actor.insert(
            actor.actor_id,
            ActorVisualEntry {
                root_entity,
                motion_anchor_entity,
                appearance_key,
                facing_yaw,
            },
        );
    }

    let stale_actor_ids: Vec<_> = actor_visual_state
        .by_actor
        .keys()
        .copied()
        .filter(|actor_id| !seen_actor_ids.contains(actor_id))
        .collect();
    for actor_id in stale_actor_ids {
        if let Some(entry) = actor_visual_state.by_actor.remove(&actor_id) {
            mesh_pick_index.clear_entity(entry.root_entity);
            commands.entity(entry.root_entity).despawn();
        }
    }
}

fn actor_facing_yaw(motion_track: Option<&ActorMotionTrack>, previous_yaw: f32) -> f32 {
    motion_track
        .and_then(ActorMotionTrack::direction_xz)
        .map(actor_direction_yaw)
        .unwrap_or(previous_yaw)
}

fn actor_direction_yaw(direction: Vec2) -> f32 {
    direction.x.atan2(direction.y)
}

fn actor_motion_anchor_transform(motion_track: Option<&ActorMotionTrack>) -> Transform {
    let step_arc = motion_track.map(ActorMotionTrack::step_arc).unwrap_or(0.0);
    Transform::from_translation(Vec3::Y * (step_arc * ACTOR_STEP_BOB_HEIGHT))
        .with_rotation(Quat::from_rotation_x(step_arc * ACTOR_STEP_LEAN_RADIANS))
}

pub(crate) fn sync_actor_precise_pick_meshes(
    mut mesh_pick_index: ResMut<crate::picking::ViewerMeshPickIndex>,
    meshes: Res<Assets<Mesh>>,
    actor_roots: Query<(Entity, &ActorBodyVisual)>,
    children_query: Query<&Children>,
    mesh_query: Query<(Entity, &Mesh3d, &GlobalTransform)>,
) {
    for (root_entity, body) in &actor_roots {
        // The fallback body proxy is registered by sync_actor_visuals. Clear only the previous
        // frame's precise child meshes here so loaded glTF parts can move/update without growing
        // duplicate pick instances or losing the fallback before assets are ready.
        mesh_pick_index.clear_precise_entity(root_entity);
        let mut stack = vec![root_entity];
        while let Some(entity) = stack.pop() {
            if let Ok(children) = children_query.get(entity) {
                for child in children.iter() {
                    stack.push(child);
                }
            }

            let Ok((_, mesh_handle, global_transform)) = mesh_query.get(entity) else {
                continue;
            };
            let Some(mesh) = meshes.get(&mesh_handle.0) else {
                continue;
            };
            let (scale, rotation, translation) = global_transform.to_scale_rotation_translation();
            let transform = Transform::from_translation(translation)
                .with_rotation(rotation)
                .with_scale(scale);
            mesh_pick_index.register_mesh_instance_preserving_fallback(
                root_entity,
                mesh,
                crate::picking::PickMeshPrototypeKey::mesh(&mesh_handle.0),
                transform,
                ViewerPickBindingSpec::actor(body.actor_id),
            );
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn spawn_actor_visual_root(
    commands: &mut Commands,
    asset_server: &AssetServer,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    palette: &ViewerPalette,
    render_config: ViewerRenderConfig,
    grid_size: f32,
    actor: &game_core::ActorDebugState,
    translation: Vec3,
    root_rotation: Quat,
    anchor_transform: Transform,
    character_definitions: Option<&game_bevy::CharacterDefinitions>,
    item_definitions: Option<&game_bevy::ItemDefinitions>,
    character_appearance_definitions: Option<&game_bevy::CharacterAppearanceDefinitions>,
    runtime_state: &ViewerRuntimeState,
) -> (Entity, Entity) {
    let actor_transform = Transform::from_translation(translation)
        .with_rotation(root_rotation)
        .with_scale(Vec3::splat(grid_size));
    let root_entity = commands
        .spawn((
            actor_transform,
            GlobalTransform::from(actor_transform),
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
            ActorBodyVisual {
                actor_id: actor.actor_id,
            },
        ))
        .id();

    let motion_anchor_entity = commands
        .spawn((
            anchor_transform,
            GlobalTransform::from(anchor_transform),
            Visibility::Visible,
            InheritedVisibility::VISIBLE,
            ActorMotionVisualAnchor,
        ))
        .id();
    commands.entity(root_entity).add_child(motion_anchor_entity);

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
    let shadow_width = body_width * 1.55;
    let shadow_depth = body_depth * 1.7;
    let pick_binding = ViewerPickBindingSpec::actor(actor.actor_id);
    let outline_member = HoverOutlineMember::new(ViewerPickTarget::Actor(actor.actor_id));
    let pick_proxy_material = make_standard_material(
        materials,
        actor_color(actor.side, palette),
        MaterialStyle::InvisiblePickProxy,
    );

    let appearance_preview = character_definitions
        .zip(item_definitions)
        .zip(character_appearance_definitions)
        .and_then(|((definitions, items), appearances)| {
            game_bevy::resolve_runtime_character_preview(
                definitions,
                items,
                appearances,
                &runtime_state.runtime,
                actor.actor_id,
                actor.definition_id.as_ref().map(|id| id.as_str()),
            )
        });

    commands.entity(root_entity).with_children(|parent| {
        parent.spawn((
            Mesh3d(meshes.add(Cuboid::new(shadow_width, 0.018, shadow_depth))),
            MeshMaterial3d(shadow_material),
            Transform::from_xyz(
                0.0,
                -(render_config.actor_radius_world + body_height * 0.5) + 0.01,
                0.0,
            ),
        ));
    });

    commands
        .entity(motion_anchor_entity)
        .with_children(|parent| {
            parent.spawn((
                Mesh3d(meshes.add(Cuboid::new(body_width, body_height, body_depth))),
                MeshMaterial3d(pick_proxy_material),
                Transform::from_xyz(0.0, -render_config.actor_radius_world, 0.0),
                pickable_target(pick_binding.into()),
                outline_member,
            ));
        });

    if let Some(preview) = appearance_preview.filter(game_bevy::character_preview_is_available) {
        let appearance_entity =
            game_bevy::spawn_character_preview_scene(commands, asset_server, materials, &preview);
        commands
            .entity(motion_anchor_entity)
            .add_child(appearance_entity);
    }

    (root_entity, motion_anchor_entity)
}

fn register_actor_pick_mesh(
    mesh_pick_index: &mut crate::picking::ViewerMeshPickIndex,
    root_entity: Entity,
    actor: &game_core::ActorDebugState,
    translation: Vec3,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) {
    mesh_pick_index.clear_entity(root_entity);
    // Keep actors in the unified mesh index so body/head hover does not fall back to the
    // occupied tile. This proxy is intentionally oversized until spawned glTF children are
    // indexed directly.
    let body_height = render_config.actor_body_length_world;
    let width = (render_config.actor_radius_world * 2.8).max(0.34);
    let depth = (render_config.actor_radius_world * 2.8).max(0.34);
    let height = (body_height + render_config.actor_radius_world * 3.2).max(0.9);
    let local_center_y = -render_config.actor_radius_world + body_height * 0.35;
    mesh_pick_index.register_cuboid_instance(
        root_entity,
        Vec3::new(width, height, depth),
        Transform::from_translation(translation + Vec3::Y * local_center_y * grid_size)
            .with_scale(Vec3::splat(grid_size)),
        ViewerPickBindingSpec::actor(actor.actor_id),
    );
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
    let is_hovered = Some(actor.actor_id) == hovered_actor_id;
    let is_focused = Some(actor.actor_id) == focused_actor_id;
    if actor.side == ActorSide::Player && render_config.overlay_mode != ViewerOverlayMode::AiDebug {
        return is_hovered || interaction_locked;
    }
    match render_config.overlay_mode {
        ViewerOverlayMode::Minimal => is_focused || is_hovered || interaction_locked,
        ViewerOverlayMode::Gameplay => is_focused || is_hovered || interaction_locked,
        ViewerOverlayMode::AiDebug => true,
    }
}

pub(crate) fn should_draw_actor_selection_ring(actor: &game_core::ActorDebugState) -> bool {
    actor.side != ActorSide::Player
}

pub(crate) fn actor_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    match side {
        ActorSide::Player => palette.player,
        ActorSide::Friendly => palette.friendly,
        ActorSide::Hostile => palette.hostile,
        ActorSide::Neutral => palette.neutral,
    }
}

pub(crate) fn actor_selection_ring_color(side: ActorSide, palette: &ViewerPalette) -> Color {
    let mut color = lerp_color(actor_color(side, palette), palette.selection, 0.35).to_srgba();
    color.red = (color.red * 1.15).min(1.0);
    color.green = (color.green * 1.15).min(1.0);
    color.blue = (color.blue * 1.15).min(1.0);
    color.into()
}
