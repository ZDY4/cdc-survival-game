//! 渲染模块测试：覆盖静态世界规格、角色可视化、交互菜单和遮挡淡化等回归场景。

use super::*;

use super::{
    actor_visual_translation, actor_visual_world_position, camera_follow_requires_reset,
    collect_closed_door_occluders, collect_ground_cells_to_render, collect_static_world_box_specs,
    collect_static_world_building_wall_tile_specs, collect_static_world_decal_specs,
    collect_walkable_tile_overlay_cells, darken_color, generated_door_render_polygon,
    interaction_menu_button_font_size_for_label, interaction_menu_layout, lighten_color,
    occluder_blocks_visible_cells, occluder_should_fade, occupied_cells_box,
    project_shadowed_visible_cells, resolve_active_interaction_hover,
    should_draw_actor_selection_ring, should_fade_occluder, should_hide_building_roofs,
    should_show_actor_label, sync_hover_mesh_outlines, update_camera_follow_focus, GridBounds,
    HoverOutlineMember, MaterialStyle, StaticWorldOccluderKind, WalkableTileOverlayKind,
    HOVER_MESH_OUTLINE_WIDTH_PX, INTERACTION_MENU_BORDER_WIDTH_PX, INTERACTION_MENU_ITEM_GAP_PX,
    INTERACTION_MENU_ITEM_HEIGHT_PX, INTERACTION_MENU_ITEM_MIN_FONT_SIZE_PX,
    INTERACTION_MENU_PADDING_PX, INTERACTION_MENU_WIDTH_PX,
};
use crate::picking::{BuildingPartKind, ViewerPickTarget};
use crate::state::{
    InteractionMenuState, ViewerActorFeedbackState, ViewerActorMotionState,
    ViewerCameraFollowState, ViewerControlMode, ViewerPalette, ViewerRenderConfig,
    ViewerRuntimeState, ViewerSceneKind, ViewerState,
};
use bevy_mesh_outline::MeshOutline;
use game_bevy::world_render::{
    building_door_color, building_wall_visual_profile, make_building_wall_material,
};
use game_bevy::SettlementDebugSnapshot;
use game_core::{
    create_demo_runtime, CombatDebugState, GeneratedBuildingDebugState, GeneratedBuildingStory,
    GeneratedStairConnection, GridDebugState, MapCellDebugState, MapObjectDebugState,
    OverworldStateSnapshot, SimulationSnapshot,
};
use game_data::{
    ActorId, GridCoord, InteractionContextSnapshot, InteractionOptionId, InteractionPrompt,
    InteractionTargetId, MapBuildingTileSetSpec, MapBuildingWallVisualKind, MapCellVisualSpec,
    MapObjectFootprint, MapObjectKind, MapRotation, ResolvedInteractionOption, TileSlopeKind,
    TurnState, WorldCoord, WorldSurfaceTileSetId, WorldWallTileSetId,
};

fn sample_building_tile_set() -> MapBuildingTileSetSpec {
    MapBuildingTileSetSpec {
        wall_set_id: WorldWallTileSetId("building_wall_legacy".into()),
        floor_surface_set_id: Some(WorldSurfaceTileSetId("building_wall_legacy/floor".into())),
        door_prototype_id: None,
    }
}

fn seed_stable_hover(app: &mut App) {
    let active = {
        let world = app.world();
        let runtime_state = world.resource::<ViewerRuntimeState>();
        let snapshot = runtime_state.runtime.snapshot();
        let viewer_state = world.resource::<ViewerState>();
        let picking_state = world.resource::<crate::picking::ViewerPickingState>();
        resolve_active_interaction_hover(runtime_state, &snapshot, viewer_state, picking_state)
    };
    let mut stable_hover = StableInteractionHoverState::default();
    stable_hover.active = active;
    app.insert_resource(stable_hover);
}

#[test]
fn actor_visual_world_position_prefers_motion_track() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let actor = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == handles.player)
        .expect("player actor should exist");
    let runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let mut motion_state = ViewerActorMotionState::default();
    motion_state.track_movement(
        handles.player,
        WorldCoord::new(0.5, 0.5, 0.5),
        WorldCoord::new(1.5, 0.5, 0.5),
        0,
        0.1,
    );
    motion_state
        .tracks
        .get_mut(&handles.player)
        .expect("track should exist")
        .advance(0.05);

    let world = actor_visual_world_position(&runtime_state, &motion_state, actor);

    assert_eq!(world, WorldCoord::new(1.0, 0.5, 0.5));
}

#[test]
fn actor_visual_translation_applies_feedback_offset_without_moving_authority() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let actor = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == handles.player)
        .expect("player actor should exist");
    let runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let motion_state = ViewerActorMotionState::default();
    let mut feedback_state = ViewerActorFeedbackState::default();
    feedback_state.queue_hit_reaction(handles.player);
    feedback_state.advance(0.03);

    let translated = actor_visual_translation(
        &runtime_state,
        &motion_state,
        &feedback_state,
        actor,
        snapshot.grid.grid_size,
        ViewerRenderConfig::default(),
    );
    let baseline = actor_visual_translation(
        &runtime_state,
        &motion_state,
        &ViewerActorFeedbackState::default(),
        actor,
        snapshot.grid.grid_size,
        ViewerRenderConfig::default(),
    );

    assert_ne!(translated, baseline);
}

#[test]
fn camera_follow_focus_smooths_toward_desired_focus() {
    let mut follow_state = ViewerCameraFollowState::default();
    follow_state.reset(Vec3::ZERO, Some(ActorId(1)), 0);
    let desired_focus = Vec3::new(1.5, 0.5, 0.0);

    let focus = update_camera_follow_focus(
        &mut follow_state,
        desired_focus,
        Some(ActorId(1)),
        0,
        1.0,
        0.016,
        ViewerSceneKind::Gameplay,
        true,
    );

    assert!(focus.x > 0.0);
    assert!(focus.x < desired_focus.x);
    assert_eq!(follow_state.last_actor_id, Some(ActorId(1)));
}

#[test]
fn camera_follow_focus_resets_on_actor_or_level_change() {
    let follow_state = ViewerCameraFollowState {
        smoothed_focus: Vec3::new(1.0, 0.5, 1.0),
        initialized: true,
        last_actor_id: Some(ActorId(1)),
        last_level: 0,
    };

    assert!(camera_follow_requires_reset(
        follow_state,
        Vec3::new(4.0, 0.5, 4.0),
        Some(ActorId(2)),
        0,
        1.0,
        ViewerSceneKind::Gameplay,
        true,
    ));
    assert!(camera_follow_requires_reset(
        follow_state,
        Vec3::new(4.0, 1.5, 4.0),
        Some(ActorId(1)),
        1,
        1.0,
        ViewerSceneKind::Gameplay,
        true,
    ));
}

#[test]
fn camera_follow_focus_resets_when_follow_is_disabled_or_main_menu() {
    let mut follow_state = ViewerCameraFollowState {
        smoothed_focus: Vec3::new(3.0, 0.5, 3.0),
        initialized: true,
        last_actor_id: Some(ActorId(1)),
        last_level: 0,
    };
    let desired_focus = Vec3::new(7.0, 0.5, 7.0);

    let manual_focus = update_camera_follow_focus(
        &mut follow_state,
        desired_focus,
        None,
        0,
        1.0,
        0.016,
        ViewerSceneKind::Gameplay,
        false,
    );
    assert_eq!(manual_focus, desired_focus);

    let menu_focus = update_camera_follow_focus(
        &mut follow_state,
        Vec3::new(9.0, 0.5, 9.0),
        Some(ActorId(1)),
        0,
        1.0,
        0.016,
        ViewerSceneKind::MainMenu,
        true,
    );
    assert_eq!(menu_focus, Vec3::new(9.0, 0.5, 9.0));
}

#[test]
fn gameplay_overlay_hides_player_label_until_hovered() {
    let snapshot = snapshot_with_focus_actor();
    let player = snapshot
        .actors
        .iter()
        .find(|actor| actor.side == game_data::ActorSide::Player)
        .expect("player actor should exist");
    let mut viewer_state = ViewerState::default();
    viewer_state.controlled_player_actor = Some(player.actor_id);

    assert!(!should_show_actor_label(
        ViewerRenderConfig::default(),
        &viewer_state,
        player,
        false,
        None,
    ));
    assert!(should_show_actor_label(
        ViewerRenderConfig::default(),
        &viewer_state,
        player,
        false,
        Some(player.actor_id),
    ));
}

#[test]
fn selection_ring_skips_player_actor() {
    let snapshot = snapshot_with_focus_actor();
    let player = snapshot
        .actors
        .iter()
        .find(|actor| actor.side == game_data::ActorSide::Player)
        .expect("player actor should exist");
    let observer = snapshot
        .actors
        .iter()
        .find(|actor| actor.side == game_data::ActorSide::Friendly)
        .expect("friendly actor should exist");

    assert!(!should_draw_actor_selection_ring(player));
    assert!(should_draw_actor_selection_ring(observer));
}

