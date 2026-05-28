//! 地图定义的结构与引用校验逻辑，保证共享内容进入运行时前合法。

use std::collections::{BTreeSet, HashMap, HashSet};

use thiserror::Error;

use crate::interaction::{default_option_id_for_kind, is_scene_transition_kind};
use crate::GridCoord;

use super::interaction::{
    resolve_interactive_object_options, resolved_option_id, validate_interaction_option,
};
use super::object::{
    building_layout_story_levels, expand_object_footprint, object_effectively_blocks_movement,
};
use super::types::{
    MapBuildingLayoutSpec, MapCellDefinition, MapDefinition, MapObjectDefinition, MapObjectKind,
    MapSize,
};

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MapValidationCatalog {
    pub item_ids: BTreeSet<String>,
    pub character_ids: BTreeSet<String>,
    pub prototype_ids: BTreeSet<String>,
    pub wall_set_ids: BTreeSet<String>,
    pub surface_set_ids: BTreeSet<String>,
}

#[derive(Debug, Clone, Error, PartialEq)]
pub enum MapDefinitionValidationError {
    #[error("map id must not be empty")]
    MissingId,
    #[error("map size width and height must be > 0, got {width}x{height}")]
    InvalidSize { width: u32, height: u32 },
    #[error("default level {y} does not exist in levels")]
    MissingDefaultLevel { y: i32 },
    #[error("duplicate level y {y}")]
    DuplicateLevel { y: i32 },
    #[error("entry point id must not be empty")]
    MissingEntryPointId,
    #[error("duplicate entry point id {entry_point_id}")]
    DuplicateEntryPointId { entry_point_id: String },
    #[error("entry point {entry_point_id} uses missing level {y}")]
    UnknownEntryPointLevel { entry_point_id: String, y: i32 },
    #[error(
        "entry point {entry_point_id} grid ({x}, {y}, {z}) is outside map bounds {width}x{height}"
    )]
    EntryPointOutOfBounds {
        entry_point_id: String,
        x: i32,
        y: i32,
        z: i32,
        width: u32,
        height: u32,
    },
    #[error("duplicate cell at ({x}, {y}, {z})")]
    DuplicateCell { x: u32, y: i32, z: u32 },
    #[error("cell ({x}, {y}, {z}) is outside map bounds {width}x{height}")]
    CellOutOfBounds {
        x: u32,
        y: i32,
        z: u32,
        width: u32,
        height: u32,
    },
    #[error("object id must not be empty")]
    MissingObjectId,
    #[error("duplicate object id {object_id}")]
    DuplicateObjectId { object_id: String },
    #[error("object {object_id} uses missing level {y}")]
    UnknownObjectLevel { object_id: String, y: i32 },
    #[error("object {object_id} anchor ({x}, {y}, {z}) is outside map bounds {width}x{height}")]
    ObjectAnchorOutOfBounds {
        object_id: String,
        x: i32,
        y: i32,
        z: i32,
        width: u32,
        height: u32,
    },
    #[error("object {object_id} footprint must be > 0, got {width}x{height}")]
    InvalidFootprint {
        object_id: String,
        width: u32,
        height: u32,
    },
    #[error(
        "object {object_id} footprint cell ({x}, {y}, {z}) is outside map bounds {width}x{height}"
    )]
    ObjectFootprintOutOfBounds {
        object_id: String,
        x: i32,
        y: i32,
        z: i32,
        width: u32,
        height: u32,
    },
    #[error(
        "blocking objects {first_object_id} and {second_object_id} overlap at ({x}, {y}, {z})"
    )]
    OverlappingBlockingObjects {
        first_object_id: String,
        second_object_id: String,
        x: i32,
        y: i32,
        z: i32,
    },
    #[error("building object {object_id} must define props.building.prefab_id")]
    MissingBuildingPrefabId { object_id: String },
    #[error("building object {object_id} must define props.building.wall_visual.kind")]
    MissingBuildingWallVisualKind { object_id: String },
    #[error("building object {object_id} must define props.building.tile_set.wall_set_id")]
    MissingBuildingWallTileSetId { object_id: String },
    #[error("building object {object_id} wall_set_id {wall_set_id} was not found in the world tile catalog")]
    UnknownBuildingWallTileSetId {
        object_id: String,
        wall_set_id: String,
    },
    #[error("building object {object_id} floor_surface_set_id {surface_set_id} was not found in the world tile catalog")]
    UnknownBuildingFloorSurfaceSetId {
        object_id: String,
        surface_set_id: String,
    },
    #[error("building object {object_id} door_prototype_id {prototype_id} was not found in the world tile catalog")]
    UnknownBuildingDoorPrototypeId {
        object_id: String,
        prototype_id: String,
    },
    #[error("building object {object_id} layout target_room_count must be > 0")]
    InvalidBuildingTargetRoomCount { object_id: String },
    #[error(
        "building object {object_id} layout min_room_size/max_room_size/min_room_area must be valid"
    )]
    InvalidBuildingRoomSize { object_id: String },
    #[error(
        "building object {object_id} footprint polygon must contain at least 3 distinct vertices"
    )]
    InvalidBuildingFootprintPolygon { object_id: String },
    #[error(
        "building object {object_id} geometry parameters wall_thickness/wall_height/door_width must be > 0"
    )]
    InvalidBuildingGeometryParameters { object_id: String },
    #[error("building object {object_id} layout stories contain duplicate level {level}")]
    DuplicateBuildingStoryLevel { object_id: String, level: i32 },
    #[error(
        "building object {object_id} stair from_level={from_level} to_level={to_level} must reference existing stories"
    )]
    InvalidBuildingStairLevels {
        object_id: String,
        from_level: i32,
        to_level: i32,
    },
    #[error("building object {object_id} stair endpoints must not be empty")]
    EmptyBuildingStairEndpoints { object_id: String },
    #[error("building object {object_id} stair width must be > 0")]
    InvalidBuildingStairWidth { object_id: String },
    #[error(
        "building object {object_id} stair endpoint counts must match and be at least width={width}"
    )]
    InvalidBuildingStairEndpointCount { object_id: String, width: u32 },
    #[error(
        "building object {object_id} visual outline edge level {level} must reference an existing story"
    )]
    InvalidBuildingVisualOutlineLevel { object_id: String, level: i32 },
    #[error("building object {object_id} visual outline edge must use distinct vertices")]
    InvalidBuildingVisualOutlineEdge { object_id: String },
    #[error("pickup object {object_id} must define props.pickup.item_id")]
    MissingPickupItemId { object_id: String },
    #[error("pickup object {object_id} item_id {item_id} was not found in the item catalog")]
    UnknownPickupItemId { object_id: String, item_id: String },
    #[error("pickup object {object_id} has invalid count range {min_count}..{max_count}")]
    InvalidPickupCountRange {
        object_id: String,
        min_count: i32,
        max_count: i32,
    },
    #[error("interactive object {object_id} must define props.interactive.interaction_kind")]
    MissingInteractiveKind { object_id: String },
    #[error("container object {object_id} item_id must not be empty")]
    MissingContainerItemId { object_id: String },
    #[error("container object {object_id} item_id {item_id} was not found in the item catalog")]
    UnknownContainerItemId { object_id: String, item_id: String },
    #[error("container object {object_id} item {item_id} has invalid count {count}")]
    InvalidContainerItemCount {
        object_id: String,
        item_id: String,
        count: i32,
    },
    #[error("container object {object_id} visual_id must not be blank")]
    InvalidContainerVisualId { object_id: String },
    #[error("object {object_id} visual.prototype_id must not be blank")]
    MissingObjectVisualPrototypeId { object_id: String },
    #[error("object {object_id} visual.prototype_id {prototype_id} was not found in the world tile catalog")]
    UnknownObjectVisualPrototypeId {
        object_id: String,
        prototype_id: String,
    },
    #[error("cell ({x}, {y}, {z}) surface_set_id {surface_set_id} was not found in the world tile catalog")]
    UnknownCellSurfaceSetId {
        x: u32,
        y: i32,
        z: u32,
        surface_set_id: String,
    },
    #[error("trigger object {object_id} must define props.trigger.interaction_kind")]
    MissingTriggerKind { object_id: String },
    #[error(
        "{object_kind} object {object_id} option {option_id} uses an invalid distance {distance}"
    )]
    InvalidInteractionDistance {
        object_id: String,
        object_kind: &'static str,
        option_id: String,
        distance: f32,
    },
    #[error(
        "{object_kind} object {object_id} option {option_id} pickup item_id must not be empty"
    )]
    MissingInteractionPickupItemId {
        object_id: String,
        object_kind: &'static str,
        option_id: String,
    },
    #[error("{object_kind} object {object_id} option {option_id} target_id must not be empty")]
    MissingInteractionTargetId {
        object_id: String,
        object_kind: &'static str,
        option_id: String,
    },
    #[error(
        "trigger object {object_id} option {option_id} must use a scene transition kind, got {kind}"
    )]
    InvalidTriggerOptionKind {
        object_id: String,
        option_id: String,
        kind: String,
    },
    #[error("ai_spawn object {object_id} must define props.ai_spawn.spawn_id")]
    MissingAiSpawnId { object_id: String },
    #[error("duplicate ai spawn id {spawn_id}")]
    DuplicateAiSpawnId { spawn_id: String },
    #[error("ai_spawn object {object_id} must define props.ai_spawn.character_id")]
    MissingAiSpawnCharacterId { object_id: String },
    #[error(
        "ai_spawn object {object_id} character_id {character_id} was not found in the character catalog"
    )]
    UnknownAiSpawnCharacterId {
        object_id: String,
        character_id: String,
    },
    #[error("ai_spawn object {object_id} respawn_delay must be >= 0, got {respawn_delay}")]
    InvalidAiRespawnDelay {
        object_id: String,
        respawn_delay: f32,
    },
    #[error("ai_spawn object {object_id} spawn_radius must be >= 0, got {spawn_radius}")]
    InvalidAiSpawnRadius {
        object_id: String,
        spawn_radius: f32,
    },
}

