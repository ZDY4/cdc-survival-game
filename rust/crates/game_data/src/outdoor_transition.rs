use std::fmt;

use thiserror::Error;

use crate::{
    expand_object_footprint, rotated_footprint_size, GridCoord, InteractionOptionDefinition,
    InteractionOptionKind, MapDefinition, MapEntryPointDefinition, MapId, MapLibrary,
    MapObjectDefinition, MapObjectKind, MapRotation, MapSize, OverworldDefinition,
    OverworldLibrary, OverworldLocationDefinition, OverworldLocationKind,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EdgeDirection {
    North,
    South,
    East,
    West,
}

impl EdgeDirection {
    fn from_delta(dx: i32, dz: i32) -> Option<Self> {
        match (dx, dz) {
            (1, 0) => Some(Self::East),
            (-1, 0) => Some(Self::West),
            (0, 1) => Some(Self::South),
            (0, -1) => Some(Self::North),
            _ => None,
        }
    }

    fn opposite(self) -> Self {
        match self {
            Self::North => Self::South,
            Self::South => Self::North,
            Self::East => Self::West,
            Self::West => Self::East,
        }
    }

    fn trigger_edge_name(self) -> &'static str {
        match self {
            Self::North => "north",
            Self::South => "south",
            Self::East => "east",
            Self::West => "west",
        }
    }

    fn target_entry_edge_name(self) -> &'static str {
        match self.opposite() {
            Self::North => "north inner edge",
            Self::South => "south inner edge",
            Self::East => "east inner edge",
            Self::West => "west inner edge",
        }
    }
}

impl fmt::Display for EdgeDirection {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.trigger_edge_name())
    }
}

#[derive(Debug, Clone, Error, PartialEq, Eq)]
pub enum OutdoorTransitionTriggerLayoutValidationError {
    #[error(
        "outdoor trigger layout invalid: source map {map_id} trigger {object_id} targeting {target_location_id} is not mapped to an outdoor overworld location"
    )]
    MissingSourceOutdoorLocation {
        map_id: String,
        object_id: String,
        target_location_id: String,
    },
    #[error(
        "outdoor trigger layout invalid: source map {map_id} trigger {object_id} source location {source_location_id} targets missing outdoor location {target_location_id}"
    )]
    MissingTargetOutdoorLocation {
        map_id: String,
        object_id: String,
        source_location_id: String,
        target_location_id: String,
    },
    #[error(
        "outdoor trigger layout invalid: source map {map_id} trigger {object_id} source location {source_location_id} at ({source_x}, {source_y}, {source_z}) and target location {target_location_id} at ({target_x}, {target_y}, {target_z}) must be orthogonally adjacent"
    )]
    NonAdjacentOutdoorLocations {
        map_id: String,
        object_id: String,
        source_location_id: String,
        target_location_id: String,
        source_x: i32,
        source_y: i32,
        source_z: i32,
        target_x: i32,
        target_y: i32,
        target_z: i32,
    },
    #[error(
        "outdoor trigger layout invalid: source map {map_id} trigger {object_id} source location {source_location_id} -> target {target_location_id} expected a {expected_edge} edge stripe, got anchor=({anchor_x}, {anchor_y}, {anchor_z}) footprint={footprint_width}x{footprint_height} rotation={rotation:?}"
    )]
    MisalignedTriggerEdge {
        map_id: String,
        object_id: String,
        source_location_id: String,
        target_location_id: String,
        expected_edge: String,
        anchor_x: i32,
        anchor_y: i32,
        anchor_z: i32,
        footprint_width: u32,
        footprint_height: u32,
        rotation: MapRotation,
    },
    #[error(
        "outdoor trigger layout invalid: source map {map_id} trigger {object_id} source location {source_location_id} -> target {target_location_id} expected a {expected_edge} edge stripe orientation, got anchor=({anchor_x}, {anchor_y}, {anchor_z}) footprint={footprint_width}x{footprint_height} rotation={rotation:?} rotated={rotated_width}x{rotated_height}"
    )]
    InvalidTriggerStripeOrientation {
        map_id: String,
        object_id: String,
        source_location_id: String,
        target_location_id: String,
        expected_edge: String,
        anchor_x: i32,
        anchor_y: i32,
        anchor_z: i32,
        footprint_width: u32,
        footprint_height: u32,
        rotation: MapRotation,
        rotated_width: u32,
        rotated_height: u32,
    },
    #[error(
        "outdoor trigger layout invalid: source map {map_id} trigger {object_id} source location {source_location_id} -> target {target_location_id} references missing target map {target_map_id}"
    )]
    MissingTargetMapDefinition {
        map_id: String,
        object_id: String,
        source_location_id: String,
        target_location_id: String,
        target_map_id: String,
    },
    #[error(
        "outdoor trigger layout invalid: source map {map_id} trigger {object_id} source location {source_location_id} -> target {target_location_id} references missing target entry point {entry_point_id} in map {target_map_id}"
    )]
    MissingTargetEntryPoint {
        map_id: String,
        object_id: String,
        source_location_id: String,
        target_location_id: String,
        target_map_id: String,
        entry_point_id: String,
    },
    #[error(
        "outdoor trigger layout invalid: source map {map_id} trigger {object_id} source location {source_location_id} -> target {target_location_id} expected entry point {entry_point_id} in map {target_map_id} on the {expected_edge} at ({expected_x}, {expected_y}, {expected_z}), got ({actual_x}, {actual_y}, {actual_z})"
    )]
    MisalignedTargetEntryPoint {
        map_id: String,
        object_id: String,
        source_location_id: String,
        target_location_id: String,
        target_map_id: String,
        entry_point_id: String,
        expected_edge: String,
        expected_x: i32,
        expected_y: i32,
        expected_z: i32,
        actual_x: i32,
        actual_y: i32,
        actual_z: i32,
    },
}

