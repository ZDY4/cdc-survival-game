use super::*;

#[test]
fn friendly_actor_interaction_prompt_prefers_talk() {
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
        display_name: "废土商人·老王".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "survivor".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let prompt = simulation
        .query_interaction_options(player, &InteractionTargetId::Actor(trader))
        .expect("friendly actor should expose options");

    assert_eq!(prompt.options[0].kind, InteractionOptionKind::Talk);
    assert!(prompt
        .options
        .iter()
        .any(|option| option.kind == InteractionOptionKind::Attack));
}

#[test]
fn self_interaction_prompt_exposes_wait_as_primary_option() {
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

    let prompt = simulation
        .query_interaction_options(player, &InteractionTargetId::Actor(player))
        .expect("player should be able to interact with self");

    assert_eq!(prompt.options.len(), 1);
    assert_eq!(prompt.options[0].kind, InteractionOptionKind::Wait);
    assert_eq!(prompt.options[0].display_name, "等待");
    assert_eq!(
        prompt.primary_option_id,
        Some(InteractionOptionId("wait".into()))
    );
}

#[test]
fn self_wait_interaction_ends_turn_without_spending_ap() {
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

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::Actor(player),
        option_id: InteractionOptionId("wait".into()),
    });

    assert!(result.success);
    let action = result
        .action_result
        .expect("wait should yield an action result");
    assert_eq!(action.ap_before, 1.0);
    assert_eq!(action.ap_after, 1.0);
    assert_eq!(action.consumed, 0.0);
    assert!(!simulation.actor_turn_open(player));
    assert_eq!(
        advance_next_progression(&mut simulation),
        Some(PendingProgressionStep::RunNonCombatWorldCycle)
    );
    assert_eq!(
        advance_next_progression(&mut simulation),
        Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
    );
}

#[test]
fn pickup_interaction_grants_inventory_and_consumes_target() {
    let mut simulation = Simulation::new();
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

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject("pickup".into()),
        option_id: InteractionOptionId("pickup".into()),
    });

    assert!(result.success);
    assert!(result.consumed_target);
    assert!(simulation.grid_world().map_object("pickup").is_none());
    assert_eq!(simulation.inventory_count(player, "1005"), 2);
}

#[test]
fn talk_interaction_returns_dialogue_id() {
    let mut simulation = Simulation::new();
    simulation.set_dialogue_library(sample_dialogue_library());
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
        display_name: "废土商人·老王".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "survivor".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::Actor(trader),
        option_id: InteractionOptionId("talk".into()),
    });

    assert!(result.success);
    let action = result
        .action_result
        .as_ref()
        .expect("talk should yield an action result");
    assert_eq!(action.ap_before, 1.0);
    assert_eq!(action.ap_after, 1.0);
    assert_eq!(action.consumed, 0.0);
    assert_eq!(result.dialogue_id.as_deref(), Some("trader_lao_wang"));
    assert_eq!(
        result
            .dialogue_state
            .as_ref()
            .and_then(|state| state.current_node.as_ref())
            .map(|node| node.id.as_str()),
        Some("start")
    );
    assert_eq!(
        simulation
            .active_dialogue_state(player)
            .and_then(|state| state.current_node)
            .map(|node| node.id),
        Some("start".to_string())
    );
    assert!(!simulation.actor_turn_open(player));
    assert_eq!(
        advance_next_progression(&mut simulation),
        Some(PendingProgressionStep::RunNonCombatWorldCycle)
    );
    assert_eq!(
        advance_next_progression(&mut simulation),
        Some(PendingProgressionStep::StartNextNonCombatPlayerTurn)
    );
}

