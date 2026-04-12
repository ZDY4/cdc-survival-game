use super::*;

#[test]
fn snapshot_exposes_definition_metadata() {
    let mut simulation = Simulation::new();
    let actor_id = simulation.register_actor(RegisterActor {
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

    let snapshot = simulation.snapshot(Vec::new(), Default::default());
    let actor = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == actor_id)
        .expect("actor should be present in snapshot");

    assert_eq!(
        actor.definition_id.as_ref().map(CharacterId::as_str),
        Some("trader_lao_wang")
    );
    assert_eq!(actor.display_name, "废土商人·老王");
}
