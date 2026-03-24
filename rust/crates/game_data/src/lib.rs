pub mod character;
pub mod content;
pub mod content_registry;
pub mod interaction;
pub mod map;
pub mod models;
pub mod quest;
pub mod recipe;
pub mod settlement;
pub mod shop;
pub mod skill;

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
pub use content_registry::{
    load_shared_content_registry, ContentAuthorityKind, ContentDomainSummary, ContentReference,
    ContentRegistryLoadError, SharedContentRegistry,
};
pub use interaction::{
    default_display_name_for_kind, default_option_id_for_kind, default_priority_for_kind,
    CharacterInteractionProfile, InteractionContextSnapshot, InteractionExecutionRequest,
    InteractionExecutionResult, InteractionOptionDefinition, InteractionOptionId,
    InteractionOptionKind, InteractionPrompt, InteractionTargetId, ResolvedInteractionOption,
    WorldMode,
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
pub use quest::{
    load_quest_library, validate_quest_definition, QuestChoiceOption, QuestConnection,
    QuestDefinition, QuestDefinitionValidationError, QuestEditorMeta, QuestFlow, QuestLibrary,
    QuestLoadError, QuestNode, QuestPosition, QuestRewardItem, QuestRewards,
    QuestValidationCatalog,
};
pub use recipe::{
    load_recipe_library, validate_recipe_definition, RecipeDefinition,
    RecipeDefinitionValidationError, RecipeLibrary, RecipeLoadError, RecipeMaterial, RecipeOutput,
    RecipeUnlockCondition, RecipeValidationCatalog,
};
pub use settlement::{
    load_settlement_library, validate_settlement_definition, ServiceRules,
    SettlementAnchorDefinition, SettlementDefinition, SettlementDefinitionValidationError,
    SettlementId, SettlementLibrary, SettlementLoadError, SettlementRouteDefinition,
    SmartObjectDefinition, SmartObjectKind, TimeWindow,
};
pub use shop::{
    load_shop_library, validate_shop_definition, ShopDefinition, ShopDefinitionValidationError,
    ShopInventoryEntry, ShopLibrary, ShopLoadError, ShopValidationCatalog,
};
pub use skill::{
    load_skill_library, load_skill_tree_library, validate_skill_definition,
    validate_skill_tree_definition, SkillActivationDefinition, SkillActivationEffect,
    SkillDefinition, SkillDefinitionValidationError, SkillGameplayEffect, SkillLibrary,
    SkillLoadError, SkillModifierDefinition, SkillTargetingDefinition, SkillTreeDefinition,
    SkillTreeDefinitionValidationError, SkillTreeLibrary, SkillTreeLink, SkillTreeLoadError,
    SkillTreePosition, SkillTreeValidationCatalog, SkillValidationCatalog,
};

pub struct GameDataPlugin;

impl Plugin for GameDataPlugin {
    fn build(&self, _app: &mut App) {}
}
