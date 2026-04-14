use super::*;

#[test]
fn attack_rejects_target_blocked_by_line_of_sight() {
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
        attack_range: 3.0,
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

    let query = simulation.query_attack_targeting(player);
    assert!(!query.valid_actor_ids.contains(&hostile));

    let result = simulation.perform_attack(player, hostile);
    assert!(!result.success);
    assert_eq!(result.reason.as_deref(), Some("target_blocked_by_los"));
}

#[test]
fn attack_rejects_out_of_range_target_on_same_level() {
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
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let result = simulation.perform_attack(player, hostile);
    assert!(!result.success);
    assert_eq!(result.reason.as_deref(), Some("target_out_of_range"));
}

#[test]
fn attack_rejects_target_on_different_level() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_two_level_combat_map_definition());
    let player = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 3.0,
        ai_controller: None,
    });
    let hostile = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Hostile".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(0, 1, 1),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let result = simulation.perform_attack(player, hostile);
    assert!(!result.success);
    assert_eq!(result.reason.as_deref(), Some("target_invalid_level"));
}

#[test]
fn single_skill_target_requires_line_of_sight_to_center_grid() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_combat_los_map_definition());
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
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation
        .economy
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("fire_bolt".to_string(), 1);
    simulation.set_actor_ap(player, 2.0);

    let preview =
        simulation.preview_skill_target(player, "fire_bolt", SkillTargetRequest::Actor(hostile));
    assert_eq!(
        preview.invalid_reason.as_deref(),
        Some("target_blocked_by_los")
    );

    let result = simulation.activate_skill(player, "fire_bolt", SkillTargetRequest::Actor(hostile));
    assert!(!result.action_result.success);
    assert_eq!(
        result.failure_reason.as_deref(),
        Some("target_blocked_by_los")
    );
}

#[test]
fn aoe_skill_expands_hit_grids_when_center_has_line_of_sight() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_two_level_combat_map_definition());
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
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let flank = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Flank".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(2, 0, 1),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation
        .economy
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("shockwave".to_string(), 1);
    simulation.set_actor_ap(player, 2.0);

    let preview = simulation.preview_skill_target(
        player,
        "shockwave",
        SkillTargetRequest::Grid(GridCoord::new(2, 0, 0)),
    );
    assert!(preview.invalid_reason.is_none());
    assert!(preview.preview_hit_grids.contains(&GridCoord::new(2, 0, 0)));
    assert!(preview.preview_hit_grids.contains(&GridCoord::new(2, 0, 1)));
    assert!(preview.preview_hit_actor_ids.contains(&hostile));
    assert!(preview.preview_hit_actor_ids.contains(&flank));
}

#[test]
fn aoe_skill_fails_when_center_point_is_occluded() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_combat_los_map_definition());
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
    simulation
        .economy
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("shockwave".to_string(), 1);
    simulation.set_actor_ap(player, 2.0);

    let preview = simulation.preview_skill_target(
        player,
        "shockwave",
        SkillTargetRequest::Grid(GridCoord::new(2, 0, 0)),
    );
    assert_eq!(
        preview.invalid_reason.as_deref(),
        Some("target_blocked_by_los")
    );
}

