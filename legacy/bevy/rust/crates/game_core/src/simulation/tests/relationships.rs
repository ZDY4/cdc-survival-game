use super::*;

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
