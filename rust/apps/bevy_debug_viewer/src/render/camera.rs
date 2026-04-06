//! Viewer 相机与基础场景入口：负责相机、灯光、UI 根节点初始化以及相机跟随更新。

use super::*;
use crate::info_panels::spawn_info_panel_ui;
use bevy::core_pipeline::prepass::DepthPrepass;
use bevy::picking::prelude::MeshPickingCamera;
use bevy_mesh_outline::OutlineCamera;

pub(crate) fn setup_viewer(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut images: ResMut<Assets<Image>>,
    palette: Res<ViewerPalette>,
    style: Res<ViewerStyleProfile>,
) {
    let ui_font = asset_server.load(VIEWER_FONT_PATH);
    let trigger_arrow_texture = images.add(build_trigger_arrow_texture());
    let current_fow_mask = images.add(build_fog_of_war_mask_image(UVec2::ONE, &[255]));
    let previous_fow_mask = images.add(build_fog_of_war_mask_image(UVec2::ONE, &[255]));
    commands.insert_resource(ViewerUiFont(ui_font.clone()));
    commands.insert_resource(StaticWorldVisualState::default());
    commands.insert_resource(GeneratedDoorVisualState::default());
    commands.insert_resource(ActorVisualState::default());
    commands.insert_resource(FogOfWarMaskState::new(
        current_fow_mask.clone(),
        previous_fow_mask.clone(),
    ));
    commands.insert_resource(DamageNumberVisualState::default());
    commands.insert_resource(TriggerDecalAssets {
        arrow_texture: trigger_arrow_texture,
    });
    commands.insert_resource(GlobalAmbientLight {
        color: palette.ambient_color,
        brightness: style.ambient_brightness,
        affects_lightmapped_meshes: true,
    });
    commands.insert_resource(DirectionalLightShadowMap { size: 2048 });
    commands.spawn((
        Camera3d::default(),
        Msaa::Off,
        DepthPrepass,
        Projection::from(PerspectiveProjection {
            fov: 30.0_f32.to_radians(),
            near: 0.1,
            far: 2000.0,
            ..PerspectiveProjection::default()
        }),
        Transform::from_xyz(0.0, 10.0, -10.0).looking_at(Vec3::ZERO, Vec3::Z),
        ViewerCamera,
        MeshPickingCamera,
        OutlineCamera,
        FogOfWarOverlay,
        FogOfWarPostProcessSettings::default(),
        FogOfWarPostProcessTextures {
            current_mask: current_fow_mask,
            previous_mask: previous_fow_mask,
        },
    ));
    commands.spawn((
        DirectionalLight {
            color: palette.key_light_color,
            illuminance: style.key_light_illuminance,
            shadows_enabled: true,
            shadow_depth_bias: 0.04,
            shadow_normal_bias: 1.6,
            ..default()
        },
        CascadeShadowConfigBuilder {
            num_cascades: 3,
            minimum_distance: 0.1,
            first_cascade_far_bound: 10.0,
            maximum_distance: 48.0,
            overlap_proportion: 0.25,
        }
        .build(),
        Transform::from_xyz(-12.0, 18.0, -10.0).looking_at(Vec3::ZERO, Vec3::Y),
        KeyLight,
    ));
    commands.spawn((
        DirectionalLight {
            color: palette.fill_light_color,
            illuminance: style.fill_light_illuminance,
            shadows_enabled: false,
            ..default()
        },
        Transform::from_xyz(15.0, 10.0, 8.0).looking_at(Vec3::ZERO, Vec3::Y),
        FillLight,
    ));
    spawn_info_panel_ui(&mut commands, ui_font.clone(), &palette);
    let interaction_style = ContextMenuStyle::for_variant(ContextMenuVariant::WorldInteraction);
    commands.spawn((
        context_menu_root_node(interaction_style, Vec2::ZERO),
        BackgroundColor(context_menu_panel_color()),
        BorderColor::all(context_menu_border_color()),
        Visibility::Hidden,
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        viewer_ui_passthrough_bundle(),
        InteractionMenuRoot,
        UiMouseBlocker,
    ));
    commands.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: px(24),
            bottom: px(DIALOGUE_PANEL_BOTTOM_PX),
            width: px(720),
            padding: UiRect::all(px(16)),
            flex_direction: FlexDirection::Column,
            ..default()
        },
        BackgroundColor(palette.dialogue_background),
        Visibility::Hidden,
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        viewer_ui_passthrough_bundle(),
        DialoguePanelRoot,
        UiMouseBlocker,
    ));
    spawn_console_panel(&mut commands, ui_font, &palette);
}