#[test]
fn advance_dialogue_command_updates_runtime_state_and_finishes_session() {
    let mut simulation = Simulation::new();
    simulation.set_dialogue_library(sample_dialogue_library());
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

    let started = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::Actor(trader),
        option_id: InteractionOptionId("talk".into()),
    });
    assert!(started.success);

    let advanced = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
        actor_id: player,
        target_id: Some(InteractionTargetId::Actor(trader)),
        dialogue_id: "trader_lao_wang".into(),
        option_id: None,
        option_index: None,
    }) {
        SimulationCommandResult::DialogueState(result) => result.expect("advance should succeed"),
        other => panic!("unexpected command result: {other:?}"),
    };
    assert_eq!(
        advanced.current_node.as_ref().map(|node| node.id.as_str()),
        Some("choice_1")
    );
    assert_eq!(advanced.available_options.len(), 2);

    let selected = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
        actor_id: player,
        target_id: Some(InteractionTargetId::Actor(trader)),
        dialogue_id: "trader_lao_wang".into(),
        option_id: Some("choice_1".into()),
        option_index: None,
    }) {
        SimulationCommandResult::DialogueState(result) => result.expect("choice should succeed"),
        other => panic!("unexpected command result: {other:?}"),
    };
    assert_eq!(
        selected.current_node.as_ref().map(|node| node.id.as_str()),
        Some("trade_action")
    );
    assert_eq!(selected.emitted_actions.len(), 0);

    let action_state = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
        actor_id: player,
        target_id: Some(InteractionTargetId::Actor(trader)),
        dialogue_id: "trader_lao_wang".into(),
        option_id: None,
        option_index: None,
    }) {
        SimulationCommandResult::DialogueState(result) => {
            result.expect("action node should advance")
        }
        other => panic!("unexpected command result: {other:?}"),
    };
    assert!(action_state.finished);
    assert_eq!(action_state.end_type.as_deref(), Some("trade"));
    assert_eq!(action_state.emitted_actions.len(), 1);
    assert_eq!(action_state.emitted_actions[0].action_type, "open_trade");
    assert!(simulation.active_dialogue_state(player).is_none());
}

#[test]
fn selecting_leave_choice_finishes_dialogue_immediately() {
    let mut simulation = Simulation::new();
    simulation.set_dialogue_library(sample_dialogue_library());
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

    let opened = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
        actor_id: player,
        target_id: Some(InteractionTargetId::Actor(trader)),
        dialogue_id: "trader_lao_wang".into(),
        option_id: None,
        option_index: None,
    }) {
        SimulationCommandResult::DialogueState(result) => result.expect("dialogue should open"),
        other => panic!("unexpected command result: {other:?}"),
    };
    assert_eq!(
        opened.current_node.as_ref().map(|node| node.id.as_str()),
        Some("start")
    );

    let choice = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
        actor_id: player,
        target_id: Some(InteractionTargetId::Actor(trader)),
        dialogue_id: "trader_lao_wang".into(),
        option_id: None,
        option_index: None,
    }) {
        SimulationCommandResult::DialogueState(result) => {
            result.expect("choice node should appear")
        }
        other => panic!("unexpected command result: {other:?}"),
    };
    assert_eq!(
        choice.current_node.as_ref().map(|node| node.id.as_str()),
        Some("choice_1")
    );

    let finished = match simulation.apply_command(SimulationCommand::AdvanceDialogue {
        actor_id: player,
        target_id: Some(InteractionTargetId::Actor(trader)),
        dialogue_id: "trader_lao_wang".into(),
        option_id: Some("choice_2".into()),
        option_index: None,
    }) {
        SimulationCommandResult::DialogueState(result) => {
            result.expect("leave choice should finish dialogue")
        }
        other => panic!("unexpected command result: {other:?}"),
    };
    assert!(finished.finished);
    assert_eq!(finished.end_type.as_deref(), Some("leave"));
    assert!(simulation.active_dialogue_state(player).is_none());
}

#[test]
fn talk_interaction_uses_dialogue_rule_variant() {
    let mut simulation = Simulation::new();
    simulation.set_dialogue_library(sample_dialogue_library());
    simulation.set_dialogue_rule_library(sample_dialogue_rule_library());
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
        definition_id: Some(CharacterId("doctor_chen".into())),
        display_name: "Doctor".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "friendly".into(),
        grid_position: GridCoord::new(1, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.set_relationship_score(player, trader, 75);

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::Actor(trader),
        option_id: InteractionOptionId("talk".into()),
    });

    assert!(result.success);
    assert_eq!(result.dialogue_id.as_deref(), Some("doctor_chen"));
    assert_eq!(
        result
            .dialogue_state
            .as_ref()
            .map(|state| state.session.dialogue_id.as_str()),
        Some("doctor_chen_medical")
    );
}
