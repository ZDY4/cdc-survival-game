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
        ai_controller: Some(Box::new(InteractOnceAiController)),
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
        ai_controller: Some(Box::new(FollowGridGoalAiController)),
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
        ai_controller: Some(Box::new(FollowGridGoalAiController)),
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