pub fn validate_outdoor_transition_trigger_layout(
    maps: &MapLibrary,
    overworld: &OverworldLibrary,
) -> Result<(), OutdoorTransitionTriggerLayoutValidationError> {
    for (map_id, map_definition) in maps.iter() {
        for object in &map_definition.objects {
            if object.kind != MapObjectKind::Trigger {
                continue;
            }
            let Some(trigger) = object.props.trigger.as_ref() else {
                continue;
            };
            for option in trigger.resolved_options() {
                if option.kind != InteractionOptionKind::EnterOutdoorLocation {
                    continue;
                }
                validate_outdoor_trigger_option(
                    maps,
                    overworld,
                    map_id,
                    map_definition,
                    object,
                    &option,
                )?;
            }
        }
    }

    Ok(())
}

fn validate_outdoor_trigger_option(
    maps: &MapLibrary,
    overworld: &OverworldLibrary,
    map_id: &MapId,
    map_definition: &MapDefinition,
    object: &MapObjectDefinition,
    option: &InteractionOptionDefinition,
) -> Result<(), OutdoorTransitionTriggerLayoutValidationError> {
    let target_location_id = option.target_id.as_str();
    let Some((source_overworld, source_location)) = find_source_outdoor_location(overworld, map_id)
    else {
        return Err(
            OutdoorTransitionTriggerLayoutValidationError::MissingSourceOutdoorLocation {
                map_id: map_id.as_str().to_string(),
                object_id: object.object_id.clone(),
                target_location_id: target_location_id.to_string(),
            },
        );
    };

    let Some(target_location) = find_outdoor_location_by_id(source_overworld, target_location_id)
    else {
        return Err(
            OutdoorTransitionTriggerLayoutValidationError::MissingTargetOutdoorLocation {
                map_id: map_id.as_str().to_string(),
                object_id: object.object_id.clone(),
                source_location_id: source_location.id.as_str().to_string(),
                target_location_id: target_location_id.to_string(),
            },
        );
    };

    let dx = target_location.overworld_cell.x - source_location.overworld_cell.x;
    let dz = target_location.overworld_cell.z - source_location.overworld_cell.z;
    let Some(edge) = EdgeDirection::from_delta(dx, dz) else {
        return Err(
            OutdoorTransitionTriggerLayoutValidationError::NonAdjacentOutdoorLocations {
                map_id: map_id.as_str().to_string(),
                object_id: object.object_id.clone(),
                source_location_id: source_location.id.as_str().to_string(),
                target_location_id: target_location_id.to_string(),
                source_x: source_location.overworld_cell.x,
                source_y: source_location.overworld_cell.y,
                source_z: source_location.overworld_cell.z,
                target_x: target_location.overworld_cell.x,
                target_y: target_location.overworld_cell.y,
                target_z: target_location.overworld_cell.z,
            },
        );
    };

    let (rotated_width, rotated_height) = rotated_footprint_size(object.footprint, object.rotation);
    let stripe_is_valid = match edge {
        EdgeDirection::East | EdgeDirection::West => rotated_width == 1,
        EdgeDirection::North | EdgeDirection::South => rotated_height == 1,
    };
    if !stripe_is_valid {
        return Err(
            OutdoorTransitionTriggerLayoutValidationError::InvalidTriggerStripeOrientation {
                map_id: map_id.as_str().to_string(),
                object_id: object.object_id.clone(),
                source_location_id: source_location.id.as_str().to_string(),
                target_location_id: target_location_id.to_string(),
                expected_edge: edge.trigger_edge_name().to_string(),
                anchor_x: object.anchor.x,
                anchor_y: object.anchor.y,
                anchor_z: object.anchor.z,
                footprint_width: object.footprint.width,
                footprint_height: object.footprint.height,
                rotation: object.rotation,
                rotated_width,
                rotated_height,
            },
        );
    }

    let occupied_cells = expand_object_footprint(object);
    let expected_index_x = map_definition.size.width.saturating_sub(1) as i32;
    let expected_index_z = map_definition.size.height.saturating_sub(1) as i32;
    let on_expected_edge = match edge {
        EdgeDirection::East => occupied_cells.iter().all(|cell| cell.x == expected_index_x),
        EdgeDirection::West => occupied_cells.iter().all(|cell| cell.x == 0),
        EdgeDirection::South => occupied_cells.iter().all(|cell| cell.z == expected_index_z),
        EdgeDirection::North => occupied_cells.iter().all(|cell| cell.z == 0),
    };
    if !on_expected_edge {
        return Err(
            OutdoorTransitionTriggerLayoutValidationError::MisalignedTriggerEdge {
                map_id: map_id.as_str().to_string(),
                object_id: object.object_id.clone(),
                source_location_id: source_location.id.as_str().to_string(),
                target_location_id: target_location_id.to_string(),
                expected_edge: edge.trigger_edge_name().to_string(),
                anchor_x: object.anchor.x,
                anchor_y: object.anchor.y,
                anchor_z: object.anchor.z,
                footprint_width: object.footprint.width,
                footprint_height: object.footprint.height,
                rotation: object.rotation,
            },
        );
    }

    let Some(target_map) = maps.get(&target_location.map_id) else {
        return Err(
            OutdoorTransitionTriggerLayoutValidationError::MissingTargetMapDefinition {
                map_id: map_id.as_str().to_string(),
                object_id: object.object_id.clone(),
                source_location_id: source_location.id.as_str().to_string(),
                target_location_id: target_location_id.to_string(),
                target_map_id: target_location.map_id.as_str().to_string(),
            },
        );
    };
    let target_entry_point_id = option
        .return_spawn_id
        .trim()
        .is_empty()
        .then(|| target_location.entry_point_id.as_str())
        .unwrap_or_else(|| option.return_spawn_id.trim());
    let Some(target_entry_point) = target_map
        .entry_points
        .iter()
        .find(|entry| entry.id == target_entry_point_id)
    else {
        return Err(
            OutdoorTransitionTriggerLayoutValidationError::MissingTargetEntryPoint {
                map_id: map_id.as_str().to_string(),
                object_id: object.object_id.clone(),
                source_location_id: source_location.id.as_str().to_string(),
                target_location_id: target_location_id.to_string(),
                target_map_id: target_location.map_id.as_str().to_string(),
                entry_point_id: target_entry_point_id.to_string(),
            },
        );
    };

    let expected_entry_point =
        expected_target_entry_point(edge, target_map.size, target_entry_point, &occupied_cells);
    if target_entry_point.grid.x != expected_entry_point.x
        || target_entry_point.grid.z != expected_entry_point.z
    {
        return Err(
            OutdoorTransitionTriggerLayoutValidationError::MisalignedTargetEntryPoint {
                map_id: map_id.as_str().to_string(),
                object_id: object.object_id.clone(),
                source_location_id: source_location.id.as_str().to_string(),
                target_location_id: target_location_id.to_string(),
                target_map_id: target_location.map_id.as_str().to_string(),
                entry_point_id: target_entry_point.id.clone(),
                expected_edge: edge.target_entry_edge_name().to_string(),
                expected_x: expected_entry_point.x,
                expected_y: expected_entry_point.y,
                expected_z: expected_entry_point.z,
                actual_x: target_entry_point.grid.x,
                actual_y: target_entry_point.grid.y,
                actual_z: target_entry_point.grid.z,
            },
        );
    }

    Ok(())
}

