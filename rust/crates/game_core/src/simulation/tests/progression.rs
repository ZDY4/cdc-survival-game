use super::*;

#[test]
fn lethal_attack_grants_xp_and_levels_up_attacker() {
    let mut simulation = Simulation::new();
    let player = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let hostile = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Hostile".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.seed_actor_progression(player, 1, 0);
    simulation.seed_actor_progression(hostile, 1, 100);
    simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
    simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
    simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
    simulation.set_actor_resource(hostile, "hp", 5.0);

    let result = simulation.perform_attack(player, hostile);

    assert!(result.success);
    assert_eq!(simulation.actor_level(player), 2);
    assert_eq!(simulation.actor_current_xp(player), 0);
    assert_eq!(
        simulation
            .actor_progression
            .get(&player)
            .map(|state| (state.available_stat_points, state.available_skill_points)),
        Some((3, 1))
    );
    assert_eq!(
        simulation.economy.actor(player).map(|state| state.level),
        Some(2)
    );
}

#[test]
fn kill_objective_completes_quest_and_grants_reward() {
    let mut simulation = Simulation::new();
    simulation.set_quest_library(sample_quest_library());
    simulation.set_recipe_library(RecipeLibrary::default());
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let hostile = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("zombie_walker".into())),
        display_name: "Zombie".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.seed_actor_progression(player, 1, 0);
    simulation.seed_actor_progression(hostile, 1, 25);
    simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
    simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
    simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
    simulation.set_actor_resource(hostile, "hp", 5.0);

    assert!(simulation.start_quest(player, "zombie_hunter"));

    let result = simulation.perform_attack(player, hostile);

    assert!(result.success);
    assert!(simulation.completed_quests.contains("zombie_hunter"));
    assert_eq!(simulation.inventory_count(player, "1006"), 3);
    assert_eq!(simulation.actor_current_xp(player), 35);
}

#[test]
fn collect_objective_completes_after_pickup_and_grants_skill_points() {
    let items = sample_combat_item_library();
    let mut simulation = Simulation::new();
    simulation.set_item_library(items);
    simulation.set_quest_library(sample_quest_library());
    simulation.set_recipe_library(RecipeLibrary::default());
    simulation
        .grid_world_mut()
        .load_map(&sample_collect_quest_map_definition());
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(1, 0, 1),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.seed_actor_progression(player, 1, 0);

    assert!(simulation.start_quest(player, "collect_food"));

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject("food_pickup".into()),
        option_id: InteractionOptionId("pickup".into()),
    });

    assert!(result.success);
    assert!(simulation.completed_quests.contains("collect_food"));
    assert_eq!(simulation.inventory_count(player, "1007"), 2);
    assert_eq!(simulation.actor_current_xp(player), 50);
    assert_eq!(
        simulation
            .economy
            .actor(player)
            .map(|state| state.skill_points),
        Some(2)
    );
}

#[test]
fn manual_turn_in_collect_objective_waits_for_dialogue_delivery() {
    let items = sample_combat_item_library();
    let mut simulation = Simulation::new();
    simulation.set_item_library(items);
    simulation.set_quest_library(QuestLibrary::from(BTreeMap::from([(
        "deliver_medkit".to_string(),
        QuestDefinition {
            quest_id: "deliver_medkit".to_string(),
            title: "交付急救包".to_string(),
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
                            item_id: Some(1005),
                            count: 1,
                            extra: BTreeMap::from([(
                                "manual_turn_in".to_string(),
                                serde_json::Value::Bool(true),
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
                                experience: 25,
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
    )])));
    simulation
        .grid_world_mut()
        .load_map(&sample_interaction_map_definition());
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(1, 0, 1),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    assert!(simulation.start_quest(player, "deliver_medkit"));

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject("pickup".into()),
        option_id: InteractionOptionId("pickup".into()),
    });

    assert!(result.success);
    assert!(simulation.is_quest_active("deliver_medkit"));
    assert!(!simulation.is_quest_completed("deliver_medkit"));
    assert_eq!(simulation.inventory_count(player, "1005"), 2);

    simulation
        .turn_in_active_quest(player, "deliver_medkit")
        .expect("manual turn-in should succeed");

    assert!(simulation.is_quest_completed("deliver_medkit"));
    assert_eq!(simulation.inventory_count(player, "1005"), 1);
    assert_eq!(simulation.actor_current_xp(player), 25);
}

#[test]
fn relationship_scores_seed_from_actor_sides() {
    let mut simulation = Simulation::new();
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let trader = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("trader_lao_wang".into())),
        display_name: "Trader".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "friendly".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let zombie = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("zombie_walker".into())),
        display_name: "Zombie".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    assert_eq!(simulation.get_relationship_score(player, trader), 40);
    assert_eq!(simulation.get_relationship_score(trader, player), 40);
    assert_eq!(simulation.get_relationship_score(player, zombie), -60);
    assert_eq!(simulation.get_relationship_score(zombie, player), -60);
}

#[test]
fn relationship_score_mutation_clamps_to_range() {
    let mut simulation = Simulation::new();
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let trader = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("trader_lao_wang".into())),
        display_name: "Trader".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "friendly".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    assert_eq!(simulation.set_relationship_score(player, trader, 120), 100);
    assert_eq!(simulation.get_relationship_score(player, trader), 100);
    assert_eq!(
        simulation.adjust_relationship_score(player, trader, -250),
        -100
    );
    assert_eq!(simulation.get_relationship_score(player, trader), -100);
}