#[test]
fn interaction_menu_layout_clamps_to_window_bounds() {
    let window = Window {
        resolution: (320, 180).into(),
        ..default()
    };
    let menu_state = InteractionMenuState {
        target_id: InteractionTargetId::MapObject("crate".into()),
        cursor_position: Vec2::new(310.0, 170.0),
    };
    let prompt = sample_prompt(2);

    let layout = interaction_menu_layout(&window, &menu_state, &prompt);

    assert_eq!(layout.width, INTERACTION_MENU_WIDTH_PX);
    assert!(layout.left >= 0.0);
    assert!(layout.top >= 0.0);
    assert!(layout.left + layout.width <= window.width() - INTERACTION_MENU_PADDING_PX);
    assert!(layout.top + layout.height <= window.height() - INTERACTION_MENU_PADDING_PX);
}

#[test]
fn interaction_menu_layout_height_only_accounts_for_option_list() {
    let window = Window {
        resolution: (640, 360).into(),
        ..default()
    };
    let menu_state = InteractionMenuState {
        target_id: InteractionTargetId::MapObject("crate".into()),
        cursor_position: Vec2::new(120.0, 90.0),
    };
    let prompt = sample_prompt(3);

    let layout = interaction_menu_layout(&window, &menu_state, &prompt);

    assert_eq!(
        layout.height,
        INTERACTION_MENU_BORDER_WIDTH_PX * 2.0
            + INTERACTION_MENU_PADDING_PX * 2.0
            + 3.0 * INTERACTION_MENU_ITEM_HEIGHT_PX
            + 2.0 * INTERACTION_MENU_ITEM_GAP_PX
    );
}

#[test]
fn interaction_menu_button_font_size_shrinks_for_long_labels() {
    let default_font_size = crate::ui_context_menu::ContextMenuStyle::for_variant(
        crate::ui_context_menu::ContextMenuVariant::WorldInteraction,
    )
    .item_font_size;
    assert_eq!(
        interaction_menu_button_font_size_for_label("开门"),
        default_font_size
    );

    let long_label_size = interaction_menu_button_font_size_for_label("打开非常远处的厚重铁门");
    assert!(long_label_size < default_font_size);
    assert!(long_label_size >= INTERACTION_MENU_ITEM_MIN_FONT_SIZE_PX);
}

#[test]
fn occupied_cells_box_uses_full_footprint() {
    let (center_x, center_z, width, depth) = occupied_cells_box(
        &[
            GridCoord::new(4, 0, 2),
            GridCoord::new(5, 0, 2),
            GridCoord::new(4, 0, 3),
            GridCoord::new(5, 0, 3),
        ],
        1.0,
    );

    assert_eq!(center_x, 5.0);
    assert_eq!(center_z, 3.0);
    assert_eq!(width, 2.0);
    assert_eq!(depth, 2.0);
}

#[test]
fn ground_cells_skip_generated_building_walkable_cells() {
    let cells = collect_ground_cells_to_render(
        &snapshot_with_generated_building(),
        0,
        GridBounds {
            min_x: 0,
            max_x: 3,
            min_z: 0,
            max_z: 3,
        },
    );

    assert!(!cells.contains(&GridCoord::new(0, 0, 0)));
    assert!(cells.contains(&GridCoord::new(1, 0, 0)));
    assert_eq!(cells.len(), 15);
}

#[test]
fn ground_cells_cover_full_bounds_without_generated_buildings() {
    let cells = collect_ground_cells_to_render(
        &snapshot_with_occluders(),
        0,
        GridBounds {
            min_x: 0,
            max_x: 1,
            min_z: 0,
            max_z: 1,
        },
    );

    assert_eq!(cells.len(), 4);
    assert!(cells.contains(&GridCoord::new(0, 0, 0)));
    assert!(cells.contains(&GridCoord::new(1, 0, 1)));
}

#[test]
fn ground_cells_exclude_tactical_surface_visual_cells() {
    let mut snapshot = snapshot_with_occluders();
    snapshot.grid.map_cells.push(MapCellDebugState {
        grid: GridCoord::new(0, 0, 1),
        blocks_movement: false,
        blocks_sight: false,
        terrain: "ground".into(),
        visual: Some(MapCellVisualSpec {
            surface_set_id: Some(WorldSurfaceTileSetId("building_wall_legacy/floor".into())),
            elevation_steps: 0,
            slope: TileSlopeKind::Flat,
        }),
    });

    let cells = collect_ground_cells_to_render(
        &snapshot,
        0,
        GridBounds {
            min_x: 0,
            max_x: 1,
            min_z: 0,
            max_z: 1,
        },
    );

    assert!(!cells.contains(&GridCoord::new(0, 0, 1)));
}

#[test]
fn ground_cells_exclude_walkable_cells_from_multiple_generated_buildings() {
    let mut snapshot = snapshot_with_generated_building();
    let mut second_building = snapshot.generated_buildings[0].clone();
    second_building.object_id = "generated_house_b".into();
    second_building.anchor = GridCoord::new(2, 0, 2);
    second_building.stories[0].walkable_cells = vec![GridCoord::new(3, 0, 3)];
    second_building.stories[0].wall_cells = vec![GridCoord::new(3, 0, 3)];
    snapshot.generated_buildings.push(second_building);

    let cells = collect_ground_cells_to_render(
        &snapshot,
        0,
        GridBounds {
            min_x: 0,
            max_x: 3,
            min_z: 0,
            max_z: 3,
        },
    );

    assert!(!cells.contains(&GridCoord::new(0, 0, 0)));
    assert!(!cells.contains(&GridCoord::new(3, 0, 3)));
    assert!(cells.contains(&GridCoord::new(2, 0, 2)));
    assert_eq!(cells.len(), 14);
}

#[test]
fn static_world_specs_hide_nonfunctional_environment_geometry() {
    let specs = collect_static_world_box_specs(
        &snapshot_with_occluders(),
        0,
        false,
        ViewerRenderConfig::default(),
        &ViewerPalette::default(),
        GridBounds {
            min_x: 0,
            max_x: 1,
            min_z: 0,
            max_z: 1,
        },
        world_from_grid,
    );

    let non_occluder_count = specs
        .iter()
        .filter(|spec| spec.occluder_kind.is_none())
        .count();
    let occluder_count = specs
        .iter()
        .filter(|spec| spec.occluder_kind.is_some())
        .count();

    assert!(non_occluder_count > 0);
    assert_eq!(occluder_count, 1);
    assert!(specs.iter().all(|spec| {
        spec.occluder_kind.is_none()
            || matches!(
                spec.occluder_kind,
                Some(StaticWorldOccluderKind::MapObject(_))
            )
    }));
}

#[test]
fn static_world_specs_skip_missing_geo_buildings_and_keep_functional_objects() {
    let specs = collect_static_world_box_specs(
        &snapshot_with_occluders(),
        0,
        false,
        ViewerRenderConfig::default(),
        &ViewerPalette::default(),
        GridBounds {
            min_x: 0,
            max_x: 1,
            min_z: 0,
            max_z: 1,
        },
        world_from_grid,
    );

    assert!(!specs.iter().any(|spec| {
        spec.occluder_kind == Some(StaticWorldOccluderKind::MapObject(MapObjectKind::Building))
    }));
    assert!(specs.iter().any(|spec| {
        spec.occluder_kind
            == Some(StaticWorldOccluderKind::MapObject(
                MapObjectKind::Interactive,
            ))
    }));
}

#[test]
fn scene_transition_triggers_render_floor_arrow_decals_per_cell() {
    let palette = ViewerPalette::default();
    let box_specs = collect_static_world_box_specs(
        &snapshot_with_trigger_strip(),
        0,
        false,
        ViewerRenderConfig::default(),
        &palette,
        GridBounds {
            min_x: 0,
            max_x: 3,
            min_z: 0,
            max_z: 1,
        },
        world_from_grid,
    );
    let decal_specs = collect_static_world_decal_specs(
        &snapshot_with_trigger_strip(),
        0,
        ViewerRenderConfig::default(),
        &palette,
    );

    let trigger_box_specs = box_specs
        .iter()
        .filter(|spec| spec.occluder_kind.is_none())
        .filter(|spec| {
            let color = spec.color.to_srgba();
            color == palette.trigger.to_srgba()
                || color == darken_color(palette.trigger, 0.08).to_srgba()
                || color == lighten_color(palette.trigger, 0.08).to_srgba()
        })
        .count();

    assert_eq!(trigger_box_specs, 0);
    assert_eq!(decal_specs.len(), 2);
    let pick_proxy_specs = box_specs
        .iter()
        .filter(|spec| spec.material_style == MaterialStyle::InvisiblePickProxy)
        .collect::<Vec<_>>();
    assert_eq!(pick_proxy_specs.len(), 2);
    assert!(pick_proxy_specs
        .iter()
        .all(|spec| spec.pick_binding.is_some()));
    assert!(pick_proxy_specs.iter().all(|spec| {
        spec.pick_binding
            .as_ref()
            .and_then(|binding| binding.interaction.as_ref())
            == Some(&InteractionTargetId::MapObject("edge_trigger".into()))
    }));
}

