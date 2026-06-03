extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const GridCoord = preload("res://scripts/core/grid/grid_coord.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")


func _init() -> void:
	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		for error in load_result.errors:
			printerr(error)
		quit(1)
		return

	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var simulation: RefCounted = runtime_result.get("simulation")
	var errors: Array[String] = _run_checks(simulation, registry)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("combat_smoke passed:")
	print(JSON.stringify(_digest(simulation.snapshot()), "\t"))
	quit(0)


func _run_checks(simulation: RefCounted, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	simulation.record_item_collected(1, "1007", 2)
	if not _active_quest_ids(simulation.snapshot()).has("zombie_hunter"):
		return ["zombie_hunter did not start after tutorial completion"]

	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var player_grid: Dictionary = player.grid_position.to_dictionary()
	_expect_combat_visibility_decay(errors, simulation, registry, player, player_grid)
	_expect_attack_target_rejections(errors, simulation, player, player_grid)
	_expect_deterministic_combat_rng(errors, simulation, registry, player, player_grid)
	_expect_combat_attribute_damage_modifiers(errors, simulation, player, player_grid)
	_expect_weapon_profile_attack(errors, simulation, registry, player, player_grid)
	_expect_attack_spatial_failures(errors, simulation, registry, player, player_grid)
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.equipment["main_hand"] = "1002"
	player.inventory["1009"] = 10
	player.ap = 20.0
	var zombie_a: int = _register_character(simulation, registry, "zombie_walker", {"x": int(player_grid.get("x", 0)) + 1, "y": int(player_grid.get("y", 0)), "z": int(player_grid.get("z", 0))})
	var zombie_b: int = _register_character(simulation, registry, "zombie_walker", {"x": int(player_grid.get("x", 0)) - 1, "y": int(player_grid.get("y", 0)), "z": int(player_grid.get("z", 0))})
	_force_combat_values(simulation, zombie_a)
	_force_combat_values(simulation, zombie_b)
	var topology: Dictionary = _topology(simulation, registry)

	var first: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": zombie_a, "topology": topology})
	if not bool(first.get("success", false)) or not bool(first.get("defeated", false)):
		errors.append("first zombie attack should defeat target")
	if _quest_progress(simulation.snapshot(), "zombie_hunter") != 1:
		errors.append("zombie_hunter progress should be 1 after first kill")
	if _corpse_count(simulation.snapshot()) != 1:
		errors.append("first zombie kill should create a corpse container")

	var second: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": zombie_b, "topology": topology})
	if not bool(second.get("success", false)) or not bool(second.get("defeated", false)):
		errors.append("second zombie attack should defeat target")
	var snapshot: Dictionary = simulation.snapshot()
	if _active_quest_ids(snapshot).has("zombie_hunter"):
		errors.append("zombie_hunter should complete after two kills")
	if not snapshot.get("completed_quests", []).has("zombie_hunter"):
		errors.append("zombie_hunter missing from completed quests")
	if _corpse_count(snapshot) != 2:
		errors.append("second zombie kill should preserve both corpse containers")
	if _event_count(snapshot, "attack_resolved") < 2:
		errors.append("attacks should emit attack_resolved events")
	if _event_count(snapshot, "corpse_created") < 2:
		errors.append("kills should emit corpse_created events")
	if bool(snapshot.get("combat_state", {}).get("active", true)):
		errors.append("combat should exit after hostiles are gone")
	return errors


func _expect_combat_visibility_decay(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.turn_open = true
	var y: int = int(player_grid.get("y", 0))
	var near_hostile: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": y,
		"z": int(player_grid.get("z", 0)),
	})
	var blocked_topology := _spatial_test_topology(player_grid, {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": int(player_grid.get("z", 0)),
	})
	simulation._enter_combat([1, near_hostile], "visibility_decay_smoke")
	var first: Dictionary = simulation.update_combat_visibility_decay(blocked_topology)
	if not bool(simulation.snapshot().get("combat_state", {}).get("active", false)):
		errors.append("combat should stay active after first no-sight turn")
	if int(first.get("turns_without_hostile_player_sight", -1)) != 1:
		errors.append("first no-sight turn should increment combat visibility counter to 1")
	var second: Dictionary = simulation.update_combat_visibility_decay(blocked_topology)
	if not bool(simulation.snapshot().get("combat_state", {}).get("active", false)):
		errors.append("combat should stay active after second no-sight turn")
	if int(second.get("turns_without_hostile_player_sight", -1)) != 2:
		errors.append("second no-sight turn should increment combat visibility counter to 2")
	var third: Dictionary = simulation.update_combat_visibility_decay(blocked_topology)
	if not bool(third.get("combat_exited", false)):
		errors.append("third no-sight turn should exit combat")
	if bool(simulation.snapshot().get("combat_state", {}).get("active", true)):
		errors.append("combat should be inactive after no-sight threshold")

	_restore_player_turn(simulation, player)
	var reset_hostile: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": y,
		"z": int(player_grid.get("z", 0)),
	})
	simulation._enter_combat([1, reset_hostile], "visibility_reset_smoke")
	var hidden: Dictionary = simulation.update_combat_visibility_decay(blocked_topology)
	if int(hidden.get("turns_without_hostile_player_sight", -1)) != 1:
		errors.append("hidden hostile should increment no-sight counter before reset")
	var hostile_actor: RefCounted = simulation.actor_registry.get_actor(reset_hostile)
	hostile_actor.grid_position = GridCoord.from_dictionary({
		"x": int(player_grid.get("x", 0)) + 2,
		"y": y,
		"z": int(player_grid.get("z", 0)) + 1,
	})
	var restored: Dictionary = simulation.update_combat_visibility_decay(blocked_topology)
	if int(restored.get("turns_without_hostile_player_sight", -1)) != 0:
		errors.append("visible hostile should reset no-sight counter to 0")
	if not bool(restored.get("visible", false)):
		errors.append("visible hostile should report visibility restored")

	_restore_player_turn(simulation, player)
	if simulation.actor_registry.get_actor(reset_hostile) != null:
		simulation.actor_registry.unregister_actor(reset_hostile)
	var far_hostile: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 5,
		"y": y + 1,
		"z": int(player_grid.get("z", 0)) + 5,
	})
	var near_again: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": y,
		"z": int(player_grid.get("z", 0)),
	})
	simulation._enter_combat([1, near_again], "far_hostile_no_block_smoke")
	for _i in range(3):
		simulation.update_combat_visibility_decay(blocked_topology)
	if bool(simulation.snapshot().get("combat_state", {}).get("active", true)):
		errors.append("far hostile without player sight should not block visibility-decay combat exit")
	if simulation.actor_registry.get_actor(far_hostile) == null:
		errors.append("far hostile should remain registered after visibility-decay combat exit")

	for actor_id in [near_hostile, reset_hostile, far_hostile, near_again]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	_restore_player_turn(simulation, player)


