//! 地图出口覆盖校验：防止玩家进入地图后没有任何场景切换出口。

use thiserror::Error;

use crate::interaction::is_scene_transition_kind;

use super::library::MapLibrary;
use super::types::{MapDefinition, MapObjectKind};

#[derive(Debug, Clone, Error, PartialEq, Eq)]
pub enum MapExitCoverageValidationError {
    #[error("map {map_id} must define at least one scene transition trigger exit")]
    MissingMapExit { map_id: String },
}

pub fn validate_map_exit_coverage(maps: &MapLibrary) -> Result<(), MapExitCoverageValidationError> {
    for (map_id, definition) in maps.iter() {
        if !map_has_scene_transition_exit(definition) {
            return Err(MapExitCoverageValidationError::MissingMapExit {
                map_id: map_id.as_str().to_string(),
            });
        }
    }

    Ok(())
}

fn map_has_scene_transition_exit(definition: &MapDefinition) -> bool {
    definition.objects.iter().any(|object| {
        if object.kind != MapObjectKind::Trigger {
            return false;
        }
        object.props.trigger.as_ref().is_some_and(|trigger| {
            // 使用 resolved_options 覆盖 legacy 字段和新 options 两种写法。
            trigger
                .resolved_options()
                .into_iter()
                .any(|option| is_scene_transition_kind(option.kind))
        })
    })
}