#[test]
fn static_world_specs_do_not_emit_fallback_building_roofs() {
    let palette = ViewerPalette::default();
    let specs_with_roof = collect_static_world_box_specs(
        &snapshot_with_occluders(),
        0,
        false,
        ViewerRenderConfig::default(),
        &palette,
        GridBounds {
            min_x: 0,
            max_x: 1,
            min_z: 0,
            max_z: 1,
        },
        world_from_grid,
    );
    let specs_without_roof = collect_static_world_box_specs(
        &snapshot_with_occluders(),
        0,
        true,
        ViewerRenderConfig::default(),
        &palette,
        GridBounds {
            min_x: 0,
            max_x: 1,
            min_z: 0,
            max_z: 1,
        },
        world_from_grid,
    );

    let roof_with = specs_with_roof
        .iter()
        .filter(|spec| spec.color.to_srgba() == palette.building_top.to_srgba())
        .count();
    let roof_without = specs_without_roof
        .iter()
        .filter(|spec| spec.color.to_srgba() == palette.building_top.to_srgba())
        .count();

    assert_eq!(roof_with, 0);
    assert_eq!(roof_without, 0);
}

#[test]
fn generated_building_tiles_do_not_require_visible_fallback_boxes() {
    let tile_specs = collect_static_world_building_wall_tile_specs(
        &snapshot_with_generated_building(),
        0,
        ViewerRenderConfig::default(),
        GridBounds {
            min_x: 0,
            max_x: 2,
            min_z: 0,
            max_z: 2,
        },
    );
    let box_specs = collect_static_world_box_specs(
        &snapshot_with_generated_building(),
        0,
        false,
        ViewerRenderConfig::default(),
        &ViewerPalette::default(),
        GridBounds {
            min_x: 0,
            max_x: 2,
            min_z: 0,
            max_z: 2,
        },
        world_from_grid,
    );

    assert_eq!(tile_specs.len(), 4);
    assert!(tile_specs.iter().all(|spec| spec.occluder_cells.len() == 1));
    assert!(box_specs
        .iter()
        .all(|spec| spec.material_style != MaterialStyle::StructureAccent));
    assert!(box_specs
        .iter()
        .all(|spec| spec.material_style == MaterialStyle::InvisiblePickProxy));
}

#[test]
fn snapshot_visual_props_do_not_emit_fallback_object_boxes() {
    let box_specs = collect_static_world_box_specs(
        &snapshot_with_visual_interactive_prop(),
        0,
        false,
        ViewerRenderConfig::default(),
        &ViewerPalette::default(),
        GridBounds {
            min_x: 0,
            max_x: 2,
            min_z: 0,
            max_z: 2,
        },
        world_from_grid,
    );

    assert!(box_specs.is_empty());
}

#[test]
fn snapshot_visual_pickups_do_not_emit_fallback_object_boxes() {
    let box_specs = collect_static_world_box_specs(
        &snapshot_with_visual_pickup_prop(),
        0,
        false,
        ViewerRenderConfig::default(),
        &ViewerPalette::default(),
        GridBounds {
            min_x: 0,
            max_x: 2,
            min_z: 0,
            max_z: 2,
        },
        world_from_grid,
    );

    assert!(box_specs.is_empty());
}

#[test]
fn snapshot_ai_spawn_objects_do_not_emit_static_world_boxes() {
    let box_specs = collect_static_world_box_specs(
        &snapshot_with_ai_spawn_object(),
        0,
        false,
        ViewerRenderConfig::default(),
        &ViewerPalette::default(),
        GridBounds {
            min_x: 0,
            max_x: 2,
            min_z: 0,
            max_z: 2,
        },
        world_from_grid,
    );

    assert!(box_specs.is_empty());
}

#[test]
fn building_roofs_hide_for_controlled_or_observed_actor_on_level() {
    let snapshot = snapshot_with_focus_actor();
    let viewer_state = ViewerState {
        controlled_player_actor: Some(ActorId(1)),
        selected_actor: Some(ActorId(1)),
        current_level: 0,
        ..ViewerState::default()
    };

    assert!(should_hide_building_roofs(&snapshot, &viewer_state, 0));

    let free_observe_state = ViewerState {
        selected_actor: Some(ActorId(2)),
        control_mode: ViewerControlMode::FreeObserve,
        current_level: 1,
        ..ViewerState::default()
    };

    assert!(should_hide_building_roofs(
        &snapshot,
        &free_observe_state,
        1
    ));
    assert!(!should_hide_building_roofs(
        &snapshot,
        &free_observe_state,
        0
    ));
}

#[test]
fn occluder_fades_when_any_focus_point_is_blocked() {
    let should_fade = occluder_should_fade(
        Vec3::new(0.0, 2.0, -10.0),
        &[Vec3::new(0.0, 0.2, 0.0), Vec3::new(20.0, 0.2, 0.0)],
        Vec3::new(0.0, 1.0, -5.0),
        Vec3::new(1.0, 2.0, 1.0),
    );

    assert!(should_fade);
}

#[test]
fn occluder_does_not_fade_without_focus_points() {
    let should_fade = occluder_should_fade(
        Vec3::new(0.0, 2.0, -10.0),
        &[],
        Vec3::new(0.0, 1.0, -5.0),
        Vec3::new(1.0, 2.0, 1.0),
    );

    assert!(!should_fade);
}

#[test]
fn projected_shadow_cells_extend_forward_for_tall_occluder() {
    let cells = project_shadowed_visible_cells(
        &[GridCoord::new(0, 0, 0)],
        0.0,
        1.2,
        1.0,
        ViewerRenderConfig::default(),
    );

    assert!(cells.contains(&GridCoord::new(0, 0, 1)));
    assert!(cells.contains(&GridCoord::new(0, 0, 2)));
    assert!(!cells.contains(&GridCoord::new(0, 0, 0)));
}

#[test]
fn projected_shadow_cells_for_short_occluder_do_not_skip_extra_row() {
    let cells = project_shadowed_visible_cells(
        &[GridCoord::new(0, 0, 0)],
        0.0,
        0.2,
        1.0,
        ViewerRenderConfig::default(),
    );

    assert!(cells.contains(&GridCoord::new(0, 0, 1)));
    assert!(!cells.contains(&GridCoord::new(0, 0, 2)));
}

#[test]
fn projected_shadow_cells_preserve_multi_cell_footprint() {
    let cells = project_shadowed_visible_cells(
        &[GridCoord::new(0, 0, 0), GridCoord::new(1, 0, 0)],
        0.0,
        0.4,
        1.0,
        ViewerRenderConfig::default(),
    );

    assert!(cells.contains(&GridCoord::new(0, 0, 1)));
    assert!(cells.contains(&GridCoord::new(1, 0, 1)));
}

#[test]
fn occluder_detects_visible_cells_only_from_projected_shadow() {
    let occluder = sample_occluder(
        vec![GridCoord::new(0, 0, 1), GridCoord::new(0, 0, 2)],
        Vec3::new(2.0, 0.5, 2.0),
    );
    let visible = HashSet::from([GridCoord::new(0, 0, 2)]);

    assert!(occluder_blocks_visible_cells(&occluder, &visible));
}

#[test]
fn occluder_does_not_treat_base_cells_as_projected_shadow() {
    let shadowed_visible_cells = project_shadowed_visible_cells(
        &[GridCoord::new(0, 0, 0)],
        0.0,
        0.35,
        1.0,
        ViewerRenderConfig::default(),
    );
    let occluder = sample_occluder(shadowed_visible_cells, Vec3::new(4.0, 0.5, 4.0));
    let visible = HashSet::from([GridCoord::new(0, 0, 0)]);

    assert!(!occluder_blocks_visible_cells(&occluder, &visible));
}

#[test]
fn occluder_can_fade_from_ray_or_projected_visible_cells() {
    let ray_only = sample_occluder(Vec::new(), Vec3::new(0.0, 1.0, -5.0));
    let vision_only = sample_occluder(vec![GridCoord::new(5, 0, 5)], Vec3::new(20.0, 1.0, -5.0));

    assert!(should_fade_occluder(
        Vec3::new(0.0, 2.0, -10.0),
        &[Vec3::new(0.0, 0.2, 0.0)],
        &ray_only,
        &HashSet::new(),
    ));
    assert!(should_fade_occluder(
        Vec3::new(0.0, 2.0, -10.0),
        &[],
        &vision_only,
        &HashSet::from([GridCoord::new(5, 0, 5)]),
    ));
}

#[test]
fn closed_doors_only_contribute_occluders() {
    let closed_shadow = vec![GridCoord::new(2, 0, 3)];
    let mut door_visual_state = GeneratedDoorVisualState::default();
    door_visual_state.by_door.insert(
        "closed".into(),
        sample_door_visual(false, closed_shadow.clone()),
    );
    door_visual_state.by_door.insert(
        "open".into(),
        sample_door_visual(true, vec![GridCoord::new(9, 0, 9)]),
    );

    let occluders = collect_closed_door_occluders(&door_visual_state);

    assert_eq!(occluders.len(), 1);
    assert_eq!(occluders[0].shadowed_visible_cells, closed_shadow);
    assert_eq!(
        occluders[0].hover_map_object_id.as_deref(),
        Some("door_object")
    );
}

#[test]
fn generated_door_render_polygon_clamps_horizontal_thickness_to_thirty_centimeters() {
    let door = sample_generated_door_debug_state(game_core::GeometryAxis::Horizontal);

    let polygon = generated_door_render_polygon(&door, 1.0);
    let z_values = polygon
        .outer
        .iter()
        .map(|point| point.z)
        .collect::<Vec<_>>();
    let min_z = z_values.iter().copied().fold(f64::INFINITY, f64::min);
    let max_z = z_values.iter().copied().fold(f64::NEG_INFINITY, f64::max);

    assert!((max_z - min_z - 0.3).abs() < 1e-6);
}

