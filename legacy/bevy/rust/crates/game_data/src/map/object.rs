//! 地图对象的纯辅助逻辑，负责 footprint 展开与阻挡规则判定。

use std::collections::BTreeSet;

use crate::GridCoord;

use super::types::{MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapRotation};

pub fn expand_object_footprint(object: &MapObjectDefinition) -> Vec<GridCoord> {
    let (width, height) = rotated_footprint_size(object.footprint, object.rotation);
    let mut cells = Vec::with_capacity((width * height) as usize);
    for dz in 0..height as i32 {
        for dx in 0..width as i32 {
            cells.push(GridCoord::new(
                object.anchor.x + dx,
                object.anchor.y,
                object.anchor.z + dz,
            ));
        }
    }
    cells
}

pub fn rotated_footprint_size(footprint: MapObjectFootprint, rotation: MapRotation) -> (u32, u32) {
    match rotation {
        MapRotation::North | MapRotation::South => (footprint.width, footprint.height),
        MapRotation::East | MapRotation::West => (footprint.height, footprint.width),
    }
}

pub fn object_effectively_blocks_movement(object: &MapObjectDefinition) -> bool {
    object.blocks_movement
        || matches!(object.kind, MapObjectKind::Building)
            && object
                .props
                .building
                .as_ref()
                .and_then(|building| building.layout.as_ref())
                .is_none()
}

pub fn object_effectively_blocks_sight(object: &MapObjectDefinition) -> bool {
    object.blocks_sight
        || matches!(object.kind, MapObjectKind::Building)
            && object
                .props
                .building
                .as_ref()
                .and_then(|building| building.layout.as_ref())
                .is_none()
}

pub fn building_layout_story_levels(object: &MapObjectDefinition) -> BTreeSet<i32> {
    object
        .props
        .building
        .as_ref()
        .and_then(|building| building.layout.as_ref())
        .map(|layout| {
            if layout.stories.is_empty() {
                BTreeSet::from([object.anchor.y])
            } else {
                layout.stories.iter().map(|story| story.level).collect()
            }
        })
        .unwrap_or_else(|| BTreeSet::from([object.anchor.y]))
}