fn find_source_outdoor_location<'a>(
    overworld: &'a OverworldLibrary,
    map_id: &MapId,
) -> Option<(&'a OverworldDefinition, &'a OverworldLocationDefinition)> {
    for (_, definition) in overworld.iter() {
        for location in &definition.locations {
            if location.kind == OverworldLocationKind::Outdoor && location.map_id == *map_id {
                return Some((definition, location));
            }
        }
    }
    None
}

fn find_outdoor_location_by_id<'a>(
    overworld: &'a OverworldDefinition,
    location_id: &str,
) -> Option<&'a OverworldLocationDefinition> {
    overworld.locations.iter().find(|location| {
        location.kind == OverworldLocationKind::Outdoor && location.id.as_str() == location_id
    })
}

fn expected_target_entry_point(
    edge: EdgeDirection,
    target_size: MapSize,
    target_entry_point: &MapEntryPointDefinition,
    trigger_cells: &[GridCoord],
) -> GridCoord {
    let centerline = trigger_centerline(edge, trigger_cells);
    let y = target_entry_point.grid.y;
    match edge {
        EdgeDirection::East => GridCoord::new(
            inside_from_west(target_size.width),
            y,
            clamp_inner_lane(centerline, target_size.height),
        ),
        EdgeDirection::West => GridCoord::new(
            inside_from_east(target_size.width),
            y,
            clamp_inner_lane(centerline, target_size.height),
        ),
        EdgeDirection::South => GridCoord::new(
            clamp_inner_lane(centerline, target_size.width),
            y,
            inside_from_north(target_size.height),
        ),
        EdgeDirection::North => GridCoord::new(
            clamp_inner_lane(centerline, target_size.width),
            y,
            inside_from_south(target_size.height),
        ),
    }
}

