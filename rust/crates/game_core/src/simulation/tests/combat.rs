use super::*;

#[test]
fn equipped_ranged_weapon_extends_attack_range_and_consumes_resources() {
    let items = sample_combat_item_library();
    let mut simulation = Simulation::new();
    simulation.set_item_library(items.clone());

    let player = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Shooter".into(),
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
        display_name: "Target".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(4, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    simulation.economy.set_actor_level(player, 8);
    simulation
        .economy
        .add_item(player, 1004, 1, &items)
        .expect("pistol should add");
    simulation
        .economy
        .add_ammo(player, 1009, 6, &items)
        .expect("ammo should add");
    simulation
        .economy
        .equip_item(player, 1004, Some("main_hand"), &items)
        .expect("pistol should equip");
    simulation
        .economy
        .reload_equipped_weapon(player, "main_hand", &items)
        .expect("reload should succeed");

    let result = simulation.perform_attack(player, hostile);

    assert!(result.success);
    let weapon = simulation
        .economy
        .equipped_weapon(player, "main_hand", &items)
        .expect("weapon should resolve")
        .expect("weapon should remain equipped");
    assert_eq!(weapon.ammo_loaded, 5);
    assert_eq!(weapon.current_durability, Some(79));
}

#[test]
fn attack_damage_reduces_target_hit_points() {
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
    simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
    simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
    simulation.set_actor_combat_attribute(hostile, "max_hp", 20.0);
    simulation.set_actor_resource(hostile, "hp", 20.0);
    simulation.set_actor_combat_attribute(hostile, "defense", 2.0);

    let result = simulation.perform_attack(player, hostile);

    assert!(result.success);
    assert_eq!(simulation.actor_hit_points(hostile), 12.0);
    assert!(simulation.actors.contains(hostile));
}

#[test]
fn attack_resolved_event_reports_deterministic_crit_outcome() {
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
    simulation.set_combat_rng_seed(123);
    simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
    simulation.set_actor_combat_attribute(player, "crit_chance", 1.0);
    simulation.set_actor_combat_attribute(hostile, "max_hp", 20.0);
    simulation.set_actor_resource(hostile, "hp", 20.0);

    let result = simulation.perform_attack(player, hostile);

    assert!(result.success);
    let attack_event = simulation
        .drain_events()
        .into_iter()
        .find_map(|event| match event {
            SimulationEvent::AttackResolved {
                actor_id,
                target_actor,
                outcome,
            } if actor_id == player && target_actor == hostile => Some(outcome),
            _ => None,
        })
        .expect("attack outcome event should be emitted");
    assert_eq!(attack_event.hit_kind, game_data::AttackHitKind::Crit);
    assert!(attack_event.damage > 0.0);
    assert_eq!(
        attack_event.remaining_hp,
        simulation.actor_hit_points(hostile)
    );
}

#[test]
fn attack_outcome_is_reproducible_with_same_seed() {
    fn run_attack(seed: u64) -> game_data::AttackOutcome {
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
        simulation.set_combat_rng_seed(seed);
        simulation.set_actor_combat_attribute(player, "attack_power", 8.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 65.0);
        simulation.set_actor_combat_attribute(player, "crit_chance", 0.35);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 20.0);
        simulation.set_actor_resource(hostile, "hp", 20.0);

        let result = simulation.perform_attack(player, hostile);
        assert!(result.success);
        simulation
            .drain_events()
            .into_iter()
            .find_map(|event| match event {
                SimulationEvent::AttackResolved { outcome, .. } => Some(outcome),
                _ => None,
            })
            .expect("attack outcome event should exist")
    }

    let first = run_attack(77);
    let second = run_attack(77);

    assert_eq!(first, second);
}

#[test]
fn lethal_attack_unregisters_target_actor() {
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
    simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
    simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
    simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
    simulation.set_actor_resource(hostile, "hp", 5.0);

    let result = simulation.perform_attack(player, hostile);

    assert!(result.success);
    assert!(!simulation.actors.contains(hostile));
}

#[test]
fn lethal_attack_spawns_runtime_pickup_loot() {
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
    simulation.set_actor_combat_attribute(player, "attack_power", 10.0);
    simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
    simulation.set_actor_combat_attribute(hostile, "max_hp", 5.0);
    simulation.set_actor_resource(hostile, "hp", 5.0);
    simulation.seed_actor_loot_table(
        hostile,
        vec![CharacterLootEntry {
            item_id: 1010,
            chance: 1.0,
            min: 2,
            max: 2,
        }],
    );

    let result = simulation.perform_attack(player, hostile);

    assert!(result.success);
    let loot_object = simulation
        .grid_world()
        .map_object_entries()
        .into_iter()
        .find(|object| object.object_id.starts_with("loot_"))
        .expect("loot drop should be spawned");
    assert_eq!(loot_object.kind, MapObjectKind::Pickup);
    assert_eq!(loot_object.anchor, GridCoord::new(1, 0, 0));
    assert_eq!(
        loot_object.props.pickup.as_ref().map(|pickup| (
            pickup.item_id.clone(),
            pickup.min_count,
            pickup.max_count
        )),
        Some(("1010".to_string(), 2, 2))
    );
}

#[test]
fn combat_exits_when_hostiles_are_gone() {
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
        grid_position: GridCoord::new(3, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.enter_combat(player, hostile);
    assert!(simulation.is_in_combat());
    simulation.unregister_actor(hostile);
    assert!(!simulation.is_in_combat());
}

#[test]
fn combat_exits_after_three_actor_turns_without_hostile_sight() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_combat_los_map_definition());
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
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    simulation.enter_combat(player, hostile);

    simulation.end_current_combat_turn();
    assert!(simulation.is_in_combat());
    assert_eq!(simulation.turn.turns_without_hostile_player_sight, 1);
    assert_eq!(simulation.current_actor(), Some(hostile));

    simulation.end_current_combat_turn();
    assert!(simulation.is_in_combat());
    assert_eq!(simulation.turn.turns_without_hostile_player_sight, 2);
    assert_eq!(simulation.current_actor(), Some(player));

    simulation.end_current_combat_turn();
    assert!(!simulation.is_in_combat());
    assert_eq!(simulation.turn.turns_without_hostile_player_sight, 0);
    assert_eq!(
        simulation.peek_pending_progression(),
        Some(&PendingProgressionStep::StartNextNonCombatPlayerTurn)
    );

    assert_eq!(
        advance_next_progression(&mut simulation),
        Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
    );
    assert!(simulation.actor_turn_open(player));
}

#[test]
fn combat_exit_counter_resets_when_hostile_regains_sight() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_combat_los_map_definition());
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
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    simulation.enter_combat(player, hostile);
    simulation.end_current_combat_turn();
    assert_eq!(simulation.turn.turns_without_hostile_player_sight, 1);

    simulation.update_actor_grid_position(hostile, GridCoord::new(2, 0, 1));
    simulation.end_current_combat_turn();

    assert!(simulation.is_in_combat());
    assert_eq!(simulation.turn.turns_without_hostile_player_sight, 0);
    assert_eq!(simulation.current_actor(), Some(player));
}

#[test]
fn far_hostile_that_cannot_see_player_does_not_block_combat_exit() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_combat_los_map_definition());
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
    let near_hostile = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Near Hostile".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile:near".into(),
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let far_hostile = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Far Hostile".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile:far".into(),
        grid_position: GridCoord::new(5, 1, 5),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    simulation.enter_combat(player, near_hostile);

    for _ in 0..3 {
        simulation.end_current_combat_turn();
    }

    assert!(!simulation.is_in_combat());
    assert!(simulation.actors.contains(far_hostile));
}