#[test]
fn aoe_skill_excludes_grids_and_targets_occluded_from_center() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_aoe_occlusion_map_definition());
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
    let center_hostile = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Center".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let occluded_hostile = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Occluded".into(),
        kind: ActorKind::Enemy,
        side: ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(4, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation
        .economy
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("shockwave_wide".to_string(), 1);
    simulation.set_actor_ap(player, 2.0);
    simulation.set_actor_resource(center_hostile, "hp", 10.0);
    simulation.set_actor_resource(occluded_hostile, "hp", 10.0);

    let preview = simulation.preview_skill_target(
        player,
        "shockwave_wide",
        SkillTargetRequest::Grid(GridCoord::new(2, 0, 0)),
    );

    assert!(preview.invalid_reason.is_none());
    assert!(preview.preview_hit_grids.contains(&GridCoord::new(2, 0, 0)));
    assert!(!preview.preview_hit_grids.contains(&GridCoord::new(4, 0, 0)));
    assert!(preview.preview_hit_actor_ids.contains(&center_hostile));
    assert!(!preview.preview_hit_actor_ids.contains(&occluded_hostile));

    let hp_before_center = simulation.actor_hit_points(center_hostile);
    let hp_before_occluded = simulation.actor_hit_points(occluded_hostile);
    let result = simulation.activate_skill(
        player,
        "shockwave_wide",
        SkillTargetRequest::Grid(GridCoord::new(2, 0, 0)),
    );

    assert!(result.action_result.success);
    assert!(result.hit_actor_ids.contains(&center_hostile));
    assert!(!result.hit_actor_ids.contains(&occluded_hostile));
    assert!(simulation.actor_hit_points(center_hostile) < hp_before_center);
    assert_eq!(
        simulation.actor_hit_points(occluded_hostile),
        hp_before_occluded
    );
}

#[test]
fn typed_targeting_policy_prevents_friendly_fire_for_hostile_only_aoe() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_two_level_combat_map_definition());
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
        grid_position: GridCoord::new(2, 0, 0),
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
        grid_position: GridCoord::new(2, 0, 1),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation
        .economy
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("shockwave_hostile_only".to_string(), 1);
    simulation.set_actor_ap(player, 2.0);
    simulation.set_actor_resource(hostile, "hp", 10.0);
    simulation.set_actor_resource(friendly, "hp", 10.0);

    let preview = simulation.preview_skill_target(
        player,
        "shockwave_hostile_only",
        SkillTargetRequest::Grid(GridCoord::new(2, 0, 0)),
    );
    assert!(preview.invalid_reason.is_none());
    assert!(preview.preview_hit_actor_ids.contains(&hostile));
    assert!(!preview.preview_hit_actor_ids.contains(&friendly));

    let hp_before_friendly = simulation.actor_hit_points(friendly);
    let result = simulation.activate_skill(
        player,
        "shockwave_hostile_only",
        SkillTargetRequest::Grid(GridCoord::new(2, 0, 0)),
    );

    assert!(result.action_result.success);
    assert!(result.hit_actor_ids.contains(&hostile));
    assert!(!result.hit_actor_ids.contains(&friendly));
    assert_eq!(simulation.actor_hit_points(friendly), hp_before_friendly);
}

#[test]
fn attack_and_skill_share_same_spatial_failure_reason() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_combat_los_map_definition());
    simulation.set_skill_library(sample_spatial_skill_library());
    let player = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 3.0,
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
    simulation
        .economy
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("fire_bolt".to_string(), 1);
    simulation.set_actor_ap(player, 2.0);

    let attack_result = simulation.perform_attack(player, hostile);
    let skill_preview =
        simulation.preview_skill_target(player, "fire_bolt", SkillTargetRequest::Actor(hostile));

    assert_eq!(
        attack_result.reason.as_deref(),
        Some("target_blocked_by_los")
    );
    assert_eq!(
        skill_preview.invalid_reason.as_deref(),
        Some("target_blocked_by_los")
    );
}

#[test]
fn ranged_attack_targeting_uses_cell_distance() {
    let items = sample_combat_item_library();
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_two_level_combat_map_definition());
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
    simulation
        .economy
        .add_item(player, 1004, 1, &items)
        .expect("pistol should add");
    simulation.economy.set_actor_level(player, 2);
    simulation
        .economy
        .equip_item(player, 1004, Some("main_hand"), &items)
        .expect("pistol should equip");

    let query = simulation.query_attack_targeting(player);
    assert!(query.valid_grids.contains(&GridCoord::new(4, 0, 0)));
    assert!(query.valid_actor_ids.contains(&hostile));
}

