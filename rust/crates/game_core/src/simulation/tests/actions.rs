use super::*;

#[test]
fn player_registration_opens_initial_turn() {
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
    assert_eq!(simulation.get_actor_ap(player), 1.0);
    assert_eq!(simulation.get_actor_available_steps(player), 1);
}

#[test]
fn ap_carries_and_caps() {
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
    simulation.set_actor_ap(player, 1.5);
    let start = simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Interact,
        phase: ActionPhase::Start,
        steps: None,
        target_actor: None,
        cost_override: None,
        success: true,
    });
    assert!(start.success);
    assert_eq!(start.ap_before, 1.5);
    let complete = simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Interact,
        phase: ActionPhase::Complete,
        steps: None,
        target_actor: None,
        cost_override: None,
        success: true,
    });
    assert!(complete.success);
    assert_eq!(complete.ap_after, 0.5);
    assert_eq!(
        advance_next_progression(&mut simulation),
        Some(PendingProgressionStep::RunNonCombatWorldCycle)
    );
    assert_eq!(
        advance_next_progression(&mut simulation),
        Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
    );
    assert_eq!(simulation.get_actor_ap(player), 1.5);
}

#[test]
fn noncombat_completed_action_with_affordable_ap_does_not_queue_progression() {
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
    simulation.config.turn_ap_max = 2.0;
    simulation.set_actor_ap(player, 2.0);

    let start = simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Interact,
        phase: ActionPhase::Start,
        steps: None,
        target_actor: None,
        cost_override: None,
        success: true,
    });
    assert!(start.success);

    let complete = simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Interact,
        phase: ActionPhase::Complete,
        steps: None,
        target_actor: None,
        cost_override: None,
        success: true,
    });
    assert!(complete.success);
    assert_eq!(complete.ap_after, 1.0);
    assert!(simulation.pending_progression.is_empty());
    assert!(simulation.actor_turn_open(player));
}

#[test]
fn world_cycle_runs_ai_and_reopens_player_turn() {
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
    let friendly = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Friendly".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "friendly".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: Some(Box::new(OneShotInteractController)),
    });
    simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Interact,
        phase: ActionPhase::Start,
        steps: None,
        target_actor: None,
        cost_override: None,
        success: true,
    });
    simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Interact,
        phase: ActionPhase::Complete,
        steps: None,
        target_actor: None,
        cost_override: None,
        success: true,
    });
    advance_all_progression(&mut simulation);
    assert_eq!(simulation.get_actor_ap(friendly), 0.0);
    assert_eq!(simulation.get_actor_ap(player), 1.0);
}

#[test]
fn player_move_into_hostile_sight_enters_combat_and_keeps_player_turn() {
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
    simulation.config.turn_ap_max = 2.0;
    simulation.set_actor_ap(player, 2.0);

    let result = simulation.move_actor_to(player, GridCoord::new(1, 0, 1));

    assert!(result.success);
    assert!(result.entered_combat);
    assert!(simulation.is_in_combat());
    assert_eq!(simulation.current_actor(), Some(player));
    assert_eq!(simulation.current_group(), Some("player"));
    assert!(simulation.actor_turn_open(player));
    assert!(simulation
        .actors
        .get(hostile)
        .is_some_and(|actor| actor.in_combat));
}

