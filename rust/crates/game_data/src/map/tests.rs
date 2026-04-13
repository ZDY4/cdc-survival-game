//! map 模块的回归测试，覆盖加载、校验与对象辅助逻辑。

use super::{
    expand_object_footprint, load_map_library, validate_map_definition, BuildingGeneratorKind,
    MapAiSpawnProps, MapBuildingDiagonalEdge, MapBuildingFootprintPolygonSpec,
    MapBuildingLayoutSpec, MapBuildingProps, MapBuildingStorySpec, MapBuildingTileSetSpec,
    MapBuildingVisualOutline, MapBuildingWallVisualKind, MapBuildingWallVisualSpec,
    MapCellDefinition, MapContainerItemEntry, MapContainerProps, MapDefinition,
    MapDefinitionValidationError, MapEntryPointDefinition, MapId, MapInteractiveProps,
    MapLevelDefinition, MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps,
    MapPickupProps, MapRotation, MapSize, MapValidationCatalog, RelativeGridCell,
    RelativeGridVertex,
};
use crate::{GridCoord, WorldWallTileSetId};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn footprint_rotation_swaps_rect_dimensions() {
    let object = MapObjectDefinition {
        object_id: "house".into(),
        kind: MapObjectKind::Building,
        anchor: GridCoord::new(2, 0, 3),
        footprint: MapObjectFootprint {
            width: 4,
            height: 2,
        },
        rotation: MapRotation::East,
        blocks_movement: true,
        blocks_sight: true,
        props: MapObjectProps {
            building: Some(MapBuildingProps {
                prefab_id: "survivor_outpost_01_dormitory".into(),
                wall_visual: Some(MapBuildingWallVisualSpec {
                    kind: MapBuildingWallVisualKind::LegacyGrid,
                }),
                tile_set: Some(sample_building_tile_set()),
                layout: None,
                extra: BTreeMap::new(),
            }),
            ..MapObjectProps::default()
        },
    };

    let cells = expand_object_footprint(&object);
    assert_eq!(cells.len(), 8);
    assert!(cells.contains(&GridCoord::new(2, 0, 3)));
    assert!(cells.contains(&GridCoord::new(3, 0, 6)));
    assert!(!cells.contains(&GridCoord::new(5, 0, 3)));
}

#[test]
fn overlapping_blocking_objects_are_rejected() {
    let map = sample_map(vec![
        sample_building("house_a", GridCoord::new(1, 0, 1), 3, 2),
        sample_building("house_b", GridCoord::new(2, 0, 1), 2, 2),
    ]);

    let error =
        validate_map_definition(&map, Some(&sample_catalog())).expect_err("overlap should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::OverlappingBlockingObjects { .. }
    ));
}

#[test]
fn invalid_external_references_are_rejected() {
    let mut map = sample_map(vec![
        sample_pickup("pickup_medkit", GridCoord::new(0, 0, 0), "9999"),
        sample_ai_spawn("spawn_enemy", GridCoord::new(6, 0, 6), "missing_character"),
    ]);
    map.objects[0].blocks_movement = false;
    map.objects[1].blocks_movement = false;

    let error = validate_map_definition(&map, Some(&sample_catalog()))
        .expect_err("catalog references should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::UnknownPickupItemId { .. }
            | MapDefinitionValidationError::UnknownAiSpawnCharacterId { .. }
    ));
}

#[test]
fn container_interactive_object_without_explicit_options_is_valid() {
    let map = sample_map(vec![sample_container(
        "crate",
        GridCoord::new(1, 0, 1),
        "1005",
        2,
    )]);

    validate_map_definition(&map, Some(&sample_catalog()))
        .expect("container object should derive a default open_container option");
}