#[test]
fn grid_math_matches_reference_grid_behavior() {
    let world = crate::grid::GridWorld::default();
    let grid = world.world_to_grid(WorldCoord::new(0.6, 0.4, 1.8));
    assert_eq!(grid, GridCoord::new(0, 0, 1));
    assert_eq!(world.grid_to_world(grid), WorldCoord::new(0.5, 0.5, 1.5));
    assert_eq!(
        world.snap_to_grid(WorldCoord::new(0.6, 0.4, 1.8)),
        WorldCoord::new(0.5, 0.5, 1.5)
    );
}

#[test]
fn static_obstacles_block_and_bump_versions() {
    let mut world = crate::grid::GridWorld::default();
    let version = world.topology_version();
    world.register_static_obstacle(GridCoord::new(1, 0, 1));
    assert!(!world.is_walkable(GridCoord::new(1, 0, 1)));
    assert!(world.topology_version() > version);
}

#[test]
fn loaded_map_blocks_only_within_same_level() {
    let mut world = crate::grid::GridWorld::default();
    world.load_map(&sample_map_definition());

    assert!(!world.is_walkable(GridCoord::new(5, 0, 2)));
    assert!(world.is_walkable(GridCoord::new(5, 1, 2)));
    assert_eq!(world.map_id().map(MapId::as_str), Some("sample_map"));
    assert_eq!(world.levels(), vec![0, 1]);
}

#[test]
fn loaded_map_enforces_bounds_from_map_size_and_levels() {
    let mut world = crate::grid::GridWorld::default();
    world.load_map(&sample_map_definition());

    assert!(world.is_in_bounds(GridCoord::new(11, 0, 11)));
    assert!(!world.is_in_bounds(GridCoord::new(12, 0, 11)));
    assert!(!world.is_in_bounds(GridCoord::new(11, 0, 12)));
    assert!(!world.is_in_bounds(GridCoord::new(-1, 0, 0)));
    assert!(!world.is_in_bounds(GridCoord::new(0, 2, 0)));
    assert!(!world.is_walkable(GridCoord::new(12, 0, 11)));
    assert!(!world.is_walkable(GridCoord::new(0, 2, 0)));
}

#[test]
fn building_footprint_from_loaded_map_blocks_pathfinding() {
    let mut world = crate::grid::GridWorld::default();
    world.load_map(&sample_map_definition());

    let result = crate::grid::find_path_grid(
        &world,
        None,
        GridCoord::new(3, 0, 2),
        GridCoord::new(5, 0, 2),
    );

    assert!(matches!(result, Err(GridPathfindingError::TargetBlocked)));
}

#[test]
fn generated_building_stairs_enable_cross_level_pathfinding() {
    let mut world = crate::grid::GridWorld::default();
    world.load_map(&sample_generated_building_map_definition());

    let path = crate::grid::find_path_grid(
        &world,
        None,
        GridCoord::new(2, 0, 2),
        GridCoord::new(2, 1, 2),
    )
    .expect("stairs should allow vertical traversal");

    assert_eq!(path.first().copied(), Some(GridCoord::new(2, 0, 2)));
    assert_eq!(path.last().copied(), Some(GridCoord::new(2, 1, 2)));
    assert!(path.iter().any(|grid| grid.y == 1));
}

#[test]
fn generated_doors_default_to_closed_unlocked_and_blocking() {
    let mut world = crate::grid::GridWorld::default();
    world.load_map(&sample_generated_building_map_definition());

    let door = world
        .generated_doors()
        .first()
        .cloned()
        .expect("generated building should produce at least one door");
    let object = world
        .map_object(&door.map_object_id)
        .expect("generated door object should be registered");

    assert!(!door.is_open);
    assert!(!door.is_locked);
    assert_eq!(object.kind, MapObjectKind::Interactive);
    assert!(object.blocks_movement);
    assert!(object.blocks_sight);
}