#[test]
fn world_cycle_interrupts_when_hostile_gains_sight_of_player() {
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
    let scout = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Scout".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile:scout".into(),
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: Some(Box::new(FollowRuntimeGoalController)),
    });
    let trailing_hostile = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Trailing".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile:after".into(),
        grid_position: GridCoord::new(4, 0, 4),
        interaction: None,
        attack_range: 1.2,
        ai_controller: Some(Box::new(FollowRuntimeGoalController)),
    });
    simulation.set_actor_autonomous_movement_goal(scout, GridCoord::new(2, 0, 1));
    simulation.set_actor_autonomous_movement_goal(trailing_hostile, GridCoord::new(3, 0, 4));

    simulation.run_world_cycle();

    assert!(simulation.is_in_combat());
    assert_eq!(simulation.current_actor(), Some(scout));
    assert_eq!(
        simulation.peek_pending_progression(),
        Some(&PendingProgressionStep::EndCurrentCombatTurn)
    );
    assert_eq!(
        simulation.actor_grid_position(scout),
        Some(GridCoord::new(2, 0, 1))
    );
    assert_eq!(
        simulation.actor_grid_position(trailing_hostile),
        Some(GridCoord::new(4, 0, 4))
    );
    assert!(!simulation
        .drain_events()
        .into_iter()
        .any(|event| matches!(event, SimulationEvent::WorldCycleCompleted)));
    assert_eq!(simulation.current_group(), Some("hostile:scout"));
    assert!(simulation
        .actors
        .get(player)
        .is_some_and(|actor| actor.in_combat));
}

#[test]
fn combat_turn_gating_and_rotation_work() {
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
    let hostile_one = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Hostile One".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile:one".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let hostile_two = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Hostile Two".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile:two".into(),
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.set_actor_combat_attribute(player, "max_hp", 4.0);
    simulation.set_actor_resource(player, "hp", 4.0);
    simulation.enter_combat(player, hostile_one);
    let wrong_turn = simulation.request_action(ActionRequest {
        actor_id: hostile_one,
        action_type: ActionType::Interact,
        phase: ActionPhase::Start,
        steps: None,
        target_actor: None,
        cost_override: None,
        success: true,
    });
    assert!(!wrong_turn.success);
    assert_eq!(wrong_turn.reason.as_deref(), Some("not_actor_turn"));
    let attack = simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Attack,
        phase: ActionPhase::Start,
        steps: None,
        target_actor: Some(hostile_one),
        cost_override: None,
        success: true,
    });
    assert!(attack.success);
    let attack_slot_taken = simulation.request_action(ActionRequest {
        actor_id: hostile_two,
        action_type: ActionType::Attack,
        phase: ActionPhase::Start,
        steps: None,
        target_actor: Some(player),
        cost_override: None,
        success: true,
    });
    assert!(!attack_slot_taken.success);
    simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Attack,
        phase: ActionPhase::Complete,
        steps: None,
        target_actor: Some(hostile_one),
        cost_override: None,
        success: true,
    });
    assert_eq!(
        advance_next_progression(&mut simulation),
        Some(PendingProgressionStep::EndCurrentCombatTurn)
    );
    assert_ne!(
        simulation.current_actor(),
        Some(player),
        "combat should advance away from the acting player once the attack resolves"
    );
    assert!(
        simulation.current_turn_index() >= 1,
        "combat turn index should advance after a completed combat action"
    );
}

#[test]
fn combat_completed_action_with_affordable_ap_keeps_current_actor() {
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
    simulation.enter_combat(player, hostile);
    simulation.config.turn_ap_max = 2.0;
    simulation.set_actor_ap(player, 2.0);

    let start = simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Attack,
        phase: ActionPhase::Start,
        steps: None,
        target_actor: Some(hostile),
        cost_override: None,
        success: true,
    });
    assert!(start.success);

    let complete = simulation.request_action(ActionRequest {
        actor_id: player,
        action_type: ActionType::Attack,
        phase: ActionPhase::Complete,
        steps: None,
        target_actor: Some(hostile),
        cost_override: None,
        success: true,
    });
    assert!(complete.success);
    assert_eq!(complete.ap_after, 1.0);
    assert!(simulation.pending_progression.is_empty());
    assert_eq!(simulation.current_actor(), Some(player));
}

#[test]
fn combat_ai_attacks_nearest_hostile_target_when_in_range() {
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
    simulation.set_actor_combat_attribute(hostile, "attack_power", 6.0);
    simulation.set_actor_combat_attribute(player, "max_hp", 20.0);
    simulation.set_actor_resource(player, "hp", 20.0);
    simulation.set_actor_ap(hostile, 1.0);
    simulation.enter_combat(hostile, player);

    simulation.run_combat_ai_turn(hostile);

    assert!(simulation.actor_hit_points(player) < 20.0);
    assert_eq!(
        simulation.peek_pending_progression(),
        Some(&PendingProgressionStep::EndCurrentCombatTurn)
    );
}