pub fn validate_map_definition(
    definition: &MapDefinition,
    catalog: Option<&MapValidationCatalog>,
) -> Result<(), MapDefinitionValidationError> {
    if definition.id.as_str().trim().is_empty() {
        return Err(MapDefinitionValidationError::MissingId);
    }

    if definition.size.width == 0 || definition.size.height == 0 {
        return Err(MapDefinitionValidationError::InvalidSize {
            width: definition.size.width,
            height: definition.size.height,
        });
    }

    let mut levels = BTreeSet::new();
    let mut seen_cells = HashSet::new();
    let mut seen_entry_points = HashSet::new();
    for level in &definition.levels {
        if !levels.insert(level.y) {
            return Err(MapDefinitionValidationError::DuplicateLevel { y: level.y });
        }

        for cell in &level.cells {
            if cell.x >= definition.size.width || cell.z >= definition.size.height {
                return Err(MapDefinitionValidationError::CellOutOfBounds {
                    x: cell.x,
                    y: level.y,
                    z: cell.z,
                    width: definition.size.width,
                    height: definition.size.height,
                });
            }

            if !seen_cells.insert((cell.x, level.y, cell.z)) {
                return Err(MapDefinitionValidationError::DuplicateCell {
                    x: cell.x,
                    y: level.y,
                    z: cell.z,
                });
            }
            validate_cell_visual_spec(cell, level.y, catalog)?;
        }
    }

    if !levels.contains(&definition.default_level) {
        return Err(MapDefinitionValidationError::MissingDefaultLevel {
            y: definition.default_level,
        });
    }

    for entry_point in &definition.entry_points {
        if entry_point.id.trim().is_empty() {
            return Err(MapDefinitionValidationError::MissingEntryPointId);
        }
        if !seen_entry_points.insert(entry_point.id.clone()) {
            return Err(MapDefinitionValidationError::DuplicateEntryPointId {
                entry_point_id: entry_point.id.clone(),
            });
        }
        if !levels.contains(&entry_point.grid.y) {
            return Err(MapDefinitionValidationError::UnknownEntryPointLevel {
                entry_point_id: entry_point.id.clone(),
                y: entry_point.grid.y,
            });
        }
        if !grid_in_bounds(entry_point.grid, definition.size) {
            return Err(MapDefinitionValidationError::EntryPointOutOfBounds {
                entry_point_id: entry_point.id.clone(),
                x: entry_point.grid.x,
                y: entry_point.grid.y,
                z: entry_point.grid.z,
                width: definition.size.width,
                height: definition.size.height,
            });
        }
    }

    let mut seen_object_ids = HashSet::new();
    let mut seen_spawn_ids = HashSet::new();
    let mut blocking_cells = HashMap::<GridCoord, String>::new();

    for object in &definition.objects {
        if object.object_id.trim().is_empty() {
            return Err(MapDefinitionValidationError::MissingObjectId);
        }
        if !seen_object_ids.insert(object.object_id.clone()) {
            return Err(MapDefinitionValidationError::DuplicateObjectId {
                object_id: object.object_id.clone(),
            });
        }
        if !levels.contains(&object.anchor.y) {
            return Err(MapDefinitionValidationError::UnknownObjectLevel {
                object_id: object.object_id.clone(),
                y: object.anchor.y,
            });
        }
        if !grid_in_bounds(object.anchor, definition.size) {
            return Err(MapDefinitionValidationError::ObjectAnchorOutOfBounds {
                object_id: object.object_id.clone(),
                x: object.anchor.x,
                y: object.anchor.y,
                z: object.anchor.z,
                width: definition.size.width,
                height: definition.size.height,
            });
        }
        if object.footprint.width == 0 || object.footprint.height == 0 {
            return Err(MapDefinitionValidationError::InvalidFootprint {
                object_id: object.object_id.clone(),
                width: object.footprint.width,
                height: object.footprint.height,
            });
        }

        for cell in expand_object_footprint(object) {
            if !grid_in_bounds(cell, definition.size) {
                return Err(MapDefinitionValidationError::ObjectFootprintOutOfBounds {
                    object_id: object.object_id.clone(),
                    x: cell.x,
                    y: cell.y,
                    z: cell.z,
                    width: definition.size.width,
                    height: definition.size.height,
                });
            }
            if object_effectively_blocks_movement(object) {
                if let Some(first_object_id) = blocking_cells.insert(cell, object.object_id.clone())
                {
                    return Err(MapDefinitionValidationError::OverlappingBlockingObjects {
                        first_object_id,
                        second_object_id: object.object_id.clone(),
                        x: cell.x,
                        y: cell.y,
                        z: cell.z,
                    });
                }
            }
        }

        validate_object_payload(object, catalog, &mut seen_spawn_ids)?;
    }

    Ok(())
}

