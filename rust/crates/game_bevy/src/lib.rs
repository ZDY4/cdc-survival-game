use std::collections::BTreeMap;

use bevy_ecs::prelude::*;
use game_core::simulation::Simulation;
use game_core::SimulationRuntime;
#[cfg(test)]
use game_data::MapObjectKind;
use game_data::{
    ActorId, CharacterAiProfile, CharacterArchetype, CharacterDisposition, CharacterId,
    CharacterLibrary, CharacterLootEntry, CharacterPlaceholderColors, CharacterResourcePool,
    GridCoord, MapId, MapLibrary, OverworldLibrary, WorldMode,
};
use spawn::register_actor_from_definition;

mod ai_spawn;
pub mod bootstrap;
mod content;
mod logging;
pub mod npc_life;
pub mod reservations;
mod spawn;
pub mod ui;

pub use ai_spawn::advance_map_ai_spawn_runtime;
pub use bootstrap::{
    build_default_startup_seed, build_runtime_from_default_startup_seed, load_runtime_bootstrap,
    RuntimeBootstrapBundle, RuntimeBootstrapError,
};
pub use content::*;
pub use logging::{init_runtime_logging, RuntimeLogInitError, RuntimeLogSettings};
pub use npc_life::{
    BackgroundLifeState, CurrentAction, CurrentGoal, CurrentPlan,
    LifeProfileComponent as CharacterLifeProfileComponent, NeedState, NpcLifePlugin, NpcLifeState,
    NpcLifeUpdateSet, ReservationState, RuntimeActorLink, RuntimeExecutionState, ScheduleState,
    SettlementContext, SettlementDebugEntry, SettlementDebugSnapshot, SettlementSimulationPlugin,
    SimClock, WorldAlertState,
};
pub use reservations::SmartObjectReservations;
pub use spawn::{register_runtime_actor_from_definition, spawn_characters_from_definition};
pub use ui::{
    ammo_item_ids, character_snapshot, classify_item, crafting_snapshot, interaction_prompt_text,
    inventory_snapshot, item_attribute_bonuses, item_equippable, item_usable, journal_snapshot,
    map_snapshot, overworld_location_prompt_snapshot, player_actor_id, skills_snapshot,
    trade_snapshot, world_status_snapshot, GameUiPlugin, UiCharacterCommand, UiCharacterSnapshot,
    UiCraftingSnapshot, UiDialogueCommand, UiDiscardQuantityModalState, UiEquipmentSlotView,
    UiHotbarSlotState, UiHotbarState, UiInputBlockState, UiInventoryCommand, UiInventoryDetailView,
    UiInventoryEntryView, UiInventoryFilter, UiInventoryFilterState, UiInventoryPanelSnapshot,
    UiItemType, UiJournalSnapshot, UiMainMenuCommand, UiMainMenuSnapshot, UiMapLocationView,
    UiMapSnapshot, UiMenuCommand, UiMenuPanel, UiMenuState, UiModalState,
    UiOverworldLocationPromptSnapshot, UiSettingsCommand, UiSkillCommand, UiSkillEntryView,
    UiSkillTreeView, UiSkillsSnapshot, UiStatusBannerState, UiTradeCommand, UiTradeEntryView,
    UiTradeSessionState, UiTradeSnapshot, UiWorldStatusSnapshot,
};

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub struct SpawnCharacterRequest {
    pub definition_id: CharacterId,
    pub grid_position: GridCoord,
}

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub struct CharacterSpawnRejected {
    pub definition_id: CharacterId,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeSpawnEntry {
    pub definition_id: CharacterId,
    pub grid_position: GridCoord,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RuntimeScenarioSeed {
    pub map_id: Option<MapId>,
    pub start_world_mode: Option<WorldMode>,
    pub start_location_id: Option<String>,
    pub start_map_id: Option<MapId>,
    pub start_entry_point_id: Option<String>,
    pub unlocked_locations: Vec<String>,
    pub static_obstacles: Vec<GridCoord>,
    pub characters: Vec<RuntimeSpawnEntry>,
}

#[derive(Resource, Debug, Clone, Default)]
pub struct MapAiSpawnRuntimeState {
    pub current_map_id: Option<MapId>,
    pub elapsed_seconds: f32,
    pub spawn_points: BTreeMap<String, RuntimeAiSpawnPoint>,
    pub active_spawn_actors: BTreeMap<String, ActorId>,
    pub respawn_deadlines: BTreeMap<String, f32>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RuntimeAiSpawnPoint {
    pub spawn_id: String,
    pub character_id: CharacterId,
    pub anchor: GridCoord,
    pub auto_spawn: bool,
    pub respawn_enabled: bool,
    pub respawn_delay_seconds: f32,
    pub spawn_radius: f32,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct CharacterDefinitionId(pub CharacterId);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct CharacterArchetypeComponent(pub CharacterArchetype);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct Disposition(pub CharacterDisposition);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct CampId(pub String);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct DisplayName(pub String);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct Description(pub String);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct Level(pub u32);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct BehaviorProfile(pub String);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct AiCombatProfile(pub CharacterAiProfile);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct XpReward(pub i32);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct LootTable(pub Vec<CharacterLootEntry>);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct PortraitPath(pub String);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct AvatarPath(pub String);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct ModelPath(pub String);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct PlaceholderColors(pub CharacterPlaceholderColors);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct BaseAttributeSet(pub BTreeMap<String, f32>);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct CombatAttributeSet(pub BTreeMap<String, f32>);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct ResourcePools(pub BTreeMap<String, CharacterResourcePool>);

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub struct GridPosition(pub GridCoord);

pub fn resolve_startup_map_id(
    maps: &MapLibrary,
    configured_map_id: Option<MapId>,
) -> Option<MapId> {
    if let Some(map_id) = configured_map_id {
        return Some(map_id);
    }

    maps.iter().next().map(|(map_id, _)| map_id.clone())
}

pub fn build_simulation_from_seed(
    definitions: &CharacterLibrary,
    maps: &MapLibrary,
    overworld: &OverworldLibrary,
    seed: &RuntimeScenarioSeed,
) -> Result<Simulation, RuntimeBuildError> {
    let mut simulation = Simulation::new();
    simulation.set_map_library(maps.clone());
    simulation.set_overworld_library(overworld.clone());

    let requested_world_mode = seed.start_world_mode.unwrap_or({
        if seed.start_location_id.is_some() || seed.start_map_id.is_some() || seed.map_id.is_some()
        {
            WorldMode::Outdoor
        } else {
            WorldMode::Unknown
        }
    });
    let requested_map_id = seed.start_map_id.as_ref().or(seed.map_id.as_ref());

    if let Some(map_id) = requested_map_id {
        if maps.get(map_id).is_none() {
            return Err(RuntimeBuildError::UnknownMapDefinition {
                map_id: map_id.clone(),
            });
        }
    }

    let mut player_actor_id = None;
    for obstacle in &seed.static_obstacles {
        simulation
            .grid_world_mut()
            .register_static_obstacle(*obstacle);
    }
    for entry in &seed.characters {
        let definition = definitions.get(&entry.definition_id).ok_or_else(|| {
            RuntimeBuildError::UnknownCharacterDefinition {
                definition_id: entry.definition_id.clone(),
            }
        })?;
        let actor_id = simulation.register_actor(register_actor_from_definition(
            definition,
            entry.grid_position,
        ));
        if player_actor_id.is_none() && definition.archetype == CharacterArchetype::Player {
            player_actor_id = Some(actor_id);
        }
        simulation.seed_actor_progression(
            actor_id,
            definition.progression.level as i32,
            definition.combat.xp_reward,
        );
        simulation.seed_actor_combat_profile(
            actor_id,
            definition
                .attributes
                .sets
                .get("combat")
                .cloned()
                .unwrap_or_default(),
            definition.attributes.resources.clone(),
        );
        simulation.seed_actor_loot_table(actor_id, definition.combat.loot.clone());
    }

    for location_id in &seed.unlocked_locations {
        match simulation.apply_command(game_core::SimulationCommand::UnlockLocation {
            location_id: location_id.clone(),
        }) {
            game_core::SimulationCommandResult::OverworldState(Ok(_))
            | game_core::SimulationCommandResult::None => {}
            game_core::SimulationCommandResult::OverworldState(Err(message)) => {
                return Err(RuntimeBuildError::InvalidOverworldSeed { message });
            }
            other => {
                return Err(RuntimeBuildError::InvalidOverworldSeed {
                    message: format!("unexpected unlock command result: {other:?}"),
                });
            }
        }
    }

    if requested_world_mode == WorldMode::Traveling {
        return Err(RuntimeBuildError::InvalidOverworldSeed {
            message: "unsupported_world_mode:Traveling".to_string(),
        });
    }

    if requested_world_mode == WorldMode::Overworld {
        simulation
            .seed_overworld_state(
                requested_world_mode,
                seed.start_location_id.clone(),
                seed.start_entry_point_id.clone(),
                Vec::<String>::new(),
            )
            .map_err(|message| RuntimeBuildError::InvalidOverworldSeed { message })?;
        if let Some(player_actor_id) = player_actor_id {
            let start_location_id = seed.start_location_id.as_deref().ok_or_else(|| {
                RuntimeBuildError::InvalidOverworldSeed {
                    message: "missing_overworld_start_location".to_string(),
                }
            })?;
            let Some((_, definition)) = overworld.iter().next() else {
                return Err(RuntimeBuildError::InvalidOverworldSeed {
                    message: "missing_overworld_definition".to_string(),
                });
            };
            let overworld_cell = definition
                .locations
                .iter()
                .find(|location| location.id.as_str() == start_location_id)
                .map(|location| location.overworld_cell)
                .ok_or_else(|| RuntimeBuildError::InvalidOverworldSeed {
                    message: format!("unknown_location:{start_location_id}"),
                })?;
            simulation.update_actor_grid_position(player_actor_id, overworld_cell);
        }
    } else if let Some(location_id) = seed.start_location_id.as_ref() {
        let Some(player_actor_id) = player_actor_id else {
            return Err(RuntimeBuildError::InvalidOverworldSeed {
                message: "missing_player_actor_for_location_start".to_string(),
            });
        };
        match simulation.apply_command(game_core::SimulationCommand::EnterLocation {
            actor_id: player_actor_id,
            location_id: location_id.clone(),
            entry_point_id: seed.start_entry_point_id.clone(),
        }) {
            game_core::SimulationCommandResult::LocationTransition(Ok(_)) => {}
            game_core::SimulationCommandResult::LocationTransition(Err(message)) => {
                return Err(RuntimeBuildError::InvalidOverworldSeed { message });
            }
            other => {
                return Err(RuntimeBuildError::InvalidOverworldSeed {
                    message: format!("unexpected enter location result: {other:?}"),
                });
            }
        }
    } else if let Some(map_id) = requested_map_id.as_ref() {
        let Some(player_actor_id) = player_actor_id else {
            return Err(RuntimeBuildError::InvalidOverworldSeed {
                message: "missing_player_actor_for_map_start".to_string(),
            });
        };
        match simulation.apply_command(game_core::SimulationCommand::TravelToMap {
            actor_id: player_actor_id,
            target_map_id: map_id.as_str().to_string(),
            entry_point_id: seed.start_entry_point_id.clone(),
            world_mode: requested_world_mode,
        }) {
            game_core::SimulationCommandResult::InteractionContext(Ok(_)) => {}
            game_core::SimulationCommandResult::InteractionContext(Err(message)) => {
                return Err(RuntimeBuildError::InvalidOverworldSeed { message });
            }
            other => {
                return Err(RuntimeBuildError::InvalidOverworldSeed {
                    message: format!("unexpected travel_to_map result: {other:?}"),
                });
            }
        }
    }

    Ok(simulation)
}

pub fn build_runtime_from_seed(
    definitions: &CharacterLibrary,
    maps: &MapLibrary,
    overworld: &OverworldLibrary,
    seed: &RuntimeScenarioSeed,
) -> Result<SimulationRuntime, RuntimeBuildError> {
    Ok(SimulationRuntime::from_simulation(
        build_simulation_from_seed(definitions, maps, overworld, seed)?,
    ))
}

pub fn default_debug_seed() -> RuntimeScenarioSeed {
    let map_id = MapId("survivor_outpost_01_grid".to_string());

    RuntimeScenarioSeed {
        map_id: Some(map_id.clone()),
        start_world_mode: Some(WorldMode::Outdoor),
        start_location_id: Some("survivor_outpost_01".to_string()),
        start_map_id: Some(map_id.clone()),
        start_entry_point_id: Some("default_entry".to_string()),
        unlocked_locations: vec![
            "survivor_outpost_01".to_string(),
            "street_a".to_string(),
            "street_b".to_string(),
            "survivor_outpost_01_perimeter".to_string(),
            "survivor_outpost_01_interior".to_string(),
        ],
        static_obstacles: Vec::new(),
        characters: debug_seed_characters_for_map(Some(&map_id)),
    }
}

pub(crate) fn debug_seed_characters_for_map(map_id: Option<&MapId>) -> Vec<RuntimeSpawnEntry> {
    match map_id.map(MapId::as_str) {
        Some("survivor_outpost_01_perimeter_grid") => vec![RuntimeSpawnEntry {
            definition_id: CharacterId("player".to_string()),
            grid_position: GridCoord::new(2, 0, 10),
        }],
        Some("survivor_outpost_01_interior_grid") => vec![
            RuntimeSpawnEntry {
                definition_id: CharacterId("player".to_string()),
                grid_position: GridCoord::new(2, 0, 2),
            },
            RuntimeSpawnEntry {
                definition_id: CharacterId("trader_lao_wang".to_string()),
                grid_position: GridCoord::new(3, 0, 2),
            },
        ],
        _ => vec![
            RuntimeSpawnEntry {
                definition_id: CharacterId("player".to_string()),
                grid_position: GridCoord::new(0, 0, 0),
            },
            RuntimeSpawnEntry {
                definition_id: CharacterId("trader_lao_wang".to_string()),
                grid_position: GridCoord::new(1, 0, 0),
            },
        ],
    }
}

#[cfg(test)]
pub(crate) fn auto_spawn_characters_for_map(
    maps: &MapLibrary,
    map_id: Option<&MapId>,
) -> Vec<RuntimeSpawnEntry> {
    let Some(map_id) = map_id else {
        return Vec::new();
    };
    let Some(map) = maps.get(map_id) else {
        return Vec::new();
    };

    map.objects
        .iter()
        .filter(|object| object.kind == MapObjectKind::AiSpawn)
        .filter_map(|object| {
            let ai_spawn = object.props.ai_spawn.as_ref()?;
            if !ai_spawn.auto_spawn || ai_spawn.character_id.trim().is_empty() {
                return None;
            }
            Some(RuntimeSpawnEntry {
                definition_id: CharacterId(ai_spawn.character_id.clone()),
                grid_position: object.anchor,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{
        advance_map_ai_spawn_runtime, auto_spawn_characters_for_map, build_runtime_from_seed,
        debug_seed_characters_for_map, default_debug_seed, load_runtime_startup_config,
        parse_runtime_startup_config, resolve_startup_map_id, spawn_characters_from_definition,
        AiCombatProfile, AvatarPath, BaseAttributeSet, BehaviorProfile, CampId,
        CharacterArchetypeComponent, CharacterDefinitionId, CharacterDefinitionPath,
        CharacterDefinitions, CharacterSpawnRejected, CombatAttributeSet, Description, DisplayName,
        Disposition, GridPosition, Level, LootTable, MapAiSpawnRuntimeState, MapDefinitionPath,
        ModelPath, PlaceholderColors, PortraitPath, ResourcePools, RuntimeBuildError,
        RuntimeScenarioSeed, RuntimeSpawnEntry, RuntimeStartupConfig, SpawnCharacterRequest,
        XpReward,
    };
    use bevy_app::{App, Update};
    use bevy_ecs::message::{MessageReader, Messages};
    use bevy_ecs::prelude::*;
    use game_data::{
        CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate, CharacterCombatProfile,
        CharacterDefinition, CharacterDisposition, CharacterFaction, CharacterId,
        CharacterIdentity, CharacterLibrary, CharacterLootEntry, CharacterPlaceholderColors,
        CharacterPresentation, CharacterProgression, CharacterResourcePool, GridCoord,
        MapBuildingProps, MapCellDefinition, MapDefinition, MapEntryPointDefinition, MapId,
        MapLevelDefinition, MapLibrary, MapObjectDefinition, MapObjectFootprint, MapObjectKind,
        MapObjectProps, MapRotation, MapSize, OverworldCellDefinition, OverworldDefinition,
        OverworldId, OverworldLibrary, OverworldLocationDefinition, OverworldLocationId,
        OverworldLocationKind, OverworldTravelRuleSet, WorldMode,
    };
    use std::collections::BTreeMap;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[derive(Resource, Debug, Default)]
    struct CapturedRejections(Vec<CharacterSpawnRejected>);

    #[test]
    fn runtime_seed_maps_character_metadata_to_core_runtime() {
        let library = sample_library();
        let maps = sample_map_library();
        let seed = RuntimeScenarioSeed {
            map_id: Some(MapId("survivor_outpost_01_grid".into())),
            static_obstacles: vec![GridCoord::new(2, 0, 1)],
            characters: vec![
                RuntimeSpawnEntry {
                    definition_id: CharacterId("player".into()),
                    grid_position: GridCoord::new(0, 0, 0),
                },
                RuntimeSpawnEntry {
                    definition_id: CharacterId("trader_lao_wang".into()),
                    grid_position: GridCoord::new(1, 0, 0),
                },
                RuntimeSpawnEntry {
                    definition_id: CharacterId("zombie_walker".into()),
                    grid_position: GridCoord::new(4, 0, 0),
                },
            ],
            ..RuntimeScenarioSeed::default()
        };

        let runtime = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect("runtime should build");
        let snapshot = runtime.snapshot();

        let player = snapshot
            .actors
            .iter()
            .find(|actor| actor.definition_id.as_ref().map(CharacterId::as_str) == Some("player"))
            .expect("player actor should exist");
        assert_eq!(player.kind, game_data::ActorKind::Player);
        assert_eq!(player.side, game_data::ActorSide::Player);
        assert_eq!(player.group_id, "player");
        assert_eq!(player.display_name, "Rust Player");

        let npc = snapshot
            .actors
            .iter()
            .find(|actor| {
                actor.definition_id.as_ref().map(CharacterId::as_str) == Some("trader_lao_wang")
            })
            .expect("npc actor should exist");
        assert_eq!(npc.kind, game_data::ActorKind::Npc);
        assert_eq!(npc.side, game_data::ActorSide::Friendly);
        assert_eq!(npc.group_id, "survivor");

        let enemy = snapshot
            .actors
            .iter()
            .find(|actor| {
                actor.definition_id.as_ref().map(CharacterId::as_str) == Some("zombie_walker")
            })
            .expect("enemy actor should exist");
        assert_eq!(enemy.kind, game_data::ActorKind::Enemy);
        assert_eq!(enemy.side, game_data::ActorSide::Hostile);
        assert_eq!(enemy.group_id, "infected");
        assert_eq!(
            snapshot.grid.map_id.as_ref().map(MapId::as_str),
            Some("survivor_outpost_01_grid")
        );
        assert_eq!(snapshot.grid.map_width, Some(12));
        assert_eq!(snapshot.grid.levels, vec![0, 1]);
        assert!(snapshot
            .grid
            .static_obstacles
            .contains(&GridCoord::new(2, 0, 1)));
    }

    #[test]
    fn unknown_definition_in_runtime_seed_returns_explicit_error() {
        let library = sample_library();
        let maps = sample_map_library();
        let seed = RuntimeScenarioSeed {
            map_id: None,
            static_obstacles: Vec::new(),
            characters: vec![RuntimeSpawnEntry {
                definition_id: CharacterId("missing".into()),
                grid_position: GridCoord::new(0, 0, 0),
            }],
            ..RuntimeScenarioSeed::default()
        };

        let error = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect_err("missing definitions should fail");
        assert_eq!(
            error,
            RuntimeBuildError::UnknownCharacterDefinition {
                definition_id: CharacterId("missing".into()),
            }
        );
    }

    #[test]
    fn unknown_map_in_runtime_seed_returns_explicit_error() {
        let library = sample_library();
        let maps = MapLibrary::default();
        let seed = RuntimeScenarioSeed {
            map_id: Some(MapId("missing_map".into())),
            static_obstacles: Vec::new(),
            characters: Vec::new(),
            ..RuntimeScenarioSeed::default()
        };

        let error = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect_err("missing map should fail");
        assert_eq!(
            error,
            RuntimeBuildError::UnknownMapDefinition {
                map_id: MapId("missing_map".into()),
            }
        );
    }

    #[test]
    fn direct_map_start_populates_runtime_context_without_location_transition() {
        let library = sample_library();
        let maps = sample_map_library();
        let seed = RuntimeScenarioSeed {
            map_id: Some(MapId("survivor_outpost_01_grid".into())),
            start_map_id: Some(MapId("survivor_outpost_01_grid".into())),
            start_world_mode: Some(WorldMode::Outdoor),
            start_entry_point_id: Some("default_entry".into()),
            characters: vec![RuntimeSpawnEntry {
                definition_id: CharacterId("player".into()),
                grid_position: GridCoord::new(4, 0, 4),
            }],
            ..RuntimeScenarioSeed::default()
        };

        let runtime = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect("runtime should build");
        let context = runtime.current_interaction_context();

        assert_eq!(
            context.current_map_id.as_deref(),
            Some("survivor_outpost_01_grid")
        );
        assert!(context.active_location_id.is_none());
        assert_eq!(context.entry_point_id.as_deref(), Some("default_entry"));
        assert_eq!(context.world_mode, WorldMode::Outdoor);
    }

    #[test]
    fn location_start_populates_runtime_context_via_location_transition() {
        let library = sample_library();
        let maps = sample_map_library();
        let seed = RuntimeScenarioSeed {
            map_id: Some(MapId("survivor_outpost_01_grid".into())),
            start_map_id: Some(MapId("survivor_outpost_01_grid".into())),
            start_location_id: Some("survivor_outpost_01".into()),
            start_world_mode: Some(WorldMode::Outdoor),
            start_entry_point_id: Some("default_entry".into()),
            characters: vec![RuntimeSpawnEntry {
                definition_id: CharacterId("player".into()),
                grid_position: GridCoord::new(4, 0, 4),
            }],
            ..RuntimeScenarioSeed::default()
        };

        let runtime = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect("runtime should build");
        let context = runtime.current_interaction_context();

        assert_eq!(
            context.current_map_id.as_deref(),
            Some("survivor_outpost_01_grid")
        );
        assert_eq!(
            context.active_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(context.entry_point_id.as_deref(), Some("default_entry"));
        assert_eq!(context.world_mode, WorldMode::Outdoor);
    }

    #[test]
    fn overworld_start_clears_scene_context_and_keeps_overworld_anchor() {
        let library = sample_library();
        let maps = sample_map_library();
        let seed = RuntimeScenarioSeed {
            map_id: Some(MapId("survivor_outpost_01_grid".into())),
            start_map_id: Some(MapId("survivor_outpost_01_grid".into())),
            start_location_id: Some("survivor_outpost_01".into()),
            start_world_mode: Some(WorldMode::Overworld),
            start_entry_point_id: Some("default_entry".into()),
            characters: vec![RuntimeSpawnEntry {
                definition_id: CharacterId("player".into()),
                grid_position: GridCoord::new(4, 0, 4),
            }],
            ..RuntimeScenarioSeed::default()
        };

        let runtime = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect("runtime should build");
        let context = runtime.current_interaction_context();

        assert_eq!(context.current_map_id, None);
        assert_eq!(
            context.active_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(
            context.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert_eq!(context.entry_point_id, None);
        assert_eq!(context.world_mode, WorldMode::Overworld);
    }

    #[test]
    fn traveling_start_returns_explicit_error() {
        let library = sample_library();
        let maps = sample_map_library();
        let seed = RuntimeScenarioSeed {
            map_id: Some(MapId("survivor_outpost_01_grid".into())),
            start_map_id: Some(MapId("survivor_outpost_01_grid".into())),
            start_location_id: Some("survivor_outpost_01".into()),
            start_world_mode: Some(WorldMode::Traveling),
            start_entry_point_id: Some("default_entry".into()),
            characters: vec![RuntimeSpawnEntry {
                definition_id: CharacterId("player".into()),
                grid_position: GridCoord::new(4, 0, 4),
            }],
            ..RuntimeScenarioSeed::default()
        };

        let error = build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
            .expect_err("traveling startup should be rejected");
        assert_eq!(
            error,
            RuntimeBuildError::InvalidOverworldSeed {
                message: "unsupported_world_mode:Traveling".to_string(),
            }
        );
    }

    #[test]
    fn spawn_request_creates_expected_character_components() {
        let mut app = App::new();
        app.add_message::<SpawnCharacterRequest>();
        app.add_message::<CharacterSpawnRejected>();
        app.insert_resource(CharacterDefinitions(sample_library()));
        app.add_systems(Update, spawn_characters_from_definition);

        app.world_mut()
            .resource_mut::<Messages<SpawnCharacterRequest>>()
            .write(SpawnCharacterRequest {
                definition_id: CharacterId("trader_lao_wang".to_string()),
                grid_position: GridCoord::new(3, 0, 2),
            });

        app.update();

        let entity = {
            let mut query = app.world_mut().query::<(Entity, &CharacterDefinitionId)>();
            query
                .iter(app.world())
                .find(|(_, id)| id.0.as_str() == "trader_lao_wang")
                .map(|(entity, _)| entity)
                .expect("spawned entity should exist")
        };
        let entity_ref = app.world().entity(entity);

        assert!(entity_ref.contains::<CharacterArchetypeComponent>());
        assert!(entity_ref.contains::<Disposition>());
        assert!(entity_ref.contains::<CampId>());
        assert!(entity_ref.contains::<DisplayName>());
        assert!(entity_ref.contains::<Description>());
        assert!(entity_ref.contains::<Level>());
        assert!(entity_ref.contains::<BehaviorProfile>());
        assert!(entity_ref.contains::<AiCombatProfile>());
        assert!(entity_ref.contains::<XpReward>());
        assert!(entity_ref.contains::<LootTable>());
        assert!(entity_ref.contains::<PortraitPath>());
        assert!(entity_ref.contains::<AvatarPath>());
        assert!(entity_ref.contains::<ModelPath>());
        assert!(entity_ref.contains::<PlaceholderColors>());
        assert!(entity_ref.contains::<BaseAttributeSet>());
        assert!(entity_ref.contains::<CombatAttributeSet>());
        assert!(entity_ref.contains::<ResourcePools>());
        assert!(entity_ref.contains::<GridPosition>());
    }

    #[test]
    fn unknown_definition_request_emits_rejection() {
        let mut app = App::new();
        app.add_message::<SpawnCharacterRequest>();
        app.add_message::<CharacterSpawnRejected>();
        app.insert_resource(CharacterDefinitions(sample_library()));
        app.insert_resource(CapturedRejections::default());
        app.add_systems(
            Update,
            (spawn_characters_from_definition, capture_rejections).chain(),
        );

        app.world_mut()
            .resource_mut::<Messages<SpawnCharacterRequest>>()
            .write(SpawnCharacterRequest {
                definition_id: CharacterId("missing".to_string()),
                grid_position: GridCoord::new(0, 0, 0),
            });

        app.update();

        let captured = app.world().resource::<CapturedRejections>();
        assert_eq!(captured.0.len(), 1);
        assert_eq!(captured.0[0].definition_id.as_str(), "missing");
        assert!(captured.0[0]
            .reason
            .contains("unknown_character_definition"));
    }

    #[test]
    fn default_debug_seed_uses_known_character_ids() {
        let ids: Vec<String> = default_debug_seed()
            .characters
            .into_iter()
            .map(|entry| entry.definition_id.0)
            .collect();

        assert_eq!(
            ids,
            vec!["player".to_string(), "trader_lao_wang".to_string(),]
        );
        assert_eq!(
            default_debug_seed().map_id.as_ref().map(MapId::as_str),
            Some("survivor_outpost_01_grid")
        );
        assert_eq!(
            default_debug_seed().start_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
    }

    #[test]
    fn perimeter_debug_seed_adds_hostile_actor_only_for_perimeter_map() {
        let characters = debug_seed_characters_for_map(Some(&MapId(
            "survivor_outpost_01_perimeter_grid".into(),
        )));
        let ids: Vec<&str> = characters
            .iter()
            .map(|entry| entry.definition_id.as_str())
            .collect();

        assert_eq!(ids, vec!["player"]);
    }

    #[test]
    fn auto_spawn_characters_for_map_reads_auto_spawn_ai_points() {
        let maps = MapLibrary::from(BTreeMap::from([(
            MapId("survivor_outpost_01_perimeter_grid".into()),
            MapDefinition {
                id: MapId("survivor_outpost_01_perimeter_grid".into()),
                name: "Perimeter".into(),
                size: MapSize {
                    width: 20,
                    height: 20,
                },
                default_level: 0,
                levels: vec![MapLevelDefinition {
                    y: 0,
                    cells: Vec::new(),
                }],
                entry_points: vec![MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(0, 0, 0),
                    facing: None,
                    extra: BTreeMap::new(),
                }],
                objects: vec![
                    MapObjectDefinition {
                        object_id: "spawn_walker".into(),
                        kind: MapObjectKind::AiSpawn,
                        anchor: GridCoord::new(15, 0, 4),
                        footprint: MapObjectFootprint::default(),
                        rotation: MapRotation::North,
                        blocks_movement: false,
                        blocks_sight: false,
                        props: MapObjectProps {
                            ai_spawn: Some(game_data::MapAiSpawnProps {
                                spawn_id: "spawn_walker".into(),
                                character_id: "zombie_walker".into(),
                                auto_spawn: true,
                                respawn_enabled: true,
                                respawn_delay: 24.0,
                                spawn_radius: 2.5,
                                extra: BTreeMap::new(),
                            }),
                            ..MapObjectProps::default()
                        },
                    },
                    MapObjectDefinition {
                        object_id: "spawn_brute".into(),
                        kind: MapObjectKind::AiSpawn,
                        anchor: GridCoord::new(12, 0, 3),
                        footprint: MapObjectFootprint::default(),
                        rotation: MapRotation::North,
                        blocks_movement: false,
                        blocks_sight: false,
                        props: MapObjectProps {
                            ai_spawn: Some(game_data::MapAiSpawnProps {
                                spawn_id: "spawn_brute".into(),
                                character_id: "zombie_brute".into(),
                                auto_spawn: false,
                                respawn_enabled: true,
                                respawn_delay: 40.0,
                                spawn_radius: 1.5,
                                extra: BTreeMap::new(),
                            }),
                            ..MapObjectProps::default()
                        },
                    },
                ],
            },
        )]));

        let characters = auto_spawn_characters_for_map(
            &maps,
            Some(&MapId("survivor_outpost_01_perimeter_grid".into())),
        );

        assert_eq!(
            characters,
            vec![RuntimeSpawnEntry {
                definition_id: CharacterId("zombie_walker".into()),
                grid_position: GridCoord::new(15, 0, 4),
            }]
        );
    }

    #[test]
    fn map_ai_spawn_runtime_spawns_and_respawns_auto_spawn_entries() {
        let library = sample_library();
        let maps = MapLibrary::from(BTreeMap::from([(
            MapId("survivor_outpost_01_perimeter_grid".into()),
            MapDefinition {
                id: MapId("survivor_outpost_01_perimeter_grid".into()),
                name: "Perimeter".into(),
                size: MapSize {
                    width: 20,
                    height: 20,
                },
                default_level: 0,
                levels: vec![MapLevelDefinition {
                    y: 0,
                    cells: Vec::new(),
                }],
                entry_points: vec![MapEntryPointDefinition {
                    id: "default_entry".into(),
                    grid: GridCoord::new(2, 0, 10),
                    facing: None,
                    extra: BTreeMap::new(),
                }],
                objects: vec![MapObjectDefinition {
                    object_id: "spawn_walker".into(),
                    kind: MapObjectKind::AiSpawn,
                    anchor: GridCoord::new(15, 0, 4),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    props: MapObjectProps {
                        ai_spawn: Some(game_data::MapAiSpawnProps {
                            spawn_id: "spawn_walker".into(),
                            character_id: "zombie_walker".into(),
                            auto_spawn: true,
                            respawn_enabled: true,
                            respawn_delay: 24.0,
                            spawn_radius: 0.0,
                            extra: BTreeMap::new(),
                        }),
                        ..MapObjectProps::default()
                    },
                }],
            },
        )]));
        let seed = RuntimeScenarioSeed {
            map_id: Some(MapId("survivor_outpost_01_perimeter_grid".into())),
            characters: vec![RuntimeSpawnEntry {
                definition_id: CharacterId("player".into()),
                grid_position: GridCoord::new(2, 0, 10),
            }],
            ..RuntimeScenarioSeed::default()
        };
        let mut runtime =
            build_runtime_from_seed(&library, &maps, &sample_overworld_library(), &seed)
                .expect("runtime should build");
        let mut state = MapAiSpawnRuntimeState::default();

        advance_map_ai_spawn_runtime(&mut state, &mut runtime, &library, &maps, 0.0);
        let walker_actor_id = runtime
            .snapshot()
            .actors
            .iter()
            .find(|actor| {
                actor.definition_id.as_ref().map(CharacterId::as_str) == Some("zombie_walker")
            })
            .map(|actor| actor.actor_id)
            .expect("walker should spawn from ai_spawn");
        assert_eq!(
            runtime.get_actor_grid_position(walker_actor_id),
            Some(GridCoord::new(15, 0, 4))
        );
        assert_eq!(
            state.active_spawn_actors.get("spawn_walker").copied(),
            Some(walker_actor_id)
        );

        runtime.unregister_actor(walker_actor_id);
        advance_map_ai_spawn_runtime(&mut state, &mut runtime, &library, &maps, 0.0);
        assert!(!state.active_spawn_actors.contains_key("spawn_walker"));
        assert!(state.respawn_deadlines.contains_key("spawn_walker"));

        advance_map_ai_spawn_runtime(&mut state, &mut runtime, &library, &maps, 23.0);
        assert!(runtime.snapshot().actors.iter().all(|actor| actor
            .definition_id
            .as_ref()
            .map(CharacterId::as_str)
            != Some("zombie_walker")));

        advance_map_ai_spawn_runtime(&mut state, &mut runtime, &library, &maps, 1.1);
        assert!(runtime.snapshot().actors.iter().any(|actor| actor
            .definition_id
            .as_ref()
            .map(CharacterId::as_str)
            == Some("zombie_walker")));
    }

    #[test]
    fn default_character_definition_path_targets_repo_data_directory() {
        let path = CharacterDefinitionPath::default();
        assert!(path.0.ends_with("data/characters"));
    }

    #[test]
    fn default_map_definition_path_targets_repo_data_directory() {
        let path = MapDefinitionPath::default();
        assert!(path.0.ends_with("data/maps"));
    }

    #[test]
    fn startup_config_reads_startup_section_map_id() {
        let config = parse_runtime_startup_config(
            r#"
[Startup]
startup_map = "survivor_outpost_01_grid"
"#,
        )
        .expect("runtime startup config should parse");

        assert_eq!(
            config,
            RuntimeStartupConfig {
                startup_map: Some(MapId("survivor_outpost_01_grid".into())),
            }
        );
    }

    #[test]
    fn startup_config_allows_blank_startup_map() {
        let config = parse_runtime_startup_config(
            r#"
[Startup]
startup_map =
"#,
        )
        .expect("blank startup_map should parse");

        assert_eq!(config, RuntimeStartupConfig { startup_map: None });
    }

    #[test]
    fn startup_map_resolution_prefers_configured_map() {
        let maps = sample_map_library();

        let resolved =
            resolve_startup_map_id(&maps, Some(MapId("survivor_outpost_01_grid".into())));

        assert_eq!(resolved, Some(MapId("survivor_outpost_01_grid".into())));
    }

    #[test]
    fn startup_map_resolution_falls_back_to_first_available_map() {
        let maps = sample_map_library();

        let resolved = resolve_startup_map_id(&maps, None);

        assert_eq!(resolved, Some(MapId("survivor_outpost_01_grid".into())));
    }

    #[test]
    fn loading_missing_startup_config_returns_default() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be available")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("missing_runtime_startup_{suffix}.ini"));

        let config = load_runtime_startup_config(&path).expect("missing file should be allowed");

        assert_eq!(config, RuntimeStartupConfig::default());
    }

    fn capture_rejections(
        mut rejections: MessageReader<CharacterSpawnRejected>,
        mut captured: ResMut<CapturedRejections>,
    ) {
        captured.0.extend(rejections.read().cloned());
    }

    fn sample_library() -> CharacterLibrary {
        let definitions = vec![
            sample_definition(
                "player",
                CharacterArchetype::Player,
                CharacterDisposition::Player,
                "survivor",
                "Rust Player",
            ),
            sample_definition(
                "trader_lao_wang",
                CharacterArchetype::Npc,
                CharacterDisposition::Friendly,
                "survivor",
                "废土商人·老王",
            ),
            sample_definition(
                "zombie_walker",
                CharacterArchetype::Enemy,
                CharacterDisposition::Hostile,
                "infected",
                "行尸",
            ),
        ];

        let mut map = BTreeMap::new();
        for definition in definitions {
            map.insert(definition.id.clone(), definition);
        }
        CharacterLibrary::from(map)
    }

    fn sample_map_library() -> MapLibrary {
        let definition = MapDefinition {
            id: MapId("survivor_outpost_01_grid".into()),
            name: "Survivor Outpost 01".into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![
                MapLevelDefinition {
                    y: 0,
                    cells: vec![MapCellDefinition {
                        x: 2,
                        z: 1,
                        blocks_movement: true,
                        blocks_sight: true,
                        terrain: "pillar".into(),
                        extra: BTreeMap::new(),
                    }],
                },
                MapLevelDefinition {
                    y: 1,
                    cells: Vec::new(),
                },
            ],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![MapObjectDefinition {
                object_id: "house".into(),
                kind: MapObjectKind::Building,
                anchor: GridCoord::new(7, 0, 4),
                footprint: MapObjectFootprint {
                    width: 2,
                    height: 2,
                },
                rotation: MapRotation::North,
                blocks_movement: true,
                blocks_sight: true,
                props: MapObjectProps {
                    building: Some(MapBuildingProps {
                        prefab_id: "survivor_outpost_01_dormitory".into(),
                        layout: None,
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        };

        let mut maps = BTreeMap::new();
        maps.insert(definition.id.clone(), definition);
        MapLibrary::from(maps)
    }

    fn sample_overworld_library() -> OverworldLibrary {
        let definition = OverworldDefinition {
            id: OverworldId("main_overworld".into()),
            locations: vec![
                OverworldLocationDefinition {
                    id: OverworldLocationId("survivor_outpost_01".into()),
                    name: "Survivor Outpost 01".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("survivor_outpost_01_grid".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(0, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                },
                OverworldLocationDefinition {
                    id: OverworldLocationId("street_a".into()),
                    name: "Street A".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("survivor_outpost_01_grid".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(-1, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                },
            ],
            walkable_cells: vec![
                OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(-1, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
            ],
            travel_rules: OverworldTravelRuleSet::default(),
        };

        let mut definitions = BTreeMap::new();
        definitions.insert(definition.id.clone(), definition);
        OverworldLibrary::from(definitions)
    }

    fn sample_definition(
        id: &str,
        archetype: CharacterArchetype,
        disposition: CharacterDisposition,
        camp_id: &str,
        display_name: &str,
    ) -> CharacterDefinition {
        CharacterDefinition {
            id: CharacterId(id.to_string()),
            archetype,
            identity: CharacterIdentity {
                display_name: display_name.to_string(),
                description: "sample".to_string(),
            },
            faction: CharacterFaction {
                camp_id: camp_id.to_string(),
                disposition,
            },
            presentation: CharacterPresentation {
                portrait_path: String::new(),
                avatar_path: String::new(),
                model_path: String::new(),
                placeholder_colors: CharacterPlaceholderColors {
                    head: "#eecba0".to_string(),
                    body: "#6a9add".to_string(),
                    legs: "#3c5c90".to_string(),
                },
            },
            progression: CharacterProgression { level: 5 },
            combat: CharacterCombatProfile {
                behavior: "neutral".to_string(),
                xp_reward: 25,
                loot: vec![CharacterLootEntry {
                    item_id: 1010,
                    chance: 0.2,
                    min: 1,
                    max: 2,
                }],
            },
            ai: CharacterAiProfile {
                aggro_range: 0.0,
                attack_range: 1.2,
                wander_radius: 3.0,
                leash_distance: 5.0,
                decision_interval: 1.2,
                attack_cooldown: 999.0,
            },
            attributes: CharacterAttributeTemplate {
                sets: BTreeMap::from([
                    (
                        "base".to_string(),
                        BTreeMap::from([("strength".to_string(), 5.0)]),
                    ),
                    (
                        "combat".to_string(),
                        BTreeMap::from([("max_hp".to_string(), 60.0)]),
                    ),
                ]),
                resources: BTreeMap::from([(
                    "hp".to_string(),
                    CharacterResourcePool { current: 60.0 },
                )]),
            },
            interaction: None,
            life: None,
        }
    }
}