#[test]
fn combat_ai_prefers_active_skill_before_basic_attack() {
    let mut simulation = Simulation::new();
    simulation.set_skill_library(sample_spatial_skill_library());
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
    simulation
        .economy
        .actor_mut(hostile)
        .expect("hostile should exist")
        .learned_skills
        .insert("fire_bolt".to_string(), 1);
    simulation.set_actor_combat_attribute(hostile, "attack_power", 2.0);
    simulation.set_actor_combat_attribute(player, "max_hp", 20.0);
    simulation.set_actor_resource(player, "hp", 20.0);
    simulation.set_actor_ap(hostile, 1.0);
    simulation.enter_combat(hostile, player);
    simulation.drain_events();

    simulation.run_combat_ai_turn(hostile);

    let events = simulation.drain_events();
    assert!(events.iter().any(|event| matches!(
        event,
        SimulationEvent::SkillActivated {
            actor_id,
            skill_id,
            ..
        } if *actor_id == hostile && skill_id == "fire_bolt"
    )));
    assert!(!events.iter().any(|event| matches!(
        event,
        SimulationEvent::AttackResolved { actor_id, .. } if *actor_id == hostile
    )));
    assert!(simulation.actor_hit_points(player) < 20.0);
}

#[test]
fn combat_ai_approaches_target_when_attack_is_out_of_range() {
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
        grid_position: GridCoord::new(4, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.set_actor_ap(hostile, 1.0);
    simulation.enter_combat(hostile, player);
    simulation.drain_events();

    simulation.run_combat_ai_turn(hostile);

    assert_eq!(
        simulation.actor_grid_position(hostile),
        Some(GridCoord::new(3, 0, 0))
    );
    assert_eq!(
        simulation.peek_pending_progression(),
        Some(&PendingProgressionStep::EndCurrentCombatTurn)
    );
}

#[test]
fn passive_profile_holds_position_in_builtin_combat_turn() {
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
        display_name: "Watcher".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(3, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.seed_actor_combat_behavior(hostile, "passive");
    simulation.set_actor_ap(hostile, 1.0);
    simulation.enter_combat(hostile, player);

    simulation.run_combat_ai_turn(hostile);

    assert_eq!(
        simulation.actor_grid_position(hostile),
        Some(GridCoord::new(3, 0, 0))
    );
}

#[test]
fn builtin_combat_ai_prefers_aoe_skill_when_it_hits_multiple_targets() {
    let mut simulation = Simulation::new();
    simulation.set_skill_library(sample_spatial_skill_library());
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
    let ally = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Guard".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "friendly".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let hostile = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Caster".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(1, 0, 1),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation
        .economy
        .actor_mut(hostile)
        .expect("hostile should exist")
        .learned_skills
        .insert("shockwave_hostile_only".to_string(), 1);
    simulation.seed_actor_combat_behavior(hostile, "neutral");
    simulation.set_actor_ap(hostile, 1.0);
    simulation.enter_combat(hostile, player);
    simulation.drain_events();

    simulation.run_combat_ai_turn(hostile);

    let events = simulation.drain_events();
    assert!(events.iter().any(|event| matches!(
        event,
        SimulationEvent::SkillActivated {
            actor_id,
            skill_id,
            hit_actor_ids,
            ..
        } if *actor_id == hostile
            && skill_id == "shockwave_hostile_only"
            && hit_actor_ids.contains(&player)
            && hit_actor_ids.contains(&ally)
    )));
}

fn sample_weapon_item_library_with_speed(attack_speed: f32) -> ItemLibrary {
    ItemLibrary::from(BTreeMap::from([
        (
            1004,
            ItemDefinition {
                id: 1004,
                name: "Test Weapon".into(),
                value: 120,
                weight: 1.2,
                fragments: vec![
                    ItemFragment::Equip {
                        slots: vec!["main_hand".into()],
                        level_requirement: 1,
                        equip_effect_ids: Vec::new(),
                        unequip_effect_ids: Vec::new(),
                    },
                    ItemFragment::Weapon {
                        subtype: "pistol".into(),
                        damage: 8,
                        attack_speed,
                        range: 12,
                        stamina_cost: 2,
                        crit_chance: 0.0,
                        crit_multiplier: 1.5,
                        accuracy: Some(100),
                        ammo_type: Some(1009),
                        max_ammo: Some(6),
                        reload_time: Some(1.0),
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
                name: "Ammo".into(),
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

#[test]
fn attack_speed_changes_attack_cost_and_affordability_threshold() {
    fn prepare_simulation(
        attack_speed: f32,
    ) -> (Simulation, game_data::ActorId, game_data::ActorId) {
        let items = sample_weapon_item_library_with_speed(attack_speed);
        let mut simulation = Simulation::new();
        simulation.set_item_library(items.clone());

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
        simulation.economy.set_actor_level(player, 1);
        simulation
            .economy
            .add_item(player, 1004, 1, &items)
            .expect("weapon should add");
        simulation
            .economy
            .add_ammo(player, 1009, 6, &items)
            .expect("ammo should add");
        simulation
            .economy
            .equip_item(player, 1004, Some("main_hand"), &items)
            .expect("weapon should equip");
        simulation
            .economy
            .reload_equipped_weapon(player, "main_hand", &items)
            .expect("weapon should reload");
        simulation.set_actor_combat_attribute(player, "attack_power", 6.0);
        simulation.set_actor_combat_attribute(player, "accuracy", 100.0);
        simulation.set_actor_combat_attribute(hostile, "max_hp", 20.0);
        simulation.set_actor_resource(hostile, "hp", 20.0);

        (simulation, player, hostile)
    }

    let (fast_simulation, fast_player, _) = prepare_simulation(2.0);
    assert_eq!(fast_simulation.attack_action_cost(fast_player), 0.5);
    assert!(fast_simulation.can_actor_afford(fast_player, ActionType::Attack, None));

    let (mut slow_simulation, slow_player, slow_hostile) = prepare_simulation(0.5);
    assert_eq!(slow_simulation.attack_action_cost(slow_player), 1.5);
    slow_simulation.set_actor_ap(slow_player, 1.4);
    assert!(!slow_simulation.can_actor_afford(slow_player, ActionType::Attack, None));

    slow_simulation.set_actor_ap(slow_player, 1.5);
    let result = slow_simulation.perform_attack(slow_player, slow_hostile);
    assert!(result.success);
    assert_eq!(result.consumed, 1.5);
}

#[test]
fn attack_rejection_event_reports_available_and_required_attack_ap() {
    let items = sample_weapon_item_library_with_speed(0.5);
    let mut simulation = Simulation::new();
    simulation.set_item_library(items.clone());

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
    simulation.economy.set_actor_level(player, 1);
    simulation
        .economy
        .add_item(player, 1004, 1, &items)
        .expect("weapon should add");
    simulation
        .economy
        .add_ammo(player, 1009, 6, &items)
        .expect("ammo should add");
    simulation
        .economy
        .equip_item(player, 1004, Some("main_hand"), &items)
        .expect("weapon should equip");
    simulation
        .economy
        .reload_equipped_weapon(player, "main_hand", &items)
        .expect("weapon should reload");
    simulation.set_actor_ap(player, 1.4);

    let result = simulation.perform_attack(player, hostile);

    assert!(!result.success);
    assert_eq!(result.reason.as_deref(), Some("insufficient_ap"));
    let rejection = simulation
        .drain_events()
        .into_iter()
        .find_map(|event| match event {
            SimulationEvent::ActionRejected {
                actor_id,
                action_type,
                reason,
            } if actor_id == player && action_type == ActionType::Attack => Some(reason),
            _ => None,
        })
        .expect("attack rejection should emit action_rejected");
    assert_eq!(rejection, "insufficient_ap available=1.4 required=1.5");
}
