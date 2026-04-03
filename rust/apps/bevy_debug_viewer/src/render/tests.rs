//! 渲染模块测试：覆盖静态世界规格、角色可视化、交互菜单和遮挡淡化等回归场景。

use super::*;

use super::{
    actor_visual_translation, actor_visual_world_position, build_wall_tile_mesh,
    camera_follow_requires_reset, classify_wall_tile, collect_static_world_box_specs,
    collect_static_world_decal_specs, collect_static_world_mesh_specs,
    collect_walkable_tile_overlay_cells, darken_color, interaction_menu_button_color,
    interaction_menu_layout, lerp_color, lighten_color, merge_cells_into_rects,
    occluder_should_fade, occupied_cells_box, should_hide_building_roofs,
    update_camera_follow_focus, GridBounds, MaterialStyle, StaticWorldOccluderKind,
    WalkableTileOverlayKind, WallTileKind, INTERACTION_MENU_BUTTON_GAP_PX,
    INTERACTION_MENU_BUTTON_HEIGHT_PX, INTERACTION_MENU_PADDING_PX, WALL_EAST, WALL_NORTH,
    WALL_SOUTH, WALL_WEST,
};
use crate::picking::{BuildingPartKind, ViewerPickTarget};
use crate::state::{
    InteractionMenuState, ViewerActorFeedbackState, ViewerActorMotionState,
    ViewerCameraFollowState, ViewerControlMode, ViewerPalette, ViewerRenderConfig,
    ViewerRuntimeState, ViewerSceneKind, ViewerState,
};
use game_bevy::SettlementDebugSnapshot;
use game_core::{
    create_demo_runtime, CombatDebugState, GeneratedBuildingDebugState, GeneratedBuildingStory,
    GeneratedStairConnection, GridDebugState, MapCellDebugState, MapObjectDebugState,
    OverworldStateSnapshot, SimulationSnapshot,
};
use game_data::{
    ActorId, GridCoord, InteractionContextSnapshot, InteractionOptionId, InteractionPrompt,
    InteractionTargetId, MapObjectFootprint, MapObjectKind, MapRotation, ResolvedInteractionOption,
    TurnState, WorldCoord,
};
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

    assert!(layout.left >= 0.0);
    assert!(layout.top >= 0.0);
    assert!(layout.left + layout.width <= window.width() - 11.0);
    assert!(layout.top + layout.height <= window.height() - 11.0);
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
        INTERACTION_MENU_PADDING_PX * 2.0
            + 3.0 * INTERACTION_MENU_BUTTON_HEIGHT_PX
            + 2.0 * INTERACTION_MENU_BUTTON_GAP_PX
    );
}