#[test]
fn generated_door_render_polygon_clamps_vertical_thickness_to_thirty_centimeters() {
    let door = sample_generated_door_debug_state(game_core::GeometryAxis::Vertical);

    let polygon = generated_door_render_polygon(&door, 1.0);
    let x_values = polygon
        .outer
        .iter()
        .map(|point| point.x)
        .collect::<Vec<_>>();
    let min_x = x_values.iter().copied().fold(f64::INFINITY, f64::min);
    let max_x = x_values.iter().copied().fold(f64::NEG_INFINITY, f64::max);

    assert!((max_x - min_x - 0.3).abs() < 1e-6);
}

#[test]
fn occluder_keys_change_when_camera_projection_changes() {
    let base_world_key = StaticWorldVisualKey {
        map_id: None,
        current_level: 0,
        topology_version: 7,
        hide_building_roofs: false,
        camera_yaw_degrees: 0,
        camera_pitch_degrees: 36,
    };
    let changed_world_key = StaticWorldVisualKey {
        camera_yaw_degrees: 15,
        ..base_world_key.clone()
    };
    let base_door_key = GeneratedDoorVisualKey {
        map_id: None,
        current_level: 0,
        camera_yaw_degrees: 0,
        camera_pitch_degrees: 36,
    };
    let changed_door_key = GeneratedDoorVisualKey {
        camera_pitch_degrees: 45,
        ..base_door_key.clone()
    };

    assert_ne!(base_world_key, changed_world_key);
    assert_ne!(base_door_key, changed_door_key);
}

#[test]
fn hovered_scene_trigger_resolves_pick_outline_proxy_box() {
    let snapshot = snapshot_with_trigger_strip();
    let picking_state = crate::picking::ViewerPickingState {
        hovered: Some(crate::picking::ViewerResolvedPick {
            entity: Entity::from_bits(1),
            semantic: ViewerPickTarget::BuildingPart(crate::picking::BuildingPartPickTarget {
                building_object_id: "edge_trigger".into(),
                story_level: 0,
                kind: BuildingPartKind::TriggerCell,
                anchor_cell: GridCoord::new(1, 0, 0),
            }),
            interaction: Some(InteractionTargetId::MapObject("edge_trigger".into())),
            priority: crate::picking::ViewerPickPriority::Trigger,
            depth: 0.0,
            position: None,
        }),
        ..Default::default()
    };

    let (center, size) =
        hovered_pick_outline_box(&snapshot, &picking_state, 0, ViewerRenderConfig::default())
            .expect("trigger hover should resolve outline box");

    assert_eq!(center, Vec3::new(1.5, 0.17, 0.5));
    assert_eq!(size, Vec3::new(0.92, 0.12, 0.92));
}

#[test]
fn hovered_wall_tile_resolves_per_cell_outline_box() {
    let snapshot = snapshot_with_generated_building();
    let picking_state = crate::picking::ViewerPickingState {
        hovered: Some(crate::picking::ViewerResolvedPick {
            entity: Entity::from_bits(2),
            semantic: ViewerPickTarget::BuildingPart(crate::picking::BuildingPartPickTarget {
                building_object_id: "generated_house".into(),
                story_level: 0,
                kind: BuildingPartKind::WallCell,
                anchor_cell: GridCoord::new(1, 0, 0),
            }),
            interaction: Some(InteractionTargetId::MapObject("generated_house".into())),
            priority: crate::picking::ViewerPickPriority::BuildingPart,
            depth: 0.0,
            position: None,
        }),
        ..Default::default()
    };

    let (center, size) =
        hovered_pick_outline_box(&snapshot, &picking_state, 0, ViewerRenderConfig::default())
            .expect("wall hover should resolve outline box");

    assert_eq!(center, Vec3::new(1.5, 1.285, 0.5));
    assert_eq!(size, Vec3::new(0.92, 2.35, 0.92));
}

#[test]
fn hovered_hostile_actor_uses_hostile_outline_color() {
    let snapshot = SimulationSnapshot {
        actors: vec![game_core::ActorDebugState {
            actor_id: ActorId(9),
            definition_id: None,
            display_name: "hostile".into(),
            kind: game_data::ActorKind::Npc,
            side: ActorSide::Hostile,
            group_id: "enemy".into(),
            ap: 6.0,
            available_steps: 3,
            turn_open: false,
            in_combat: false,
            grid_position: GridCoord::new(0, 0, 0),
            level: 1,
            current_xp: 0,
            available_stat_points: 0,
            available_skill_points: 0,
            hp: 10.0,
            max_hp: 10.0,
        }],
        ..snapshot_with_occluders()
    };
    let hovered = crate::picking::ViewerResolvedPick {
        entity: Entity::from_bits(3),
        semantic: ViewerPickTarget::Actor(ActorId(9)),
        interaction: Some(InteractionTargetId::Actor(ActorId(9))),
        priority: crate::picking::ViewerPickPriority::Actor,
        depth: 0.0,
        position: None,
    };

    assert_eq!(
        hovered_pick_outline_color(&snapshot, &hovered, &ViewerPalette::default()).to_srgba(),
        with_alpha(ViewerPalette::default().hover_hostile, 0.98).to_srgba()
    );
}

#[test]
fn hovered_pickup_uses_neutral_outline_color() {
    let snapshot = snapshot_with_occluders();
    let hovered = crate::picking::ViewerResolvedPick {
        entity: Entity::from_bits(4),
        semantic: ViewerPickTarget::MapObject("terminal".into()),
        interaction: Some(InteractionTargetId::MapObject("terminal".into())),
        priority: crate::picking::ViewerPickPriority::MapObject,
        depth: 0.0,
        position: None,
    };

    assert_eq!(
        hovered_pick_outline_color(&snapshot, &hovered, &ViewerPalette::default()).to_srgba(),
        with_alpha(ViewerPalette::default().hover_walkable, 0.98).to_srgba()
    );
}

#[test]
fn hover_outline_system_marks_all_actor_mesh_members_and_skips_shadow() {
    let (runtime, handles) = create_demo_runtime();
    let mut app = App::new();
    app.insert_resource(ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    });
    app.insert_resource(ViewerPalette::default());
    app.insert_resource(ViewerState {
        controlled_player_actor: Some(handles.player),
        ..ViewerState::default()
    });
    app.insert_resource(crate::picking::ViewerPickingState {
        hovered: Some(crate::picking::ViewerResolvedPick {
            entity: Entity::from_bits(10),
            semantic: ViewerPickTarget::Actor(handles.player),
            interaction: Some(InteractionTargetId::Actor(handles.player)),
            priority: crate::picking::ViewerPickPriority::Actor,
            depth: 0.0,
            position: None,
        }),
        ..default()
    });
    seed_stable_hover(&mut app);
    app.add_systems(Update, sync_hover_mesh_outlines);

    let body = app
        .world_mut()
        .spawn(HoverOutlineMember::new(ViewerPickTarget::Actor(
            handles.player,
        )))
        .id();
    let head = app
        .world_mut()
        .spawn(HoverOutlineMember::new(ViewerPickTarget::Actor(
            handles.player,
        )))
        .id();
    let shadow = app.world_mut().spawn_empty().id();

    app.update();

    let world = app.world();
    assert_eq!(
        world
            .get::<MeshOutline>(body)
            .expect("body should get outline")
            .width,
        HOVER_MESH_OUTLINE_WIDTH_PX
    );
    assert!(world.get::<MeshOutline>(head).is_some());
    assert!(world.get::<MeshOutline>(shadow).is_none());
}

#[test]
fn hover_outline_system_marks_all_visible_mesh_members_for_same_map_object() {
    let (runtime, handles) = create_demo_runtime();
    let mut app = App::new();
    app.insert_resource(ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    });
    app.insert_resource(ViewerPalette::default());
    app.insert_resource(ViewerState {
        controlled_player_actor: Some(handles.player),
        ..ViewerState::default()
    });
    app.insert_resource(crate::picking::ViewerPickingState {
        hovered: Some(crate::picking::ViewerResolvedPick {
            entity: Entity::from_bits(20),
            semantic: ViewerPickTarget::MapObject("terminal".into()),
            interaction: Some(InteractionTargetId::MapObject("terminal".into())),
            priority: crate::picking::ViewerPickPriority::MapObject,
            depth: 0.0,
            position: None,
        }),
        ..default()
    });
    seed_stable_hover(&mut app);
    app.add_systems(Update, sync_hover_mesh_outlines);

    let base = app
        .world_mut()
        .spawn(HoverOutlineMember::new(ViewerPickTarget::MapObject(
            "terminal".into(),
        )))
        .id();
    let top = app
        .world_mut()
        .spawn(HoverOutlineMember::new(ViewerPickTarget::MapObject(
            "terminal".into(),
        )))
        .id();
    let other = app
        .world_mut()
        .spawn(HoverOutlineMember::new(ViewerPickTarget::MapObject(
            "other".into(),
        )))
        .id();

    app.update();

    let world = app.world();
    assert!(world.get::<MeshOutline>(base).is_none());
    assert!(world.get::<MeshOutline>(top).is_none());
    assert!(world.get::<MeshOutline>(other).is_none());
}