#[test]
fn container_items_require_known_positive_entries() {
    let map = sample_map(vec![sample_container(
        "crate",
        GridCoord::new(1, 0, 1),
        "9999",
        0,
    )]);

    let error = validate_map_definition(&map, Some(&sample_catalog()))
        .expect_err("container validation should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::UnknownContainerItemId { .. }
            | MapDefinitionValidationError::InvalidContainerItemCount { .. }
    ));
}

#[test]
fn container_visual_id_must_not_be_blank() {
    let mut container = sample_container("crate", GridCoord::new(1, 0, 1), "1005", 2);
    container
        .props
        .container
        .as_mut()
        .expect("container props")
        .visual_id = Some("   ".into());

    let error = validate_map_definition(&sample_map(vec![container]), Some(&sample_catalog()))
        .expect_err("blank container visual_id should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::InvalidContainerVisualId { .. }
    ));
}

#[test]
fn migrated_sample_map_library_loads_successfully() {
    let data_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join("data/maps");
    let library = load_map_library(&data_dir).expect("sample maps should load");

    assert!(!library.is_empty());
    assert!(library.get(&MapId("survivor_outpost_01".into())).is_some());
}

#[test]
fn map_cells_outside_bounds_are_rejected() {
    let mut map = sample_map(Vec::new());
    map.levels[0].cells.push(MapCellDefinition {
        x: 99,
        z: 0,
        blocks_movement: true,
        blocks_sight: false,
        terrain: "wall".into(),
        visual: None,
        extra: BTreeMap::new(),
    });

    let error =
        validate_map_definition(&map, Some(&sample_catalog())).expect_err("bounds should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::CellOutOfBounds { .. }
    ));
}

#[test]
fn building_layout_requires_positive_target_room_count() {
    let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
    building.blocks_movement = false;
    building.blocks_sight = false;
    building
        .props
        .building
        .as_mut()
        .expect("building props")
        .layout = Some(MapBuildingLayoutSpec {
        target_room_count: 0,
        shape_cells: vec![
            RelativeGridCell::new(0, 0),
            RelativeGridCell::new(1, 0),
            RelativeGridCell::new(0, 1),
            RelativeGridCell::new(1, 1),
        ],
        generator: BuildingGeneratorKind::RectilinearBsp,
        ..MapBuildingLayoutSpec::default()
    });

    let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
        .expect_err("zero room target should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::InvalidBuildingTargetRoomCount { .. }
    ));
}

#[test]
fn building_requires_explicit_wall_visual_kind() {
    let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
    building
        .props
        .building
        .as_mut()
        .expect("building props")
        .wall_visual = None;

    let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
        .expect_err("missing wall visual should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::MissingBuildingWallVisualKind { .. }
    ));
}

#[test]
fn building_layout_requires_positive_min_room_area() {
    let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
    building.blocks_movement = false;
    building.blocks_sight = false;
    building
        .props
        .building
        .as_mut()
        .expect("building props")
        .layout = Some(MapBuildingLayoutSpec {
        min_room_area: 0,
        shape_cells: vec![
            RelativeGridCell::new(0, 0),
            RelativeGridCell::new(1, 0),
            RelativeGridCell::new(0, 1),
            RelativeGridCell::new(1, 1),
        ],
        generator: BuildingGeneratorKind::RectilinearBsp,
        ..MapBuildingLayoutSpec::default()
    });

    let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
        .expect_err("zero min room area should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::InvalidBuildingRoomSize { .. }
    ));
}

#[test]
fn building_layout_rejects_duplicate_story_levels() {
    let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
    building.blocks_movement = false;
    building.blocks_sight = false;
    building
        .props
        .building
        .as_mut()
        .expect("building props")
        .layout = Some(MapBuildingLayoutSpec {
        shape_cells: vec![
            RelativeGridCell::new(0, 0),
            RelativeGridCell::new(1, 0),
            RelativeGridCell::new(0, 1),
            RelativeGridCell::new(1, 1),
        ],
        stories: vec![
            MapBuildingStorySpec {
                level: 0,
                shape_cells: Vec::new(),
            },
            MapBuildingStorySpec {
                level: 0,
                shape_cells: Vec::new(),
            },
        ],
        ..MapBuildingLayoutSpec::default()
    });

    let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
        .expect_err("duplicate story level should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::DuplicateBuildingStoryLevel { .. }
    ));
}