fn trigger_centerline(edge: EdgeDirection, trigger_cells: &[GridCoord]) -> i32 {
    let (min_value, max_value) = match edge {
        EdgeDirection::East | EdgeDirection::West => trigger_cells
            .iter()
            .fold((i32::MAX, i32::MIN), |(min_value, max_value), cell| {
                (min_value.min(cell.z), max_value.max(cell.z))
            }),
        EdgeDirection::North | EdgeDirection::South => trigger_cells
            .iter()
            .fold((i32::MAX, i32::MIN), |(min_value, max_value), cell| {
                (min_value.min(cell.x), max_value.max(cell.x))
            }),
    };
    (min_value + max_value) / 2
}

fn clamp_inner_lane(value: i32, axis_size: u32) -> i32 {
    let max_index = axis_size.saturating_sub(1) as i32;
    if max_index <= 1 {
        value.clamp(0, max_index)
    } else {
        value.clamp(1, max_index - 1)
    }
}

fn inside_from_west(axis_size: u32) -> i32 {
    let max_index = axis_size.saturating_sub(1) as i32;
    if max_index <= 0 {
        0
    } else {
        1.min(max_index)
    }
}

fn inside_from_east(axis_size: u32) -> i32 {
    let max_index = axis_size.saturating_sub(1) as i32;
    if max_index <= 0 {
        0
    } else {
        (max_index - 1).max(0)
    }
}

fn inside_from_north(axis_size: u32) -> i32 {
    inside_from_west(axis_size)
}

fn inside_from_south(axis_size: u32) -> i32 {
    inside_from_east(axis_size)
}