fn validate_building_layout(
    object: &MapObjectDefinition,
    layout: &MapBuildingLayoutSpec,
) -> Result<(), MapDefinitionValidationError> {
    if layout.target_room_count == 0 {
        return Err(
            MapDefinitionValidationError::InvalidBuildingTargetRoomCount {
                object_id: object.object_id.clone(),
            },
        );
    }

    let min = layout.min_room_size;
    let max = layout.max_room_size.unwrap_or(layout.min_room_size);
    if min.width == 0
        || min.height == 0
        || layout.min_room_area == 0
        || max.width == 0
        || max.height == 0
        || max.width < min.width
        || max.height < min.height
    {
        return Err(MapDefinitionValidationError::InvalidBuildingRoomSize {
            object_id: object.object_id.clone(),
        });
    }
    if layout.wall_thickness <= 0.0 || layout.wall_height <= 0.0 || layout.door_width <= 0.0 {
        return Err(
            MapDefinitionValidationError::InvalidBuildingGeometryParameters {
                object_id: object.object_id.clone(),
            },
        );
    }
    if let Some(footprint_polygon) = layout.footprint_polygon.as_ref() {
        let distinct_vertices = footprint_polygon
            .outer
            .iter()
            .copied()
            .collect::<HashSet<_>>();
        if footprint_polygon.outer.len() < 3 || distinct_vertices.len() < 3 {
            return Err(
                MapDefinitionValidationError::InvalidBuildingFootprintPolygon {
                    object_id: object.object_id.clone(),
                },
            );
        }
    }

    let story_levels = building_layout_story_levels(object);
    let mut seen_story_levels = HashSet::new();
    for story in &layout.stories {
        if !seen_story_levels.insert(story.level) {
            return Err(MapDefinitionValidationError::DuplicateBuildingStoryLevel {
                object_id: object.object_id.clone(),
                level: story.level,
            });
        }
    }

    for stair in &layout.stairs {
        if stair.width == 0 {
            return Err(MapDefinitionValidationError::InvalidBuildingStairWidth {
                object_id: object.object_id.clone(),
            });
        }
        if stair.from_cells.is_empty() || stair.to_cells.is_empty() {
            return Err(MapDefinitionValidationError::EmptyBuildingStairEndpoints {
                object_id: object.object_id.clone(),
            });
        }
        if stair.from_cells.len() != stair.to_cells.len()
            || stair.from_cells.len() < stair.width as usize
        {
            return Err(
                MapDefinitionValidationError::InvalidBuildingStairEndpointCount {
                    object_id: object.object_id.clone(),
                    width: stair.width,
                },
            );
        }
        if !story_levels.contains(&stair.from_level) || !story_levels.contains(&stair.to_level) {
            return Err(MapDefinitionValidationError::InvalidBuildingStairLevels {
                object_id: object.object_id.clone(),
                from_level: stair.from_level,
                to_level: stair.to_level,
            });
        }
    }

    if let Some(outline) = layout.visual_outline.as_ref() {
        for edge in &outline.diagonal_edges {
            if edge.from == edge.to {
                return Err(
                    MapDefinitionValidationError::InvalidBuildingVisualOutlineEdge {
                        object_id: object.object_id.clone(),
                    },
                );
            }
            if !story_levels.contains(&edge.level) {
                return Err(
                    MapDefinitionValidationError::InvalidBuildingVisualOutlineLevel {
                        object_id: object.object_id.clone(),
                        level: edge.level,
                    },
                );
            }
        }
    }

    Ok(())
}

