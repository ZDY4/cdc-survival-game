pub mod ai;
pub mod ai_content;
pub mod ai_preview;
pub mod character;
pub mod content;
pub mod content_registry;
pub mod dialogue_rules;
pub mod dialogue_runtime;
pub mod interaction;
pub mod map;
pub mod map_edit;
pub mod models;
pub mod outdoor_transition;
pub mod overworld;
pub mod quest;
pub mod recipe;
pub mod settlement;
pub mod shop;
pub mod skill;

use bevy_app::prelude::*;

pub use ai::{
    load_ai_module_library, resolve_ai_behavior_profile, validate_ai_module_library,
    AiActionDefinition, AiActionGroupDefinition, AiActionGroupId, AiActionId, AiAnchorBinding,
    AiBehaviorDefinition, AiBehaviorProfile, AiBehaviorProfileRef, AiComparisonOperator,
    AiConditionDefinition, AiConditionId, AiConditionModuleDefinition,
    AiConditionalPlannerRequirements, AiExecutorBindingDefinition, AiExecutorBindingId,
    AiFactGroupDefinition, AiFactGroupId, AiFactId, AiFactModuleDefinition, AiGoalDefinition,
    AiGoalGroupDefinition, AiGoalGroupId, AiGoalId, AiMetadata, AiModuleLibrary, AiModuleLoadError,
    AiModulePack, AiModuleValidationError, AiNeedEffectDefinition, AiPlannerDatumAssignment,
    AiProfilePack, AiReservationBinding, AiScoreRuleDefinition, AiScoreRuleId,
    AiWorldStateEffectDefinition, BuiltinAiExecutorKind, NeedProfileDefinition,
    PersonalityProfileDefinition, ScheduleTemplateDefinition, SmartObjectAccessProfileDefinition,
    SmartObjectAccessRuleDefinition,
};
pub use ai_content::{validate_ai_content, AiContentIssue, AiContentIssueSeverity};
pub use ai_preview::{
    build_behavior_preview, build_character_ai_preview, build_character_ai_preview_at_time,
    build_schedule_preview, resolve_character_life_profile, AiActionAvailabilityPreview,
    AiAvailabilityContext, AiBehaviorPreview, AiGoalScorePreview, AiPreviewModuleRef,
    CharacterAiPreview, CharacterAiPreviewContext, CharacterAiPreviewError,
    CharacterLifeBindingPreview, NeedProfilePreview, PersonalityProfilePreview,
    ResolvedCharacterLifeProfile, SmartObjectAccessProfilePreview, SmartObjectAccessRulePreview,
    WeeklyScheduleEntryPreview, WeeklySchedulePreview,
};
pub use character::{
    load_character_library, validate_character_definition, CharacterAiProfile, CharacterArchetype,
    CharacterAttributeTemplate, CharacterCombatProfile, CharacterDefinition,
    CharacterDefinitionValidationError, CharacterDisposition, CharacterFaction, CharacterId,
    CharacterIdentity, CharacterLibrary, CharacterLifeProfile, CharacterLoadError,
    CharacterLootEntry, CharacterPlaceholderColors, CharacterPresentation, CharacterProgression,
    CharacterResourcePool, NeedProfile, NpcRole, PersonalityProfileOverride, ScheduleBlock,
    ScheduleDay,
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
pub use dialogue_rules::{
    load_dialogue_library, load_dialogue_rule_library, resolve_dialogue_preview,
    validate_dialogue_definition, validate_dialogue_rule_definition, DialogueLibrary,
    DialogueLoadError, DialogueResolutionContext, DialogueResolutionPreview,
    DialogueResolutionResult, DialogueResolutionSource, DialogueRuleConditions,
    DialogueRuleDefinition, DialogueRuleLibrary, DialogueRuleLoadError,
    DialogueRuleValidationCatalog, DialogueRuleValidationError, DialogueRuleVariant,
    DialogueValidationError,
};
pub use dialogue_runtime::{
    advance_dialogue, current_dialogue_node, dialogue_runtime_state, find_dialogue_start_node,
    resolve_dialogue_start_node_id, DialogueAdvanceError, DialogueAdvanceOutcome,
    DialogueRuntimeState, DialogueSessionState,
};
pub use interaction::{
    all_interaction_kind_specs, default_display_name_for_kind, default_option_id_for_kind,
    default_priority_for_kind, interaction_kind_spec, is_scene_transition_kind,
    parse_legacy_interaction_kind, CharacterInteractionProfile, InteractionContextSnapshot,
    InteractionExecutionRequest, InteractionExecutionResult, InteractionKindSpec,
    InteractionKindValidation, InteractionOptionDefinition, InteractionOptionId,
    InteractionOptionKind, InteractionPrompt, InteractionTargetId, ResolvedInteractionOption,
    WorldMode,
};
pub use map::{
    building_layout_story_levels, expand_object_footprint, load_map_library,
    load_map_library_with_catalog, object_effectively_blocks_movement,
    object_effectively_blocks_sight, rotated_footprint_size, validate_map_definition,
    BuildingGeneratorKind, MapAiSpawnProps, MapBuildingDiagonalEdge,
    MapBuildingFootprintPolygonSpec, MapBuildingLayoutSpec, MapBuildingProps, MapBuildingStairSpec,
    MapBuildingStorySpec, MapBuildingVisualOutline, MapCellDefinition, MapContainerItemEntry,
    MapContainerProps, MapDefinition, MapDefinitionValidationError, MapEntryPointDefinition, MapId,
    MapInteractiveProps, MapLevelDefinition, MapLibrary, MapLoadError, MapObjectDefinition,
    MapObjectFootprint, MapObjectKind, MapObjectProps, MapPickupProps, MapRotation, MapSize,
    MapTriggerProps, MapValidationCatalog, RelativeGridCell, RelativeGridVertex, StairKind,
};
pub use map_edit::{
    normalize_map_definition, MapEditCommand, MapEditDiagnostic, MapEditDiagnosticSeverity,
    MapEditError, MapEditOperationSummary, MapEditResult, MapEditTarget, MapEditorService,
};
pub use models::{
    ActionPhase, ActionRequest, ActionResult, ActionType, ActorId, ActorKind, ActorSide, GridCoord,
    SkillTargetRequest, TurnState, WorldCoord,
};
pub use outdoor_transition::{
    validate_outdoor_transition_trigger_layout, OutdoorTransitionTriggerLayoutValidationError,
};
pub use overworld::{
    load_overworld_library, load_overworld_library_with_catalog, validate_overworld_definition,
    OverworldCellDefinition, OverworldDefinition, OverworldId, OverworldLibrary,
    OverworldLoadError, OverworldLocationDefinition, OverworldLocationId, OverworldLocationKind,
    OverworldTravelRuleSet, OverworldValidationCatalog, OverworldValidationError,
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