#[cfg(test)]
mod tests {
    use super::{
        validate_outdoor_transition_trigger_layout, OutdoorTransitionTriggerLayoutValidationError,
    };
    use crate::{
        GridCoord, InteractionOptionDefinition, InteractionOptionKind, MapDefinition,
        MapEntryPointDefinition, MapId, MapLevelDefinition, MapLibrary, MapObjectDefinition,
        MapObjectFootprint, MapObjectKind, MapObjectProps, MapRotation, MapSize, MapTriggerProps,
        OverworldCellDefinition, OverworldDefinition, OverworldId, OverworldLibrary,
        OverworldLocationDefinition, OverworldLocationId, OverworldLocationKind,
        OverworldTerrainKind,
        OverworldTravelRuleSet,
    };
    use std::collections::BTreeMap;

    #[test]
    fn cardinal_edge_triggers_validate_successfully() {
        for (name, delta, trigger_anchor, trigger_footprint, trigger_rotation, expected_entry) in [
            (
                "east",
                GridCoord::new(1, 0, 0),
                GridCoord::new(11, 0, 8),
                MapObjectFootprint {
                    width: 1,
                    height: 5,
                },
                MapRotation::North,
                GridCoord::new(1, 0, 10),
            ),
            (
                "west",
                GridCoord::new(-1, 0, 0),
                GridCoord::new(0, 0, 8),
                MapObjectFootprint {
                    width: 1,
                    height: 5,
                },
                MapRotation::North,
                GridCoord::new(10, 0, 10),
            ),
            (
                "south",
                GridCoord::new(0, 0, 1),
                GridCoord::new(4, 0, 11),
                MapObjectFootprint {
                    width: 5,
                    height: 1,
                },
                MapRotation::North,
                GridCoord::new(6, 0, 1),
            ),
            (
                "north",
                GridCoord::new(0, 0, -1),
                GridCoord::new(4, 0, 0),
                MapObjectFootprint {
                    width: 5,
                    height: 1,
                },
                MapRotation::North,
                GridCoord::new(6, 0, 10),
            ),
        ] {
            let libraries = sample_libraries(
                delta,
                trigger_anchor,
                trigger_footprint,
                trigger_rotation,
                expected_entry,
            );
            validate_outdoor_transition_trigger_layout(&libraries.maps, &libraries.overworld)
                .unwrap_or_else(|error| panic!("{name} should be valid, got {error}"));
        }
    }

    #[test]
    fn misaligned_edge_trigger_is_rejected() {
        let libraries = sample_libraries(
            GridCoord::new(1, 0, 0),
            GridCoord::new(4, 0, 11),
            MapObjectFootprint {
                width: 5,
                height: 1,
            },
            MapRotation::North,
            GridCoord::new(1, 0, 6),
        );

        let error =
            validate_outdoor_transition_trigger_layout(&libraries.maps, &libraries.overworld)
                .expect_err("south edge placement should be rejected for east neighbor");
        assert!(matches!(
            error,
            OutdoorTransitionTriggerLayoutValidationError::InvalidTriggerStripeOrientation { .. }
                | OutdoorTransitionTriggerLayoutValidationError::MisalignedTriggerEdge { .. }
        ));
    }

    #[test]
    fn east_west_trigger_requires_single_column_stripe() {
        let libraries = sample_libraries(
            GridCoord::new(1, 0, 0),
            GridCoord::new(10, 0, 8),
            MapObjectFootprint {
                width: 2,
                height: 5,
            },
            MapRotation::North,
            GridCoord::new(1, 0, 10),
        );

        let error =
            validate_outdoor_transition_trigger_layout(&libraries.maps, &libraries.overworld)
                .expect_err("east neighbor trigger must be a single column");
        assert!(matches!(
            error,
            OutdoorTransitionTriggerLayoutValidationError::InvalidTriggerStripeOrientation { .. }
        ));
    }

    #[test]
    fn north_south_trigger_requires_single_row_stripe() {
        let libraries = sample_libraries(
            GridCoord::new(0, 0, -1),
            GridCoord::new(4, 0, 0),
            MapObjectFootprint {
                width: 5,
                height: 2,
            },
            MapRotation::North,
            GridCoord::new(6, 0, 10),
        );

        let error =
            validate_outdoor_transition_trigger_layout(&libraries.maps, &libraries.overworld)
                .expect_err("north neighbor trigger must be a single row");
        assert!(matches!(
            error,
            OutdoorTransitionTriggerLayoutValidationError::InvalidTriggerStripeOrientation { .. }
        ));
    }