func _expect_deterministic_combat_rng(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	var first_roll: float = _single_seeded_crit_roll(registry, player_grid, 77)
	var repeated_roll: float = _single_seeded_crit_roll(registry, player_grid, 77)
	if absf(first_roll - repeated_roll) > 0.000001:
		errors.append("same combat RNG seed should reproduce the same crit roll")
	var different_seed_roll: float = _single_seeded_crit_roll(registry, player_grid, 78)
	if absf(first_roll - different_seed_roll) <= 0.000001:
		errors.append("different combat RNG seed should alter crit roll")

	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.equipment["main_hand"] = "1003"
	player.ap = 20.0
	simulation.set_combat_rng_seed(911)
	var y: int = int(player_grid.get("y", 0))
	var z: int = int(player_grid.get("z", 0))
	var target_a: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": y,
		"z": z,
	})
	var actor_a: RefCounted = simulation.actor_registry.get_actor(target_a)
	actor_a.hp = 100.0
	actor_a.max_hp = 100.0
	actor_a.defense = 0.0
	var first: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": target_a, "topology": _topology(simulation, registry)})
	if int(simulation.snapshot().get("combat_state", {}).get("combat_rng_counter", -1)) != 1:
		errors.append("combat RNG counter should advance after crit-capable attack")
	if not first.has("crit_roll"):
		errors.append("attack result should expose crit_roll")

	var saved_snapshot: Dictionary = simulation.snapshot()
	var restored: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	restored.load_snapshot(saved_snapshot)
	var restored_player: RefCounted = restored.actor_registry.get_actor(1)
	restored_player.turn_open = true
	restored_player.ap = 20.0
	var target_b: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) - 2,
		"y": y,
		"z": z,
	})
	var restored_target_b: int = _register_character(restored, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) - 2,
		"y": y,
		"z": z,
	})
	var actor_b: RefCounted = simulation.actor_registry.get_actor(target_b)
	actor_b.hp = 100.0
	actor_b.max_hp = 100.0
	actor_b.defense = 0.0
	var restored_actor_b: RefCounted = restored.actor_registry.get_actor(restored_target_b)
	restored_actor_b.hp = 100.0
	restored_actor_b.max_hp = 100.0
	restored_actor_b.defense = 0.0
	player.ap = 20.0
	var continued: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": target_b, "topology": _topology(simulation, registry)})
	var restored_continued: Dictionary = restored.submit_player_command({"kind": "attack", "target_actor_id": restored_target_b, "topology": _topology(restored, registry)})
	if absf(float(continued.get("crit_roll", -1.0)) - float(restored_continued.get("crit_roll", -2.0))) > 0.000001:
		errors.append("combat RNG should continue deterministically after snapshot load")
	if int(restored.snapshot().get("combat_state", {}).get("combat_rng_counter", -1)) != 2:
		errors.append("restored combat RNG counter should advance from loaded counter")

	for actor_id in [target_a, target_b]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	_restore_player_turn(simulation, player)