fn validate_object_payload(
    object: &MapObjectDefinition,
    catalog: Option<&MapValidationCatalog>,
    seen_spawn_ids: &mut HashSet<String>,
) -> Result<(), MapDefinitionValidationError> {
    match object.kind {
        MapObjectKind::Building => {
            let Some(building) = object.props.building.as_ref() else {
                return Err(MapDefinitionValidationError::MissingBuildingPrefabId {
                    object_id: object.object_id.clone(),
                });
            };
            if building.prefab_id.trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingBuildingPrefabId {
                    object_id: object.object_id.clone(),
                });
            }
            if building.wall_visual.is_none() {
                return Err(
                    MapDefinitionValidationError::MissingBuildingWallVisualKind {
                        object_id: object.object_id.clone(),
                    },
                );
            }
            let Some(tile_set) = building.tile_set.as_ref() else {
                return Err(MapDefinitionValidationError::MissingBuildingWallTileSetId {
                    object_id: object.object_id.clone(),
                });
            };
            if tile_set.wall_set_id.as_str().trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingBuildingWallTileSetId {
                    object_id: object.object_id.clone(),
                });
            }
            if let Some(catalog) = catalog {
                if !catalog.wall_set_ids.is_empty()
                    && !catalog.wall_set_ids.contains(tile_set.wall_set_id.as_str())
                {
                    return Err(MapDefinitionValidationError::UnknownBuildingWallTileSetId {
                        object_id: object.object_id.clone(),
                        wall_set_id: tile_set.wall_set_id.as_str().to_string(),
                    });
                }
                if let Some(surface_set_id) = tile_set.floor_surface_set_id.as_ref() {
                    if !catalog.surface_set_ids.is_empty()
                        && !catalog.surface_set_ids.contains(surface_set_id.as_str())
                    {
                        return Err(
                            MapDefinitionValidationError::UnknownBuildingFloorSurfaceSetId {
                                object_id: object.object_id.clone(),
                                surface_set_id: surface_set_id.as_str().to_string(),
                            },
                        );
                    }
                }
                if let Some(prototype_id) = tile_set.door_prototype_id.as_ref() {
                    if !catalog.prototype_ids.is_empty()
                        && !catalog.prototype_ids.contains(prototype_id.as_str())
                    {
                        return Err(
                            MapDefinitionValidationError::UnknownBuildingDoorPrototypeId {
                                object_id: object.object_id.clone(),
                                prototype_id: prototype_id.as_str().to_string(),
                            },
                        );
                    }
                }
            }
            if let Some(layout) = building.layout.as_ref() {
                validate_building_layout(object, layout)?;
            }
        }
        MapObjectKind::Pickup => {
            let Some(pickup) = object.props.pickup.as_ref() else {
                return Err(MapDefinitionValidationError::MissingPickupItemId {
                    object_id: object.object_id.clone(),
                });
            };
            if pickup.item_id.trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingPickupItemId {
                    object_id: object.object_id.clone(),
                });
            }
            if pickup.min_count < 1 || pickup.max_count < pickup.min_count {
                return Err(MapDefinitionValidationError::InvalidPickupCountRange {
                    object_id: object.object_id.clone(),
                    min_count: pickup.min_count,
                    max_count: pickup.max_count,
                });
            }
            if let Some(catalog) = catalog {
                if !catalog.item_ids.contains(pickup.item_id.trim()) {
                    return Err(MapDefinitionValidationError::UnknownPickupItemId {
                        object_id: object.object_id.clone(),
                        item_id: pickup.item_id.clone(),
                    });
                }
            }
        }
        MapObjectKind::Prop => {}
        MapObjectKind::Interactive => {
            let Some(interactive) = object.props.interactive.as_ref() else {
                return Err(MapDefinitionValidationError::MissingInteractiveKind {
                    object_id: object.object_id.clone(),
                });
            };
            validate_container_payload(object, catalog)?;
            let options = resolve_interactive_object_options(object, interactive);
            if options.is_empty() {
                return Err(MapDefinitionValidationError::MissingInteractiveKind {
                    object_id: object.object_id.clone(),
                });
            }
            for option in options {
                validate_interaction_option(&object.object_id, "interactive", &option)?;
            }
        }
        MapObjectKind::Trigger => {
            let Some(trigger) = object.props.trigger.as_ref() else {
                return Err(MapDefinitionValidationError::MissingTriggerKind {
                    object_id: object.object_id.clone(),
                });
            };
            let options = trigger.resolved_options();
            if options.is_empty() {
                return Err(MapDefinitionValidationError::MissingTriggerKind {
                    object_id: object.object_id.clone(),
                });
            }
            for option in options {
                validate_interaction_option(&object.object_id, "trigger", &option)?;
                if !is_scene_transition_kind(option.kind) {
                    return Err(MapDefinitionValidationError::InvalidTriggerOptionKind {
                        object_id: object.object_id.clone(),
                        option_id: resolved_option_id(&option),
                        kind: default_option_id_for_kind(option.kind),
                    });
                }
            }
        }
        MapObjectKind::AiSpawn => {
            let Some(ai_spawn) = object.props.ai_spawn.as_ref() else {
                return Err(MapDefinitionValidationError::MissingAiSpawnId {
                    object_id: object.object_id.clone(),
                });
            };
            if ai_spawn.spawn_id.trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingAiSpawnId {
                    object_id: object.object_id.clone(),
                });
            }
            if !seen_spawn_ids.insert(ai_spawn.spawn_id.clone()) {
                return Err(MapDefinitionValidationError::DuplicateAiSpawnId {
                    spawn_id: ai_spawn.spawn_id.clone(),
                });
            }
            if ai_spawn.character_id.trim().is_empty() {
                return Err(MapDefinitionValidationError::MissingAiSpawnCharacterId {
                    object_id: object.object_id.clone(),
                });
            }
            if let Some(catalog) = catalog {
                if !catalog.character_ids.contains(ai_spawn.character_id.trim()) {
                    return Err(MapDefinitionValidationError::UnknownAiSpawnCharacterId {
                        object_id: object.object_id.clone(),
                        character_id: ai_spawn.character_id.clone(),
                    });
                }
            }
            if ai_spawn.respawn_delay < 0.0 {
                return Err(MapDefinitionValidationError::InvalidAiRespawnDelay {
                    object_id: object.object_id.clone(),
                    respawn_delay: ai_spawn.respawn_delay,
                });
            }
            if ai_spawn.spawn_radius < 0.0 {
                return Err(MapDefinitionValidationError::InvalidAiSpawnRadius {
                    object_id: object.object_id.clone(),
                    spawn_radius: ai_spawn.spawn_radius,
                });
            }
        }
    }

    validate_object_visual_spec(object, catalog)?;

    Ok(())
}