#[test]
fn hover_outline_system_keeps_building_part_outline_scoped_to_single_cell() {
    let (runtime, handles) = create_demo_runtime();
    let target = ViewerPickTarget::BuildingPart(crate::picking::BuildingPartPickTarget {
        building_object_id: "house_01".into(),
        story_level: 0,
        kind: BuildingPartKind::WallCell,
        anchor_cell: GridCoord::new(4, 0, 9),
    });
    let other = ViewerPickTarget::BuildingPart(crate::picking::BuildingPartPickTarget {
        building_object_id: "house_01".into(),
        story_level: 0,
        kind: BuildingPartKind::WallCell,
        anchor_cell: GridCoord::new(5, 0, 9),
    });
    let mut app = App::new();
    app.insert_resource(ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    });
    app.insert_resource(ViewerPalette::default());
    app.insert_resource(ViewerState {
        controlled_player_actor: Some(handles.player),
        ..ViewerState::default()
    });
    app.insert_resource(crate::picking::ViewerPickingState {
        hovered: Some(crate::picking::ViewerResolvedPick {
            entity: Entity::from_bits(30),
            semantic: target.clone(),
            interaction: Some(InteractionTargetId::MapObject("house_01".into())),
            priority: crate::picking::ViewerPickPriority::BuildingPart,
            depth: 0.0,
            position: None,
        }),
        ..default()
    });
    seed_stable_hover(&mut app);
    app.add_systems(Update, sync_hover_mesh_outlines);

    let highlighted = app.world_mut().spawn(HoverOutlineMember::new(target)).id();
    let untouched = app.world_mut().spawn(HoverOutlineMember::new(other)).id();

    app.update();

    let world = app.world();
    assert!(world.get::<MeshOutline>(highlighted).is_none());
    assert!(world.get::<MeshOutline>(untouched).is_none());
}

#[test]
fn hover_outline_system_skips_targets_without_real_interaction_prompt() {
    let (runtime, handles) = create_demo_runtime();
    let mut app = App::new();
    app.insert_resource(ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    });
    app.insert_resource(ViewerPalette::default());
    app.insert_resource(ViewerState {
        controlled_player_actor: Some(handles.player),
        ..ViewerState::default()
    });
    app.insert_resource(crate::picking::ViewerPickingState {
        hovered: Some(crate::picking::ViewerResolvedPick {
            entity: Entity::from_bits(40),
            semantic: ViewerPickTarget::MapObject("non_interactive_wall_proxy".into()),
            interaction: Some(InteractionTargetId::MapObject(
                "non_interactive_wall_proxy".into(),
            )),
            priority: crate::picking::ViewerPickPriority::BuildingPart,
            depth: 0.0,
            position: None,
        }),
        ..default()
    });
    seed_stable_hover(&mut app);
    app.add_systems(Update, sync_hover_mesh_outlines);

    let member = app
        .world_mut()
        .spawn(HoverOutlineMember::new(ViewerPickTarget::MapObject(
            "non_interactive_wall_proxy".into(),
        )))
        .id();

    app.update();

    assert!(app.world().get::<MeshOutline>(member).is_none());
}

#[test]
fn active_interaction_hover_uses_target_grid_instead_of_ground_pick_grid() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let viewer_state = ViewerState {
        controlled_player_actor: Some(handles.player),
        hovered_grid: Some(GridCoord::new(4, 0, 1)),
        current_level: 0,
        ..ViewerState::default()
    };
    let picking_state = crate::picking::ViewerPickingState {
        hovered: Some(crate::picking::ViewerResolvedPick {
            entity: Entity::from_bits(41),
            semantic: ViewerPickTarget::Actor(handles.hostile),
            interaction: Some(InteractionTargetId::Actor(handles.hostile)),
            priority: crate::picking::ViewerPickPriority::Actor,
            depth: 0.0,
            position: None,
        }),
        cursor_position: Some(Vec2::new(100.0, 100.0)),
        ..default()
    };

    let active =
        resolve_active_interaction_hover(&runtime_state, &snapshot, &viewer_state, &picking_state)
            .expect("hovered hostile actor should resolve to active interaction hover");

    assert_eq!(active.semantic, ViewerPickTarget::Actor(handles.hostile));
    assert_eq!(active.display_grid, GridCoord::new(4, 0, 0));
    assert_eq!(active.outline_kind, HoveredGridOutlineKind::Hostile);
}

#[test]
fn hover_outline_system_falls_back_to_interactable_target_in_hovered_grid() {
    let (runtime, handles) = create_demo_runtime();
    let mut app = App::new();
    app.insert_resource(ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    });
    app.insert_resource(ViewerPalette::default());
    app.insert_resource(ViewerState {
        controlled_player_actor: Some(handles.player),
        hovered_grid: Some(GridCoord::new(4, 0, 0)),
        current_level: 0,
        ..ViewerState::default()
    });
    app.insert_resource(crate::picking::ViewerPickingState {
        hovered: Some(crate::picking::ViewerResolvedPick {
            entity: Entity::from_bits(42),
            semantic: ViewerPickTarget::MapObject("non_interactive_wall_proxy".into()),
            interaction: Some(InteractionTargetId::MapObject(
                "non_interactive_wall_proxy".into(),
            )),
            priority: crate::picking::ViewerPickPriority::BuildingPart,
            depth: 0.0,
            position: None,
        }),
        cursor_position: Some(Vec2::new(120.0, 100.0)),
        ..default()
    });
    seed_stable_hover(&mut app);
    app.add_systems(Update, sync_hover_mesh_outlines);

    let hostile = app
        .world_mut()
        .spawn(HoverOutlineMember::new(ViewerPickTarget::Actor(
            handles.hostile,
        )))
        .id();
    let wall = app
        .world_mut()
        .spawn(HoverOutlineMember::new(ViewerPickTarget::MapObject(
            "non_interactive_wall_proxy".into(),
        )))
        .id();

    app.update();

    let world = app.world();
    assert!(world.get::<MeshOutline>(hostile).is_some());
    assert!(world.get::<MeshOutline>(wall).is_none());
}

#[test]
fn scene_transition_trigger_outline_targets_visible_decal_not_pick_proxy() {
    let snapshot = snapshot_with_trigger_strip();
    let box_specs = collect_static_world_box_specs(
        &snapshot,
        0,
        false,
        ViewerRenderConfig::default(),
        &ViewerPalette::default(),
        GridBounds {
            min_x: 0,
            max_x: 3,
            min_z: 0,
            max_z: 1,
        },
        world_from_grid,
    );
    let decal_specs = collect_static_world_decal_specs(
        &snapshot,
        0,
        ViewerRenderConfig::default(),
        &ViewerPalette::default(),
    );

    let proxy_specs = box_specs
        .iter()
        .filter(|spec| spec.material_style == MaterialStyle::InvisiblePickProxy)
        .collect::<Vec<_>>();
    assert!(!proxy_specs.is_empty());
    assert!(proxy_specs.iter().all(|spec| spec.outline_target.is_none()));
    assert!(!decal_specs.is_empty());
    assert!(decal_specs.iter().all(|spec| matches!(
        spec.outline_target.as_ref(),
        Some(ViewerPickTarget::BuildingPart(part))
            if part.kind == BuildingPartKind::TriggerCell
    )));
}

#[test]
fn walkable_tile_overlay_marks_selected_actor_cell_walkable() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let player_grid = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == handles.player)
        .expect("player actor should exist")
        .grid_position;
    let viewer_state = ViewerState {
        selected_actor: Some(handles.player),
        current_level: player_grid.y,
        show_walkable_tiles_overlay: true,
        ..ViewerState::default()
    };

    let cells = collect_walkable_tile_overlay_cells(
        &runtime,
        &snapshot,
        &viewer_state,
        grid_bounds(&snapshot, player_grid.y),
    );

    assert!(cells
        .iter()
        .any(|(grid, kind)| *grid == player_grid && *kind == WalkableTileOverlayKind::Walkable));
}

#[test]
fn walkable_tile_overlay_falls_back_to_runtime_blocking_without_command_actor() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let player_grid = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == handles.player)
        .expect("player actor should exist")
        .grid_position;
    let viewer_state = ViewerState {
        control_mode: ViewerControlMode::FreeObserve,
        current_level: player_grid.y,
        show_walkable_tiles_overlay: true,
        ..ViewerState::default()
    };

    let cells = collect_walkable_tile_overlay_cells(
        &runtime,
        &snapshot,
        &viewer_state,
        grid_bounds(&snapshot, player_grid.y),
    );

    assert!(cells
        .iter()
        .any(|(grid, kind)| *grid == player_grid && *kind == WalkableTileOverlayKind::Blocked));
}

#[test]
fn walkable_tile_overlay_only_collects_cells_on_current_level() {
    let (runtime, _) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let viewer_state = ViewerState {
        current_level: 0,
        show_walkable_tiles_overlay: true,
        ..ViewerState::default()
    };

    let cells = collect_walkable_tile_overlay_cells(
        &runtime,
        &snapshot,
        &viewer_state,
        grid_bounds(&snapshot, 0),
    );

    assert!(!cells.is_empty());
    assert!(cells.iter().all(|(grid, _)| grid.y == 0));
}

