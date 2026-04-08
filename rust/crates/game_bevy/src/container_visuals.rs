use std::collections::HashMap;

use bevy::prelude::*;

#[derive(Debug, Clone)]
pub struct ContainerVisualDefinition {
    pub scene_path: String,
    pub scale: Vec3,
    pub translation_offset: Vec3,
    pub rotation_offset: Quat,
}

impl ContainerVisualDefinition {
    pub fn new(
        scene_path: impl Into<String>,
        scale: Vec3,
        translation_offset: Vec3,
        rotation_offset: Quat,
    ) -> Self {
        Self {
            scene_path: scene_path.into(),
            scale,
            translation_offset,
            rotation_offset,
        }
    }
}

#[derive(Resource, Debug, Clone)]
pub struct ContainerVisualRegistry {
    definitions: HashMap<String, ContainerVisualDefinition>,
}

impl ContainerVisualRegistry {
    pub fn new(definitions: HashMap<String, ContainerVisualDefinition>) -> Self {
        Self { definitions }
    }

    pub fn builtin() -> Self {
        let mut definitions = HashMap::new();
        definitions.insert(
            "crate_wood".to_string(),
            ContainerVisualDefinition::new(
                "container_placeholders/crate_wood.gltf",
                Vec3::splat(0.92),
                Vec3::new(0.0, 0.0, 0.0),
                Quat::IDENTITY,
            ),
        );
        definitions.insert(
            "locker_metal".to_string(),
            ContainerVisualDefinition::new(
                "container_placeholders/locker_metal.gltf",
                Vec3::splat(0.68),
                Vec3::new(0.0, 0.0, 0.0),
                Quat::IDENTITY,
            ),
        );
        definitions.insert(
            "cabinet_medical".to_string(),
            ContainerVisualDefinition::new(
                "container_placeholders/cabinet_medical.gltf",
                Vec3::splat(0.74),
                Vec3::new(0.0, 0.0, 0.0),
                Quat::IDENTITY,
            ),
        );
        Self::new(definitions)
    }

    pub fn get(&self, visual_id: &str) -> Option<&ContainerVisualDefinition> {
        self.definitions.get(visual_id)
    }

    pub fn contains(&self, visual_id: &str) -> bool {
        self.definitions.contains_key(visual_id)
    }
}

impl Default for ContainerVisualRegistry {
    fn default() -> Self {
        Self::builtin()
    }
}