fn validate_cell_visual_spec(
    cell: &MapCellDefinition,
    level_y: i32,
    catalog: Option<&MapValidationCatalog>,
) -> Result<(), MapDefinitionValidationError> {
    let Some(visual) = cell.visual.as_ref() else {
        return Ok(());
    };
    let Some(surface_set_id) = visual.surface_set_id.as_ref() else {
        return Ok(());
    };
    if surface_set_id.as_str().trim().is_empty() {
        return Err(MapDefinitionValidationError::UnknownCellSurfaceSetId {
            x: cell.x,
            y: level_y,
            z: cell.z,
            surface_set_id: String::new(),
        });
    }
    if let Some(catalog) = catalog {
        if !catalog.surface_set_ids.is_empty()
            && !catalog.surface_set_ids.contains(surface_set_id.as_str())
        {
            return Err(MapDefinitionValidationError::UnknownCellSurfaceSetId {
                x: cell.x,
                y: level_y,
                z: cell.z,
                surface_set_id: surface_set_id.as_str().to_string(),
            });
        }
    }
    Ok(())
}

fn validate_object_visual_spec(
    object: &MapObjectDefinition,
    catalog: Option<&MapValidationCatalog>,
) -> Result<(), MapDefinitionValidationError> {
    let Some(visual) = object.props.visual.as_ref() else {
        return Ok(());
    };
    if visual.prototype_id.as_str().trim().is_empty() {
        return Err(
            MapDefinitionValidationError::MissingObjectVisualPrototypeId {
                object_id: object.object_id.clone(),
            },
        );
    }
    if let Some(catalog) = catalog {
        if !catalog.prototype_ids.is_empty()
            && !catalog.prototype_ids.contains(visual.prototype_id.as_str())
        {
            return Err(
                MapDefinitionValidationError::UnknownObjectVisualPrototypeId {
                    object_id: object.object_id.clone(),
                    prototype_id: visual.prototype_id.as_str().to_string(),
                },
            );
        }
    }
    Ok(())
}