fn sample_prompt(option_count: usize) -> InteractionPrompt {
    InteractionPrompt {
        actor_id: ActorId(1),
        target_id: InteractionTargetId::MapObject("crate".into()),
        target_name: "Crate".into(),
        anchor_grid: GridCoord::new(1, 0, 1),
        primary_option_id: Some(InteractionOptionId("option_0".into())),
        options: (0..option_count)
            .map(|index| ResolvedInteractionOption {
                id: InteractionOptionId(format!("option_{index}")),
                display_name: format!("Option {index}"),
                ..ResolvedInteractionOption::default()
            })
            .collect(),
    }
}

fn snapshot_with_occluders() -> SimulationSnapshot {
    SimulationSnapshot {
        turn: TurnState::default(),
        actors: Vec::new(),
        grid: GridDebugState {
            grid_size: 1.0,
            map_id: None,
            map_width: Some(2),
            map_height: Some(2),
            default_level: Some(0),
            levels: vec![0],
            static_obstacles: vec![GridCoord::new(1, 0, 0)],
            map_blocked_cells: vec![GridCoord::new(0, 0, 0)],
            map_cells: vec![
                MapCellDebugState {
                    grid: GridCoord::new(0, 0, 0),
                    blocks_movement: true,
                    blocks_sight: true,
                    terrain: "wall".into(),
                    visual: None,
                },
                MapCellDebugState {
                    grid: GridCoord::new(1, 0, 1),
                    blocks_movement: false,
                    blocks_sight: true,
                    terrain: "curtain".into(),
                    visual: None,
                },
            ],
            map_objects: vec![
                MapObjectDebugState {
                    object_id: "house".into(),
                    kind: MapObjectKind::Building,
                    anchor: GridCoord::new(0, 0, 1),
                    footprint: MapObjectFootprint {
                        width: 1,
                        height: 1,
                    },
                    rotation: MapRotation::North,
                    blocks_movement: true,
                    blocks_sight: true,
                    occupied_cells: vec![GridCoord::new(0, 0, 1)],
                    payload_summary: Default::default(),
                },
                MapObjectDebugState {
                    object_id: "terminal".into(),
                    kind: MapObjectKind::Interactive,
                    anchor: GridCoord::new(1, 0, 1),
                    footprint: MapObjectFootprint {
                        width: 1,
                        height: 1,
                    },
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    occupied_cells: vec![GridCoord::new(1, 0, 1)],
                    payload_summary: [("interaction_kind".to_string(), "terminal".to_string())]
                        .into_iter()
                        .collect(),
                },
            ],
            runtime_blocked_cells: Vec::new(),
            topology_version: 0,
            runtime_obstacle_version: 0,
        },
        vision: Default::default(),
        generated_buildings: Vec::new(),
        generated_doors: Vec::new(),
        combat: CombatDebugState {
            in_combat: false,
            current_actor_id: None,
            current_group_id: None,
            current_turn_index: 0,
        },
        interaction_context: InteractionContextSnapshot::default(),
        overworld: OverworldStateSnapshot::default(),
        path_preview: Vec::new(),
    }
}

fn snapshot_with_trigger_strip() -> SimulationSnapshot {
    SimulationSnapshot {
        turn: TurnState::default(),
        actors: Vec::new(),
        grid: GridDebugState {
            grid_size: 1.0,
            map_id: None,
            map_width: Some(4),
            map_height: Some(2),
            default_level: Some(0),
            levels: vec![0],
            static_obstacles: Vec::new(),
            map_blocked_cells: Vec::new(),
            map_cells: Vec::new(),
            map_objects: vec![MapObjectDebugState {
                object_id: "edge_trigger".into(),
                kind: MapObjectKind::Trigger,
                anchor: GridCoord::new(1, 0, 0),
                footprint: MapObjectFootprint {
                    width: 2,
                    height: 1,
                },
                rotation: MapRotation::East,
                blocks_movement: false,
                blocks_sight: false,
                occupied_cells: vec![GridCoord::new(1, 0, 0), GridCoord::new(2, 0, 0)],
                payload_summary: [
                    (
                        "trigger_kind".to_string(),
                        "enter_outdoor_location".to_string(),
                    ),
                    ("target_id".to_string(), "street_b".to_string()),
                ]
                .into_iter()
                .collect(),
            }],
            runtime_blocked_cells: Vec::new(),
            topology_version: 0,
            runtime_obstacle_version: 0,
        },
        vision: Default::default(),
        generated_buildings: Vec::new(),
        generated_doors: Vec::new(),
        combat: CombatDebugState {
            in_combat: false,
            current_actor_id: None,
            current_group_id: None,
            current_turn_index: 0,
        },
        interaction_context: InteractionContextSnapshot::default(),
        overworld: OverworldStateSnapshot::default(),
        path_preview: Vec::new(),
    }
}

fn world_from_grid(grid: GridCoord) -> WorldCoord {
    WorldCoord::new(
        grid.x as f32 + 0.5,
        grid.y as f32 + 0.5,
        grid.z as f32 + 0.5,
    )
}

fn sample_occluder(
    shadowed_visible_cells: Vec<GridCoord>,
    aabb_center: Vec3,
) -> StaticWorldOccluderVisual {
    StaticWorldOccluderVisual {
        material: StaticWorldMaterialHandle::Standard(Handle::default()),
        tile_instance_handle: None,
        base_color: Color::WHITE,
        base_alpha: 1.0,
        base_alpha_mode: AlphaMode::Opaque,
        aabb_center,
        aabb_half_extents: Vec3::splat(0.5),
        shadowed_visible_cells,
        hover_map_object_id: None,
        currently_faded: false,
    }
}

#[test]
fn building_wall_grid_material_defaults_to_visible_grid_lines() {
    let mut building_wall_materials = Assets::<BuildingWallGridMaterial>::default();
    let wall_profile = building_wall_visual_profile(MapBuildingWallVisualKind::LegacyGrid);
    let material = make_building_wall_material(&mut building_wall_materials, wall_profile);
    let StaticWorldMaterialHandle::BuildingWallGrid(handle) = material else {
        panic!("building wall tile path should create wall grid material");
    };
    let material = building_wall_materials
        .get(&handle)
        .expect("wall grid material should exist");

    assert_eq!(material.extension.grid_line_visibility, 1.0);
    assert_eq!(material.extension.top_face_grid_visibility, 1.0);
    assert_ne!(
        material.extension.cap_color.to_srgba(),
        material.extension.base_color.to_srgba()
    );
}

#[test]
fn building_door_material_uses_standard_path_with_door_color() {
    let mut materials = Assets::<StandardMaterial>::default();
    let mut building_wall_materials = Assets::<BuildingWallGridMaterial>::default();
    let material = make_static_world_material(
        &mut materials,
        &mut building_wall_materials,
        building_door_color(),
        MaterialStyle::BuildingDoor,
    );

    let StaticWorldMaterialHandle::Standard(handle) = material else {
        panic!("building door style should create standard material");
    };
    let material = materials
        .get(&handle)
        .expect("building door material should exist");

    assert_eq!(
        material.base_color.to_srgba(),
        building_door_color().to_srgba()
    );
}

#[test]
fn building_wall_grid_occluder_hides_grid_lines_when_faded_and_restores_them() {
    let mut materials = Assets::<StandardMaterial>::default();
    let mut building_wall_materials = Assets::<BuildingWallGridMaterial>::default();
    let wall_profile = building_wall_visual_profile(MapBuildingWallVisualKind::LegacyGrid);
    let material = make_building_wall_material(&mut building_wall_materials, wall_profile.clone());
    let StaticWorldMaterialHandle::BuildingWallGrid(handle) = material.clone() else {
        panic!("building wall tile path should create wall grid material");
    };
    let mut occluder = StaticWorldOccluderVisual {
        material,
        tile_instance_handle: None,
        base_color: wall_profile.face_color,
        base_alpha: 1.0,
        base_alpha_mode: AlphaMode::Opaque,
        aabb_center: Vec3::ZERO,
        aabb_half_extents: Vec3::splat(0.5),
        shadowed_visible_cells: Vec::new(),
        hover_map_object_id: None,
        currently_faded: false,
    };

    set_occluder_faded(
        &mut occluder,
        true,
        None,
        &mut materials,
        &mut building_wall_materials,
    );
    let faded = building_wall_materials
        .get(&handle)
        .expect("wall grid material should exist after fade");
    assert_eq!(faded.extension.grid_line_visibility, 0.0);
    assert_eq!(faded.base.base_color.to_srgba().alpha, 0.28);

    set_occluder_faded(
        &mut occluder,
        false,
        None,
        &mut materials,
        &mut building_wall_materials,
    );
    let restored = building_wall_materials
        .get(&handle)
        .expect("wall grid material should exist after restore");
    assert_eq!(restored.extension.grid_line_visibility, 1.0);
    assert_eq!(restored.base.base_color.to_srgba().alpha, 1.0);
}

