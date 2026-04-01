use bevy_ecs::prelude::*;
use game_core::{
    FollowGridGoalAiController, NoopAiController, RegisterActor, SimulationRuntime,
};
use game_data::{
    ActorId, ActorKind, ActorSide, CharacterArchetype, CharacterDefinition,
    CharacterDisposition, GridCoord,
};

use crate::npc_life::LifeProfileComponent;
use crate::{
    AiCombatProfile, AvatarPath, BaseAttributeSet, BehaviorProfile, CampId,
    CharacterArchetypeComponent, CharacterDefinitionId, CharacterDefinitions,
    CharacterSpawnRejected, CombatAttributeSet, Description, Disposition, DisplayName,
    GridPosition, Level, LootTable, ModelPath, PlaceholderColors, PortraitPath, ResourcePools,
    SpawnCharacterRequest, XpReward,
};

#[derive(Bundle, Debug, Clone, PartialEq)]
struct SpawnedCharacterBundle {
    definition_id: CharacterDefinitionId,
    archetype: CharacterArchetypeComponent,
    disposition: Disposition,
    camp_id: CampId,
    display_name: DisplayName,
    description: Description,
    level: Level,
    behavior: BehaviorProfile,
    ai: AiCombatProfile,
    xp_reward: XpReward,
    loot: LootTable,
    portrait: PortraitPath,
    avatar: AvatarPath,
    model: ModelPath,
    placeholder_colors: PlaceholderColors,
    base_attributes: BaseAttributeSet,
    combat_attributes: CombatAttributeSet,
    resources: ResourcePools,
    grid_position: GridPosition,
}

pub fn spawn_characters_from_definition(
    mut commands: Commands,
    definitions: Option<Res<CharacterDefinitions>>,
    mut requests: MessageReader<SpawnCharacterRequest>,
    mut rejections: MessageWriter<CharacterSpawnRejected>,
) {
    let Some(definitions) = definitions else {
        for request in requests.read() {
            rejections.write(CharacterSpawnRejected {
                definition_id: request.definition_id.clone(),
                reason: "character_definitions_missing".to_string(),
            });
        }
        return;
    };

    for request in requests.read() {
        let Some(definition) = definitions.0.get(&request.definition_id) else {
            rejections.write(CharacterSpawnRejected {
                definition_id: request.definition_id.clone(),
                reason: format!("unknown_character_definition: {}", request.definition_id),
            });
            continue;
        };

        spawn_character_entity(&mut commands, definition, request.grid_position);
    }
}

pub fn register_runtime_actor_from_definition(
    runtime: &mut SimulationRuntime,
    definition: &CharacterDefinition,
    grid_position: GridCoord,
) -> ActorId {
    let actor_id =
        runtime.register_actor(register_actor_from_definition(definition, grid_position));
    runtime.seed_actor_progression(
        actor_id,
        definition.progression.level as i32,
        definition.combat.xp_reward,
    );
    runtime.seed_actor_combat_profile(
        actor_id,
        definition
            .attributes
            .sets
            .get("combat")
            .cloned()
            .unwrap_or_default(),
        definition.attributes.resources.clone(),
    );
    runtime.seed_actor_loot_table(actor_id, definition.combat.loot.clone());
    actor_id
}

fn spawn_character_entity(
    commands: &mut Commands,
    definition: &CharacterDefinition,
    grid_position: GridCoord,
) -> Entity {
    let base_attributes = definition
        .attributes
        .sets
        .get("base")
        .cloned()
        .unwrap_or_default();
    let combat_attributes = definition
        .attributes
        .sets
        .get("combat")
        .cloned()
        .unwrap_or_default();

    let entity = commands
        .spawn(SpawnedCharacterBundle {
            definition_id: CharacterDefinitionId(definition.id.clone()),
            archetype: CharacterArchetypeComponent(definition.archetype),
            disposition: Disposition(definition.faction.disposition),
            camp_id: CampId(definition.faction.camp_id.clone()),
            display_name: DisplayName(definition.identity.display_name.clone()),
            description: Description(definition.identity.description.clone()),
            level: Level(definition.progression.level),
            behavior: BehaviorProfile(definition.combat.behavior.clone()),
            ai: AiCombatProfile(definition.ai.clone()),
            xp_reward: XpReward(definition.combat.xp_reward),
            loot: LootTable(definition.combat.loot.clone()),
            portrait: PortraitPath(definition.presentation.portrait_path.clone()),
            avatar: AvatarPath(definition.presentation.avatar_path.clone()),
            model: ModelPath(definition.presentation.model_path.clone()),
            placeholder_colors: PlaceholderColors(
                definition.presentation.placeholder_colors.clone(),
            ),
            base_attributes: BaseAttributeSet(base_attributes),
            combat_attributes: CombatAttributeSet(combat_attributes),
            resources: ResourcePools(definition.attributes.resources.clone()),
            grid_position: GridPosition(grid_position),
        })
        .id();

    if let Some(life) = definition.life.clone() {
        commands.entity(entity).insert(LifeProfileComponent(life));
    }

    entity
}

pub(crate) fn register_actor_from_definition(
    definition: &CharacterDefinition,
    grid_position: GridCoord,
) -> RegisterActor {
    let ai_controller = if definition.life.is_some() {
        Some(Box::new(FollowGridGoalAiController) as Box<_>)
    } else {
        Some(Box::new(NoopAiController) as Box<_>)
    };

    RegisterActor {
        definition_id: Some(definition.id.clone()),
        display_name: definition.identity.display_name.clone(),
        kind: actor_kind_from_archetype(definition.archetype),
        side: actor_side_from_disposition(definition.faction.disposition),
        group_id: actor_group_id(definition),
        grid_position,
        interaction: definition.interaction.clone(),
        attack_range: definition.ai.attack_range,
        ai_controller,
    }
}

fn actor_kind_from_archetype(archetype: CharacterArchetype) -> ActorKind {
    match archetype {
        CharacterArchetype::Player => ActorKind::Player,
        CharacterArchetype::Npc => ActorKind::Npc,
        CharacterArchetype::Enemy => ActorKind::Enemy,
    }
}

fn actor_side_from_disposition(disposition: CharacterDisposition) -> ActorSide {
    match disposition {
        CharacterDisposition::Player => ActorSide::Player,
        CharacterDisposition::Friendly => ActorSide::Friendly,
        CharacterDisposition::Hostile => ActorSide::Hostile,
        CharacterDisposition::Neutral => ActorSide::Neutral,
    }
}

fn actor_group_id(definition: &CharacterDefinition) -> String {
    if definition.archetype == CharacterArchetype::Player {
        "player".to_string()
    } else {
        definition.faction.camp_id.clone()
    }
}