func _single_seeded_crit_roll(registry: RefCounted, player_grid: Dictionary, seed: int) -> float:
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.equipment["main_hand"] = "1003"
	player.ap = 20.0
	simulation.set_combat_rng_seed(seed)
	var target_id: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	var target: RefCounted = simulation.actor_registry.get_actor(target_id)
	target.hp = 100.0
	target.max_hp = 100.0
	target.defense = 0.0
	var result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": target_id, "topology": _topology(simulation, registry)})
	return float(result.get("crit_roll", -1.0))


func _expect_combat_attribute_damage_modifiers(errors: Array[String], simulation: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	player.grid_position = GridCoord.from_dictionary(player_grid)
	var original_attributes: Dictionary = player.combat_attributes.duplicate(true)
	player.combat_attributes = {
		"attack_power": 10.0,
		"defense": 0.0,
		"crit_damage": 2.0,
	}
	simulation.set_combat_rng_seed(313)
	var y: int = int(player_grid.get("y", 0))
	var z: int = int(player_grid.get("z", 0))

	var blocked_target: int = _register_test_actor(simulation, "blocked_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z,
	}, 20.0)
	var blocked_actor: RefCounted = simulation.actor_registry.get_actor(blocked_target)
	blocked_actor.defense = 99.0
	blocked_actor.combat_attributes = {"damage_reduction": 0.0}
	var blocked: Dictionary = simulation.perform_attack(player.actor_id, blocked_target, {}, {"range": 2, "weapon_profile": {"damage": 10.0, "crit_chance": 0.0}})
	if str(blocked.get("hit_kind", "")) != "blocked":
		errors.append("over-defended target should report blocked hit_kind")
	if absf(float(blocked.get("damage", -1.0))) > 0.01:
		errors.append("blocked attack should deal zero damage")
	if absf(blocked_actor.hp - 20.0) > 0.01:
		errors.append("blocked attack should not change target hp")

	var reduced_target: int = _register_test_actor(simulation, "reduced_target", "hostile", {
		"x": int(player_grid.get("x", 0)),
		"y": y,
		"z": z + 1,
	}, 20.0)
	var reduced_actor: RefCounted = simulation.actor_registry.get_actor(reduced_target)
	reduced_actor.defense = 0.0
	reduced_actor.combat_attributes = {"damage_reduction": 0.5}
	var reduced: Dictionary = simulation.perform_attack(player.actor_id, reduced_target, {}, {"range": 2, "weapon_profile": {"damage": 20.0, "crit_chance": 0.0}})
	if absf(float(reduced.get("damage", 0.0)) - 10.0) > 0.01:
		errors.append("damage_reduction 0.5 should halve 20 damage")

	var armored_target: int = _register_test_actor(simulation, "armored_target", "hostile", {
		"x": int(player_grid.get("x", 0)) - 1,
		"y": y,
		"z": z,
	}, 20.0)
	var armored_actor: RefCounted = simulation.actor_registry.get_actor(armored_target)
	armored_actor.defense = 0.0
	armored_actor.combat_attributes = {"damage_reduction": 0.0}
	armored_actor.equipment["body"] = "2008"
	var armored: Dictionary = simulation.perform_attack(player.actor_id, armored_target, {}, {"range": 2, "weapon_profile": {"damage": 20.0, "crit_chance": 0.0}})
	if absf(float(armored.get("damage", 0.0)) - 4.0) > 0.01:
		errors.append("equipped armor modifiers should apply defense and damage_reduction")

	var crit_target: int = _register_test_actor(simulation, "crit_target", "hostile", {
		"x": int(player_grid.get("x", 0)),
		"y": y,
		"z": z - 1,
	}, 30.0)
	var crit_actor: RefCounted = simulation.actor_registry.get_actor(crit_target)
	crit_actor.defense = 0.0
	crit_actor.combat_attributes = {"damage_reduction": 0.0}
	var crit: Dictionary = simulation.perform_attack(player.actor_id, crit_target, {}, {"range": 2, "weapon_profile": {"damage": 10.0, "crit_chance": 1.0}})
	if str(crit.get("hit_kind", "")) != "crit":
		errors.append("forced crit should report crit hit_kind")
	if absf(float(crit.get("damage", 0.0)) - 20.0) > 0.01:
		errors.append("actor crit_damage should multiply critical damage when weapon has no crit_multiplier")

	for actor_id in [blocked_target, reduced_target, armored_target, crit_target]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	player.combat_attributes = original_attributes
	_restore_player_turn(simulation, player)


