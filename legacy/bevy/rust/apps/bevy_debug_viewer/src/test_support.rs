use game_core::ActorDebugState;
use game_data::{ActorId, ActorKind, ActorSide, GridCoord};

pub(crate) fn actor_debug_state_fixture() -> ActorDebugState {
    ActorDebugState {
        actor_id: ActorId(1),
        definition_id: None,
        display_name: "actor".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Neutral,
        group_id: "group".into(),
        ap: 1.0,
        available_steps: 1,
        turn_open: true,
        in_combat: false,
        grid_position: GridCoord::new(0, 0, 0),
        level: 1,
        current_xp: 0,
        available_stat_points: 0,
        available_skill_points: 0,
        hp: 60.0,
        max_hp: 60.0,
    }
}