#[test]
fn building_layout_rejects_invalid_visual_outline_edge() {
    let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
    building.blocks_movement = false;
    building.blocks_sight = false;
    building
        .props
        .building
        .as_mut()
        .expect("building props")
        .layout = Some(MapBuildingLayoutSpec {
        shape_cells: vec![
            RelativeGridCell::new(0, 0),
            RelativeGridCell::new(1, 0),
            RelativeGridCell::new(0, 1),
            RelativeGridCell::new(1, 1),
        ],
        visual_outline: Some(MapBuildingVisualOutline {
            diagonal_edges: vec![MapBuildingDiagonalEdge {
                level: 0,
                from: RelativeGridVertex::new(0, 0),
                to: RelativeGridVertex::new(0, 0),
            }],
        }),
        ..MapBuildingLayoutSpec::default()
    });

    let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
        .expect_err("degenerate outline edge should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::InvalidBuildingVisualOutlineEdge { .. }
    ));
}

#[test]
fn building_layout_rejects_invalid_polygon_footprint() {
    let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
    building.blocks_movement = false;
    building.blocks_sight = false;
    building
        .props
        .building
        .as_mut()
        .expect("building props")
        .layout = Some(MapBuildingLayoutSpec {
        footprint_polygon: Some(MapBuildingFootprintPolygonSpec {
            outer: vec![RelativeGridVertex::new(0, 0), RelativeGridVertex::new(0, 0)],
        }),
        ..MapBuildingLayoutSpec::default()
    });

    let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
        .expect_err("degenerate polygon should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::InvalidBuildingFootprintPolygon { .. }
    ));
}

#[test]
fn building_layout_rejects_non_positive_geometry_parameters() {
    let mut building = sample_building("layout_house", GridCoord::new(1, 0, 1), 4, 4);
    building.blocks_movement = false;
    building.blocks_sight = false;
    building
        .props
        .building
        .as_mut()
        .expect("building props")
        .layout = Some(MapBuildingLayoutSpec {
        wall_thickness: 0.0,
        ..MapBuildingLayoutSpec::default()
    });

    let error = validate_map_definition(&sample_map(vec![building]), Some(&sample_catalog()))
        .expect_err("non-positive geometry params should fail");

    assert!(matches!(
        error,
        MapDefinitionValidationError::InvalidBuildingGeometryParameters { .. }
    ));
}