#[test]
fn tile_instance_occluder_records_desired_fade_before_material_apply() {
    let mut materials = Assets::<StandardMaterial>::default();
    let mut building_wall_materials = Assets::<BuildingWallGridMaterial>::default();
    let wall_profile = building_wall_visual_profile(MapBuildingWallVisualKind::LegacyGrid);
    let material = make_building_wall_material(&mut building_wall_materials, wall_profile.clone());
    let handle = WorldRenderTileInstanceHandle {
        batch_id: game_bevy::world_render::WorldRenderTileBatchId(3),
        instance_index: 7,
    };
    let mut tile_instances = HashMap::from([(
        handle,
        StaticWorldTileInstanceVisual {
            entity: Entity::from_bits(77),
            material: material.clone(),
            material_fade_enabled: true,
            base_color: wall_profile.face_color,
            base_alpha: 1.0,
            base_alpha_mode: AlphaMode::Opaque,
            desired_faded: false,
            applied_faded: false,
        },
    )]);
    let StaticWorldMaterialHandle::BuildingWallGrid(material_handle) = material.clone() else {
        panic!("building wall tile path should create wall grid material");
    };
    let mut occluder = StaticWorldOccluderVisual {
        material,
        tile_instance_handle: Some(handle),
        base_color: wall_profile.face_color,
        base_alpha: 1.0,
        base_alpha_mode: AlphaMode::Opaque,
        aabb_center: Vec3::ZERO,
        aabb_half_extents: Vec3::splat(0.5),
        shadowed_visible_cells: Vec::new(),
        hover_map_object_id: None,
        currently_faded: false,
    };

    set_occluder_faded(
        &mut occluder,
        true,
        Some(&mut tile_instances),
        &mut materials,
        &mut building_wall_materials,
    );

    assert!(occluder.currently_faded);
    let tile_visual = tile_instances
        .get(&handle)
        .expect("tile instance visual should still exist");
    assert!(tile_visual.desired_faded);
    assert!(!tile_visual.applied_faded);
    let material = building_wall_materials
        .get(&material_handle)
        .expect("wall grid material should still exist");
    assert_eq!(material.extension.grid_line_visibility, 1.0);
    assert_eq!(material.base.base_color.to_srgba().alpha, 1.0);

    let mut applied_visual_state = None;
    apply_tile_instance_fade_updates(
        &mut tile_instances,
        |entity, visual_state| {
            applied_visual_state = Some((entity, visual_state));
        },
        &mut materials,
        &mut building_wall_materials,
    );

    let tile_visual = tile_instances
        .get(&handle)
        .expect("tile instance visual should still exist");
    assert!(tile_visual.applied_faded);
    let (entity, visual_state) =
        applied_visual_state.expect("tile instance visual state should be written");
    assert_eq!(entity, Entity::from_bits(77));
    assert_eq!(visual_state.fade_alpha, 0.28);
    assert_eq!(
        visual_state.tint.to_srgba(),
        wall_profile.face_color.to_srgba()
    );
    let material = building_wall_materials
        .get(&material_handle)
        .expect("wall grid material should exist after apply");
    assert_eq!(material.extension.grid_line_visibility, 0.0);
    assert_eq!(material.base.base_color.to_srgba().alpha, 0.28);
}

#[test]
fn hovered_closed_door_stays_opaque_even_when_occlusion_would_fade_it() {
    let mut door_occluders = vec![sample_occluder(Vec::new(), Vec3::new(0.0, 1.0, -5.0))];
    door_occluders[0].hover_map_object_id = Some("door_object".into());
    let mut materials = Assets::<StandardMaterial>::default();
    let mut building_wall_materials = Assets::<BuildingWallGridMaterial>::default();

    update_occluder_list_fade(
        &mut door_occluders,
        Vec3::new(0.0, 2.0, -10.0),
        &[Vec3::new(0.0, 0.2, 0.0)],
        &HashSet::new(),
        Some("door_object"),
        None,
        &mut materials,
        &mut building_wall_materials,
    );

    assert!(!door_occluders[0].currently_faded);
}

#[test]
fn door_fade_returns_after_hover_leaves() {
    let mut door_occluders = vec![sample_occluder(Vec::new(), Vec3::new(0.0, 1.0, -5.0))];
    door_occluders[0].hover_map_object_id = Some("door_object".into());
    let mut materials = Assets::<StandardMaterial>::default();
    let mut building_wall_materials = Assets::<BuildingWallGridMaterial>::default();

    update_occluder_list_fade(
        &mut door_occluders,
        Vec3::new(0.0, 2.0, -10.0),
        &[Vec3::new(0.0, 0.2, 0.0)],
        &HashSet::new(),
        Some("door_object"),
        None,
        &mut materials,
        &mut building_wall_materials,
    );
    update_occluder_list_fade(
        &mut door_occluders,
        Vec3::new(0.0, 2.0, -10.0),
        &[Vec3::new(0.0, 0.2, 0.0)],
        &HashSet::new(),
        None,
        None,
        &mut materials,
        &mut building_wall_materials,
    );

    assert!(door_occluders[0].currently_faded);
}

#[test]
fn hovered_door_override_does_not_change_static_world_occluders() {
    let mut static_occluders = vec![sample_occluder(Vec::new(), Vec3::new(0.0, 1.0, -5.0))];
    let mut materials = Assets::<StandardMaterial>::default();
    let mut building_wall_materials = Assets::<BuildingWallGridMaterial>::default();

    update_occluder_list_fade(
        &mut static_occluders,
        Vec3::new(0.0, 2.0, -10.0),
        &[Vec3::new(0.0, 0.2, 0.0)],
        &HashSet::new(),
        Some("door_object"),
        None,
        &mut materials,
        &mut building_wall_materials,
    );

    assert!(static_occluders[0].currently_faded);
}

fn sample_door_visual(
    is_open: bool,
    shadowed_visible_cells: Vec<GridCoord>,
) -> GeneratedDoorVisual {
    GeneratedDoorVisual {
        pivot_entity: Entity::from_bits(1),
        leaf_entity: Entity::from_bits(2),
        map_object_id: "door_object".into(),
        material: StaticWorldMaterialHandle::Standard(Handle::default()),
        base_color: Color::WHITE,
        base_alpha: 1.0,
        base_alpha_mode: AlphaMode::Opaque,
        pivot_translation: Vec3::ZERO,
        current_yaw: 0.0,
        target_yaw: 0.0,
        open_yaw: std::f32::consts::FRAC_PI_2,
        closed_aabb_center: Vec3::ZERO,
        closed_aabb_half_extents: Vec3::splat(0.5),
        shadowed_visible_cells,
        is_open,
    }
}

fn sample_generated_door_debug_state(
    axis: game_core::GeometryAxis,
) -> game_core::GeneratedDoorDebugState {
    let polygon = match axis {
        game_core::GeometryAxis::Horizontal => game_core::GeometryPolygon2 {
            outer: vec![
                game_core::GeometryPoint2::new(0.1, 0.2),
                game_core::GeometryPoint2::new(0.9, 0.2),
                game_core::GeometryPoint2::new(0.9, 0.8),
                game_core::GeometryPoint2::new(0.1, 0.8),
            ],
            holes: Vec::new(),
        },
        game_core::GeometryAxis::Vertical => game_core::GeometryPolygon2 {
            outer: vec![
                game_core::GeometryPoint2::new(0.2, 0.1),
                game_core::GeometryPoint2::new(0.8, 0.1),
                game_core::GeometryPoint2::new(0.8, 0.9),
                game_core::GeometryPoint2::new(0.2, 0.9),
            ],
            holes: Vec::new(),
        },
    };

    game_core::GeneratedDoorDebugState {
        door_id: "door".into(),
        map_object_id: "door_object".into(),
        building_object_id: "building".into(),
        building_anchor: GridCoord::new(0, 0, 0),
        level: 0,
        opening_id: 0,
        anchor_grid: GridCoord::new(0, 0, 0),
        axis,
        kind: game_core::DoorOpeningKind::Exterior,
        polygon,
        wall_height: 2.35,
        is_open: false,
        is_locked: false,
    }
}

fn snapshot_with_focus_actor() -> SimulationSnapshot {
    SimulationSnapshot {
        turn: TurnState::default(),
        actors: vec![
            game_core::ActorDebugState {
                actor_id: ActorId(1),
                definition_id: None,
                display_name: "player".into(),
                kind: game_data::ActorKind::Npc,
                side: game_data::ActorSide::Player,
                group_id: "player".into(),
                ap: 6.0,
                available_steps: 3,
                turn_open: false,
                in_combat: false,
                grid_position: GridCoord::new(0, 0, 0),
                level: 1,
                current_xp: 0,
                available_stat_points: 0,
                available_skill_points: 0,
                hp: 10.0,
                max_hp: 10.0,
            },
            game_core::ActorDebugState {
                actor_id: ActorId(2),
                definition_id: None,
                display_name: "observer".into(),
                kind: game_data::ActorKind::Npc,
                side: game_data::ActorSide::Friendly,
                group_id: "ally".into(),
                ap: 6.0,
                available_steps: 3,
                turn_open: false,
                in_combat: false,
                grid_position: GridCoord::new(0, 1, 0),
                level: 1,
                current_xp: 0,
                available_stat_points: 0,
                available_skill_points: 0,
                hp: 10.0,
                max_hp: 10.0,
            },
        ],
        grid: GridDebugState {
            grid_size: 1.0,
            map_id: None,
            map_width: Some(2),
            map_height: Some(2),
            default_level: Some(0),
            levels: vec![0, 1],
            static_obstacles: Vec::new(),
            map_blocked_cells: Vec::new(),
            map_cells: Vec::new(),
            map_objects: Vec::new(),
            runtime_blocked_cells: Vec::new(),
            topology_version: 0,
            runtime_obstacle_version: 0,
        },
        vision: Default::default(),
        generated_buildings: Vec::new(),
        generated_doors: Vec::new(),
        combat: CombatDebugState {
            in_combat: false,
            current_actor_id: None,
            current_group_id: None,
            current_turn_index: 0,
        },
        interaction_context: InteractionContextSnapshot::default(),
        overworld: OverworldStateSnapshot::default(),
        path_preview: Vec::new(),
    }
}

