use std::collections::BTreeMap;

use game_data::{
    ActionPhase, ActionRequest, ActionType, ActorKind, ActorSide, CharacterId, CharacterLootEntry,
    DialogueAction, DialogueData, DialogueLibrary, DialogueNode, DialogueOption,
    DialogueRuleConditions, DialogueRuleDefinition, DialogueRuleLibrary, DialogueRuleVariant,
    GridCoord, InteractionExecutionRequest, InteractionOptionDefinition, InteractionOptionId,
    InteractionOptionKind, InteractionTargetId, ItemDefinition, ItemFragment, ItemLibrary,
    MapBuildingLayoutSpec, MapBuildingProps, MapBuildingStairSpec, MapBuildingStorySpec,
    MapCellDefinition, MapDefinition, MapEntryPointDefinition, MapId, MapInteractiveProps,
    MapLevelDefinition, MapLibrary, MapObjectDefinition, MapObjectFootprint, MapObjectKind,
    MapObjectProps, MapPickupProps, MapRotation, MapSize, MapTriggerProps, OverworldCellDefinition,
    OverworldDefinition, OverworldId, OverworldLibrary, OverworldLocationDefinition,
    OverworldLocationId, OverworldLocationKind, OverworldTerrainKind, OverworldTravelRuleSet,
    QuestConnection, QuestDefinition, QuestFlow, QuestLibrary, QuestNode, QuestRewards,
    RecipeLibrary, RelativeGridCell, SkillActivationDefinition, SkillActivationEffect,
    SkillDefinition, SkillExecutionKind, SkillLibrary, SkillModifierDefinition, SkillTargetRequest,
    SkillTargetSideRule, SkillTargetingDefinition, StairKind, WorldCoord, WorldMode,
    WorldWallTileSetId,
};

use crate::grid::GridPathfindingError;
use crate::movement::PendingProgressionStep;
use crate::runtime_ai::{FollowRuntimeGoalController, OneShotInteractController};
use crate::RuntimeAiController;

use super::{
    RegisterActor, Simulation, SimulationCommand, SimulationCommandResult, SimulationEvent,
};

mod actions;
mod combat;
mod dialogue;
mod overworld;
mod progression;
mod snapshot;
mod spatial;

fn advance_next_progression(simulation: &mut Simulation) -> Option<PendingProgressionStep> {
    let step = simulation.pop_pending_progression()?;
    simulation.apply_pending_progression_step(step);
    Some(step)
}

fn advance_all_progression(simulation: &mut Simulation) {
    while advance_next_progression(simulation).is_some() {}
}

