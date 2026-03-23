pub mod character;
pub mod content;
pub mod map;
pub mod models;

use bevy_app::prelude::*;

pub use character::{
    load_character_library, validate_character_definition, CharacterAiProfile, CharacterArchetype,
    CharacterAttributeTemplate, CharacterCombatProfile, CharacterDefinition,
    CharacterDefinitionValidationError, CharacterDisposition, CharacterFaction, CharacterId,
    CharacterIdentity, CharacterLibrary, CharacterLoadError, CharacterLootEntry,
    CharacterPlaceholderColors, CharacterPresentation, CharacterProgression, CharacterResourcePool,
};
pub use content::{
    ArmorData, ConsumableData, DialogueAction, DialogueConnection, DialogueData, DialogueNode,
    DialogueOption, DialoguePosition, ItemData, WeaponData,
};
pub use map::{
    expand_object_footprint, load_map_library, load_map_library_with_catalog,
    object_effectively_blocks_movement, object_effectively_blocks_sight, rotated_footprint_size,
    validate_map_definition, MapAiSpawnProps, MapBuildingProps, MapCellDefinition, MapDefinition,
    MapDefinitionValidationError, MapId, MapInteractiveProps, MapLibrary, MapLevelDefinition,
    MapLoadError, MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps,
    MapPickupProps, MapRotation, MapSize, MapValidationCatalog,
};
pub use models::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, ActorKind, ActorSide, GridCoord,
    TurnState, WorldCoord,
};

pub struct GameDataPlugin;

impl Plugin for GameDataPlugin {
    fn build(&self, _app: &mut App) {}
}
