//! static_world 模块的回归测试，覆盖地图与 overworld 场景生成。

use super::{
    build_static_world_from_map_definition, build_static_world_from_overworld_definition,
    build_static_world_from_topology, is_overworld_location_material_role, StaticMapTopology,
    StaticWorldBuildConfig, StaticWorldGridBounds, StaticWorldMaterialRole,
};
use game_core::{GeneratedBuildingDebugState, GeneratedBuildingStory, GeneratedWalkablePolygons};
use game_data::{
    GridCoord, InteractionOptionDefinition, InteractionOptionId, MapBuildingLayoutSpec,
    MapBuildingProps, MapBuildingStorySpec, MapBuildingTileSetSpec, MapBuildingWallVisualKind,
    MapBuildingWallVisualSpec, MapCellDefinition, MapDefinition, MapEntryPointDefinition, MapId,
    MapLevelDefinition, MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps,
    MapObjectVisualSpec, MapRotation, MapSize, MapTriggerProps, OverworldCellDefinition,
    OverworldDefinition, OverworldId, OverworldLocationDefinition, OverworldLocationId,
    OverworldLocationKind, OverworldTerrainKind, OverworldTravelRuleSet, RelativeGridCell,
    WorldSurfaceTileSetId, WorldTilePrototypeId, WorldWallTileSetId,
};
use std::collections::BTreeMap;

#[test]
fn overworld_builds_continuous_ground_for_full_grid() {
    let scene = build_static_world_from_overworld_definition(&sample_overworld(false));

    assert_eq!(scene.ground.len(), 1);
    assert!(scene.boxes.is_empty());
    assert!(scene.decals.is_empty());
}

#[test]
fn overworld_keeps_blocked_cells_as_overlay_decals() {
    let scene = build_static_world_from_overworld_definition(&sample_overworld(true));

    assert_eq!(
        scene
            .decals
            .iter()
            .filter(|spec| { spec.material_role == StaticWorldMaterialRole::OverworldBlockedCell })
            .count(),
        1
    );
    assert!(
        scene
            .labels
            .iter()
            .filter(|spec| is_overworld_location_material_role(spec.material_role))
            .count()
            >= 1
    );
    assert!(scene.boxes.is_empty());
    assert_eq!(scene.labels.len(), 1);
}

#[test]
fn overworld_overlays_are_centered_on_cells() {
    let scene = build_static_world_from_overworld_definition(&sample_overworld(true));

    let blocked = scene
        .decals
        .iter()
        .find(|spec| spec.material_role == StaticWorldMaterialRole::OverworldBlockedCell)
        .expect("blocked overlay should exist");
    assert_eq!(blocked.translation.x, 1.5);
    assert_eq!(blocked.translation.z, 1.5);

    let location_labels = scene
        .labels
        .iter()
        .filter(|spec| is_overworld_location_material_role(spec.material_role))
        .collect::<Vec<_>>();
    assert_eq!(location_labels.len(), 1);
    assert!(location_labels.iter().all(|spec| {
        spec.translation.x >= 0.05
            && spec.translation.x <= 0.95
            && spec.translation.z >= 0.05
            && spec.translation.z <= 0.95
    }));
    assert!(location_labels.iter().all(|spec| spec.translation.y > 0.3));
    assert_eq!(scene.labels[0].text, "据 Outpost");
}

#[test]
fn generated_buildings_emit_one_wall_tile_per_wall_cell() {
    let scene = build_static_world_from_map_definition(
        &sample_generated_building_map(),
        0,
        StaticWorldBuildConfig::default(),
    );

    assert_eq!(scene.building_wall_tiles.len(), 4);
    assert!(scene.boxes.is_empty());
    assert!(scene
        .surface_tiles
        .iter()
        .all(|tile| tile.surface_set_id.as_str() == "building_wall/floor"));
    assert!(scene
        .building_wall_tiles
        .iter()
        .all(|tile| tile.occluder_cells == vec![tile.grid]));
    assert!(scene
        .building_wall_tiles
        .iter()
        .all(|tile| tile.visual_kind == MapBuildingWallVisualKind::Grid));
}

#[test]
fn generated_building_walkable_cells_emit_individual_floor_tiles() {
    let scene = build_static_world_from_topology(
        &sample_topology_with_walkable_generated_building(),
        0,
        StaticWorldBuildConfig::default(),
    );

    let floor_tiles = scene
        .surface_tiles
        .iter()
        .filter(|tile| tile.surface_set_id.as_str() == "building_wall/floor")
        .count();
    assert_eq!(floor_tiles, 1);
}

