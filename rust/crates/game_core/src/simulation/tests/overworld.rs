use super::*;

#[test]
fn scene_transition_interaction_enters_target_location_map() {
    let mut simulation = Simulation::new();
    simulation.set_map_library(sample_scene_transition_map_library());
    simulation.set_overworld_library(sample_scene_transition_overworld_library());
    simulation
        .grid_world_mut()
        .load_map(&sample_interaction_map_definition());
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(4, 0, 7),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject("exit".into()),
        option_id: InteractionOptionId("enter_outdoor_location".into()),
    });

    assert!(result.success);
    let context = result
        .context_snapshot
        .expect("scene transition should publish context");
    assert_eq!(
        context.current_map_id.as_deref(),
        Some("survivor_outpost_01")
    );
    assert_eq!(
        context.active_outdoor_location_id.as_deref(),
        Some("survivor_outpost_01")
    );
    assert_eq!(
        context.active_location_id.as_deref(),
        Some("survivor_outpost_01")
    );
    assert_eq!(context.entry_point_id.as_deref(), Some("default_entry"));
    assert_eq!(context.world_mode, WorldMode::Outdoor);
    assert_eq!(
        simulation.actor_grid_position(player),
        Some(GridCoord::new(0, 0, 0))
    );
    assert!(simulation.actor_turn_open(player));
    assert_eq!(simulation.get_actor_ap(player), 0.0);
    assert_eq!(
        simulation.pending_progression.front(),
        Some(&PendingProgressionStep::RunNonCombatWorldCycle)
    );
}

#[test]
fn exit_to_outdoor_interaction_returns_to_outdoor_map_entry_point() {
    let mut simulation = Simulation::new();
    simulation.set_map_library(sample_scene_transition_map_library());
    simulation.set_overworld_library(sample_scene_transition_overworld_library());
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
    simulation
        .enter_location(player, "survivor_outpost_01_interior", None)
        .expect("interior entry should succeed");

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject("interior_exit".into()),
        option_id: InteractionOptionId("exit_to_outdoor".into()),
    });

    assert!(result.success);
    let context = result
        .context_snapshot
        .expect("scene transition should publish context");
    assert_eq!(
        context.current_map_id.as_deref(),
        Some("survivor_outpost_01")
    );
    assert_eq!(
        context.active_location_id.as_deref(),
        Some("survivor_outpost_01")
    );
    assert_eq!(
        context.active_outdoor_location_id.as_deref(),
        Some("survivor_outpost_01")
    );
    assert_eq!(context.entry_point_id.as_deref(), Some("interior_return"));
    assert_eq!(context.world_mode, WorldMode::Outdoor);
    assert_eq!(
        simulation.actor_grid_position(player),
        Some(GridCoord::new(6, 0, 6))
    );
    assert!(simulation.actor_turn_open(player));
    assert_eq!(simulation.get_actor_ap(player), 0.0);
    assert_eq!(
        simulation.pending_progression.front(),
        Some(&PendingProgressionStep::RunNonCombatWorldCycle)
    );
}

#[test]
fn seed_overworld_state_outdoor_preserves_loaded_map_and_entry_point() {
    let mut simulation = Simulation::new();
    simulation.set_map_library(sample_scene_transition_map_library());
    simulation.set_overworld_library(sample_scene_transition_overworld_library());
    simulation
        .grid_world_mut()
        .load_map(&sample_scene_transition_outdoor_map_definition());

    simulation
        .seed_overworld_state(
            WorldMode::Outdoor,
            Some("survivor_outpost_01".into()),
            Some("default_entry".into()),
            ["survivor_outpost_01".to_string()],
        )
        .expect("outdoor overworld state should seed");

    let context = simulation.current_interaction_context();
    assert_eq!(
        simulation.grid_world().map_id().map(MapId::as_str),
        Some("survivor_outpost_01")
    );
    assert_eq!(
        context.current_map_id.as_deref(),
        Some("survivor_outpost_01")
    );
    assert_eq!(
        context.active_location_id.as_deref(),
        Some("survivor_outpost_01")
    );
    assert_eq!(
        context.active_outdoor_location_id.as_deref(),
        Some("survivor_outpost_01")
    );
    assert_eq!(context.entry_point_id.as_deref(), Some("default_entry"));
    assert_eq!(context.world_mode, WorldMode::Outdoor);
}

