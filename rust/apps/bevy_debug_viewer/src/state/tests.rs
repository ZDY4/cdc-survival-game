//! 状态模块测试：覆盖控制模式、插值轨迹和战斗反馈等基础行为。

use super::{
    ActorMotionTrack, AttackLungeTrack, HitReactionTrack, ViewerActorFeedbackState,
    ViewerCameraMode, ViewerCameraShakeState, ViewerControlMode, ViewerDamageNumberState,
    ViewerState, sync_viewer_ui_pick_passthrough,
};
use bevy::picking::prelude::Pickable;
use bevy::prelude::{App, Node, Text, Update};
use bevy::text::TextSpan;
use game_core::{
    ActorDebugState, CombatDebugState, GridDebugState, OverworldStateSnapshot, SimulationSnapshot,
};
use game_data::{
    ActorId, ActorKind, ActorSide, CharacterId, GridCoord, InteractionContextSnapshot, TurnState,
    WorldCoord,
};

#[test]
fn command_actor_uses_controlled_player_in_player_control_mode() {
    let snapshot = snapshot_with_actors(vec![
        actor(ActorId(1), ActorSide::Player, "player"),
        actor(ActorId(2), ActorSide::Friendly, "guard"),
    ]);
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(ActorId(1), ActorSide::Player);

    assert_eq!(viewer_state.selected_actor, None);
    assert_eq!(viewer_state.controlled_player_actor, Some(ActorId(1)));
    assert_eq!(viewer_state.command_actor_id(&snapshot), Some(ActorId(1)));
}

#[test]
fn select_actor_only_sets_selected_actor_in_free_observe_mode() {
    let mut viewer_state = ViewerState::default();
    viewer_state.control_mode = ViewerControlMode::FreeObserve;

    viewer_state.select_actor(ActorId(7), ActorSide::Friendly);

    assert_eq!(viewer_state.selected_actor, Some(ActorId(7)));
    assert_eq!(viewer_state.controlled_player_actor, None);
}

#[test]
fn command_actor_is_disabled_in_free_observe_mode() {
    let snapshot = snapshot_with_actors(vec![actor(ActorId(1), ActorSide::Player, "player")]);
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(ActorId(1), ActorSide::Player);
    viewer_state.control_mode = ViewerControlMode::FreeObserve;

    assert_eq!(viewer_state.command_actor_id(&snapshot), None);
}

#[test]
fn viewer_state_follows_selected_actor_by_default() {
    let viewer_state = ViewerState::default();

    assert_eq!(
        viewer_state.camera_mode,
        ViewerCameraMode::FollowSelectedActor
    );
    assert!(viewer_state.is_camera_following_selected_actor());
}

#[test]
fn resume_camera_follow_resets_manual_pan_state() {
    let mut viewer_state = ViewerState {
        camera_mode: ViewerCameraMode::ManualPan,
        camera_pan_offset: bevy::prelude::Vec2::new(3.0, -2.0),
        camera_drag_cursor: Some(bevy::prelude::Vec2::new(120.0, 48.0)),
        camera_drag_anchor_world: Some(bevy::prelude::Vec2::new(6.5, 9.5)),
        ..ViewerState::default()
    };

    viewer_state.resume_camera_follow();

    assert_eq!(
        viewer_state.camera_mode,
        ViewerCameraMode::FollowSelectedActor
    );
    assert_eq!(viewer_state.camera_pan_offset, bevy::prelude::Vec2::ZERO);
    assert_eq!(viewer_state.camera_drag_cursor, None);
    assert_eq!(viewer_state.camera_drag_anchor_world, None);
}

#[test]
fn actor_motion_track_interpolates_linearly() {
    let mut track = ActorMotionTrack::new(
        WorldCoord::new(0.5, 0.5, 0.5),
        WorldCoord::new(1.5, 0.5, 0.5),
        0,
        0.1,
    );

    track.advance(0.05);

    assert_eq!(track.current_world, WorldCoord::new(1.0, 0.5, 0.5));
    assert!(track.active);

    track.advance(0.05);

    assert_eq!(track.current_world, WorldCoord::new(1.5, 0.5, 0.5));
    assert!(!track.active);
}

#[test]
fn actor_motion_track_snaps_to_authoritative_world() {
    let mut track = ActorMotionTrack::new(
        WorldCoord::new(0.5, 0.5, 0.5),
        WorldCoord::new(1.5, 0.5, 0.5),
        0,
        0.1,
    );

    track.advance(0.03);
    track.snap_to(WorldCoord::new(4.5, 1.5, 2.5), 1);

    assert_eq!(track.current_world, WorldCoord::new(4.5, 1.5, 2.5));
    assert_eq!(track.level, 1);
    assert_eq!(track.elapsed_sec, 0.0);
    assert!(!track.active);
}

