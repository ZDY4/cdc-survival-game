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