#[test]
fn generated_stairs_use_dedicated_stair_specs_instead_of_boxes() {
    let scene = build_static_world_from_topology(
        &sample_topology_with_generated_stairs(),
        0,
        StaticWorldBuildConfig::default(),
    );

    assert!(scene.boxes.is_empty());
    assert!(!scene.stairs.is_empty());
    assert!(scene
        .stairs
        .iter()
        .any(|spec| spec.material_role == StaticWorldMaterialRole::StairBase));
    assert!(scene
        .stairs
        .iter()
        .any(|spec| spec.material_role == StaticWorldMaterialRole::StairAccent));
}

#[test]
fn prototype_visual_props_do_not_emit_fallback_object_boxes() {
    let scene = build_static_world_from_map_definition(
        &sample_map_with_interactive_object(true),
        0,
        StaticWorldBuildConfig::default(),
    );

    assert!(scene.boxes.is_empty());
}

#[test]
fn prototype_visual_pickups_do_not_emit_fallback_object_boxes() {
    let scene = build_static_world_from_map_definition(
        &sample_map_with_pickup_object(true),
        0,
        StaticWorldBuildConfig::default(),
    );

    assert!(scene.boxes.is_empty());
}

#[test]
fn non_visual_interactives_downgrade_to_pick_proxies_only() {
    let scene = build_static_world_from_map_definition(
        &sample_map_with_interactive_object(false),
        0,
        StaticWorldBuildConfig::default(),
    );

    assert!(scene.boxes.is_empty());
    assert_eq!(scene.pick_proxies.len(), 1);
    assert!(scene
        .pick_proxies
        .iter()
        .all(|spec| spec.material_role == StaticWorldMaterialRole::InvisiblePickProxy));
}

#[test]
fn non_visual_pickups_downgrade_to_pick_proxies_only() {
    let scene = build_static_world_from_map_definition(
        &sample_map_with_pickup_object(false),
        0,
        StaticWorldBuildConfig::default(),
    );

    assert!(scene.boxes.is_empty());
    assert_eq!(scene.pick_proxies.len(), 1);
    assert!(scene
        .pick_proxies
        .iter()
        .all(|spec| spec.material_role == StaticWorldMaterialRole::InvisiblePickProxy));
}

#[test]
fn ai_spawn_objects_do_not_emit_static_world_boxes() {
    let scene = build_static_world_from_map_definition(
        &sample_map_with_ai_spawn_object(),
        0,
        Default::default(),
    );

    assert!(scene.boxes.is_empty());
}

#[test]
fn scene_transition_triggers_emit_pick_proxies_and_decals_only() {
    let scene = build_static_world_from_map_definition(
        &sample_map_with_trigger_object("enter_subscene"),
        0,
        Default::default(),
    );

    assert!(scene.boxes.is_empty());
    assert_eq!(scene.pick_proxies.len(), 2);
    assert!(scene
        .pick_proxies
        .iter()
        .all(|spec| spec.material_role == StaticWorldMaterialRole::InvisiblePickProxy));
    assert_eq!(scene.decals.len(), 2);
    assert!(scene
        .decals
        .iter()
        .all(|spec| spec.material_role == StaticWorldMaterialRole::TriggerAccent));
}

#[test]
fn non_transition_triggers_emit_pick_proxies_without_visible_box_fallback() {
    let scene = build_static_world_from_map_definition(
        &sample_map_with_trigger_object("inspect_console"),
        0,
        Default::default(),
    );

    assert!(scene.boxes.is_empty());
    assert_eq!(scene.pick_proxies.len(), 2);
    assert!(scene
        .pick_proxies
        .iter()
        .all(|spec| spec.material_role == StaticWorldMaterialRole::InvisiblePickProxy));
    assert!(scene.decals.is_empty());
}

fn sample_overworld(block_center: bool) -> OverworldDefinition {
    OverworldDefinition {
        id: OverworldId("test_overworld".into()),
        size: MapSize {
            width: 3,
            height: 3,
        },
        locations: vec![OverworldLocationDefinition {
            id: OverworldLocationId("outpost".into()),
            name: "Outpost".into(),
            description: String::new(),
            kind: OverworldLocationKind::Outdoor,
            map_id: MapId("outpost_map".into()),
            entry_point_id: "default_entry".into(),
            parent_outdoor_location_id: None,
            return_entry_point_id: None,
            default_unlocked: true,
            visible: true,
            overworld_cell: GridCoord::new(0, 0, 0),
            danger_level: 0,
            icon: String::new(),
            extra: BTreeMap::new(),
        }],
        cells: (0..3)
            .flat_map(|z| {
                (0..3).map(move |x| OverworldCellDefinition {
                    grid: GridCoord::new(x, 0, z),
                    terrain: OverworldTerrainKind::Plain,
                    blocked: block_center && x == 1 && z == 1,
                    visual: None,
                    extra: BTreeMap::new(),
                })
            })
            .collect(),
        travel_rules: OverworldTravelRuleSet::default(),
    }
}