fn grid_in_bounds(grid: GridCoord, size: MapSize) -> bool {
    grid.x >= 0 && grid.z >= 0 && (grid.x as u32) < size.width && (grid.z as u32) < size.height
}

fn validate_container_payload(
    object: &MapObjectDefinition,
    catalog: Option<&MapValidationCatalog>,
) -> Result<(), MapDefinitionValidationError> {
    let Some(container) = object.props.container.as_ref() else {
        return Ok(());
    };

    if container
        .visual_id
        .as_deref()
        .is_some_and(|visual_id| visual_id.trim().is_empty())
    {
        return Err(MapDefinitionValidationError::InvalidContainerVisualId {
            object_id: object.object_id.clone(),
        });
    }

    for entry in &container.initial_inventory {
        if entry.item_id.trim().is_empty() {
            return Err(MapDefinitionValidationError::MissingContainerItemId {
                object_id: object.object_id.clone(),
            });
        }
        if entry.count < 1 {
            return Err(MapDefinitionValidationError::InvalidContainerItemCount {
                object_id: object.object_id.clone(),
                item_id: entry.item_id.clone(),
                count: entry.count,
            });
        }
        if let Some(catalog) = catalog {
            if !catalog.item_ids.contains(entry.item_id.trim()) {
                return Err(MapDefinitionValidationError::UnknownContainerItemId {
                    object_id: object.object_id.clone(),
                    item_id: entry.item_id.clone(),
                });
            }
        }
    }

    Ok(())
}
