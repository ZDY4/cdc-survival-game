pub mod character;
pub mod content;
pub mod map;
pub mod models;
pub mod settlement;

use bevy_app::prelude::*;

pub use character::{
    load_character_library, validate_character_definition, CharacterAiProfile, CharacterArchetype,
    CharacterAttributeTemplate, CharacterCombatProfile, CharacterDefinition,
    CharacterDefinitionValidationError, CharacterDisposition, CharacterFaction, CharacterId,
    CharacterIdentity, CharacterLibrary, CharacterLifeProfile, CharacterLoadError,
    CharacterLootEntry, CharacterPlaceholderColors, CharacterPresentation, CharacterProgression,
    CharacterResourcePool, NeedProfile, NpcRole, ScheduleBlock, ScheduleDay,
};
pub use content::{
    load_effect_library, load_item_library, migrate_legacy_item_value, validate_effect_definition,
    validate_item_definition, CraftingRecipe, DialogueAction, DialogueConnection, DialogueData,
    DialogueNode, DialogueOption, DialoguePosition, EffectDefinition,
    EffectDefinitionValidationError, EffectLibrary, EffectLoadError, GameplayEffectData,
    ItemAmount, ItemDefinition, ItemDefinitionValidationError, ItemFragment, ItemLibrary,
    ItemLoadError, ItemValidationCatalog, LegacyItemMigrationError, MigratedItemArtifact,
};
pub use map::{
    expand_object_footprint, load_map_library, load_map_library_with_catalog,
    object_effectively_blocks_movement, object_effectively_blocks_sight, rotated_footprint_size,
    validate_map_definition, MapAiSpawnProps, MapBuildingProps, MapCellDefinition, MapDefinition,
    MapDefinitionValidationError, MapId, MapInteractiveProps, MapLevelDefinition, MapLibrary,
    MapLoadError, MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps,
    MapPickupProps, MapRotation, MapSize, MapValidationCatalog,
};
pub use models::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, ActorKind, ActorSide, GridCoord,
    TurnState, WorldCoord,
};
pub use settlement::{
    load_settlement_library, validate_settlement_definition, ServiceRules,
    SettlementAnchorDefinition, SettlementDefinition, SettlementDefinitionValidationError,
    SettlementId, SettlementLibrary, SettlementLoadError, SettlementRouteDefinition,
    SmartObjectDefinition, SmartObjectKind, TimeWindow,
};

pub struct GameDataPlugin;

impl Plugin for GameDataPlugin {
    fn build(&self, _app: &mut App) {}
}