#[test]
fn generated_door_state_toggle_updates_runtime_blocking_flags() {
    let mut world = crate::grid::GridWorld::default();
    world.load_map(&sample_generated_building_map_definition());

    let door = world
        .generated_doors()
        .first()
        .cloned()
        .expect("generated building should produce at least one door");

    assert!(world.set_generated_door_state(&door.door_id, true, false));
    let open_door = world
        .generated_door_by_object_id(&door.map_object_id)
        .expect("generated door should still exist after opening");
    let open_object = world
        .map_object(&door.map_object_id)
        .expect("generated door object should stay registered");
    assert!(open_door.is_open);
    assert!(!open_door.is_locked);
    assert!(!open_object.blocks_movement);
    assert!(!open_object.blocks_sight);

    assert!(world.set_generated_door_state(&door.door_id, false, true));
    let closed_locked_door = world
        .generated_door_by_object_id(&door.map_object_id)
        .expect("generated door should still exist after closing");
    let closed_locked_object = world
        .map_object(&door.map_object_id)
        .expect("generated door object should stay registered");
    assert!(!closed_locked_door.is_open);
    assert!(closed_locked_door.is_locked);
    assert!(closed_locked_object.blocks_movement);
    assert!(closed_locked_object.blocks_sight);
}

#[test]
fn unlocked_generated_door_primary_option_toggles_open_and_closed() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_generated_building_map_definition());
    let door = simulation
        .grid_world()
        .generated_doors()
        .first()
        .cloned()
        .expect("generated building should produce at least one door");
    let player_grid = [
        GridCoord::new(
            door.anchor_grid.x - 1,
            door.anchor_grid.y,
            door.anchor_grid.z,
        ),
        GridCoord::new(
            door.anchor_grid.x + 1,
            door.anchor_grid.y,
            door.anchor_grid.z,
        ),
        GridCoord::new(
            door.anchor_grid.x,
            door.anchor_grid.y,
            door.anchor_grid.z - 1,
        ),
        GridCoord::new(
            door.anchor_grid.x,
            door.anchor_grid.y,
            door.anchor_grid.z + 1,
        ),
    ]
    .into_iter()
    .find(|grid| simulation.grid_world().is_walkable(*grid))
    .expect("generated door should have at least one walkable adjacent cell");
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: player_grid,
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.set_actor_ap(player, 2.0);

    let closed_prompt = simulation
        .query_interaction_options(
            player,
            &InteractionTargetId::MapObject(door.map_object_id.clone()),
        )
        .expect("generated door should expose interaction prompt");
    assert_eq!(
        closed_prompt.primary_option_id,
        Some(InteractionOptionId("open_door".into()))
    );
    assert_eq!(closed_prompt.options.len(), 1);
    assert_eq!(
        closed_prompt.options[0].kind,
        InteractionOptionKind::OpenDoor
    );

    let open_result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject(door.map_object_id.clone()),
        option_id: InteractionOptionId("open_door".into()),
    });
    assert!(open_result.success);
    simulation.set_actor_ap(player, 2.0);

    let open_prompt = simulation
        .query_interaction_options(
            player,
            &InteractionTargetId::MapObject(door.map_object_id.clone()),
        )
        .expect("opened generated door should still expose prompt");
    assert_eq!(
        open_prompt.primary_option_id,
        Some(InteractionOptionId("close_door".into()))
    );
    assert_eq!(open_prompt.options.len(), 1);
    assert_eq!(
        open_prompt.options[0].kind,
        InteractionOptionKind::CloseDoor
    );

    let close_result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject(door.map_object_id.clone()),
        option_id: InteractionOptionId("close_door".into()),
    });
    assert!(close_result.success);

    let closed_again = simulation
        .grid_world()
        .generated_door_by_object_id(&door.map_object_id)
        .expect("generated door should still exist after close");
    assert!(!closed_again.is_open);
    assert!(!closed_again.is_locked);
}