#[test]
fn seed_overworld_state_overworld_clears_loaded_map_and_entry_point() {
    let mut simulation = Simulation::new();
    simulation.set_map_library(sample_scene_transition_map_library());
    simulation.set_overworld_library(sample_scene_transition_overworld_library());
    simulation
        .grid_world_mut()
        .load_map(&sample_scene_transition_outdoor_map_definition());

    simulation
        .seed_overworld_state(
            WorldMode::Overworld,
            Some("survivor_outpost_01".into()),
            Some("default_entry".into()),
            ["survivor_outpost_01".to_string()],
        )
        .expect("overworld state should seed");

    let context = simulation.current_interaction_context();
    assert_eq!(simulation.grid_world().map_id(), None);
    assert!(simulation.grid_world().is_walkable(GridCoord::new(0, 0, 0)));
    assert!(!simulation
        .grid_world()
        .is_in_bounds(GridCoord::new(1, 0, 0)));
    assert!(simulation
        .grid_world()
        .map_object("overworld_trigger::survivor_outpost_01")
        .is_some());
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
fn stepping_onto_trigger_exposes_interaction_without_auto_transition() {
    let mut simulation = Simulation::new();
    simulation.set_map_library(sample_scene_transition_map_library());
    simulation.set_overworld_library(sample_scene_transition_overworld_library());
    simulation
        .grid_world_mut()
        .load_map(&sample_trigger_map_definition(
            GridCoord::new(5, 0, 7),
            MapObjectFootprint::default(),
            MapRotation::East,
        ));
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(4, 0, 7),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let result = simulation.move_actor_to(player, GridCoord::new(5, 0, 7));

    assert!(result.success);
    let context = simulation.current_interaction_context();
    assert_eq!(context.current_map_id.as_deref(), Some("trigger_map"));
    assert_eq!(context.active_outdoor_location_id, None);
    assert_eq!(context.entry_point_id, None);
    assert_eq!(
        simulation.actor_grid_position(player),
        Some(GridCoord::new(5, 0, 7))
    );

    let prompt = simulation
        .query_interaction_options(
            player,
            &InteractionTargetId::MapObject("exit_trigger".into()),
        )
        .expect("trigger should expose an interaction prompt");
    assert_eq!(prompt.target_name, "进入幸存者据点");
    assert_eq!(
        prompt.primary_option_id.as_ref().map(|id| id.as_str()),
        Some("enter_outdoor_location")
    );

    let events = simulation.drain_events();
    assert!(!events
        .iter()
        .any(|event| matches!(event, SimulationEvent::InteractionSucceeded { .. })));
}

#[test]
fn stepping_onto_trigger_queues_noncombat_turn_progression_when_ap_is_spent() {
    let mut simulation = Simulation::new();
    simulation.set_map_library(sample_scene_transition_map_library());
    simulation.set_overworld_library(sample_scene_transition_overworld_library());
    simulation
        .grid_world_mut()
        .load_map(&sample_trigger_map_definition(
            GridCoord::new(5, 0, 7),
            MapObjectFootprint::default(),
            MapRotation::East,
        ));
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(4, 0, 7),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let result = simulation.move_actor_to(player, GridCoord::new(5, 0, 7));

    assert!(result.success);
    assert_eq!(
        simulation
            .current_interaction_context()
            .current_map_id
            .as_deref(),
        Some("trigger_map")
    );
    assert_eq!(
        simulation.actor_grid_position(player),
        Some(GridCoord::new(5, 0, 7))
    );
    assert!(simulation
        .query_interaction_options(
            player,
            &InteractionTargetId::MapObject("exit_trigger".into())
        )
        .is_some());
    assert!(simulation.get_actor_ap(player) < simulation.config.affordable_threshold);
    assert_eq!(
        simulation
            .pending_progression
            .iter()
            .copied()
            .collect::<Vec<_>>(),
        vec![
            PendingProgressionStep::RunNonCombatWorldCycle,
            PendingProgressionStep::StartNextNonCombatPlayerTurn,
        ]
    );
}

#[test]
fn scene_trigger_interaction_approach_targets_trigger_cell() {
    let mut simulation = Simulation::new();
    simulation.set_map_library(sample_scene_transition_map_library());
    simulation.set_overworld_library(sample_scene_transition_overworld_library());
    simulation
        .grid_world_mut()
        .load_map(&sample_trigger_map_definition(
            GridCoord::new(5, 0, 7),
            MapObjectFootprint::default(),
            MapRotation::East,
        ));
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(3, 0, 7),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject("exit_trigger".into()),
        option_id: InteractionOptionId("enter_outdoor_location".into()),
    });

    assert!(result.success);
    assert!(result.approach_required);
    assert_eq!(result.approach_goal, Some(GridCoord::new(5, 0, 7)));
    assert!(result.context_snapshot.is_none());
    assert_eq!(
        simulation.actor_grid_position(player),
        Some(GridCoord::new(3, 0, 7))
    );
    assert_eq!(
        simulation
            .current_interaction_context()
            .current_map_id
            .as_deref(),
        Some("trigger_map")
    );
}

#[test]
fn multi_cell_scene_trigger_interaction_approach_targets_covered_cell() {
    let mut simulation = Simulation::new();
    simulation.set_map_library(sample_scene_transition_map_library());
    simulation.set_overworld_library(sample_scene_transition_overworld_library());
    simulation
        .grid_world_mut()
        .load_map(&sample_trigger_map_definition(
            GridCoord::new(5, 0, 7),
            MapObjectFootprint {
                width: 3,
                height: 1,
            },
            MapRotation::North,
        ));
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(8, 0, 7),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject("exit_trigger".into()),
        option_id: InteractionOptionId("enter_outdoor_location".into()),
    });

    assert!(result.success);
    assert!(result.approach_required);
    assert_eq!(result.approach_goal, Some(GridCoord::new(7, 0, 7)));
    assert!(result.context_snapshot.is_none());
}

#[test]
fn multi_cell_trigger_exposes_prompt_from_any_covered_cell() {
    let mut simulation = Simulation::new();
    simulation.set_map_library(sample_scene_transition_map_library());
    simulation.set_overworld_library(sample_scene_transition_overworld_library());
    simulation
        .grid_world_mut()
        .load_map(&sample_trigger_map_definition(
            GridCoord::new(5, 0, 7),
            MapObjectFootprint {
                width: 3,
                height: 1,
            },
            MapRotation::North,
        ));
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(8, 0, 7),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let result = simulation.move_actor_to(player, GridCoord::new(7, 0, 7));

    assert!(result.success);
    assert_eq!(
        simulation
            .current_interaction_context()
            .current_map_id
            .as_deref(),
        Some("trigger_map")
    );
    assert_eq!(
        simulation.actor_grid_position(player),
        Some(GridCoord::new(7, 0, 7))
    );
    assert!(simulation
        .query_interaction_options(
            player,
            &InteractionTargetId::MapObject("exit_trigger".into())
        )
        .is_some());
}