fn sample_generated_building_map() -> MapDefinition {
    MapDefinition {
        id: MapId("generated_building_map".into()),
        name: "Generated Building".into(),
        size: MapSize {
            width: 4,
            height: 4,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: vec![MapCellDefinition {
                x: 0,
                z: 0,
                blocks_movement: false,
                blocks_sight: false,
                terrain: "ground".into(),
                visual: None,
                extra: BTreeMap::new(),
            }],
        }],
        entry_points: vec![MapEntryPointDefinition {
            id: "default_entry".into(),
            grid: GridCoord::new(0, 0, 0),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: vec![MapObjectDefinition {
            object_id: "test_building".into(),
            kind: MapObjectKind::Building,
            anchor: GridCoord::new(0, 0, 0),
            footprint: MapObjectFootprint {
                width: 2,
                height: 2,
            },
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                building: Some(MapBuildingProps {
                    prefab_id: "generated_house".into(),
                    wall_visual: Some(MapBuildingWallVisualSpec {
                        kind: MapBuildingWallVisualKind::Grid,
                    }),
                    tile_set: Some(sample_building_tile_set()),
                    layout: Some(MapBuildingLayoutSpec {
                        generator: game_data::BuildingGeneratorKind::SolidShell,
                        exterior_door_count: 0,
                        stories: vec![MapBuildingStorySpec {
                            level: 0,
                            shape_cells: vec![
                                RelativeGridCell::new(0, 0),
                                RelativeGridCell::new(1, 0),
                                RelativeGridCell::new(0, 1),
                                RelativeGridCell::new(1, 1),
                            ],
                        }],
                        ..MapBuildingLayoutSpec::default()
                    }),
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        }],
    }
}

fn sample_topology_with_walkable_generated_building() -> StaticMapTopology {
    StaticMapTopology {
        grid_size: 1.0,
        bounds: StaticWorldGridBounds {
            min_x: 0,
            max_x: 2,
            min_z: 0,
            max_z: 2,
        },
        surface_cells: Vec::new(),
        objects: Vec::new(),
        generated_buildings: vec![GeneratedBuildingDebugState {
            object_id: "generated_building".into(),
            prefab_id: "generated_building".into(),
            wall_visual: MapBuildingWallVisualSpec {
                kind: MapBuildingWallVisualKind::Grid,
            },
            tile_set: sample_building_tile_set(),
            anchor: GridCoord::new(0, 0, 0),
            rotation: MapRotation::North,
            stories: vec![GeneratedBuildingStory {
                level: 0,
                wall_height: 2.4,
                wall_thickness: 0.6,
                shape_cells: vec![
                    GridCoord::new(0, 0, 0),
                    GridCoord::new(1, 0, 0),
                    GridCoord::new(2, 0, 0),
                    GridCoord::new(0, 0, 1),
                    GridCoord::new(1, 0, 1),
                    GridCoord::new(2, 0, 1),
                    GridCoord::new(0, 0, 2),
                    GridCoord::new(1, 0, 2),
                    GridCoord::new(2, 0, 2),
                ],
                footprint_polygon: None,
                rooms: Vec::new(),
                room_polygons: Vec::new(),
                wall_cells: vec![
                    GridCoord::new(0, 0, 0),
                    GridCoord::new(1, 0, 0),
                    GridCoord::new(2, 0, 0),
                    GridCoord::new(0, 0, 1),
                    GridCoord::new(2, 0, 1),
                    GridCoord::new(0, 0, 2),
                    GridCoord::new(1, 0, 2),
                    GridCoord::new(2, 0, 2),
                ],
                interior_door_cells: Vec::new(),
                exterior_door_cells: Vec::new(),
                door_openings: Vec::new(),
                walkable_cells: vec![GridCoord::new(1, 0, 1)],
                walkable_polygons: GeneratedWalkablePolygons::default(),
            }],
            stairs: Vec::new(),
            visual_outline: Vec::new(),
        }],
    }
}

fn sample_topology_with_generated_stairs() -> StaticMapTopology {
    let mut topology = sample_topology_with_walkable_generated_building();
    topology.generated_buildings[0].stairs = vec![game_core::GeneratedStairConnection {
        from_level: 0,
        to_level: 1,
        from_cells: vec![GridCoord::new(1, 0, 1)],
        to_cells: vec![GridCoord::new(1, 1, 1)],
        width: 1,
        kind: game_data::StairKind::Straight,
    }];
    topology
}

fn sample_map_with_interactive_object(include_visual: bool) -> MapDefinition {
    MapDefinition {
        id: MapId("visual_interactive_map".into()),
        name: "Visual Interactive".into(),
        size: MapSize {
            width: 2,
            height: 2,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: vec![MapCellDefinition {
                x: 0,
                z: 0,
                blocks_movement: false,
                blocks_sight: false,
                terrain: String::new(),
                visual: None,
                extra: BTreeMap::new(),
            }],
        }],
        entry_points: vec![MapEntryPointDefinition {
            id: "default".into(),
            grid: GridCoord::new(0, 0, 0),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: vec![MapObjectDefinition {
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
            props: MapObjectProps {
                visual: include_visual.then(|| MapObjectVisualSpec {
                    prototype_id: WorldTilePrototypeId("props/locker_metal".into()),
                    ..MapObjectVisualSpec::default()
                }),
                interactive: Some(Default::default()),
                ..MapObjectProps::default()
            },
        }],
    }
}

fn sample_map_with_pickup_object(include_visual: bool) -> MapDefinition {
    MapDefinition {
        id: MapId("visual_pickup_map".into()),
        name: "Visual Pickup".into(),
        size: MapSize {
            width: 2,
            height: 2,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: vec![MapCellDefinition {
                x: 0,
                z: 0,
                blocks_movement: false,
                blocks_sight: false,
                terrain: String::new(),
                visual: None,
                extra: BTreeMap::new(),
            }],
        }],
        entry_points: vec![MapEntryPointDefinition {
            id: "default".into(),
            grid: GridCoord::new(0, 0, 0),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: vec![MapObjectDefinition {
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
            props: MapObjectProps {
                visual: include_visual.then(|| MapObjectVisualSpec {
                    prototype_id: WorldTilePrototypeId("props/crate_wood".into()),
                    ..MapObjectVisualSpec::default()
                }),
                pickup: Some(Default::default()),
                ..MapObjectProps::default()
            },
        }],
    }
}

fn sample_map_with_ai_spawn_object() -> MapDefinition {
    MapDefinition {
        id: MapId("ai_spawn_map".into()),
        name: "AI Spawn".into(),
        size: MapSize {
            width: 2,
            height: 2,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: vec![MapCellDefinition {
                x: 0,
                z: 0,
                blocks_movement: false,
                blocks_sight: false,
                terrain: String::new(),
                visual: None,
                extra: BTreeMap::new(),
            }],
        }],
        entry_points: vec![MapEntryPointDefinition {
            id: "default".into(),
            grid: GridCoord::new(0, 0, 0),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: vec![MapObjectDefinition {
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
            props: MapObjectProps {
                ai_spawn: Some(Default::default()),
                ..MapObjectProps::default()
            },
        }],
    }
}

fn sample_map_with_trigger_object(trigger_kind: &str) -> MapDefinition {
    MapDefinition {
        id: MapId(format!("trigger_map_{trigger_kind}").into()),
        name: "Trigger Map".into(),
        size: MapSize {
            width: 3,
            height: 2,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: vec![MapCellDefinition {
                x: 0,
                z: 0,
                blocks_movement: false,
                blocks_sight: false,
                terrain: String::new(),
                visual: None,
                extra: BTreeMap::new(),
            }],
        }],
        entry_points: vec![MapEntryPointDefinition {
            id: "default".into(),
            grid: GridCoord::new(0, 0, 0),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: vec![MapObjectDefinition {
            object_id: format!("trigger_{trigger_kind}"),
            kind: MapObjectKind::Trigger,
            anchor: GridCoord::new(1, 0, 0),
            footprint: MapObjectFootprint {
                width: 2,
                height: 1,
            },
            rotation: MapRotation::East,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                trigger: Some(MapTriggerProps {
                    display_name: "Trigger".into(),
                    options: vec![InteractionOptionDefinition {
                        id: InteractionOptionId(trigger_kind.into()),
                        ..InteractionOptionDefinition::default()
                    }],
                    ..MapTriggerProps::default()
                }),
                ..MapObjectProps::default()
            },
        }],
    }
}

fn sample_building_tile_set() -> MapBuildingTileSetSpec {
    MapBuildingTileSetSpec {
        wall_set_id: WorldWallTileSetId("building_wall".into()),
        floor_surface_set_id: Some(WorldSurfaceTileSetId("building_wall/floor".into())),
        door_prototype_id: None,
    }
}