#[test]
fn locked_generated_door_exposes_placeholder_options_without_primary() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_generated_building_map_definition());
    let door = simulation
        .grid_world()
        .generated_doors()
        .first()
        .cloned()
        .expect("generated building should produce at least one door");
    assert!(simulation
        .grid_world_mut()
        .set_generated_door_state(&door.door_id, false, true));
    let player_grid = [
        GridCoord::new(
            door.anchor_grid.x - 1,
            door.anchor_grid.y,
            door.anchor_grid.z,
        ),
        GridCoord::new(
            door.anchor_grid.x + 1,
            door.anchor_grid.y,
            door.anchor_grid.z,
        ),
        GridCoord::new(
            door.anchor_grid.x,
            door.anchor_grid.y,
            door.anchor_grid.z - 1,
        ),
        GridCoord::new(
            door.anchor_grid.x,
            door.anchor_grid.y,
            door.anchor_grid.z + 1,
        ),
    ]
    .into_iter()
    .find(|grid| simulation.grid_world().is_walkable(*grid))
    .expect("generated door should have at least one walkable adjacent cell");
    let player = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: player_grid,
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });

    let prompt = simulation
        .query_interaction_options(
            player,
            &InteractionTargetId::MapObject(door.map_object_id.clone()),
        )
        .expect("locked generated door should expose interaction prompt");
    assert!(prompt.primary_option_id.is_none());
    assert_eq!(prompt.options.len(), 2);
    assert!(prompt
        .options
        .iter()
        .any(|option| option.kind == InteractionOptionKind::UnlockDoor));
    assert!(prompt
        .options
        .iter()
        .any(|option| option.kind == InteractionOptionKind::PickLockDoor));

    let result = simulation.execute_interaction(InteractionExecutionRequest {
        actor_id: player,
        target_id: InteractionTargetId::MapObject(door.map_object_id.clone()),
        option_id: InteractionOptionId("unlock_door".into()),
    });
    assert!(!result.success);
    assert_eq!(
        result.reason.as_deref(),
        Some("door_interaction_not_implemented")
    );

    let locked_again = simulation
        .grid_world()
        .generated_door_by_object_id(&door.map_object_id)
        .expect("generated door should remain after placeholder interaction");
    assert!(!locked_again.is_open);
    assert!(locked_again.is_locked);
}

#[test]
fn unlocked_generated_door_is_pathfindable_and_auto_opens_during_movement() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_generated_building_map_definition());
    let door = simulation
        .grid_world()
        .generated_doors()
        .first()
        .cloned()
        .expect("generated building should produce at least one door");
    let (start, goal) = generated_door_passage_cells(simulation.grid_world(), &door);

    let path = simulation
        .find_path_grid(None, start, goal)
        .expect("closed unlocked door should remain pathfindable");
    assert_eq!(path.first().copied(), Some(start));
    assert_eq!(path.last().copied(), Some(goal));
    assert!(
        path.contains(&door.anchor_grid),
        "path should cross the closed unlocked door cell"
    );

    let actor_id = simulation.register_actor(RegisterActor {
        definition_id: Some(CharacterId("player".into())),
        display_name: "Player".into(),
        kind: ActorKind::Player,
        side: ActorSide::Player,
        group_id: "player".into(),
        grid_position: start,
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation.config.turn_ap_max = 4.0;
    simulation.set_actor_ap(actor_id, 4.0);

    let outcome = simulation
        .move_actor_to_reachable(actor_id, goal)
        .expect("movement through unlocked generated door should plan");
    assert!(outcome.result.success);
    assert_eq!(simulation.actor_grid_position(actor_id), Some(goal));

    let opened_door = simulation
        .grid_world()
        .generated_door_by_object_id(&door.map_object_id)
        .expect("generated door should remain registered");
    assert!(opened_door.is_open);
    assert!(!opened_door.is_locked);
}

#[test]
fn follow_goal_ai_auto_opens_unlocked_generated_door() {
    let mut simulation = Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_generated_building_map_definition());
    let door = simulation
        .grid_world()
        .generated_doors()
        .first()
        .cloned()
        .expect("generated building should produce at least one door");
    let (start, goal) = generated_door_passage_cells(simulation.grid_world(), &door);

    let actor_id = simulation.register_actor(RegisterActor {
        definition_id: None,
        display_name: "Guard".into(),
        kind: ActorKind::Npc,
        side: ActorSide::Friendly,
        group_id: "friendly".into(),
        grid_position: start,
        interaction: None,
        attack_range: 1.0,
        ai_controller: None,
    });
    simulation.config.turn_ap_max = 4.0;
    simulation.set_actor_ap(actor_id, 4.0);
    simulation.set_actor_autonomous_movement_goal(actor_id, goal);

    let mut controller = FollowRuntimeGoalController;
    let result = controller.execute_turn_step(actor_id, &mut simulation);

    assert!(result.performed);
    assert_eq!(simulation.actor_grid_position(actor_id), Some(goal));
    assert!(
        simulation
            .grid_world()
            .generated_door_by_object_id(&door.map_object_id)
            .expect("generated door should remain registered")
            .is_open
    );
}