func _expect_attack_target_rejections(errors: Array[String], simulation: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.ap = 12.0
	_restore_player_turn(simulation, player)
	var base_x: int = int(player_grid.get("x", 0))
	var y: int = int(player_grid.get("y", 0))
	var z: int = int(player_grid.get("z", 0))
	var friendly_id: int = _register_test_actor(simulation, "friendly_target", "friendly", {
		"x": base_x + 1,
		"y": y,
		"z": z,
	})
	var neutral_id: int = _register_test_actor(simulation, "neutral_target", "neutral", {
		"x": base_x,
		"y": y,
		"z": z + 1,
	})
	var dead_hostile_id: int = _register_test_actor(simulation, "dead_hostile_target", "hostile", {
		"x": base_x - 1,
		"y": y,
		"z": z,
	}, 0.0)

	var before_ap: float = player.ap
	var self_result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": player.actor_id})
	if self_result.get("reason", "") != "target_self":
		errors.append("self attack should report target_self, got %s" % self_result.get("reason", ""))
	if absf(player.ap - before_ap) > 0.01:
		errors.append("self attack rejection should not spend AP")
	if bool(simulation.snapshot().get("combat_state", {}).get("active", false)):
		errors.append("self attack rejection should not enter combat")

	var friendly_result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": friendly_id})
	if friendly_result.get("reason", "") != "target_not_hostile":
		errors.append("friendly attack should report target_not_hostile, got %s" % friendly_result.get("reason", ""))
	if absf(player.ap - before_ap) > 0.01:
		errors.append("friendly attack rejection should not spend AP")
	if bool(simulation.snapshot().get("combat_state", {}).get("active", false)):
		errors.append("friendly attack rejection should not enter combat")

	var neutral_result: Dictionary = simulation.perform_attack(player.actor_id, neutral_id, {}, {"range": 2})
	if neutral_result.get("reason", "") != "target_not_hostile":
		errors.append("neutral attack should report target_not_hostile, got %s" % neutral_result.get("reason", ""))
	var dead_result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": dead_hostile_id})
	if dead_result.get("reason", "") != "target_defeated":
		errors.append("dead target attack should report target_defeated, got %s" % dead_result.get("reason", ""))
	if absf(player.ap - before_ap) > 0.01:
		errors.append("dead target attack rejection should not spend AP")
	if bool(simulation.snapshot().get("combat_state", {}).get("active", false)):
		errors.append("dead target attack rejection should not enter combat")

	var hostile_actor: RefCounted = simulation.actor_registry.get_actor(dead_hostile_id)
	hostile_actor.hp = 5.0
	var hostile_same_side: Dictionary = simulation.perform_attack(dead_hostile_id, dead_hostile_id, {}, {"range": 2})
	if hostile_same_side.get("reason", "") != "target_self":
		errors.append("hostile self attack should report target_self, got %s" % hostile_same_side.get("reason", ""))

	for actor_id in [friendly_id, neutral_id, dead_hostile_id]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	_restore_player_turn(simulation, player)


func _expect_attack_spatial_failures(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.equipment["main_hand"] = "1003"
	player.ap = 20.0
	var y: int = int(player_grid.get("y", 0))
	var z: int = int(player_grid.get("z", 0))
	var level_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)),
		"y": y + 1,
		"z": z + 1,
	})
	var level_result: Dictionary = simulation.perform_attack(1, level_target, {}, {"range": 10})
	if level_result.get("reason", "") != "target_invalid_level":
		errors.append("cross-level attack should report target_invalid_level, got %s" % level_result.get("reason", ""))

	var far_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 4,
		"y": y,
		"z": z,
	})
	var far_result: Dictionary = simulation.perform_attack(1, far_target, {}, {"range": 2})
	if far_result.get("reason", "") != "target_out_of_range":
		errors.append("out-of-range attack should report target_out_of_range, got %s" % far_result.get("reason", ""))
	if int(far_result.get("distance", 0)) != 4 or int(far_result.get("range", 0)) != 2:
		errors.append("out-of-range attack should report distance and range")

	var los_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": y,
		"z": z + 2,
	})
	var los_topology := _spatial_test_topology(player_grid, {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z + 1,
	})
	var los_result: Dictionary = simulation.perform_attack(1, los_target, los_topology, {"range": 8})
	if los_result.get("reason", "") != "target_blocked_by_los":
		errors.append("blocked diagonal LOS attack should report target_blocked_by_los, got %s" % los_result.get("reason", ""))

	var command_los_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": y,
		"z": z,
	})
	var command_los_topology := _spatial_test_topology(player_grid, {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z,
	})
	player.ap = 20.0
	var command_los_result: Dictionary = simulation.submit_player_command({
		"kind": "attack",
		"target_actor_id": command_los_target,
		"topology": command_los_topology,
		"range": 8,
	})
	if command_los_result.get("reason", "") != "target_blocked_by_los":
		errors.append("submit attack with blocked LOS should report target_blocked_by_los, got %s" % command_los_result.get("reason", ""))

	for actor_id in [level_target, far_target, los_target, command_los_target]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	simulation.exit_combat_if_clear("spatial_failure_smoke_cleanup")