    #[test]
    fn non_adjacent_target_location_is_rejected() {
        let libraries = sample_libraries(
            GridCoord::new(2, 0, 0),
            GridCoord::new(11, 0, 8),
            MapObjectFootprint {
                width: 1,
                height: 5,
            },
            MapRotation::North,
            GridCoord::new(1, 0, 10),
        );

        let error =
            validate_outdoor_transition_trigger_layout(&libraries.maps, &libraries.overworld)
                .expect_err("non-adjacent target should be rejected");
        assert!(matches!(
            error,
            OutdoorTransitionTriggerLayoutValidationError::NonAdjacentOutdoorLocations { .. }
        ));
    }

    #[test]
    fn misaligned_target_entry_point_is_rejected() {
        let libraries = sample_libraries(
            GridCoord::new(1, 0, 0),
            GridCoord::new(11, 0, 8),
            MapObjectFootprint {
                width: 1,
                height: 5,
            },
            MapRotation::North,
            GridCoord::new(1, 0, 1),
        );

        let error =
            validate_outdoor_transition_trigger_layout(&libraries.maps, &libraries.overworld)
                .expect_err("misaligned target entry point should be rejected");
        assert!(matches!(
            error,
            OutdoorTransitionTriggerLayoutValidationError::MisalignedTargetEntryPoint { .. }
        ));
    }