fn sample_map_definition() -> MapDefinition {
    MapDefinition {
        id: MapId("sample_map".into()),
        name: "Sample".into(),
        size: MapSize {
            width: 12,
            height: 12,
        },
        default_level: 0,
        levels: vec![
            MapLevelDefinition {
                y: 0,
                cells: vec![MapCellDefinition {
                    x: 8,
                    z: 8,
                    blocks_movement: true,
                    blocks_sight: true,
                    terrain: "pillar".into(),
                    visual: None,
                    extra: std::collections::BTreeMap::new(),
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
        objects: vec![
            MapObjectDefinition {
                object_id: "house".into(),
                kind: MapObjectKind::Building,
                anchor: GridCoord::new(4, 0, 2),
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
                        wall_visual: Some(game_data::MapBuildingWallVisualSpec {
                            kind: game_data::MapBuildingWallVisualKind::LegacyGrid,
                        }),
                        tile_set: None,
                        layout: None,
                        extra: std::collections::BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            },
            MapObjectDefinition {
                object_id: "pickup".into(),
                kind: MapObjectKind::Pickup,
                anchor: GridCoord::new(2, 0, 1),
                footprint: MapObjectFootprint::default(),
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps::default(),
            },
        ],
    }
}

fn sample_two_level_combat_map_definition() -> MapDefinition {
    MapDefinition {
        id: MapId("combat_two_level_map".into()),
        name: "Combat Two Level".into(),
        size: MapSize {
            width: 6,
            height: 6,
        },
        default_level: 0,
        levels: vec![
            MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
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
        objects: Vec::new(),
    }
}

fn sample_combat_los_map_definition() -> MapDefinition {
    let mut map = sample_two_level_combat_map_definition();
    map.id = MapId("combat_los_map".into());
    map.name = "Combat LoS".into();
    map.levels[0].cells.push(MapCellDefinition {
        x: 1,
        z: 0,
        blocks_movement: true,
        blocks_sight: true,
        terrain: "wall".into(),
        visual: None,
        extra: BTreeMap::new(),
    });
    map
}

fn sample_aoe_occlusion_map_definition() -> MapDefinition {
    let mut map = sample_two_level_combat_map_definition();
    map.id = MapId("combat_aoe_occlusion_map".into());
    map.name = "Combat AOE Occlusion".into();
    map.levels[0].cells.push(MapCellDefinition {
        x: 3,
        z: 0,
        blocks_movement: true,
        blocks_sight: true,
        terrain: "wall".into(),
        visual: None,
        extra: BTreeMap::new(),
    });
    map
}

fn sample_spatial_skill_library() -> SkillLibrary {
    SkillLibrary::from(BTreeMap::from([
        (
            "fire_bolt".to_string(),
            SkillDefinition {
                id: "fire_bolt".to_string(),
                name: "Fire Bolt".to_string(),
                activation: Some(SkillActivationDefinition {
                    mode: "active".to_string(),
                    cooldown: 0.0,
                    effect: Some(SkillActivationEffect {
                        modifiers: BTreeMap::from([(
                            "damage".to_string(),
                            SkillModifierDefinition {
                                base: 4.0,
                                per_level: 1.0,
                                max_value: 6.0,
                                ..SkillModifierDefinition::default()
                            },
                        )]),
                        ..SkillActivationEffect::default()
                    }),
                    targeting: Some(SkillTargetingDefinition {
                        enabled: true,
                        range_cells: 5,
                        shape: "single".to_string(),
                        radius: 0,
                        execution_kind: SkillExecutionKind::DamageSingle,
                        target_side_rule: SkillTargetSideRule::HostileOnly,
                        allow_self: false,
                        ..SkillTargetingDefinition::default()
                    }),
                    ..SkillActivationDefinition::default()
                }),
                ..SkillDefinition::default()
            },
        ),
        (
            "shockwave".to_string(),
            SkillDefinition {
                id: "shockwave".to_string(),
                name: "Shockwave".to_string(),
                activation: Some(SkillActivationDefinition {
                    mode: "active".to_string(),
                    cooldown: 0.0,
                    effect: Some(SkillActivationEffect {
                        modifiers: BTreeMap::from([(
                            "damage".to_string(),
                            SkillModifierDefinition {
                                base: 2.0,
                                per_level: 0.5,
                                max_value: 3.0,
                                ..SkillModifierDefinition::default()
                            },
                        )]),
                        ..SkillActivationEffect::default()
                    }),
                    targeting: Some(SkillTargetingDefinition {
                        enabled: true,
                        range_cells: 3,
                        shape: "diamond".to_string(),
                        radius: 1,
                        execution_kind: SkillExecutionKind::DamageAoe,
                        ..SkillTargetingDefinition::default()
                    }),
                    ..SkillActivationDefinition::default()
                }),
                ..SkillDefinition::default()
            },
        ),
        (
            "shockwave_wide".to_string(),
            SkillDefinition {
                id: "shockwave_wide".to_string(),
                name: "Shockwave Wide".to_string(),
                activation: Some(SkillActivationDefinition {
                    mode: "active".to_string(),
                    cooldown: 0.0,
                    effect: Some(SkillActivationEffect {
                        modifiers: BTreeMap::from([(
                            "damage".to_string(),
                            SkillModifierDefinition {
                                base: 2.0,
                                per_level: 0.5,
                                max_value: 3.0,
                                ..SkillModifierDefinition::default()
                            },
                        )]),
                        ..SkillActivationEffect::default()
                    }),
                    targeting: Some(SkillTargetingDefinition {
                        enabled: true,
                        range_cells: 4,
                        shape: "diamond".to_string(),
                        radius: 2,
                        execution_kind: SkillExecutionKind::DamageAoe,
                        ..SkillTargetingDefinition::default()
                    }),
                    ..SkillActivationDefinition::default()
                }),
                ..SkillDefinition::default()
            },
        ),
        (
            "shockwave_hostile_only".to_string(),
            SkillDefinition {
                id: "shockwave_hostile_only".to_string(),
                name: "Shockwave Hostile Only".to_string(),
                activation: Some(SkillActivationDefinition {
                    mode: "active".to_string(),
                    cooldown: 0.0,
                    effect: Some(SkillActivationEffect {
                        modifiers: BTreeMap::from([(
                            "damage".to_string(),
                            SkillModifierDefinition {
                                base: 2.0,
                                per_level: 0.5,
                                max_value: 3.0,
                                ..SkillModifierDefinition::default()
                            },
                        )]),
                        ..SkillActivationEffect::default()
                    }),
                    targeting: Some(SkillTargetingDefinition {
                        enabled: true,
                        range_cells: 3,
                        shape: "diamond".to_string(),
                        radius: 1,
                        execution_kind: SkillExecutionKind::DamageAoe,
                        target_side_rule: SkillTargetSideRule::HostileOnly,
                        allow_self: false,
                        allow_friendly_fire: false,
                        ..SkillTargetingDefinition::default()
                    }),
                    ..SkillActivationDefinition::default()
                }),
                ..SkillDefinition::default()
            },
        ),
    ]))
}

fn sample_generated_building_map_definition() -> MapDefinition {
    MapDefinition {
        id: MapId("generated_building_map".into()),
        name: "Generated Building".into(),
        size: MapSize {
            width: 8,
            height: 8,
        },
        default_level: 0,
        levels: vec![
            MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
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
            object_id: "layout_building".into(),
            kind: MapObjectKind::Building,
            anchor: GridCoord::new(1, 0, 1),
            footprint: MapObjectFootprint {
                width: 5,
                height: 5,
            },
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                building: Some(MapBuildingProps {
                    prefab_id: "generated_house".into(),
                    wall_visual: Some(game_data::MapBuildingWallVisualSpec {
                        kind: game_data::MapBuildingWallVisualKind::LegacyGrid,
                    }),
                    tile_set: Some(sample_building_tile_set()),
                    layout: Some(MapBuildingLayoutSpec {
                        seed: 7,
                        target_room_count: 3,
                        min_room_size: MapSize {
                            width: 2,
                            height: 2,
                        },
                        shape_cells: (0..5)
                            .flat_map(|z| (0..5).map(move |x| RelativeGridCell::new(x, z)))
                            .collect(),
                        stories: vec![
                            MapBuildingStorySpec {
                                level: 0,
                                shape_cells: Vec::new(),
                            },
                            MapBuildingStorySpec {
                                level: 1,
                                shape_cells: Vec::new(),
                            },
                        ],
                        stairs: vec![MapBuildingStairSpec {
                            from_level: 0,
                            to_level: 1,
                            from_cells: vec![RelativeGridCell::new(1, 1)],
                            to_cells: vec![RelativeGridCell::new(1, 1)],
                            width: 1,
                            kind: StairKind::Straight,
                        }],
                        ..MapBuildingLayoutSpec::default()
                    }),
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        }],
    }
}

fn sample_building_tile_set() -> game_data::MapBuildingTileSetSpec {
    game_data::MapBuildingTileSetSpec {
        wall_set_id: WorldWallTileSetId("building_wall_legacy".into()),
        floor_surface_set_id: Some(game_data::WorldSurfaceTileSetId(
            "building_wall_legacy/floor".into(),
        )),
        door_prototype_id: None,
    }
}

fn generated_door_passage_cells(
    world: &crate::grid::GridWorld,
    door: &crate::GeneratedDoorDebugState,
) -> (GridCoord, GridCoord) {
    let candidates = match door.axis {
        crate::GeometryAxis::Vertical => [
            GridCoord::new(
                door.anchor_grid.x - 1,
                door.anchor_grid.y,
                door.anchor_grid.z,
            ),
            GridCoord::new(
                door.anchor_grid.x + 1,
                door.anchor_grid.y,
                door.anchor_grid.z,
            ),
        ],
        crate::GeometryAxis::Horizontal => [
            GridCoord::new(
                door.anchor_grid.x,
                door.anchor_grid.y,
                door.anchor_grid.z - 1,
            ),
            GridCoord::new(
                door.anchor_grid.x,
                door.anchor_grid.y,
                door.anchor_grid.z + 1,
            ),
        ],
    };
    assert!(
        world.is_walkable(candidates[0]) && world.is_walkable(candidates[1]),
        "generated door should connect two walkable adjacent cells"
    );
    (candidates[0], candidates[1])
}

fn sample_interaction_map_definition() -> MapDefinition {
    MapDefinition {
        id: MapId("interaction_map".into()),
        name: "Interaction".into(),
        size: MapSize {
            width: 12,
            height: 12,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: Vec::new(),
        }],
        entry_points: vec![MapEntryPointDefinition {
            id: "default_entry".into(),
            grid: GridCoord::new(4, 0, 7),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: vec![
            MapObjectDefinition {
                object_id: "pickup".into(),
                kind: MapObjectKind::Pickup,
                anchor: GridCoord::new(2, 0, 1),
                footprint: MapObjectFootprint::default(),
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    pickup: Some(MapPickupProps {
                        item_id: "1005".into(),
                        min_count: 1,
                        max_count: 2,
                        extra: std::collections::BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            },
            MapObjectDefinition {
                object_id: "exit".into(),
                kind: MapObjectKind::Interactive,
                anchor: GridCoord::new(5, 0, 7),
                footprint: MapObjectFootprint::default(),
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    interactive: Some(MapInteractiveProps {
                        display_name: "Exit".into(),
                        interaction_distance: 1.4,
                        interaction_kind: "enter_outdoor_location".into(),
                        target_id: Some("survivor_outpost_01".into()),
                        options: Vec::new(),
                        extra: std::collections::BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            },
        ],
    }
}

fn sample_trigger_map_definition(
    anchor: GridCoord,
    footprint: MapObjectFootprint,
    rotation: MapRotation,
) -> MapDefinition {
    MapDefinition {
        id: MapId("trigger_map".into()),
        name: "Trigger".into(),
        size: MapSize {
            width: 12,
            height: 12,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: Vec::new(),
        }],
        entry_points: vec![MapEntryPointDefinition {
            id: "default_entry".into(),
            grid: GridCoord::new(1, 0, 7),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: vec![MapObjectDefinition {
            object_id: "exit_trigger".into(),
            kind: MapObjectKind::Trigger,
            anchor,
            footprint,
            rotation,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                trigger: Some(MapTriggerProps {
                    display_name: "进入幸存者据点".into(),
                    interaction_distance: 1.4,
                    interaction_kind: "enter_outdoor_location".into(),
                    target_id: Some("survivor_outpost_01".into()),
                    options: Vec::new(),
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        }],
    }
}

fn sample_scene_transition_map_library() -> MapLibrary {
    MapLibrary::from(BTreeMap::from([
        (
            MapId("survivor_outpost_01".into()),
            sample_scene_transition_outdoor_map_definition(),
        ),
        (
            MapId("survivor_outpost_01_interior".into()),
            sample_scene_transition_interior_map_definition(),
        ),
    ]))
}

fn sample_scene_transition_outdoor_map_definition() -> MapDefinition {
    MapDefinition {
        id: MapId("survivor_outpost_01".into()),
        name: "Outpost Outdoor".into(),
        size: MapSize {
            width: 12,
            height: 12,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: Vec::new(),
        }],
        entry_points: vec![
            MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(0, 0, 0),
                facing: None,
                extra: BTreeMap::new(),
            },
            MapEntryPointDefinition {
                id: "interior_return".into(),
                grid: GridCoord::new(6, 0, 6),
                facing: None,
                extra: BTreeMap::new(),
            },
        ],
        objects: Vec::new(),
    }
}

fn sample_scene_transition_interior_map_definition() -> MapDefinition {
    MapDefinition {
        id: MapId("survivor_outpost_01_interior".into()),
        name: "Outpost Interior".into(),
        size: MapSize {
            width: 8,
            height: 8,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: Vec::new(),
        }],
        entry_points: vec![
            MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(2, 0, 2),
                facing: None,
                extra: BTreeMap::new(),
            },
            MapEntryPointDefinition {
                id: "outdoor_return".into(),
                grid: GridCoord::new(2, 0, 2),
                facing: None,
                extra: BTreeMap::new(),
            },
        ],
        objects: vec![MapObjectDefinition {
            object_id: "interior_exit".into(),
            kind: MapObjectKind::Interactive,
            anchor: GridCoord::new(2, 0, 2),
            footprint: MapObjectFootprint::default(),
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                interactive: Some(MapInteractiveProps {
                    display_name: "Exit".into(),
                    interaction_distance: 1.4,
                    interaction_kind: String::new(),
                    target_id: None,
                    options: vec![InteractionOptionDefinition {
                        id: InteractionOptionId("exit_to_outdoor".into()),
                        display_name: "Exit".into(),
                        interaction_distance: 1.4,
                        kind: InteractionOptionKind::ExitToOutdoor,
                        target_id: "survivor_outpost_01".into(),
                        return_spawn_id: "interior_return".into(),
                        ..InteractionOptionDefinition::default()
                    }],
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        }],
    }
}

fn sample_scene_transition_overworld_library() -> OverworldLibrary {
    OverworldLibrary::from(BTreeMap::from([(
        OverworldId("scene_transition_test".into()),
        OverworldDefinition {
            id: OverworldId("scene_transition_test".into()),
            size: MapSize {
                width: 1,
                height: 1,
            },
            locations: vec![
                OverworldLocationDefinition {
                    id: OverworldLocationId("survivor_outpost_01".into()),
                    name: "Outpost".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("survivor_outpost_01".into()),
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
                    id: OverworldLocationId("survivor_outpost_01_interior".into()),
                    name: "Outpost Interior".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Interior,
                    map_id: MapId("survivor_outpost_01_interior".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: Some(OverworldLocationId(
                        "survivor_outpost_01".into(),
                    )),
                    return_entry_point_id: Some("outdoor_return".into()),
                    default_unlocked: true,
                    visible: false,
                    overworld_cell: GridCoord::new(0, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                },
            ],
            cells: vec![OverworldCellDefinition {
                grid: GridCoord::new(0, 0, 0),
                terrain: OverworldTerrainKind::Road,
                blocked: false,
                visual: None,
                extra: BTreeMap::new(),
            }],
            travel_rules: OverworldTravelRuleSet::default(),
        },
    )]))
}

fn sample_collect_quest_map_definition() -> MapDefinition {
    MapDefinition {
        id: MapId("collect_map".into()),
        name: "Collect".into(),
        size: MapSize {
            width: 8,
            height: 8,
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
        objects: vec![MapObjectDefinition {
            object_id: "food_pickup".into(),
            kind: MapObjectKind::Pickup,
            anchor: GridCoord::new(2, 0, 1),
            footprint: MapObjectFootprint::default(),
            rotation: MapRotation::North,
            blocks_movement: false,
            blocks_sight: false,
            props: MapObjectProps {
                pickup: Some(MapPickupProps {
                    item_id: "1007".into(),
                    min_count: 2,
                    max_count: 2,
                    extra: BTreeMap::new(),
                }),
                ..MapObjectProps::default()
            },
        }],
    }
}

fn sample_quest_library() -> QuestLibrary {
    QuestLibrary::from(BTreeMap::from([
        (
            "zombie_hunter".to_string(),
            QuestDefinition {
                quest_id: "zombie_hunter".to_string(),
                title: "僵尸猎人".to_string(),
                description: "击败一只僵尸".to_string(),
                flow: QuestFlow {
                    start_node_id: "start".to_string(),
                    nodes: BTreeMap::from([
                        (
                            "start".to_string(),
                            QuestNode {
                                id: "start".to_string(),
                                node_type: "start".to_string(),
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "kill_one".to_string(),
                            QuestNode {
                                id: "kill_one".to_string(),
                                node_type: "objective".to_string(),
                                objective_type: "kill".to_string(),
                                count: 1,
                                extra: BTreeMap::from([(
                                    "enemy_type".to_string(),
                                    serde_json::Value::String("zombie".to_string()),
                                )]),
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "reward".to_string(),
                            QuestNode {
                                id: "reward".to_string(),
                                node_type: "reward".to_string(),
                                rewards: QuestRewards {
                                    items: vec![game_data::QuestRewardItem {
                                        id: 1006,
                                        count: 3,
                                        extra: BTreeMap::new(),
                                    }],
                                    experience: 10,
                                    ..QuestRewards::default()
                                },
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "end".to_string(),
                            QuestNode {
                                id: "end".to_string(),
                                node_type: "end".to_string(),
                                ..QuestNode::default()
                            },
                        ),
                    ]),
                    connections: vec![
                        QuestConnection {
                            from: "start".to_string(),
                            to: "kill_one".to_string(),
                            from_port: 0,
                            to_port: 0,
                            extra: BTreeMap::new(),
                        },
                        QuestConnection {
                            from: "kill_one".to_string(),
                            to: "reward".to_string(),
                            from_port: 0,
                            to_port: 0,
                            extra: BTreeMap::new(),
                        },
                        QuestConnection {
                            from: "reward".to_string(),
                            to: "end".to_string(),
                            from_port: 0,
                            to_port: 0,
                            extra: BTreeMap::new(),
                        },
                    ],
                    ..QuestFlow::default()
                },
                ..QuestDefinition::default()
            },
        ),
        (
            "collect_food".to_string(),
            QuestDefinition {
                quest_id: "collect_food".to_string(),
                title: "搜集食物".to_string(),
                description: "捡起两份罐头".to_string(),
                flow: QuestFlow {
                    start_node_id: "start".to_string(),
                    nodes: BTreeMap::from([
                        (
                            "start".to_string(),
                            QuestNode {
                                id: "start".to_string(),
                                node_type: "start".to_string(),
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "collect".to_string(),
                            QuestNode {
                                id: "collect".to_string(),
                                node_type: "objective".to_string(),
                                objective_type: "collect".to_string(),
                                item_id: Some(1007),
                                count: 2,
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "reward".to_string(),
                            QuestNode {
                                id: "reward".to_string(),
                                node_type: "reward".to_string(),
                                rewards: QuestRewards {
                                    experience: 50,
                                    skill_points: 2,
                                    ..QuestRewards::default()
                                },
                                ..QuestNode::default()
                            },
                        ),
                        (
                            "end".to_string(),
                            QuestNode {
                                id: "end".to_string(),
                                node_type: "end".to_string(),
                                ..QuestNode::default()
                            },
                        ),
                    ]),
                    connections: vec![
                        QuestConnection {
                            from: "start".to_string(),
                            to: "collect".to_string(),
                            from_port: 0,
                            to_port: 0,
                            extra: BTreeMap::new(),
                        },
                        QuestConnection {
                            from: "collect".to_string(),
                            to: "reward".to_string(),
                            from_port: 0,
                            to_port: 0,
                            extra: BTreeMap::new(),
                        },
                        QuestConnection {
                            from: "reward".to_string(),
                            to: "end".to_string(),
                            from_port: 0,
                            to_port: 0,
                            extra: BTreeMap::new(),
                        },
                    ],
                    ..QuestFlow::default()
                },
                ..QuestDefinition::default()
            },
        ),
    ]))
}

fn sample_dialogue_library() -> DialogueLibrary {
    DialogueLibrary::from(BTreeMap::from([
        (
            "trader_lao_wang".to_string(),
            DialogueData {
                dialog_id: "trader_lao_wang".to_string(),
                nodes: vec![
                    DialogueNode {
                        id: "start".to_string(),
                        node_type: "dialog".to_string(),
                        is_start: true,
                        next: "choice_1".to_string(),
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "choice_1".to_string(),
                        node_type: "choice".to_string(),
                        options: vec![
                            DialogueOption {
                                text: "Trade".to_string(),
                                next: "trade_action".to_string(),
                                ..DialogueOption::default()
                            },
                            DialogueOption {
                                text: "Leave".to_string(),
                                next: "leave_end".to_string(),
                                ..DialogueOption::default()
                            },
                        ],
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "trade_action".to_string(),
                        node_type: "action".to_string(),
                        actions: vec![DialogueAction {
                            action_type: "open_trade".to_string(),
                            extra: BTreeMap::new(),
                        }],
                        next: "trade_end".to_string(),
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "trade_end".to_string(),
                        node_type: "end".to_string(),
                        end_type: "trade".to_string(),
                        ..DialogueNode::default()
                    },
                    DialogueNode {
                        id: "leave_end".to_string(),
                        node_type: "end".to_string(),
                        end_type: "leave".to_string(),
                        ..DialogueNode::default()
                    },
                ],
                ..DialogueData::default()
            },
        ),
        (
            "doctor_chen".to_string(),
            DialogueData {
                dialog_id: "doctor_chen".to_string(),
                nodes: vec![DialogueNode {
                    id: "start".to_string(),
                    node_type: "dialog".to_string(),
                    is_start: true,
                    text: "Default doctor dialogue".to_string(),
                    ..DialogueNode::default()
                }],
                ..DialogueData::default()
            },
        ),
        (
            "doctor_chen_medical".to_string(),
            DialogueData {
                dialog_id: "doctor_chen_medical".to_string(),
                nodes: vec![DialogueNode {
                    id: "start".to_string(),
                    node_type: "dialog".to_string(),
                    is_start: true,
                    text: "Medical variant".to_string(),
                    ..DialogueNode::default()
                }],
                ..DialogueData::default()
            },
        ),
    ]))
}

fn sample_dialogue_rule_library() -> DialogueRuleLibrary {
    DialogueRuleLibrary::from(BTreeMap::from([(
        "doctor_chen".to_string(),
        DialogueRuleDefinition {
            dialogue_key: "doctor_chen".to_string(),
            default_dialogue_id: "doctor_chen".to_string(),
            variants: vec![DialogueRuleVariant {
                dialogue_id: "doctor_chen_medical".to_string(),
                when: DialogueRuleConditions {
                    relation_score_min: Some(50),
                    ..DialogueRuleConditions::default()
                },
                extra: BTreeMap::new(),
            }],
            extra: BTreeMap::new(),
        },
    )]))
}

fn sample_combat_item_library() -> ItemLibrary {
    ItemLibrary::from(BTreeMap::from([
        (
            1004,
            ItemDefinition {
                id: 1004,
                name: "手枪".into(),
                value: 120,
                weight: 1.2,
                fragments: vec![
                    ItemFragment::Equip {
                        slots: vec!["main_hand".into()],
                        level_requirement: 2,
                        equip_effect_ids: Vec::new(),
                        unequip_effect_ids: Vec::new(),
                    },
                    ItemFragment::Durability {
                        durability: 80,
                        max_durability: 80,
                        repairable: true,
                        repair_materials: Vec::new(),
                    },
                    ItemFragment::Weapon {
                        subtype: "pistol".into(),
                        damage: 18,
                        attack_speed: 1.0,
                        range: 12,
                        stamina_cost: 2,
                        crit_chance: 0.1,
                        crit_multiplier: 1.8,
                        accuracy: Some(70),
                        ammo_type: Some(1009),
                        max_ammo: Some(6),
                        reload_time: Some(1.5),
                        on_hit_effect_ids: Vec::new(),
                    },
                ],
                ..ItemDefinition::default()
            },
        ),
        (
            1009,
            ItemDefinition {
                id: 1009,
                name: "手枪弹药".into(),
                value: 5,
                weight: 0.1,
                fragments: vec![ItemFragment::Stacking {
                    stackable: true,
                    max_stack: 50,
                }],
                ..ItemDefinition::default()
            },
        ),
    ]))
}