func _expect_weapon_profile_attack(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	var topology: Dictionary = _topology(simulation, registry)
	player.ap = 20.0
	player.equipment["main_hand"] = "1003"
	var blunt_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	var blunt: RefCounted = simulation.actor_registry.get_actor(blunt_target)
	blunt.hp = 30.0
	blunt.max_hp = 30.0
	blunt.defense = 0.0
	var before_ap: float = player.ap
	var blunt_result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": blunt_target, "topology": topology})
	if not bool(blunt_result.get("success", false)):
		errors.append("baseball bat range-2 attack failed: %s" % blunt_result.get("reason", "unknown"))
	if absf(float(blunt_result.get("damage", 0.0)) - 15.0) > 0.01:
		errors.append("baseball bat attack should use weapon damage 15")
	if absf((before_ap - player.ap) - 3.0) > 0.01:
		errors.append("baseball bat attack should use attack_speed-derived AP cost 3")
	if not _has_attack_resolved_for_weapon(simulation.snapshot(), "1003"):
		errors.append("attack_resolved should include weapon item id")

	player.equipment["main_hand"] = "1004"
	player.inventory["1009"] = 2
	player.weapon_ammo.erase("main_hand")
	player.ap = 20.0
	var pistol_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 8,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	var pistol_enemy: RefCounted = simulation.actor_registry.get_actor(pistol_target)
	pistol_enemy.hp = 40.0
	pistol_enemy.max_hp = 40.0
	pistol_enemy.defense = 0.0
	var pistol_result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": pistol_target, "topology": topology})
	if not bool(pistol_result.get("success", false)):
		errors.append("pistol range attack failed: %s" % pistol_result.get("reason", "unknown"))
	if int(player.inventory.get("1009", 0)) != 1:
		errors.append("pistol attack should consume one pistol ammo")
	if absf(float(pistol_result.get("damage", 0.0)) - 25.0) > 0.01:
		errors.append("pistol attack should use weapon damage 25")
	player.inventory["1009"] = 2
	player.weapon_ammo["main_hand"] = 1
	var magazine_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 7,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	var magazine_enemy: RefCounted = simulation.actor_registry.get_actor(magazine_target)
	magazine_enemy.hp = 40.0
	magazine_enemy.max_hp = 40.0
	magazine_enemy.defense = 0.0
	var magazine_result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": magazine_target, "topology": topology})
	if not bool(magazine_result.get("success", false)):
		errors.append("loaded pistol magazine attack failed: %s" % magazine_result.get("reason", "unknown"))
	if int(player.weapon_ammo.get("main_hand", 0)) != 0:
		errors.append("loaded pistol attack should consume one magazine round")
	if int(player.inventory.get("1009", 0)) != 2:
		errors.append("loaded pistol attack should not consume spare inventory ammo")
	var no_ammo_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 9,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	var no_ammo: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": no_ammo_target, "topology": topology})
	if no_ammo.get("reason", "") != "magazine_empty":
		errors.append("ranged weapon with empty tracked magazine should report magazine_empty")
	player.weapon_ammo.erase("main_hand")
	player.inventory.erase("1009")
	var inventory_no_ammo_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 10,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	var inventory_no_ammo: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": inventory_no_ammo_target, "topology": topology})
	if inventory_no_ammo.get("reason", "") != "ammo_insufficient":
		errors.append("ranged weapon without tracked magazine or inventory ammo should report ammo_insufficient")
	for actor_id in [blunt_target, pistol_target, magazine_target, no_ammo_target, inventory_no_ammo_target]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	simulation.exit_combat_if_clear("weapon_profile_smoke_cleanup")


func _register_character(simulation: RefCounted, registry: RefCounted, definition_id: String, grid: Dictionary) -> int:
	var record: Dictionary = registry.get_library("characters").get(definition_id, {})
	var data: Dictionary = record.get("data", {})
	var identity: Dictionary = data.get("identity", {})
	var faction: Dictionary = data.get("faction", {})
	var combat: Dictionary = data.get("combat", {})
	var attributes: Dictionary = data.get("attributes", {})
	var sets: Dictionary = attributes.get("sets", {})
	var combat_attributes: Dictionary = sets.get("combat", {})
	var resources: Dictionary = attributes.get("resources", {})
	var hp: Dictionary = resources.get("hp", {})
	return simulation.register_actor({
		"definition_id": definition_id,
		"display_name": str(identity.get("display_name", definition_id)),
		"kind": "enemy",
		"side": str(faction.get("disposition", "hostile")),
		"group_id": str(faction.get("camp_id", "infected")),
		"grid_position": GridCoord.from_dictionary(grid),
		"max_hp": float(combat_attributes.get("max_hp", 1.0)),
		"hp": float(hp.get("current", combat_attributes.get("max_hp", 1.0))),
		"attack_power": float(combat_attributes.get("attack_power", 1.0)),
		"defense": float(combat_attributes.get("defense", 0.0)),
		"xp_reward": int(combat.get("xp_reward", 0)),
	})


func _register_test_actor(simulation: RefCounted, definition_id: String, side: String, grid: Dictionary, hp: float = 10.0) -> int:
	return simulation.register_actor({
		"definition_id": definition_id,
		"display_name": definition_id,
		"kind": "npc" if side != "hostile" else "enemy",
		"side": side,
		"group_id": side,
		"grid_position": GridCoord.from_dictionary(grid),
		"max_hp": max(1.0, hp),
		"hp": hp,
		"attack_power": 4.0,
		"defense": 0.0,
		"combat_attributes": {
			"attack_power": 4.0,
			"defense": 0.0,
		},
		"xp_reward": 0,
	})


func _force_combat_values(simulation: RefCounted, actor_id: int) -> void:
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var target: RefCounted = simulation.actor_registry.get_actor(actor_id)
	player.attack_power = 10.0
	target.hp = 5.0
	target.max_hp = 5.0
	target.defense = 0.0


func _restore_player_turn(simulation: RefCounted, player: RefCounted) -> void:
	player.turn_open = true
	simulation.turn_state["phase"] = "player"
	simulation.turn_state["active_actor_id"] = player.actor_id


func _has_attack_resolved_for_weapon(snapshot: Dictionary, weapon_item_id: String) -> bool:
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		var payload: Dictionary = event_data.get("payload", {})
		if event_data.get("kind", "") == "attack_resolved" and str(payload.get("weapon_item_id", "")) == weapon_item_id:
			return true
	return false


func _active_quest_ids(snapshot: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for quest in snapshot.get("active_quests", []):
		var quest_data: Dictionary = quest
		output.append(str(quest_data.get("quest_id", "")))
	return output


func _quest_progress(snapshot: Dictionary, quest_id: String) -> int:
	for quest in snapshot.get("active_quests", []):
		var quest_data: Dictionary = quest
		if quest_data.get("quest_id", "") == quest_id:
			var completed: Dictionary = quest_data.get("completed_objectives", {})
			return int(completed.get("step_1", 0))
	return 0


func _digest(snapshot: Dictionary) -> Dictionary:
	return {
		"active_quests": snapshot.get("active_quests", []),
		"completed_quests": snapshot.get("completed_quests", []),
		"actors": snapshot.get("actors", []).size(),
		"corpse_containers": snapshot.get("corpse_containers", []),
		"combat_state": snapshot.get("combat_state", {}),
		"event_count": snapshot.get("events", []).size(),
	}


func _topology(simulation: RefCounted, registry: RefCounted) -> Dictionary:
	var world: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	return world.get("map", {})


func _corpse_count(snapshot: Dictionary) -> int:
	return snapshot.get("corpse_containers", []).size()


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _spatial_test_topology(player_grid: Dictionary, blocker_grid: Dictionary) -> Dictionary:
	var px: int = int(player_grid.get("x", 0))
	var py: int = int(player_grid.get("y", 0))
	var pz: int = int(player_grid.get("z", 0))
	var bx: int = int(blocker_grid.get("x", 0))
	var by: int = int(blocker_grid.get("y", py))
	var bz: int = int(blocker_grid.get("z", 0))
	return {
		"bounds": {
			"min_x": min(px, bx) - 4,
			"max_x": max(px, bx) + 6,
			"min_z": min(pz, bz) - 4,
			"max_z": max(pz, bz) + 6,
		},
		"sight_blocking_cells": {
			"%d:%d:%d" % [bx, by, bz]: true,
		},
	}