pub(crate) fn update_camera(
    time: Res<Time>,
    window: Single<&Window>,
    camera_query: Single<(&mut Projection, &mut Transform), With<ViewerCamera>>,
    motion_state: Res<ViewerActorMotionState>,
    runtime_state: Res<ViewerRuntimeState>,
    scene_kind: Res<ViewerSceneKind>,
    mut camera_shake_state: ResMut<ViewerCameraShakeState>,
    mut camera_follow_state: ResMut<ViewerCameraFollowState>,
    mut viewer_state: ResMut<ViewerState>,
    render_config: Res<ViewerRenderConfig>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let grid_size = snapshot.grid.grid_size;
    let (desired_focus, followed_actor_id, smooth_follow_enabled) =
        if scene_kind.is_gameplay() && viewer_state.is_camera_following_selected_actor() {
            let (focus, actor_id) = camera_focus_following_selected_actor(
                &runtime_state,
                &motion_state,
                &snapshot,
                &viewer_state,
                bounds,
                window.width(),
                window.height(),
                *render_config,
            );
            (focus, actor_id, true)
        } else {
            viewer_state.camera_pan_offset = clamp_camera_pan_offset(
                bounds,
                grid_size,
                viewer_state.camera_pan_offset,
                window.width(),
                window.height(),
                *render_config,
            );
            (
                camera_focus_point(
                    bounds,
                    viewer_state.current_level,
                    grid_size,
                    viewer_state.camera_pan_offset,
                ),
                None,
                false,
            )
        };
    let focus = update_camera_follow_focus(
        &mut camera_follow_state,
        desired_focus,
        followed_actor_id,
        viewer_state.current_level,
        grid_size,
        time.delta_secs(),
        *scene_kind,
        smooth_follow_enabled,
    );
    let distance = camera_world_distance(
        bounds,
        window.width(),
        window.height(),
        grid_size,
        *render_config,
    );
    let pitch = render_config.camera_pitch_radians();
    let yaw = render_config.camera_yaw_radians();
    let horizontal = distance * pitch.cos();
    let offset = Vec3::new(
        horizontal * yaw.sin(),
        distance * pitch.sin(),
        -horizontal * yaw.cos(),
    );
    let (mut projection, mut transform) = camera_query.into_inner();

    if let Projection::Perspective(perspective) = &mut *projection {
        perspective.fov = render_config.camera_fov_radians();
        perspective.near = 0.1;
        perspective.far = (distance * 8.0).max(1000.0);
    }

    camera_shake_state.advance(time.delta_secs());
    transform.translation = focus + offset + camera_shake_state.current_offset();
    transform.look_at(focus, Vec3::Z);
}

pub(super) fn camera_focus_following_selected_actor(
    runtime_state: &ViewerRuntimeState,
    motion_state: &ViewerActorMotionState,
    snapshot: &game_core::SimulationSnapshot,
    viewer_state: &ViewerState,
    bounds: GridBounds,
    viewport_width: f32,
    viewport_height: f32,
    render_config: ViewerRenderConfig,
) -> (Vec3, Option<ActorId>) {
    let grid_size = snapshot.grid.grid_size;
    let Some(actor) = selected_actor(snapshot, viewer_state) else {
        return (
            camera_focus_point(bounds, viewer_state.current_level, grid_size, Vec2::ZERO),
            None,
        );
    };
    let actor_world = motion_state
        .current_world(actor.actor_id)
        .unwrap_or_else(|| runtime_state.runtime.grid_to_world(actor.grid_position));
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (bounds.min_z + bounds.max_z + 1) as f32 * grid_size * 0.5;
    let follow_offset = Vec2::new(actor_world.x - center_x, actor_world.z - center_z);
    let clamped_offset = clamp_camera_pan_offset(
        bounds,
        grid_size,
        follow_offset,
        viewport_width,
        viewport_height,
        render_config,
    );

    (
        camera_focus_point(
            bounds,
            viewer_state.current_level,
            grid_size,
            clamped_offset,
        ),
        Some(actor.actor_id),
    )
}

pub(super) fn update_camera_follow_focus(
    camera_follow_state: &mut ViewerCameraFollowState,
    desired_focus: Vec3,
    followed_actor_id: Option<ActorId>,
    current_level: i32,
    grid_size: f32,
    delta_sec: f32,
    scene_kind: ViewerSceneKind,
    smooth_follow_enabled: bool,
) -> Vec3 {
    if camera_follow_requires_reset(
        *camera_follow_state,
        desired_focus,
        followed_actor_id,
        current_level,
        grid_size,
        scene_kind,
        smooth_follow_enabled,
    ) {
        camera_follow_state.reset(desired_focus, followed_actor_id, current_level);
        return desired_focus;
    }

    let alpha = 1.0 - (-delta_sec.max(0.0) / CAMERA_FOLLOW_SMOOTHING_TAU_SEC).exp();
    camera_follow_state.smoothed_focus = camera_follow_state
        .smoothed_focus
        .lerp(desired_focus, alpha.clamp(0.0, 1.0));
    camera_follow_state.last_actor_id = followed_actor_id;
    camera_follow_state.last_level = current_level;
    camera_follow_state.smoothed_focus
}

pub(super) fn camera_follow_requires_reset(
    camera_follow_state: ViewerCameraFollowState,
    desired_focus: Vec3,
    followed_actor_id: Option<ActorId>,
    current_level: i32,
    grid_size: f32,
    scene_kind: ViewerSceneKind,
    smooth_follow_enabled: bool,
) -> bool {
    scene_kind.is_main_menu()
        || !smooth_follow_enabled
        || !camera_follow_state.initialized
        || camera_follow_state.last_actor_id != followed_actor_id
        || camera_follow_state.last_level != current_level
        || camera_follow_state.smoothed_focus.distance(desired_focus)
            > grid_size * CAMERA_FOLLOW_RESET_DISTANCE_CELLS
}