#[test]
fn attack_lunge_track_returns_to_origin() {
    let mut track = AttackLungeTrack::new(
        WorldCoord::new(0.5, 0.5, 0.5),
        WorldCoord::new(3.5, 0.5, 0.5),
    )
    .expect("track should be created");

    track.advance(0.04);
    assert!(track.current_offset().x > 0.0);

    track.advance(0.16);
    assert_eq!(track.current_offset(), bevy::prelude::Vec3::ZERO);
    assert!(!track.is_active());
}

#[test]
fn hit_reaction_track_returns_to_origin() {
    let mut track = HitReactionTrack::new();

    track.advance(0.03);
    assert!(track.current_offset().length() > 0.0);

    track.advance(0.20);
    assert_eq!(track.current_offset(), bevy::prelude::Vec3::ZERO);
    assert!(!track.is_active());
}

#[test]
fn viewer_actor_feedback_state_sums_offsets() {
    let mut feedback_state = ViewerActorFeedbackState::default();
    feedback_state.queue_attack_lunge(
        ActorId(1),
        WorldCoord::new(0.5, 0.5, 0.5),
        WorldCoord::new(3.5, 0.5, 0.5),
    );
    feedback_state.queue_hit_reaction(ActorId(1));
    feedback_state.advance(0.03);

    assert!(feedback_state.visual_offset(ActorId(1)).length() > 0.0);
}

#[test]
fn damage_number_state_queues_and_expires_entries() {
    let mut damage_numbers = ViewerDamageNumberState::default();
    let id = damage_numbers.queue_damage_number(WorldCoord::new(1.5, 0.5, 2.5), 12, false);

    assert!(damage_numbers.entries.contains_key(&id));

    damage_numbers.advance(0.7);

    assert!(!damage_numbers.entries.contains_key(&id));
}

#[test]
fn camera_shake_state_returns_to_rest_offset() {
    let mut shake_state = ViewerCameraShakeState::default();
    shake_state.trigger_default_damage_shake();
    shake_state.advance(0.05);
    assert!(shake_state.current_offset().length() > 0.0);

    shake_state.advance(0.4);
    assert_eq!(shake_state.current_offset(), bevy::prelude::Vec3::ZERO);
}

#[test]
fn sync_viewer_ui_pick_passthrough_marks_ui_entities_ignored() {
    let mut app = App::new();
    app.add_systems(Update, sync_viewer_ui_pick_passthrough);
    let node = app.world_mut().spawn(Node::default()).id();
    let text = app.world_mut().spawn(Text::new("label")).id();
    let span = app.world_mut().spawn(TextSpan::new("span")).id();

    app.update();

    for entity in [node, text, span] {
        assert_eq!(
            app.world().entity(entity).get::<Pickable>(),
            Some(&Pickable::IGNORE)
        );
    }
}

fn actor(actor_id: ActorId, side: ActorSide, definition_id: &str) -> ActorDebugState {
    ActorDebugState {
        actor_id,
        definition_id: Some(CharacterId(definition_id.into())),
        display_name: definition_id.into(),
        kind: ActorKind::Npc,
        side,
        group_id: "group".into(),
        ap: 6.0,
        available_steps: 3,
        turn_open: false,
        in_combat: false,
        grid_position: GridCoord::new(0, 0, 0),
        level: 1,
        current_xp: 0,
        available_stat_points: 0,
        available_skill_points: 0,
        hp: 10.0,
        max_hp: 10.0,
    }
}

fn snapshot_with_actors(actors: Vec<ActorDebugState>) -> SimulationSnapshot {
    SimulationSnapshot {
        turn: TurnState::default(),
        actors,
        grid: GridDebugState {
            grid_size: 1.0,
            map_id: None,
            map_width: Some(8),
            map_height: Some(8),
            default_level: Some(0),
            levels: vec![0],
            static_obstacles: Vec::new(),
            map_blocked_cells: Vec::new(),
            map_cells: Vec::new(),
            map_objects: Vec::new(),
            runtime_blocked_cells: Vec::new(),
            topology_version: 0,
            runtime_obstacle_version: 0,
        },
        vision: Default::default(),
        generated_buildings: Vec::new(),
        generated_doors: Vec::new(),
        combat: CombatDebugState {
            in_combat: false,
            current_actor_id: None,
            current_group_id: None,
            current_turn_index: 0,
        },
        interaction_context: InteractionContextSnapshot::default(),
        overworld: OverworldStateSnapshot::default(),
        path_preview: Vec::new(),
    }
}