    #[test]
    fn trigger_return_spawn_id_overrides_target_location_default_entry_point() {
        let source_map = sample_map(
            "source_map",
            vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(1, 0, 1),
                facing: None,
                extra: BTreeMap::new(),
            }],
            vec![MapObjectDefinition {
                object_id: "to_target".into(),
                kind: MapObjectKind::Trigger,
                anchor: GridCoord::new(11, 0, 8),
                footprint: MapObjectFootprint {
                    width: 1,
                    height: 5,
                },
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    trigger: Some(MapTriggerProps {
                        display_name: "Return".into(),
                        interaction_distance: 1.4,
                        interaction_kind: String::new(),
                        target_id: None,
                        options: vec![InteractionOptionDefinition {
                            id: crate::InteractionOptionId("enter_outdoor_location".into()),
                            display_name: "Return".into(),
                            kind: InteractionOptionKind::EnterOutdoorLocation,
                            target_id: "target".into(),
                            return_spawn_id: "return_gate".into(),
                            ..InteractionOptionDefinition::default()
                        }],
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        );
        let target_map = sample_map(
            "target_map",
            vec![
                MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(5, 0, 5),
                    facing: None,
                    extra: BTreeMap::new(),
                },
                MapEntryPointDefinition {
                    id: "return_gate".into(),
                    grid: GridCoord::new(1, 0, 10),
                    facing: None,
                    extra: BTreeMap::new(),
                },
            ],
            Vec::new(),
        );
        let maps = MapLibrary::from(BTreeMap::from([
            (source_map.id.clone(), source_map),
            (target_map.id.clone(), target_map),
        ]));
        let overworld = OverworldLibrary::from(BTreeMap::from([(
            OverworldId("main".into()),
            OverworldDefinition {
                id: OverworldId("main".into()),
                size: MapSize {
                    width: 2,
                    height: 1,
                },
                locations: vec![
                    OverworldLocationDefinition {
                        id: OverworldLocationId("source".into()),
                        name: "Source".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Outdoor,
                        map_id: MapId("source_map".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: None,
                        return_entry_point_id: None,
                        default_unlocked: true,
                        visible: true,
                        overworld_cell: GridCoord::new(0, 0, 0),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                    OverworldLocationDefinition {
                        id: OverworldLocationId("target".into()),
                        name: "Target".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Outdoor,
                        map_id: MapId("target_map".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: None,
                        return_entry_point_id: None,
                        default_unlocked: true,
                        visible: true,
                        overworld_cell: GridCoord::new(1, 0, 0),
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                ],
                cells: vec![
                    OverworldCellDefinition {
                        grid: GridCoord::new(0, 0, 0),
                        terrain: OverworldTerrainKind::Plain,
                        blocked: false,
                        extra: BTreeMap::new(),
                    },
                    OverworldCellDefinition {
                        grid: GridCoord::new(1, 0, 0),
                        terrain: OverworldTerrainKind::Plain,
                        blocked: false,
                        extra: BTreeMap::new(),
                    },
                ],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]));

        validate_outdoor_transition_trigger_layout(&maps, &overworld)
            .expect("return spawn override should be honored");
    }

    struct SampleLibraries {
        maps: MapLibrary,
        overworld: OverworldLibrary,
    }

    fn sample_libraries(
        target_delta: GridCoord,
        trigger_anchor: GridCoord,
        trigger_footprint: MapObjectFootprint,
        trigger_rotation: MapRotation,
        target_entry: GridCoord,
    ) -> SampleLibraries {
        let source_cell = GridCoord::new(2 - target_delta.x.min(0), 0, 2 - target_delta.z.min(0));
        let target_cell = GridCoord::new(
            source_cell.x + target_delta.x,
            0,
            source_cell.z + target_delta.z,
        );
        let size = MapSize {
            width: (source_cell.x.max(target_cell.x) + 3) as u32,
            height: (source_cell.z.max(target_cell.z) + 3) as u32,
        };
        let source_map = sample_map(
            "source_map",
            vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(1, 0, 1),
                facing: None,
                extra: BTreeMap::new(),
            }],
            vec![MapObjectDefinition {
                object_id: "to_target".into(),
                kind: MapObjectKind::Trigger,
                anchor: trigger_anchor,
                footprint: trigger_footprint,
                rotation: trigger_rotation,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    trigger: Some(MapTriggerProps {
                        display_name: "Go".into(),
                        interaction_distance: 1.4,
                        interaction_kind: "enter_outdoor_location".into(),
                        target_id: Some("target".into()),
                        options: Vec::new(),
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        );
        let target_map = sample_map(
            "target_map",
            vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: target_entry,
                facing: None,
                extra: BTreeMap::new(),
            }],
            Vec::new(),
        );

        let maps = MapLibrary::from(BTreeMap::from([
            (source_map.id.clone(), source_map),
            (target_map.id.clone(), target_map),
        ]));
        let overworld = OverworldLibrary::from(BTreeMap::from([(
            OverworldId("main".into()),
            OverworldDefinition {
                id: OverworldId("main".into()),
                locations: vec![
                    OverworldLocationDefinition {
                        id: OverworldLocationId("source".into()),
                        name: "Source".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Outdoor,
                        map_id: MapId("source_map".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: None,
                        return_entry_point_id: None,
                        default_unlocked: true,
                        visible: true,
                        overworld_cell: source_cell,
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                    OverworldLocationDefinition {
                        id: OverworldLocationId("target".into()),
                        name: "Target".into(),
                        description: String::new(),
                        kind: OverworldLocationKind::Outdoor,
                        map_id: MapId("target_map".into()),
                        entry_point_id: "default_entry".into(),
                        parent_outdoor_location_id: None,
                        return_entry_point_id: None,
                        default_unlocked: true,
                        visible: true,
                        overworld_cell: target_cell,
                        danger_level: 0,
                        icon: String::new(),
                        extra: BTreeMap::new(),
                    },
                ],
                size,
                cells: sample_overworld_cells(size),
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]));

        SampleLibraries { maps, overworld }
    }

    fn sample_map(
        id: &str,
        entry_points: Vec<MapEntryPointDefinition>,
        objects: Vec<MapObjectDefinition>,
    ) -> MapDefinition {
        MapDefinition {
            id: MapId(id.into()),
            name: id.into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points,
            objects,
        }
    }

    fn sample_overworld_cells(size: MapSize) -> Vec<OverworldCellDefinition> {
        let mut cells = Vec::new();
        for z in 0..size.height as i32 {
            for x in 0..size.width as i32 {
                cells.push(OverworldCellDefinition {
                    grid: GridCoord::new(x, 0, z),
                    terrain: OverworldTerrainKind::Plain,
                    blocked: false,
                    extra: BTreeMap::new(),
                });
            }
        }
        cells
    }
}