fn snapshot_with_generated_building() -> SimulationSnapshot {
    SimulationSnapshot {
        turn: TurnState::default(),
        actors: Vec::new(),
        grid: GridDebugState {
            grid_size: 1.0,
            map_id: None,
            map_width: Some(4),
            map_height: Some(4),
            default_level: Some(0),
            levels: vec![0],
            static_obstacles: Vec::new(),
            map_blocked_cells: Vec::new(),
            map_cells: Vec::new(),
            map_objects: vec![MapObjectDebugState {
                object_id: "generated_house".into(),
                kind: MapObjectKind::Building,
                anchor: GridCoord::new(0, 0, 0),
                footprint: MapObjectFootprint {
                    width: 4,
                    height: 4,
                },
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                occupied_cells: vec![
                    GridCoord::new(0, 0, 0),
                    GridCoord::new(1, 0, 0),
                    GridCoord::new(0, 0, 1),
                    GridCoord::new(1, 0, 1),
                ],
                payload_summary: Default::default(),
            }],
            runtime_blocked_cells: Vec::new(),
            topology_version: 0,
            runtime_obstacle_version: 0,
        },
        vision: Default::default(),
        generated_buildings: vec![GeneratedBuildingDebugState {
            object_id: "generated_house".into(),
            prefab_id: "generated_house".into(),
            wall_visual: game_data::MapBuildingWallVisualSpec {
                kind: game_data::MapBuildingWallVisualKind::LegacyGrid,
            },
            tile_set: sample_building_tile_set(),
            anchor: GridCoord::new(0, 0, 0),
            rotation: MapRotation::North,
            stories: vec![GeneratedBuildingStory {
                level: 0,
                wall_height: 2.35,
                wall_thickness: 0.08,
                shape_cells: vec![
                    GridCoord::new(0, 0, 0),
                    GridCoord::new(1, 0, 0),
                    GridCoord::new(0, 0, 1),
                    GridCoord::new(1, 0, 1),
                ],
                footprint_polygon: Some(game_core::BuildingFootprint2d {
                    polygon: game_core::GeometryPolygon2 {
                        outer: vec![
                            game_core::GeometryPoint2::new(0.0, 0.0),
                            game_core::GeometryPoint2::new(2.0, 0.0),
                            game_core::GeometryPoint2::new(2.0, 2.0),
                            game_core::GeometryPoint2::new(0.0, 2.0),
                        ],
                        holes: Vec::new(),
                    },
                }),
                rooms: Vec::new(),
                room_polygons: Vec::new(),
                wall_cells: vec![
                    GridCoord::new(0, 0, 0),
                    GridCoord::new(1, 0, 0),
                    GridCoord::new(0, 0, 1),
                    GridCoord::new(1, 0, 1),
                ],
                interior_door_cells: Vec::new(),
                exterior_door_cells: Vec::new(),
                door_openings: Vec::new(),
                walkable_cells: vec![GridCoord::new(0, 0, 0)],
                walkable_polygons: game_core::GeneratedWalkablePolygons {
                    polygons: game_core::GeometryMultiPolygon2 {
                        polygons: vec![game_core::GeometryPolygon2 {
                            outer: vec![
                                game_core::GeometryPoint2::new(0.0, 0.0),
                                game_core::GeometryPoint2::new(1.0, 0.0),
                                game_core::GeometryPoint2::new(1.0, 1.0),
                                game_core::GeometryPoint2::new(0.0, 1.0),
                            ],
                            holes: Vec::new(),
                        }],
                    },
                },
            }],
            stairs: vec![GeneratedStairConnection {
                from_level: 0,
                to_level: 1,
                from_cells: vec![GridCoord::new(0, 0, 0)],
                to_cells: vec![GridCoord::new(0, 1, 0)],
                width: 1,
                kind: game_data::StairKind::Straight,
            }],
            visual_outline: Vec::new(),
        }],
        generated_doors: Vec::new(),
        combat: CombatDebugState {
            in_combat: false,
            current_actor_id: None,
            current_group_id: None,
            current_turn_index: 0,
        },
        interaction_context: InteractionContextSnapshot::default(),
        overworld: OverworldStateSnapshot::default(),
        path_preview: Vec::new(),
    }
}

fn snapshot_with_visual_interactive_prop() -> SimulationSnapshot {
    SimulationSnapshot {
        turn: TurnState::default(),
        actors: Vec::new(),
        grid: GridDebugState {
            grid_size: 1.0,
            map_id: None,
            map_width: Some(3),
            map_height: Some(3),
            default_level: Some(0),
            levels: vec![0],
            static_obstacles: Vec::new(),
            map_blocked_cells: Vec::new(),
            map_cells: Vec::new(),
            map_objects: vec![MapObjectDebugState {
                object_id: "terminal_visual".into(),
                kind: MapObjectKind::Interactive,
                anchor: GridCoord::new(1, 0, 1),
                footprint: MapObjectFootprint {
                    width: 1,
                    height: 1,
                },
                rotation: MapRotation::South,
                blocks_movement: false,
                blocks_sight: false,
                occupied_cells: vec![GridCoord::new(1, 0, 1)],
                payload_summary: [
                    ("interaction_kind".to_string(), "terminal".to_string()),
                    ("prototype_id".to_string(), "props/locker_metal".to_string()),
                ]
                .into_iter()
                .collect(),
            }],
            runtime_blocked_cells: Vec::new(),
            topology_version: 0,
            runtime_obstacle_version: 0,
        },
        vision: Default::default(),
        generated_buildings: Vec::new(),
        generated_doors: Vec::new(),
        combat: CombatDebugState {
            in_combat: false,
            current_actor_id: None,
            current_group_id: None,
            current_turn_index: 0,
        },
        interaction_context: InteractionContextSnapshot::default(),
        overworld: OverworldStateSnapshot::default(),
        path_preview: Vec::new(),
    }
}

fn snapshot_with_visual_pickup_prop() -> SimulationSnapshot {
    SimulationSnapshot {
        turn: TurnState::default(),
        actors: Vec::new(),
        grid: GridDebugState {
            grid_size: 1.0,
            map_id: None,
            map_width: Some(3),
            map_height: Some(3),
            default_level: Some(0),
            levels: vec![0],
            static_obstacles: Vec::new(),
            map_blocked_cells: Vec::new(),
            map_cells: Vec::new(),
            map_objects: vec![MapObjectDebugState {
                object_id: "pickup_visual".into(),
                kind: MapObjectKind::Pickup,
                anchor: GridCoord::new(1, 0, 1),
                footprint: MapObjectFootprint {
                    width: 1,
                    height: 1,
                },
                rotation: MapRotation::South,
                blocks_movement: false,
                blocks_sight: false,
                occupied_cells: vec![GridCoord::new(1, 0, 1)],
                payload_summary: [
                    ("item_id".to_string(), "1007".to_string()),
                    ("prototype_id".to_string(), "props/crate_wood".to_string()),
                ]
                .into_iter()
                .collect(),
            }],
            runtime_blocked_cells: Vec::new(),
            topology_version: 0,
            runtime_obstacle_version: 0,
        },
        vision: Default::default(),
        generated_buildings: Vec::new(),
        generated_doors: Vec::new(),
        combat: CombatDebugState {
            in_combat: false,
            current_actor_id: None,
            current_group_id: None,
            current_turn_index: 0,
        },
        interaction_context: InteractionContextSnapshot::default(),
        overworld: OverworldStateSnapshot::default(),
        path_preview: Vec::new(),
    }
}

fn snapshot_with_ai_spawn_object() -> SimulationSnapshot {
    SimulationSnapshot {
        turn: TurnState::default(),
        actors: Vec::new(),
        grid: GridDebugState {
            grid_size: 1.0,
            map_id: None,
            map_width: Some(3),
            map_height: Some(3),
            default_level: Some(0),
            levels: vec![0],
            static_obstacles: Vec::new(),
            map_blocked_cells: Vec::new(),
            map_cells: Vec::new(),
            map_objects: vec![MapObjectDebugState {
                object_id: "spawn_visual".into(),
                kind: MapObjectKind::AiSpawn,
                anchor: GridCoord::new(1, 0, 1),
                footprint: MapObjectFootprint {
                    width: 1,
                    height: 1,
                },
                rotation: MapRotation::South,
                blocks_movement: false,
                blocks_sight: false,
                occupied_cells: vec![GridCoord::new(1, 0, 1)],
                payload_summary: [
                    ("spawn_id".to_string(), "spawn_visual".to_string()),
                    ("character_id".to_string(), "zombie_walker".to_string()),
                ]
                .into_iter()
                .collect(),
            }],
            runtime_blocked_cells: Vec::new(),
            topology_version: 0,
            runtime_obstacle_version: 0,
        },
        vision: Default::default(),
        generated_buildings: Vec::new(),
        generated_doors: Vec::new(),
        combat: CombatDebugState {
            in_combat: false,
            current_actor_id: None,
            current_group_id: None,
            current_turn_index: 0,
        },
        interaction_context: InteractionContextSnapshot::default(),
        overworld: OverworldStateSnapshot::default(),
        path_preview: Vec::new(),
    }
}