fn sample_map(objects: Vec<MapObjectDefinition>) -> MapDefinition {
    MapDefinition {
        id: MapId("sample_map".into()),
        name: "Sample".into(),
        size: MapSize {
            width: 12,
            height: 12,
        },
        default_level: 0,
        levels: vec![
            MapLevelDefinition {
                y: 0,
                cells: vec![MapCellDefinition {
                    x: 5,
                    z: 5,
                    blocks_movement: true,
                    blocks_sight: true,
                    terrain: "pillar".into(),
                    visual: None,
                    extra: BTreeMap::new(),
                }],
            },
            MapLevelDefinition {
                y: 1,
                cells: Vec::new(),
            },
        ],
        entry_points: vec![MapEntryPointDefinition {
            id: "default_entry".into(),
            grid: GridCoord::new(0, 0, 0),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects,
    }
}

fn sample_building(
    object_id: &str,
    anchor: GridCoord,
    width: u32,
    height: u32,
) -> MapObjectDefinition {
    MapObjectDefinition {
        object_id: object_id.into(),
        kind: MapObjectKind::Building,
        anchor,
        footprint: MapObjectFootprint { width, height },
        rotation: MapRotation::North,
        blocks_movement: true,
        blocks_sight: true,
        props: MapObjectProps {
            building: Some(MapBuildingProps {
                prefab_id: "survivor_outpost_01_dormitory".into(),
                wall_visual: Some(MapBuildingWallVisualSpec {
                    kind: MapBuildingWallVisualKind::LegacyGrid,
                }),
                tile_set: Some(sample_building_tile_set()),
                layout: None,
                extra: BTreeMap::new(),
            }),
            ..MapObjectProps::default()
        },
    }
}

fn sample_pickup(object_id: &str, anchor: GridCoord, item_id: &str) -> MapObjectDefinition {
    MapObjectDefinition {
        object_id: object_id.into(),
        kind: MapObjectKind::Pickup,
        anchor,
        footprint: MapObjectFootprint::default(),
        rotation: MapRotation::North,
        blocks_movement: false,
        blocks_sight: false,
        props: MapObjectProps {
            pickup: Some(MapPickupProps {
                item_id: item_id.into(),
                min_count: 1,
                max_count: 2,
                extra: BTreeMap::new(),
            }),
            ..MapObjectProps::default()
        },
    }
}

fn sample_ai_spawn(object_id: &str, anchor: GridCoord, character_id: &str) -> MapObjectDefinition {
    MapObjectDefinition {
        object_id: object_id.into(),
        kind: MapObjectKind::AiSpawn,
        anchor,
        footprint: MapObjectFootprint::default(),
        rotation: MapRotation::North,
        blocks_movement: false,
        blocks_sight: false,
        props: MapObjectProps {
            ai_spawn: Some(MapAiSpawnProps {
                spawn_id: format!("{object_id}_id"),
                character_id: character_id.into(),
                auto_spawn: true,
                respawn_enabled: false,
                respawn_delay: 10.0,
                spawn_radius: 0.0,
                extra: BTreeMap::new(),
            }),
            ..MapObjectProps::default()
        },
    }
}

fn sample_container(
    object_id: &str,
    anchor: GridCoord,
    item_id: &str,
    count: i32,
) -> MapObjectDefinition {
    MapObjectDefinition {
        object_id: object_id.into(),
        kind: MapObjectKind::Interactive,
        anchor,
        footprint: MapObjectFootprint::default(),
        rotation: MapRotation::North,
        blocks_movement: false,
        blocks_sight: false,
        props: MapObjectProps {
            container: Some(MapContainerProps {
                display_name: "储物箱".into(),
                visual_id: None,
                initial_inventory: vec![MapContainerItemEntry {
                    item_id: item_id.into(),
                    count,
                }],
                extra: BTreeMap::new(),
            }),
            interactive: Some(MapInteractiveProps {
                display_name: "旧箱子".into(),
                interaction_distance: 1.5,
                interaction_kind: String::new(),
                target_id: None,
                options: Vec::new(),
                extra: BTreeMap::new(),
            }),
            ..MapObjectProps::default()
        },
    }
}

fn sample_catalog() -> MapValidationCatalog {
    MapValidationCatalog {
        item_ids: ["1005".to_string()].into_iter().collect(),
        character_ids: ["zombie_walker".to_string()].into_iter().collect(),
        prototype_ids: Default::default(),
        wall_set_ids: Default::default(),
        surface_set_ids: Default::default(),
    }
}

fn sample_building_tile_set() -> MapBuildingTileSetSpec {
    MapBuildingTileSetSpec {
        wall_set_id: WorldWallTileSetId("building_wall_legacy".into()),
        floor_surface_set_id: None,
        door_prototype_id: None,
    }
}

#[allow(dead_code)]
fn create_temp_dir(label: &str) -> PathBuf {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock should be available")
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("cdc_map_tests_{label}_{suffix}"));
    fs::create_dir_all(&dir).expect("temp dir should be created");
    dir
}

#[allow(dead_code)]
fn cleanup_temp_dir(path: &Path) {
    let _ = fs::remove_dir_all(path);
}
