//! 静态世界场景组装的门面模块，统一导出场景生成入口与共享类型。

mod geometry;
mod map_scene;
mod overworld;
mod types;

pub use map_scene::{
    build_static_world_from_map_definition, build_static_world_from_simulation_snapshot,
};
pub use overworld::build_static_world_from_overworld_definition;
pub use types::*;

#[cfg(test)]
pub(crate) use map_scene::build_static_world_from_topology;
#[cfg(test)]
pub(crate) use overworld::{
    is_overworld_location_material_role, push_overworld_location_marker_boxes,
};
#[cfg(test)]
pub(crate) use types::{OverworldLocationMarkerArchetype, StaticMapTopology};

#[cfg(test)]
mod tests;