#[test]
fn primary_button_is_not_always_highlighted_when_idle() {
    assert_eq!(
        interaction_menu_button_color(true, Interaction::None).to_srgba(),
        interaction_menu_button_color(false, Interaction::None).to_srgba()
    );
    assert_eq!(
        interaction_menu_button_color(true, Interaction::Hovered).to_srgba(),
        interaction_menu_button_color(false, Interaction::Hovered).to_srgba()
    );
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
fn merge_cells_into_rects_coalesces_solid_areas() {
    let rects = merge_cells_into_rects(&[
        GridCoord::new(0, 0, 0),
        GridCoord::new(1, 0, 0),
        GridCoord::new(0, 0, 1),
        GridCoord::new(1, 0, 1),
        GridCoord::new(3, 0, 0),
    ]);

    assert_eq!(rects.len(), 2);
    assert_eq!(rects[0].min_x, 0);
    assert_eq!(rects[0].max_x, 1);
    assert_eq!(rects[0].min_z, 0);
    assert_eq!(rects[0].max_z, 1);
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
fn static_world_specs_add_wireframe_boxes_for_unrendered_blocked_map_cells() {
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

    let wireframe_spec_count = specs
        .iter()
        .filter(|spec| {
            let color = spec.color.to_srgba();
            spec.material_style == MaterialStyle::UtilityAccent
                && (color.red - 0.95).abs() < 0.001
                && (color.green - 0.18).abs() < 0.001
                && (color.blue - 0.18).abs() < 0.001
        })
        .count();

    assert_eq!(wireframe_spec_count, 12);
}

#[test]
fn static_world_specs_skip_wireframe_fallback_when_cell_already_has_visible_object() {
    let mut snapshot = snapshot_with_occluders();
    snapshot.grid.map_cells[0].grid = GridCoord::new(1, 0, 1);

    let specs = collect_static_world_box_specs(
        &snapshot,
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

    let wireframe_spec_count = specs
        .iter()
        .filter(|spec| {
            let color = spec.color.to_srgba();
            spec.material_style == MaterialStyle::UtilityAccent
                && (color.red - 0.95).abs() < 0.001
                && (color.green - 0.18).abs() < 0.001
                && (color.blue - 0.18).abs() < 0.001
        })
        .count();

    assert_eq!(wireframe_spec_count, 0);
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
fn generated_building_specs_render_walls_as_tiles() {
    let palette = ViewerPalette::default();
    let box_specs = collect_static_world_box_specs(
        &snapshot_with_generated_building(),
        0,
        false,
        ViewerRenderConfig::default(),
        &palette,
        GridBounds {
            min_x: 0,
            max_x: 3,
            min_z: 0,
            max_z: 3,
        },
        world_from_grid,
    );
    let mesh_specs = collect_static_world_mesh_specs(
        &snapshot_with_generated_building(),
        0,
        false,
        ViewerRenderConfig::default(),
        &palette,
    );

    let wall_specs = mesh_specs
        .iter()
        .filter(|spec| {
            spec.color.to_srgba() == darken_color(palette.building_base, 0.2).to_srgba()
                && spec.material_style == MaterialStyle::BuildingWallGrid
                && spec.occluder_kind
                    == Some(StaticWorldOccluderKind::MapObject(MapObjectKind::Building))
        })
        .count();
    let walkable_specs = mesh_specs
        .iter()
        .filter(|spec| {
            spec.color.to_srgba()
                == lerp_color(palette.building_top, palette.building_base, 0.38).to_srgba()
        })
        .count();
    let roof_specs = mesh_specs
        .iter()
        .filter(|spec| spec.color.to_srgba() == palette.building_top.to_srgba())
        .count();
    let stair_specs = box_specs
        .iter()
        .filter(|spec| spec.material_style != MaterialStyle::BuildingWallGrid)
        .count();

    assert_eq!(wall_specs, 4);
    assert!(walkable_specs >= 1);
    assert_eq!(roof_specs, 0);
    assert!(stair_specs >= 1);
}

#[test]
fn classify_wall_tile_covers_all_adjacency_shapes() {
    assert_eq!(classify_wall_tile(0), WallTileKind::Isolated);
    assert_eq!(classify_wall_tile(WALL_EAST), WallTileKind::EndEast);
    assert_eq!(
        classify_wall_tile(WALL_EAST | WALL_WEST),
        WallTileKind::StraightHorizontal
    );
    assert_eq!(
        classify_wall_tile(WALL_NORTH | WALL_SOUTH),
        WallTileKind::StraightVertical
    );
    assert_eq!(
        classify_wall_tile(WALL_NORTH | WALL_EAST),
        WallTileKind::CornerNorthEast
    );
    assert_eq!(
        classify_wall_tile(WALL_EAST | WALL_SOUTH | WALL_WEST),
        WallTileKind::TJunctionMissingNorth
    );
    assert_eq!(
        classify_wall_tile(WALL_NORTH | WALL_EAST | WALL_SOUTH | WALL_WEST),
        WallTileKind::Cross
    );
}

#[test]
fn generated_building_wall_tiles_keep_per_cell_occluders() {
    let palette = ViewerPalette::default();
    let mesh_specs = collect_static_world_mesh_specs(
        &snapshot_with_generated_building(),
        0,
        false,
        ViewerRenderConfig::default(),
        &palette,
    );

    let wall_specs = mesh_specs
        .iter()
        .filter(|spec| {
            spec.occluder_kind == Some(StaticWorldOccluderKind::MapObject(MapObjectKind::Building))
        })
        .collect::<Vec<_>>();

    assert_eq!(wall_specs.len(), 4);
    assert!(wall_specs.iter().all(|spec| spec.aabb_half_extents.x > 0.0));
    assert!(wall_specs.iter().all(|spec| spec.aabb_half_extents.y > 0.0));
    assert!(wall_specs.iter().all(|spec| spec.aabb_half_extents.z > 0.0));
    assert!(wall_specs.iter().all(|spec| {
        spec.pick_binding.as_ref().is_some_and(|binding| {
            binding.interaction == Some(InteractionTargetId::MapObject("generated_house".into()))
                && matches!(
                    binding.semantic,
                    ViewerPickTarget::BuildingPart(ref part)
                        if part.kind == BuildingPartKind::WallCell
                            && part.building_object_id == "generated_house"
                )
        })
    }));
}

#[test]
fn generated_building_walkable_meshes_do_not_become_pickable() {
    let palette = ViewerPalette::default();
    let mesh_specs = collect_static_world_mesh_specs(
        &snapshot_with_generated_building(),
        0,
        false,
        ViewerRenderConfig::default(),
        &palette,
    );

    let walkable_specs = mesh_specs
        .iter()
        .filter(|spec| spec.material_style == MaterialStyle::StructureAccent)
        .collect::<Vec<_>>();

    assert!(!walkable_specs.is_empty());
    assert!(walkable_specs
        .iter()
        .all(|spec| spec.pick_binding.is_none()));
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

#[test]
fn wall_tile_mesh_uses_requested_visual_thickness() {
    let (_, _, half_extents) = build_wall_tile_mesh(
        GridCoord::new(0, 0, 0),
        WallTileKind::StraightHorizontal,
        0.0,
        2.35,
        0.5,
        1.0,
    )
    .expect("wall tile mesh should build");

    assert!((half_extents.x - 0.5).abs() < 1e-5);
    assert!((half_extents.z - 0.25).abs() < 1e-5);
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
                },
                MapCellDebugState {
                    grid: GridCoord::new(1, 0, 1),
                    blocks_movement: false,
                    blocks_sight: true,
                    terrain: "curtain".into(),
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