#[test]
fn non_blocking_pickup_does_not_block_pathfinding() {
    let mut world = crate::grid::GridWorld::default();
    world.load_map(&sample_map_definition());

    let result = crate::grid::find_path_grid(
        &world,
        None,
        GridCoord::new(0, 0, 0),
        GridCoord::new(2, 0, 1),
    );

    assert!(result.is_ok());
}

#[test]
fn runtime_occupancy_blocks_other_actors_but_not_self() {
    let mut world = crate::grid::GridWorld::default();
    let actor = game_data::ActorId(1);
    world.set_runtime_actor_grid(actor, GridCoord::new(2, 0, 2));
    assert!(!world.is_walkable(GridCoord::new(2, 0, 2)));
    assert!(world.is_walkable_for_actor(GridCoord::new(2, 0, 2), Some(actor)));
    assert!(!world.is_walkable_for_actor(GridCoord::new(2, 0, 2), Some(game_data::ActorId(2))));
}

#[test]
fn pathfinding_supports_diagonal_paths() {
    let world = crate::grid::GridWorld::default();
    let path = crate::grid::find_path_grid(
        &world,
        None,
        GridCoord::new(0, 0, 0),
        GridCoord::new(2, 0, 2),
    )
    .expect("path should exist");
    assert_eq!(path.len(), 3);
    assert_eq!(path.first().copied(), Some(GridCoord::new(0, 0, 0)));
    assert_eq!(path.last().copied(), Some(GridCoord::new(2, 0, 2)));
}

#[test]
fn pathfinding_prevents_corner_cutting() {
    let mut world = crate::grid::GridWorld::default();
    world.register_static_obstacle(GridCoord::new(1, 0, 0));
    world.register_static_obstacle(GridCoord::new(0, 0, 1));
    let path = crate::grid::find_path_grid(
        &world,
        None,
        GridCoord::new(0, 0, 0),
        GridCoord::new(1, 0, 1),
    )
    .expect("path should route around blocked corner");
    assert!(
        !path.contains(&GridCoord::new(1, 0, 1)) || path.len() > 2,
        "corner cutting should not allow a direct diagonal hop"
    );
    assert_ne!(
        path,
        vec![GridCoord::new(0, 0, 0), GridCoord::new(1, 0, 1)],
        "path should not jump directly through a blocked diagonal corner"
    );
}

#[test]
fn pathfinding_rejects_blocked_target() {
    let mut world = crate::grid::GridWorld::default();
    world.register_static_obstacle(GridCoord::new(3, 0, 3));
    let result = crate::grid::find_path_grid(
        &world,
        None,
        GridCoord::new(0, 0, 0),
        GridCoord::new(3, 0, 3),
    );
    assert!(matches!(result, Err(GridPathfindingError::TargetBlocked)));
}

#[test]
fn pathfinding_rejects_out_of_bounds_target() {
    let mut world = crate::grid::GridWorld::default();
    world.load_map(&sample_map_definition());
    let result = crate::grid::find_path_grid(
        &world,
        None,
        GridCoord::new(0, 0, 0),
        GridCoord::new(12, 0, 3),
    );
    assert!(matches!(
        result,
        Err(GridPathfindingError::TargetOutOfBounds)
    ));
}
