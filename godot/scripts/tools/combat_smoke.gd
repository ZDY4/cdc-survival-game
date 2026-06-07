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
	var force_end_runtime: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var force_end_simulation: RefCounted = force_end_runtime.get("simulation")
	var force_end_player: RefCounted = force_end_simulation.actor_registry.get_actor(1)
	_expect_force_end_combat(errors, force_end_simulation, registry, force_end_player, force_end_player.grid_position.to_dictionary())
	_expect_combat_npc_turn_ap_and_close(errors, registry)
	_expect_attack_target_rejections(errors, simulation, player, player_grid)
	_expect_deterministic_combat_rng(errors, simulation, registry, player, player_grid)
	_expect_deterministic_loot_rng(errors, registry, player_grid)
	_expect_combat_attribute_damage_modifiers(errors, simulation, registry, player, player_grid)
	_expect_combat_pending_cancel_turn_policy(errors, registry)
	_expect_weapon_profile_attack(errors, simulation, registry, player, player_grid)
	_expect_attack_spatial_failures(errors, simulation, registry, player, player_grid)
	_expect_attack_target_preview(errors, simulation, registry, player, player_grid)
	_expect_corpse_inventory_and_metadata(errors, simulation, registry, player, player_grid)
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.equipment["main_hand"] = "1002"
	player.inventory["1009"] = 10
	player.ap = 20.0
	var zombie_a: int = _register_character(simulation, registry, "zombie_walker", {"x": int(player_grid.get("x", 0)) + 1, "y": int(player_grid.get("y", 0)), "z": int(player_grid.get("z", 0))})
	var zombie_b: int = _register_character(simulation, registry, "zombie_walker", {"x": int(player_grid.get("x", 0)) - 1, "y": int(player_grid.get("y", 0)), "z": int(player_grid.get("z", 0))})
	_force_combat_values(simulation, zombie_a)
	_force_combat_values(simulation, zombie_b)
	var topology: Dictionary = _topology(simulation, registry)
	var corpse_count_before_zombies: int = _corpse_count(simulation.snapshot())

	var first: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": zombie_a, "topology": topology})
	if not bool(first.get("success", false)) or not bool(first.get("defeated", false)):
		errors.append("first zombie attack should defeat target")
	_expect_turn_policy(errors, first, "attack", false, "first zombie attack")
	if _quest_progress(simulation.snapshot(), "zombie_hunter") != 1:
		errors.append("zombie_hunter progress should be 1 after first kill")
	if _corpse_count(simulation.snapshot()) != corpse_count_before_zombies + 1:
		errors.append("first zombie kill should create a corpse container")

	var second: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": zombie_b, "topology": topology})
	if not bool(second.get("success", false)) or not bool(second.get("defeated", false)):
		errors.append("second zombie attack should defeat target")
	var snapshot: Dictionary = simulation.snapshot()
	if _active_quest_ids(snapshot).has("zombie_hunter"):
		errors.append("zombie_hunter should complete after two kills")
	if not snapshot.get("completed_quests", []).has("zombie_hunter"):
		errors.append("zombie_hunter missing from completed quests")
	if _corpse_count(snapshot) != corpse_count_before_zombies + 2:
		errors.append("second zombie kill should preserve both corpse containers")
	if _event_count(snapshot, "attack_resolved") < 2:
		errors.append("attacks should emit attack_resolved events")
	if _event_count(snapshot, "actor_defeated") < 2:
		errors.append("kills should emit actor_defeated events")
	if _event_count(snapshot, "corpse_created") < 2:
		errors.append("kills should emit corpse_created events")
	if _event_count(snapshot, "combat_started") <= 0:
		errors.append("attacks should emit combat_started")
	if _event_count(snapshot, "combat_ended") <= 0:
		errors.append("clearing hostiles should emit combat_ended")
	if bool(snapshot.get("combat_state", {}).get("active", true)):
		errors.append("combat should exit after hostiles are gone")
	_expect_skill_targeting_preview(errors, simulation, registry, player, player_grid)
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


func _expect_force_end_combat(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.hp = max(1.0, player.hp)
	var force_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	simulation._enter_combat([player.actor_id, force_target], "force_end_smoke")
	var force_result: Dictionary = simulation.force_end_combat("smoke_forced", {
		"source": "combat_smoke",
		"target_actor_id": force_target,
	})
	if not bool(force_result.get("success", false)):
		errors.append("force_end_combat should end active combat")
	var force_snapshot: Dictionary = simulation.snapshot()
	if bool(force_snapshot.get("combat_state", {}).get("active", true)):
		errors.append("force_end_combat should clear combat active state")
	if player.in_combat or player.turn_open:
		errors.append("force_end_combat should clear actor combat and turn state")
	var forced_payload: Dictionary = _last_event_payload(force_snapshot, "combat_ended")
	if str(forced_payload.get("reason", "")) != "smoke_forced" or str(forced_payload.get("source", "")) != "combat_smoke":
		errors.append("force_end_combat should emit combat_ended with reason and metadata")
	if _array_or_empty(forced_payload.get("participants", [])).is_empty():
		errors.append("force_end_combat should expose previous participants")
	var inactive_result: Dictionary = simulation.force_end_combat("smoke_inactive")
	if bool(inactive_result.get("success", false)) or str(inactive_result.get("reason", "")) != "combat_inactive":
		errors.append("force_end_combat should reject inactive combat with combat_inactive")
	if simulation.actor_registry.get_actor(force_target) != null:
		simulation.actor_registry.unregister_actor(force_target)
	_restore_player_turn(simulation, player)

	var defeat_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)) + 1,
	})
	player.hp = 0.0
	simulation._enter_combat([player.actor_id, defeat_target], "player_defeat_smoke")
	if not simulation.exit_combat_if_player_defeated("player_defeated_smoke"):
		errors.append("exit_combat_if_player_defeated should end combat when no living player remains")
	var defeat_payload: Dictionary = _last_event_payload(simulation.snapshot(), "combat_ended")
	if str(defeat_payload.get("reason", "")) != "player_defeated_smoke":
		errors.append("player defeated combat exit should emit combat_ended with reason")
	player.hp = player.max_hp
	_restore_player_turn(simulation, player)
	if simulation.actor_registry.get_actor(defeat_target) != null:
		simulation.actor_registry.unregister_actor(defeat_target)


func _expect_combat_npc_turn_ap_and_close(errors: Array[String], registry: RefCounted) -> void:
	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var simulation: RefCounted = runtime_result.get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	if player == null:
		errors.append("combat NPC turn AP smoke missing player")
		return
	var player_grid: Dictionary = player.grid_position.to_dictionary()
	player.hp = 100.0
	player.max_hp = 100.0
	player.defense = 0.0
	var npc_id: int = _register_test_actor(simulation, "combat_turn_ap_hostile", "hostile", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 20.0)
	var npc: RefCounted = simulation.actor_registry.get_actor(npc_id)
	if npc == null:
		errors.append("combat NPC turn AP smoke missing hostile")
		return
	npc.ap = 5.0
	npc.combat_attributes["turn_ap_gain"] = 9.0
	npc.combat_attributes["turn_ap_max"] = 9.0
	npc.combat_attributes["combat_turn_ap_gain"] = 2.0
	npc.combat_attributes["combat_turn_ap_max"] = 2.0
	npc.combat_attributes["combat_affordable_ap_threshold"] = 2.0
	simulation._enter_combat([player.actor_id, npc_id], "npc_turn_ap_smoke")
	var event_count_before: int = simulation.snapshot().get("events", []).size()
	var results: Array = simulation.advance_world_turn(_topology(simulation, registry))
	var npc_result: Dictionary = _npc_result_for_actor(results, npc_id)
	if npc_result.is_empty():
		errors.append("combat NPC turn AP smoke should return NPC result")
		return
	var turn_open: Dictionary = _dictionary_or_empty(npc_result.get("turn_open", {}))
	if float(turn_open.get("ap_gain", 0.0)) != 2.0 or float(turn_open.get("ap_max", 0.0)) != 2.0:
		errors.append("combat NPC turn should use combat AP gain/max instead of exploration AP")
	if float(turn_open.get("affordable_ap_threshold", 0.0)) != 2.0:
		errors.append("combat NPC turn should expose combat affordable AP threshold")
	if not bool(turn_open.get("combat_active", false)):
		errors.append("combat NPC turn open snapshot should mark combat active")
	if float(turn_open.get("ap", -1.0)) != 2.0:
		errors.append("combat NPC turn should clamp AP to combat max on open")
	if str(npc_result.get("intent", "")) != "attack":
		errors.append("adjacent combat NPC should attack during combat AP smoke")
	if float(npc_result.get("ap_after_action", -1.0)) != 0.0:
		errors.append("combat NPC attack should spend AP down to 0")
	if str(npc_result.get("turn_close_reason", "")) != "npc_turn_exhausted":
		errors.append("combat NPC exhausted turn should close with npc_turn_exhausted")
	if bool(npc.turn_open):
		errors.append("combat NPC turn should be closed after world turn")
	if float(npc.ap) != 0.0:
		errors.append("combat NPC AP should stay at 0 after exhausted turn close")
	var started_payload: Dictionary = _event_payload_after(simulation.snapshot(), "turn_started", npc_id, event_count_before)
	if float(started_payload.get("ap_gain", 0.0)) != 2.0 or float(started_payload.get("ap_max", 0.0)) != 2.0:
		errors.append("combat NPC turn_started should expose combat AP gain/max")
	var ended_payload: Dictionary = _event_payload_after(simulation.snapshot(), "turn_ended", npc_id, event_count_before)
	if str(ended_payload.get("reason", "")) != "npc_turn_exhausted":
		errors.append("combat NPC turn_ended should expose npc_turn_exhausted")


func _expect_combat_pending_cancel_turn_policy(errors: Array[String], registry: RefCounted) -> void:
	var runtime_result: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime()
	var simulation: RefCounted = runtime_result.get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var player_grid: Dictionary = player.grid_position.to_dictionary()
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.ap = 0.0
	player.equipment["main_hand"] = "1002"
	player.combat_attributes["accuracy"] = 100.0
	_restore_player_turn(simulation, player)
	var target_id: int = _register_test_actor(simulation, "combat_cancel_pending_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 20.0)
	simulation._enter_combat([player.actor_id, target_id], "combat_cancel_pending_smoke")
	var topology: Dictionary = _topology(simulation, registry)
	var queued: Dictionary = simulation.submit_player_command({
		"kind": "attack",
		"target_actor_id": target_id,
		"topology": topology,
	})
	if str(queued.get("reason", "")) != "ap_insufficient_attack_queued":
		errors.append("combat AP-insufficient attack should queue pending attack, got %s" % queued.get("reason", "unknown"))
	var pending: Dictionary = _dictionary_or_empty(simulation.snapshot().get("pending_interaction", {}))
	if str(pending.get("kind", "")) != "attack":
		errors.append("combat AP-insufficient attack should create pending attack interaction")
	var round_before: int = int(simulation.snapshot().get("turn_state", {}).get("round", 0))
	var cancel_events_before: int = _event_count(simulation.snapshot(), "interaction_cancelled")
	var cancelled: Dictionary = simulation.cancel_pending("combat_smoke_cancel", true, topology)
	if not bool(cancelled.get("had_pending", false)):
		errors.append("combat cancel_pending should report queued pending attack")
	var policy: Dictionary = _dictionary_or_empty(cancelled.get("turn_policy", {}))
	if str(policy.get("action_kind", "")) != "cancel_pending":
		errors.append("combat cancel turn_policy should expose cancel_pending action")
	if str(policy.get("reason", "")) != "preserved_turn":
		errors.append("combat cancel turn_policy should preserve turn, got %s" % policy.get("reason", ""))
	if str(policy.get("auto_end_blocked_reason", "")) != "combat_active":
		errors.append("combat cancel turn_policy should explain combat_active auto-end block")
	if bool(policy.get("auto_advanced", true)):
		errors.append("combat cancel turn_policy should not auto advance while combat is active")
	if not bool(policy.get("combat_active_before", false)) or not bool(policy.get("combat_active_after", false)):
		errors.append("combat cancel turn_policy should preserve combat active diagnostics")
	if bool(policy.get("pending_interaction", true)) or bool(policy.get("pending_movement", true)):
		errors.append("combat cancel turn_policy should report pending cleared")
	if int(simulation.snapshot().get("turn_state", {}).get("round", 0)) != round_before:
		errors.append("combat cancel should not advance world round")
	if not bool(simulation.snapshot().get("combat_state", {}).get("active", false)):
		errors.append("combat cancel should keep combat active")
	if _event_count(simulation.snapshot(), "interaction_cancelled") <= cancel_events_before:
		errors.append("combat cancel should emit interaction_cancelled")
	if not _dictionary_or_empty(simulation.snapshot().get("pending_interaction", {})).is_empty():
		errors.append("combat cancel should clear pending interaction")
	simulation.force_end_combat("combat_cancel_smoke_cleanup")
	if simulation.actor_registry.get_actor(target_id) != null:
		simulation.actor_registry.unregister_actor(target_id)


func _expect_deterministic_combat_rng(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	var original_attributes: Dictionary = player.combat_attributes.duplicate(true)
	var first_roll: float = _single_seeded_crit_roll(registry, player_grid, 77)
	var repeated_roll: float = _single_seeded_crit_roll(registry, player_grid, 77)
	if absf(first_roll - repeated_roll) > 0.000001:
		errors.append("same combat RNG seed should reproduce the same crit roll")
	var different_seed_roll: float = _single_seeded_crit_roll(registry, player_grid, 78)
	if absf(first_roll - different_seed_roll) <= 0.000001:
		errors.append("different combat RNG seed should alter crit roll")

	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.equipment["main_hand"] = "1003"
	player.combat_attributes["accuracy"] = 100.0
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
	actor_a.combat_attributes["evasion"] = 0.0
	var first: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": target_a, "topology": _topology(simulation, registry)})
	if int(simulation.snapshot().get("combat_state", {}).get("combat_rng_counter", -1)) != 2:
		errors.append("combat RNG counter should advance for hit and crit rolls after crit-capable attack")
	if not first.has("crit_roll"):
		errors.append("attack result should expose crit_roll")
	if not first.has("hit_roll") or not first.has("hit_chance"):
		errors.append("attack result should expose hit_roll and hit_chance")

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
	actor_b.combat_attributes["evasion"] = 0.0
	var restored_actor_b: RefCounted = restored.actor_registry.get_actor(restored_target_b)
	restored_actor_b.hp = 100.0
	restored_actor_b.max_hp = 100.0
	restored_actor_b.defense = 0.0
	restored_actor_b.combat_attributes["evasion"] = 0.0
	player.ap = 20.0
	var continued: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": target_b, "topology": _topology(simulation, registry)})
	var restored_continued: Dictionary = restored.submit_player_command({"kind": "attack", "target_actor_id": restored_target_b, "topology": _topology(restored, registry)})
	if absf(float(continued.get("crit_roll", -1.0)) - float(restored_continued.get("crit_roll", -2.0))) > 0.000001:
		errors.append("combat RNG should continue deterministically after snapshot load")
	if int(restored.snapshot().get("combat_state", {}).get("combat_rng_counter", -1)) != 4:
		errors.append("restored combat RNG counter should advance from loaded counter")

	for actor_id in [target_a, target_b]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	player.combat_attributes = original_attributes
	_restore_player_turn(simulation, player)


func _single_seeded_crit_roll(registry: RefCounted, player_grid: Dictionary, seed: int) -> float:
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.equipment["main_hand"] = "1003"
	player.combat_attributes["accuracy"] = 100.0
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
	target.combat_attributes["evasion"] = 0.0
	var result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": target_id, "topology": _topology(simulation, registry)})
	return float(result.get("crit_roll", -1.0))


func _expect_deterministic_loot_rng(errors: Array[String], registry: RefCounted, player_grid: Dictionary) -> void:
	var first: Dictionary = _single_seeded_loot_drop(registry, player_grid, 191)
	var repeated: Dictionary = _single_seeded_loot_drop(registry, player_grid, 191)
	if int(first.get("loot_count", -1)) != int(repeated.get("loot_count", -2)):
		errors.append("same combat RNG seed should reproduce random loot count")
	if int(first.get("counter", -1)) != int(repeated.get("counter", -2)):
		errors.append("same combat RNG seed should reproduce loot RNG counter")
	var different: Dictionary = _single_seeded_loot_drop(registry, player_grid, 192)
	if int(first.get("loot_count", -1)) == int(different.get("loot_count", -1)) and float(first.get("roll", -1.0)) == float(different.get("roll", -1.0)):
		errors.append("different combat RNG seed should alter random loot roll or count")

	var saved_snapshot: Dictionary = _loot_snapshot_after_kill(registry, player_grid, 233, "loot_rng_saved_target")
	var restored: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	restored.load_snapshot(saved_snapshot)
	var restored_counter_before: int = int(restored.snapshot().get("combat_state", {}).get("combat_rng_counter", -1))
	_kill_random_loot_actor(restored, registry, player_grid, "loot_rng_after_restore_target")
	var restored_counter_after: int = int(restored.snapshot().get("combat_state", {}).get("combat_rng_counter", -1))
	if restored_counter_after <= restored_counter_before:
		errors.append("random loot should advance combat RNG counter after snapshot load")


func _single_seeded_loot_drop(registry: RefCounted, player_grid: Dictionary, seed: int) -> Dictionary:
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	simulation.set_combat_rng_seed(seed)
	var target_id: int = _kill_random_loot_actor(simulation, registry, player_grid, "loot_rng_target")
	var corpse: Dictionary = _corpse_by_source_actor(simulation.snapshot(), target_id)
	return {
		"loot_count": _entry_count(_array_or_empty(corpse.get("inventory", [])), "1009"),
		"counter": int(simulation.snapshot().get("combat_state", {}).get("combat_rng_counter", -1)),
		"roll": _loot_roll_probe(seed, target_id, "1009", 0),
	}


func _loot_snapshot_after_kill(registry: RefCounted, player_grid: Dictionary, seed: int, definition_id: String) -> Dictionary:
	var simulation: RefCounted = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("simulation")
	simulation.set_combat_rng_seed(seed)
	_kill_random_loot_actor(simulation, registry, player_grid, definition_id)
	return simulation.snapshot()


func _kill_random_loot_actor(simulation: RefCounted, registry: RefCounted, player_grid: Dictionary, definition_id: String) -> int:
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.equipment["main_hand"] = "1003"
	player.combat_attributes["accuracy"] = 100.0
	player.ap = 20.0
	var target_id: int = _register_test_actor(simulation, definition_id, "hostile", {
		"x": int(player_grid.get("x", 0)) + 3,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 5.0)
	var target: RefCounted = simulation.actor_registry.get_actor(target_id)
	target.map_id = str(simulation.active_map_id)
	target.inventory = {}
	target.equipment = {}
	target.weapon_ammo = {}
	var random_loot_table: Array[Dictionary] = [{
		"item_id": "1009",
		"chance": 1.0,
		"min": 1,
		"max": 3,
	}]
	target.loot_table = random_loot_table
	target.combat_attributes["evasion"] = 0.0
	target.defense = 0.0
	var result: Dictionary = simulation.perform_attack(player.actor_id, target_id, _topology(simulation, registry), {
		"range": 4,
		"weapon_profile": {"damage": 99.0, "crit_chance": 0.0, "accuracy": 100.0},
	})
	if not bool(result.get("defeated", false)):
		push_error("random loot smoke kill failed: %s" % result.get("reason", "unknown"))
	return target_id


func _loot_roll_probe(seed: int, actor_id: int, item_id: String, loot_index: int) -> float:
	var salt_base: int = abs(actor_id * 65537 + abs(hash(item_id)) + loot_index * 4099)
	var mixed: int = max(1, abs(seed)) % 2147483647
	mixed = (mixed + 1103515245) % 2147483647
	mixed = (mixed + (abs(salt_base) % 2147483647) * 1664525) % 2147483647
	mixed = (mixed + 1013904223) % 2147483647
	return float(mixed % 1000000) / 1000000.0


func _expect_combat_attribute_damage_modifiers(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	player.grid_position = GridCoord.from_dictionary(player_grid)
	var original_attributes: Dictionary = player.combat_attributes.duplicate(true)
	var original_progression: Dictionary = player.progression.duplicate(true)
	var original_active_effects: Array[Dictionary] = player.active_effects.duplicate(true)
	player.combat_attributes = {
		"attack_power": 10.0,
		"defense": 0.0,
		"accuracy": 100.0,
		"crit_damage": 2.0,
	}
	simulation.set_combat_rng_seed(313)
	var y: int = int(player_grid.get("y", 0))
	var z: int = int(player_grid.get("z", 0))

	var miss_target: int = _register_test_actor(simulation, "miss_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": y,
		"z": z,
	}, 20.0)
	var miss_actor: RefCounted = simulation.actor_registry.get_actor(miss_target)
	miss_actor.defense = 0.0
	miss_actor.combat_attributes = {"damage_reduction": 0.0, "evasion": 0.95}
	player.combat_attributes["accuracy"] = 0.0
	var miss_counter_before: int = int(simulation.snapshot().get("combat_state", {}).get("combat_rng_counter", 0))
	var missed: Dictionary = simulation.perform_attack(player.actor_id, miss_target, {}, {"range": 3, "weapon_profile": {"damage": 20.0, "crit_chance": 1.0, "accuracy": 0.0}})
	if str(missed.get("hit_kind", "")) != "miss":
		errors.append("zero accuracy attack against evasive target should report miss")
	if absf(float(missed.get("damage", -1.0))) > 0.01:
		errors.append("missed attack should deal zero damage")
	if absf(miss_actor.hp - 20.0) > 0.01:
		errors.append("missed attack should not change target hp")
	if bool(missed.get("critical", false)):
		errors.append("missed attack should not crit")
	if not _array_or_empty(missed.get("triggered_on_hit_effect_ids", [])).is_empty():
		errors.append("missed attack should not trigger on-hit effects")
	if absf(float(missed.get("hit_chance", -1.0))) > 0.001:
		errors.append("missed attack should expose zero hit_chance")
	if int(simulation.snapshot().get("combat_state", {}).get("combat_rng_counter", 0)) != miss_counter_before + 1:
		errors.append("missed attack should consume only the hit roll")
	player.combat_attributes["accuracy"] = 100.0

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

	simulation.grant_skill_points(player.actor_id, 2, "combat_smoke")
	var combat_skill_result: Dictionary = simulation.learn_skill(player.actor_id, "combat", registry.get_library("skills"))
	if not bool(combat_skill_result.get("success", false)):
		errors.append("combat passive skill learn should succeed before passive damage bonus check: %s" % combat_skill_result.get("reason", "unknown"))
	var passive_target: int = _register_test_actor(simulation, "passive_target", "hostile", {
		"x": int(player_grid.get("x", 0)) - 1,
		"y": y,
		"z": z + 1,
	}, 40.0)
	var passive_actor: RefCounted = simulation.actor_registry.get_actor(passive_target)
	passive_actor.defense = 0.0
	passive_actor.combat_attributes = {"damage_reduction": 0.0}
	var passive: Dictionary = simulation.perform_attack(player.actor_id, passive_target, {}, {"range": 3, "weapon_profile": {"damage": 20.0, "crit_chance": 0.0}})
	if absf(float(passive.get("damage", 0.0)) - 21.0) > 0.01:
		errors.append("combat passive damage_bonus should increase 20 damage to 21")
	if absf(float(passive.get("damage_bonus", 0.0)) - 0.04) > 0.001:
		errors.append("passive attack result should expose 0.04 damage_bonus")

	var adrenaline_learn_result: Dictionary = simulation.learn_skill(player.actor_id, "adrenaline_rush", registry.get_library("skills"))
	if not bool(adrenaline_learn_result.get("success", false)):
		errors.append("adrenaline_rush learn should succeed before active damage bonus check: %s" % adrenaline_learn_result.get("reason", "unknown"))
	player.ap = 20.0
	var skill_result: Dictionary = simulation.submit_player_command({
		"kind": "use_skill",
		"skill_id": "adrenaline_rush",
		"skill_library": registry.get_library("skills"),
	})
	if not bool(skill_result.get("success", false)):
		errors.append("adrenaline_rush activation should succeed before combat damage bonus check: %s" % skill_result.get("reason", "unknown"))
	_expect_turn_policy(errors, skill_result, "use_skill", false, "adrenaline_rush activation")
	var buffed_target: int = _register_test_actor(simulation, "buffed_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z + 1,
	}, 40.0)
	var buffed_actor: RefCounted = simulation.actor_registry.get_actor(buffed_target)
	buffed_actor.defense = 0.0
	buffed_actor.combat_attributes = {"damage_reduction": 0.0}
	var buffed: Dictionary = simulation.perform_attack(player.actor_id, buffed_target, {}, {"range": 3, "weapon_profile": {"damage": 20.0, "crit_chance": 0.0}})
	if absf(float(buffed.get("damage", 0.0)) - 26.0) > 0.01:
		errors.append("combat passive plus adrenaline_rush damage_bonus should increase 20 damage to 26")
	if absf(float(buffed.get("damage_bonus", 0.0)) - 0.29) > 0.001:
		errors.append("buffed attack result should expose stacked 0.29 damage_bonus")

	for actor_id in [miss_target, blocked_target, reduced_target, armored_target, crit_target, passive_target, buffed_target]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	player.combat_attributes = original_attributes
	player.progression = original_progression
	player.active_effects = original_active_effects
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
	if int(friendly_result.get("actor_id", 0)) != player.actor_id or int(friendly_result.get("target_actor_id", 0)) != friendly_id:
		errors.append("friendly attack rejection should expose actor ids")
	if str(friendly_result.get("attacker_side", "")) != "player" or str(friendly_result.get("target_side", "")) != "friendly":
		errors.append("friendly attack rejection should expose attacker and target sides")
	if absf(player.ap - before_ap) > 0.01:
		errors.append("friendly attack rejection should not spend AP")
	if bool(simulation.snapshot().get("combat_state", {}).get("active", false)):
		errors.append("friendly attack rejection should not enter combat")
	var friendly_preview: Dictionary = simulation.preview_attack(player.actor_id, friendly_id, {}, {"range": 2})
	if bool(friendly_preview.get("can_attack", false)) or str(friendly_preview.get("reason", "")) != "target_not_hostile":
		errors.append("friendly attack preview should require explicit friendly fire confirmation")
	if not bool(friendly_preview.get("friendly_fire", false)) or not bool(friendly_preview.get("confirmation_required", false)):
		errors.append("friendly attack rejection preview should expose friendly fire confirmation requirement")
	var confirmed_preview: Dictionary = simulation.preview_attack(player.actor_id, friendly_id, {}, {
		"range": 2,
		"allow_non_hostile_attack": true,
		"confirmation_required": true,
	})
	if not bool(confirmed_preview.get("can_attack", false)) or not bool(confirmed_preview.get("friendly_fire", false)):
		errors.append("confirmed friendly fire preview should be attackable")
	var consequence_preview: Dictionary = _dictionary_or_empty(confirmed_preview.get("relationship_consequence_preview", {}))
	if float(consequence_preview.get("score_after", 0.0)) > -50.0:
		errors.append("confirmed friendly fire preview should show hostile relationship consequence")
	player.ap = 12.0
	var friendly_actor: RefCounted = simulation.actor_registry.get_actor(friendly_id)
	friendly_actor.hp = 40.0
	friendly_actor.max_hp = 40.0
	var friendly_hp_before: float = friendly_actor.hp
	var confirmed_friendly: Dictionary = simulation.submit_player_command({
		"kind": "attack",
		"target_actor_id": friendly_id,
		"range": 2,
		"allow_non_hostile_attack": true,
		"confirmation_required": true,
	})
	if not bool(confirmed_friendly.get("success", false)) or not bool(confirmed_friendly.get("friendly_fire", false)):
		errors.append("confirmed friendly fire attack should succeed and expose friendly_fire")
	if friendly_actor.hp >= friendly_hp_before:
		errors.append("confirmed friendly fire attack should damage friendly target")
	if simulation.relationship_score(player.actor_id, friendly_id) > -50.0:
		errors.append("confirmed friendly fire attack should make target relationship-hostile")
	if not bool(simulation.actor_hostility(player.actor_id, friendly_id).get("hostile", false)):
		errors.append("confirmed friendly fire attack should make target hostile to player")
	if not bool(simulation.snapshot().get("combat_state", {}).get("active", false)):
		errors.append("confirmed friendly fire attack should enter combat")
	var friendly_payload: Dictionary = _last_event_payload(simulation.snapshot(), "attack_resolved")
	if not bool(friendly_payload.get("friendly_fire", false)):
		errors.append("friendly fire attack_resolved event should expose friendly_fire")
	if _dictionary_or_empty(friendly_payload.get("relationship_consequence", {})).is_empty():
		errors.append("friendly fire attack_resolved event should expose relationship consequence")
	simulation.force_end_combat("combat_smoke_friendly_fire_cleanup")
	friendly_actor.hp = friendly_hp_before
	player.ap = before_ap
	_restore_player_turn(simulation, player)
	var relation_hostile_result: Dictionary = simulation.set_relationship_score(player.actor_id, friendly_id, -75.0, "combat_smoke_relation_hostile")
	if not bool(relation_hostile_result.get("success", false)):
		errors.append("combat smoke should make friendly target relationship-hostile")
	var relation_attack: Dictionary = simulation.preview_attack(player.actor_id, friendly_id, {}, {"range": 2})
	if not bool(relation_attack.get("can_attack", false)):
		errors.append("relationship-hostile friendly target should become attackable: %s" % relation_attack.get("reason", "unknown"))
	simulation.set_relationship_score(player.actor_id, friendly_id, 50.0, "combat_smoke_relation_restored")

	var neutral_result: Dictionary = simulation.perform_attack(player.actor_id, neutral_id, {}, {"range": 2})
	if neutral_result.get("reason", "") != "target_not_hostile":
		errors.append("neutral attack should report target_not_hostile, got %s" % neutral_result.get("reason", ""))
	var hostile_actor_for_relation: RefCounted = simulation.actor_registry.get_actor(dead_hostile_id)
	hostile_actor_for_relation.hp = 5.0
	simulation.set_relationship_score(player.actor_id, dead_hostile_id, 25.0, "combat_smoke_hostile_pacified")
	var pacified_hostile: Dictionary = simulation.perform_attack(player.actor_id, dead_hostile_id, {}, {"range": 2})
	if pacified_hostile.get("reason", "") != "target_not_hostile":
		errors.append("positive relationship should pacify hostile side attack target, got %s" % pacified_hostile.get("reason", ""))
	if str(pacified_hostile.get("hostility_reason", "")) != "relationship_non_hostile":
		errors.append("pacified hostile rejection should expose relationship_non_hostile")
	simulation.set_relationship_score(player.actor_id, dead_hostile_id, -100.0, "combat_smoke_hostile_restored")
	hostile_actor_for_relation.hp = 0.0
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
	if int(level_result.get("actor_id", 0)) != 1 or int(level_result.get("target_actor_id", 0)) != level_target:
		errors.append("cross-level attack should expose actor ids")
	if _dictionary_or_empty(level_result.get("attacker_grid", {})).is_empty() or _dictionary_or_empty(level_result.get("target_grid", {})).is_empty():
		errors.append("cross-level attack should expose attacker and target grids")
	if int(level_result.get("range", 0)) != 10:
		errors.append("cross-level attack should expose resolved range")
	_expect_spatial_diagnostics(errors, level_result, "cross-level attack", false, true, true, false, false, "target_invalid_level")

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
	if int(far_result.get("actor_id", 0)) != 1 or int(far_result.get("target_actor_id", 0)) != far_target:
		errors.append("out-of-range attack should expose actor ids")
	if _dictionary_or_empty(far_result.get("attacker_grid", {})).is_empty() or _dictionary_or_empty(far_result.get("target_grid", {})).is_empty():
		errors.append("out-of-range attack should expose attacker and target grids")
	_expect_spatial_diagnostics(errors, far_result, "out-of-range attack", true, false, true, true, false, "target_out_of_range")

	var close_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z,
	})
	var close_ap_before: float = player.ap
	var close_result: Dictionary = simulation.perform_attack(1, close_target, {}, {
		"range": 6,
		"min_range": 2,
		"weapon_profile": {"damage": 20.0, "range": 6, "min_range": 2},
	})
	if close_result.get("reason", "") != "target_too_close":
		errors.append("minimum-range attack should report target_too_close, got %s" % close_result.get("reason", ""))
	if int(close_result.get("distance", 0)) != 1 or int(close_result.get("min_range", -1)) != 2:
		errors.append("minimum-range attack should expose distance and min_range")
	if absf(player.ap - close_ap_before) > 0.01:
		errors.append("minimum-range perform_attack rejection should not spend AP")
	_expect_spatial_diagnostics(errors, close_result, "minimum-range attack", true, true, false, true, false, "target_too_close")

	simulation.set_actor_vision_radius(1, 0)
	simulation.refresh_actor_vision(1, _topology(simulation, registry))
	var hidden_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z,
	})
	var hidden_result: Dictionary = simulation.perform_attack(1, hidden_target, {}, {"range": 2})
	if hidden_result.get("reason", "") != "target_not_visible":
		errors.append("hidden target attack should report target_not_visible, got %s" % hidden_result.get("reason", ""))
	if int(hidden_result.get("actor_id", 0)) != 1 or int(hidden_result.get("target_actor_id", 0)) != hidden_target:
		errors.append("hidden target attack should expose actor ids")
	if _dictionary_or_empty(hidden_result.get("attacker_grid", {})).is_empty():
		errors.append("hidden target attack should expose attacker_grid")
	if _dictionary_or_empty(hidden_result.get("target_grid", {})).is_empty():
		errors.append("hidden target attack should expose target_grid")
	simulation.clear_actor_vision(1)

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
	if int(los_result.get("actor_id", 0)) != 1 or int(los_result.get("target_actor_id", 0)) != los_target:
		errors.append("blocked diagonal LOS attack should expose actor ids")
	if _dictionary_or_empty(los_result.get("attacker_grid", {})).is_empty() or _dictionary_or_empty(los_result.get("target_grid", {})).is_empty():
		errors.append("blocked diagonal LOS attack should expose attacker and target grids")
	if int(los_result.get("distance", 0)) != 4 or int(los_result.get("range", 0)) != 8:
		errors.append("blocked diagonal LOS attack should expose distance and range")
	_expect_spatial_diagnostics(errors, los_result, "blocked diagonal LOS attack", true, true, true, false, true, "target_blocked_by_los")

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
	if int(command_los_result.get("actor_id", 0)) != 1 or int(command_los_result.get("target_actor_id", 0)) != command_los_target:
		errors.append("submit attack with blocked LOS should expose actor ids")
	if _dictionary_or_empty(command_los_result.get("attacker_grid", {})).is_empty() or _dictionary_or_empty(command_los_result.get("target_grid", {})).is_empty():
		errors.append("submit attack with blocked LOS should expose attacker and target grids")
	_expect_spatial_diagnostics(errors, command_los_result, "submit blocked LOS attack", true, true, true, false, true, "target_blocked_by_los")

	var command_close_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z,
	})
	player.ap = 20.0
	var command_close_ap_before: float = player.ap
	var command_close_combat_started_before: int = _event_count(simulation.snapshot(), "combat_started")
	var command_close_result: Dictionary = simulation.submit_player_command({
		"kind": "attack",
		"target_actor_id": command_close_target,
		"topology": _topology(simulation, registry),
		"range": 6,
		"min_range": 2,
	})
	if command_close_result.get("reason", "") != "target_too_close":
		errors.append("submit attack inside minimum range should report target_too_close, got %s" % command_close_result.get("reason", ""))
	if absf(player.ap - command_close_ap_before) > 0.01:
		errors.append("submit attack inside minimum range should not spend AP")
	if _event_count(simulation.snapshot(), "combat_started") != command_close_combat_started_before:
		errors.append("submit attack inside minimum range should not emit combat_started")
	_expect_spatial_diagnostics(errors, command_close_result, "submit minimum-range attack", true, true, false, true, true, "target_too_close")

	for actor_id in [level_target, far_target, close_target, hidden_target, los_target, command_los_target, command_close_target]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	simulation.exit_combat_if_clear("spatial_failure_smoke_cleanup")


func _expect_attack_target_preview(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	player.grid_position = GridCoord.from_dictionary(player_grid)
	player.equipment["main_hand"] = "1003"
	player.ap = 20.0
	player.combat_attributes["accuracy"] = 100.0
	var topology: Dictionary = _topology(simulation, registry)
	var y: int = int(player_grid.get("y", 0))
	var z: int = int(player_grid.get("z", 0))
	var target_id: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z,
	})
	var target: RefCounted = simulation.actor_registry.get_actor(target_id)
	target.combat_attributes["evasion"] = 0.0
	target.combat_attributes["damage_reduction"] = 0.0
	var ap_before: float = player.ap
	var rng_before: int = int(simulation.snapshot().get("combat_state", {}).get("combat_rng_counter", -1))
	var event_count_before: int = _array_or_empty(simulation.snapshot().get("events", [])).size()
	var preview: Dictionary = simulation.preview_attack(player.actor_id, target_id, topology)
	if not bool(preview.get("success", false)) or not bool(preview.get("can_attack", false)):
		errors.append("attack preview should succeed for reachable hostile target: %s" % preview.get("reason", "unknown"))
	if str(preview.get("preview_kind", "")) != "attack":
		errors.append("attack preview should expose preview_kind=attack")
	if int(preview.get("target_actor_id", 0)) != target_id or int(preview.get("actor_id", 0)) != player.actor_id:
		errors.append("attack preview should expose actor and target ids")
	if _dictionary_or_empty(preview.get("attacker_grid", {})).is_empty() or _dictionary_or_empty(preview.get("target_grid", {})).is_empty():
		errors.append("attack preview should expose attacker and target grids")
	if int(preview.get("distance", -1)) != 1:
		errors.append("attack preview should expose target distance")
	_expect_spatial_diagnostics(errors, preview, "attack preview", true, true, true, true, true, "")
	if float(preview.get("ap_cost", 0.0)) <= 0.0 or not bool(preview.get("ap_affordable", false)):
		errors.append("attack preview should expose affordable AP cost")
	if not bool(preview.get("ammo_available", true)):
		errors.append("attack preview should expose ammo availability for equipped weapon")
	if float(preview.get("hit_chance", -1.0)) < 0.99:
		errors.append("attack preview should expose hit chance without consuming RNG")
	if float(preview.get("estimated_damage", 0.0)) <= 0.0:
		errors.append("attack preview should expose estimated damage")
	if absf(player.ap - ap_before) > 0.001:
		errors.append("attack preview should not spend AP")
	if int(simulation.snapshot().get("combat_state", {}).get("combat_rng_counter", -1)) != rng_before:
		errors.append("attack preview should not advance combat RNG")
	if _array_or_empty(simulation.snapshot().get("events", [])).size() != event_count_before:
		errors.append("attack preview should not emit simulation events")
	if bool(simulation.snapshot().get("combat_state", {}).get("active", false)):
		errors.append("attack preview should not enter combat")

	var far_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 5,
		"y": y,
		"z": z,
	})
	var far_preview: Dictionary = simulation.preview_attack(player.actor_id, far_target, topology, {"range": 2})
	if bool(far_preview.get("can_attack", true)) or far_preview.get("reason", "") != "target_out_of_range":
		errors.append("out-of-range attack preview should report target_out_of_range, got %s" % far_preview.get("reason", ""))
	if int(far_preview.get("distance", 0)) != 5 or int(far_preview.get("range", 0)) != 2:
		errors.append("out-of-range attack preview should expose distance and range")
	_expect_spatial_diagnostics(errors, far_preview, "out-of-range attack preview", true, false, true, true, true, "target_out_of_range")

	var close_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z,
	})
	var close_preview: Dictionary = simulation.preview_attack(player.actor_id, close_target, topology, {"range": 6, "min_range": 2})
	if bool(close_preview.get("can_attack", true)) or close_preview.get("reason", "") != "target_too_close":
		errors.append("minimum-range attack preview should report target_too_close, got %s" % close_preview.get("reason", ""))
	if int(close_preview.get("min_range", -1)) != 2:
		errors.append("minimum-range attack preview should expose min_range=2")
	_expect_spatial_diagnostics(errors, close_preview, "minimum-range attack preview", true, true, false, true, true, "target_too_close")

	var los_target: int = _register_character(simulation, registry, "zombie_walker", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": y,
		"z": z,
	})
	var los_topology := _spatial_test_topology(player_grid, {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": y,
		"z": z,
	})
	var los_preview: Dictionary = simulation.preview_attack(player.actor_id, los_target, los_topology, {"range": 8})
	if bool(los_preview.get("can_attack", true)) or los_preview.get("reason", "") != "target_blocked_by_los":
		errors.append("blocked LOS attack preview should report target_blocked_by_los, got %s" % los_preview.get("reason", ""))
	_expect_spatial_diagnostics(errors, los_preview, "blocked LOS attack preview", true, true, true, false, true, "target_blocked_by_los")

	player.ap = 0.0
	var ap_preview: Dictionary = simulation.preview_attack(player.actor_id, target_id, topology)
	if bool(ap_preview.get("can_attack", true)) or ap_preview.get("reason", "") != "ap_insufficient":
		errors.append("AP-short attack preview should report ap_insufficient, got %s" % ap_preview.get("reason", ""))

	for actor_id in [target_id, far_target, close_target, los_target]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	_restore_player_turn(simulation, player)


func _expect_skill_targeting_preview(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	player.grid_position = GridCoord.from_dictionary(player_grid)
	var original_progression: Dictionary = player.progression.duplicate(true)
	var original_active_effects: Array[Dictionary] = player.active_effects.duplicate(true)
	var original_ap: float = player.ap
	player.progression["learned_skills"] = {"adrenaline_rush": 1}
	var empty_effects: Array[Dictionary] = []
	player.active_effects = empty_effects
	player.ap = 20.0
	var topology: Dictionary = _topology(simulation, registry)
	var hostile_id: int = _register_test_actor(simulation, "skill_target_hostile", "hostile", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 10.0)
	var friendly_id: int = _register_test_actor(simulation, "skill_target_friendly", "friendly", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 10.0)
	var single_skill: Dictionary = _targeted_skill_library(registry, {
		"kind": "single",
		"policy": "hostile_only",
		"range": 4,
	})
	var single_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", single_skill, {"actor_id": hostile_id}, topology)
	if not bool(single_preview.get("success", false)):
		errors.append("single hostile skill target preview should succeed: %s" % single_preview.get("reason", "unknown"))
	elif _array_or_empty(single_preview.get("affected_actor_ids", [])).size() != 1 or int(_array_or_empty(single_preview.get("affected_actor_ids", []))[0]) != hostile_id:
		errors.append("single hostile skill target preview should include hostile actor")
	var hidden_skill_target_id: int = _register_test_actor(simulation, "skill_hidden_hostile", "hostile", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)) + 1,
	}, 10.0)
	simulation.set_actor_vision_radius(player.actor_id, 0)
	simulation.refresh_actor_vision(player.actor_id, topology)
	var hidden_skill_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", single_skill, {"actor_id": hidden_skill_target_id}, topology)
	if hidden_skill_preview.get("reason", "") != "target_not_visible":
		errors.append("active vision should reject hidden skill actor target, got %s" % hidden_skill_preview.get("reason", ""))
	var ap_before_hidden_skill: float = player.ap
	var hidden_skill_use: Dictionary = simulation.submit_player_command({
		"kind": "use_skill",
		"skill_id": "adrenaline_rush",
		"skill_library": single_skill,
		"target": {"actor_id": hidden_skill_target_id},
		"topology": topology,
	})
	if bool(hidden_skill_use.get("success", false)) or hidden_skill_use.get("reason", "") != "target_not_visible":
		errors.append("active vision should reject hidden skill use before spending AP")
	if absf(player.ap - ap_before_hidden_skill) > 0.001:
		errors.append("hidden skill target should not spend AP")
	simulation.clear_actor_vision(player.actor_id)
	var los_blocked_topology: Dictionary = _spatial_test_topology(player_grid, {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	var blocked_single: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", single_skill, {"actor_id": hostile_id}, los_blocked_topology)
	if blocked_single.get("reason", "") != "skill_target_blocked_by_los":
		errors.append("single skill target blocked by LOS should report skill_target_blocked_by_los, got %s" % blocked_single.get("reason", ""))
	var friendly_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", single_skill, {"actor_id": friendly_id}, topology)
	if friendly_preview.get("reason", "") != "skill_target_not_hostile":
		errors.append("hostile-only skill should reject friendly target, got %s" % friendly_preview.get("reason", ""))
	var ap_before_invalid: float = player.ap
	var invalid_use: Dictionary = simulation.submit_player_command({
		"kind": "use_skill",
		"skill_id": "adrenaline_rush",
		"skill_library": single_skill,
		"target": {"actor_id": friendly_id},
		"topology": topology,
	})
	if bool(invalid_use.get("success", false)) or invalid_use.get("reason", "") != "skill_target_not_hostile":
		errors.append("invalid targeted skill use should fail before spending AP")
	if absf(player.ap - ap_before_invalid) > 0.001:
		errors.append("invalid targeted skill use should not spend AP")
	var use_result: Dictionary = simulation.submit_player_command({
		"kind": "use_skill",
		"skill_id": "adrenaline_rush",
		"skill_library": single_skill,
		"target": {"actor_id": hostile_id},
		"topology": topology,
	})
	if not bool(use_result.get("success", false)):
		errors.append("valid targeted skill use should succeed: %s" % use_result.get("reason", "unknown"))
	elif int(_array_or_empty(use_result.get("affected_actor_ids", []))[0]) != hostile_id:
		errors.append("valid targeted skill use should expose affected actor id")
	var skill_event_payload: Dictionary = _last_event_payload(simulation.snapshot(), "skill_used")
	if int(_array_or_empty(skill_event_payload.get("affected_actor_ids", []))[0]) != hostile_id:
		errors.append("skill_used event should include affected_actor_ids from target preview")
	var reset_effects: Array[Dictionary] = []
	player.active_effects = reset_effects
	player.ap = 20.0
	var radius_skill: Dictionary = _targeted_skill_library(registry, {
		"kind": "radius",
		"policy": "any_grid",
		"affected_policy": "hostile_only",
		"range": 4,
		"radius": 1,
	})
	var radius_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", radius_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 1,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, topology)
	if not bool(radius_preview.get("success", false)):
		errors.append("radius skill target preview should succeed: %s" % radius_preview.get("reason", "unknown"))
	elif not _array_or_empty(radius_preview.get("affected_actor_ids", [])).has(hostile_id):
		errors.append("radius hostile-only preview should include nearby hostile")
	elif _array_or_empty(radius_preview.get("affected_actor_ids", [])).has(friendly_id):
		errors.append("radius hostile-only preview should filter friendly actors")
	if _array_or_empty(radius_preview.get("affected_cells", [])).size() != 5:
		errors.append("radius 1 preview should include center plus four cardinal cells")
	simulation.set_actor_vision_radius(player.actor_id, 0)
	simulation.refresh_actor_vision(player.actor_id, topology)
	var hidden_radius_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", radius_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 1,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, topology)
	if hidden_radius_preview.get("reason", "") != "target_not_visible":
		errors.append("active vision should reject hidden skill grid center, got %s" % hidden_radius_preview.get("reason", ""))
	simulation.clear_actor_vision(player.actor_id)
	var blocked_aoe_actor_id: int = _register_test_actor(simulation, "skill_aoe_blocked_hostile", "hostile", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)) + 2,
	}, 10.0)
	var aoe_los_topology: Dictionary = _spatial_test_topology(player_grid, {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)) + 1,
	})
	var los_radius_skill: Dictionary = _targeted_skill_library(registry, {
		"kind": "radius",
		"policy": "any_grid",
		"affected_policy": "hostile_only",
		"range": 4,
		"radius": 2,
	})
	var los_radius_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", los_radius_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 2,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, aoe_los_topology)
	if not bool(los_radius_preview.get("success", false)):
		errors.append("radius skill target with clear center LOS should succeed: %s" % los_radius_preview.get("reason", "unknown"))
	elif _array_or_empty(los_radius_preview.get("affected_actor_ids", [])).has(blocked_aoe_actor_id):
		errors.append("radius AOE should exclude actors in cells blocked from center LOS")
	elif _cells_include_grid(_array_or_empty(los_radius_preview.get("affected_cells", [])), {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)) + 2,
	}):
		errors.append("radius AOE respecting LOS should exclude blocked target cell")
	var ignore_los_radius_skill: Dictionary = _targeted_skill_library(registry, {
		"kind": "radius",
		"policy": "any_grid",
		"affected_policy": "hostile_only",
		"range": 4,
		"radius": 2,
		"respect_los": false,
	})
	var ignore_los_radius_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", ignore_los_radius_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 2,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, aoe_los_topology)
	if not _array_or_empty(ignore_los_radius_preview.get("affected_actor_ids", [])).has(blocked_aoe_actor_id):
		errors.append("radius AOE with respect_los=false should include blocked actor")
	var line_hostile_id: int = _register_test_actor(simulation, "skill_line_hostile", "hostile", {
		"x": int(player_grid.get("x", 0)) + 3,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 10.0)
	var line_friendly_id: int = _register_test_actor(simulation, "skill_line_friendly", "friendly", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 10.0)
	var line_skill: Dictionary = _targeted_skill_library(registry, {
		"kind": "line",
		"policy": "any_grid",
		"affected_policy": "hostile_only",
		"range": 4,
		"length": 4,
	})
	var line_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", line_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 4,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, topology)
	if not bool(line_preview.get("success", false)):
		errors.append("line skill target preview should succeed: %s" % line_preview.get("reason", "unknown"))
	elif not _array_or_empty(line_preview.get("affected_actor_ids", [])).has(line_hostile_id):
		errors.append("line hostile-only preview should include hostile on line")
	elif _array_or_empty(line_preview.get("affected_actor_ids", [])).has(line_friendly_id):
		errors.append("line hostile-only preview should filter friendly on line")
	if _array_or_empty(line_preview.get("affected_cells", [])).size() != 4:
		errors.append("line preview should include four cells after origin")
	var line_blocked_topology: Dictionary = _spatial_test_topology(player_grid, {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	})
	var blocked_line: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", line_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 4,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, line_blocked_topology)
	if blocked_line.get("reason", "") != "skill_target_blocked_by_los":
		errors.append("line skill blocked center LOS should report skill_target_blocked_by_los, got %s" % blocked_line.get("reason", ""))
	var line_ignore_los_skill: Dictionary = _targeted_skill_library(registry, {
		"kind": "line",
		"policy": "any_grid",
		"affected_policy": "hostile_only",
		"range": 4,
		"length": 4,
		"requires_los": false,
		"respect_los": false,
	})
	var line_ignore_los_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", line_ignore_los_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 4,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, line_blocked_topology)
	if not _array_or_empty(line_ignore_los_preview.get("affected_actor_ids", [])).has(line_hostile_id):
		errors.append("line skill with LOS disabled should include hostile behind blocker")
	var cone_hostile_id: int = _register_test_actor(simulation, "skill_cone_hostile", "hostile", {
		"x": int(player_grid.get("x", 0)) + 3,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)) + 1,
	}, 10.0)
	var cone_friendly_id: int = _register_test_actor(simulation, "skill_cone_friendly", "friendly", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)) - 1,
	}, 10.0)
	var cone_back_id: int = _register_test_actor(simulation, "skill_cone_back_hostile", "hostile", {
		"x": int(player_grid.get("x", 0)) - 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 10.0)
	var cone_skill: Dictionary = _targeted_skill_library(registry, {
		"kind": "cone",
		"policy": "any_grid",
		"affected_policy": "hostile_only",
		"range": 4,
		"length": 4,
		"width": 2,
	})
	var cone_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", cone_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 4,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, topology)
	if not bool(cone_preview.get("success", false)):
		errors.append("cone skill target preview should succeed: %s" % cone_preview.get("reason", "unknown"))
	elif not _array_or_empty(cone_preview.get("affected_actor_ids", [])).has(cone_hostile_id):
		errors.append("cone hostile-only preview should include hostile in cone")
	elif _array_or_empty(cone_preview.get("affected_actor_ids", [])).has(cone_friendly_id):
		errors.append("cone hostile-only preview should filter friendly in cone")
	elif _array_or_empty(cone_preview.get("affected_actor_ids", [])).has(cone_back_id):
		errors.append("cone preview should not include hostile behind origin")
	var blocked_cone: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", cone_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 4,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, line_blocked_topology)
	if blocked_cone.get("reason", "") != "skill_target_blocked_by_los":
		errors.append("cone skill blocked center LOS should report skill_target_blocked_by_los, got %s" % blocked_cone.get("reason", ""))
	var cone_ignore_los_skill: Dictionary = _targeted_skill_library(registry, {
		"kind": "cone",
		"policy": "any_grid",
		"affected_policy": "hostile_only",
		"range": 4,
		"length": 4,
		"width": 2,
		"requires_los": false,
		"respect_los": false,
	})
	var cone_ignore_los_preview: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", cone_ignore_los_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 4,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, line_blocked_topology)
	if not _array_or_empty(cone_ignore_los_preview.get("affected_actor_ids", [])).has(cone_hostile_id):
		errors.append("cone skill with LOS disabled should include hostile behind blocker")
	var out_of_range: Dictionary = simulation.preview_skill_target(player.actor_id, "adrenaline_rush", radius_skill, {
		"grid": {
			"x": int(player_grid.get("x", 0)) + 20,
			"y": int(player_grid.get("y", 0)),
			"z": int(player_grid.get("z", 0)),
		},
	}, topology)
	if out_of_range.get("reason", "") != "skill_target_out_of_range":
		errors.append("out-of-range skill preview should report skill_target_out_of_range, got %s" % out_of_range.get("reason", ""))
	for actor_id in [hostile_id, friendly_id, hidden_skill_target_id, blocked_aoe_actor_id, line_hostile_id, line_friendly_id, cone_hostile_id, cone_friendly_id, cone_back_id]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	player.progression = original_progression
	player.active_effects = original_active_effects
	player.ap = original_ap
	_restore_player_turn(simulation, player)


func _expect_corpse_inventory_and_metadata(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	player.grid_position = GridCoord.from_dictionary(player_grid)
	var original_equipment: Dictionary = player.equipment.duplicate(true)
	var original_attributes: Dictionary = player.combat_attributes.duplicate(true)
	var original_money: int = int(player.money)
	player.equipment["main_hand"] = "1003"
	player.combat_attributes["accuracy"] = 100.0
	player.ap = 20.0
	var target_id: int = _register_test_actor(simulation, "corpse_loot_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)) + 1,
	}, 5.0)
	var target: RefCounted = simulation.actor_registry.get_actor(target_id)
	target.display_name = "Corpse Loot Target"
	target.map_id = str(simulation.active_map_id)
	target.inventory = {"1006": 2, "1009": 3}
	var target_inventory_order: Array[String] = ["1006", "1009"]
	target.inventory_order = target_inventory_order
	target.equipment = {"main_hand": "1004"}
	target.weapon_ammo = {"main_hand": 4}
	target.money = 17
	var target_loot_table: Array[Dictionary] = [{
		"item_id": "1009",
		"chance": 1.0,
		"min": 2,
		"max": 2,
	}]
	target.loot_table = target_loot_table
	target.combat_attributes["evasion"] = 0.0
	target.defense = 0.0
	var result: Dictionary = simulation.perform_attack(player.actor_id, target_id, _topology(simulation, registry), {
		"range": 4,
		"weapon_profile": {"damage": 99.0, "crit_chance": 0.0, "accuracy": 100.0},
	})
	if not bool(result.get("success", false)) or not bool(result.get("defeated", false)):
		errors.append("corpse loot target should be defeated for corpse metadata smoke")
	var corpse: Dictionary = _corpse_by_source_actor(simulation.snapshot(), target_id)
	if corpse.is_empty():
		errors.append("corpse metadata smoke should create corpse for target")
	else:
		if str(corpse.get("display_name", "")) != "Corpse Loot Target的尸体":
			errors.append("corpse display name should use defeated actor name")
		if str(corpse.get("container_type", "")) != "corpse":
			errors.append("corpse should expose container_type=corpse")
		if str(corpse.get("container_origin", "")) != "combat_defeat":
			errors.append("corpse should expose container_origin=combat_defeat")
		if int(corpse.get("source_actor_id", 0)) != target_id:
			errors.append("corpse should expose source_actor_id")
		if str(corpse.get("source_actor_definition_id", "")) != "corpse_loot_target":
			errors.append("corpse should expose source actor definition id")
		if int(corpse.get("defeated_by_actor_id", 0)) != player.actor_id:
			errors.append("corpse should expose defeated_by_actor_id")
		if str(corpse.get("map_id", "")) != str(simulation.active_map_id):
			errors.append("corpse should preserve source actor map id")
		if int(corpse.get("money", 0)) != 17:
			errors.append("corpse should expose source actor money")
		var equipped_slots: Dictionary = _dictionary_or_empty(corpse.get("equipped_slots", {}))
		if str(equipped_slots.get("main_hand", "")) != "1004":
			errors.append("corpse should preserve equipped main_hand metadata")
		var corpse_inventory: Array = _array_or_empty(corpse.get("inventory", []))
		if _entry_count(corpse_inventory, "1006") != 2:
			errors.append("corpse should include actor inventory bandages")
		if _entry_count(corpse_inventory, "1004") != 1:
			errors.append("corpse should include equipped weapon")
		if _entry_count(corpse_inventory, "1009") != 9:
			errors.append("corpse should merge inventory ammo, loaded ammo and loot table ammo")
		var container: Dictionary = _container_by_id(simulation.snapshot(), str(corpse.get("container_id", "")))
		if str(container.get("container_type", "")) != "corpse":
			errors.append("corpse container session should expose container_type=corpse")
		if str(container.get("container_origin", "")) != "combat_defeat":
			errors.append("corpse container session should expose container_origin=combat_defeat")
		if _entry_count(_array_or_empty(container.get("inventory", [])), "1009") != 9:
			errors.append("corpse container session should mirror merged ammo")
		if int(container.get("money", 0)) != 17:
			errors.append("corpse container session should mirror corpse money")
		var player_money_before: int = int(player.money)
		var money_result: Dictionary = simulation.take_money_from_container(player.actor_id, str(corpse.get("container_id", "")), -1)
		if not bool(money_result.get("success", false)):
			errors.append("taking corpse money should succeed: %s" % money_result.get("reason", "unknown"))
		elif int(player.money) != player_money_before + 17:
			errors.append("taking corpse money should increase player money")
		var updated_corpse: Dictionary = _corpse_by_source_actor(simulation.snapshot(), target_id)
		var updated_container: Dictionary = _container_by_id(simulation.snapshot(), str(corpse.get("container_id", "")))
		if int(updated_corpse.get("money", -1)) != 0:
			errors.append("taking corpse money should clear corpse money")
		if int(updated_container.get("money", -1)) != 0:
			errors.append("taking corpse money should clear container session money")
		if _event_count(simulation.snapshot(), "container_money_taken") <= 0:
			errors.append("taking corpse money should emit container_money_taken")
		var second_money_result: Dictionary = simulation.take_money_from_container(player.actor_id, str(corpse.get("container_id", "")), 1)
		if second_money_result.get("reason", "") != "container_money_insufficient":
			errors.append("taking exhausted corpse money should report container_money_insufficient")
	if simulation.actor_registry.get_actor(target_id) != null:
		simulation.actor_registry.unregister_actor(target_id)
	player.equipment = original_equipment
	player.combat_attributes = original_attributes
	player.money = original_money
	simulation.exit_combat_if_clear("corpse_metadata_smoke_cleanup")


func _expect_weapon_profile_attack(errors: Array[String], simulation: RefCounted, registry: RefCounted, player: RefCounted, player_grid: Dictionary) -> void:
	var topology: Dictionary = _topology(simulation, registry)
	var original_active_effects: Array[Dictionary] = player.active_effects.duplicate(true)
	var no_active_effects: Array[Dictionary] = []
	var original_attributes: Dictionary = player.combat_attributes.duplicate(true)
	player.active_effects = no_active_effects
	player.combat_attributes["accuracy"] = 100.0
	player.ap = 20.0
	player.equipment["main_hand"] = "1003"
	var blunt_target: int = _register_test_actor(simulation, "on_hit_stun_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 2,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 60.0)
	var blunt: RefCounted = simulation.actor_registry.get_actor(blunt_target)
	blunt.hp = 60.0
	blunt.max_hp = 60.0
	blunt.defense = 0.0
	var before_ap: float = player.ap
	var blunt_result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": blunt_target, "topology": topology})
	if not bool(blunt_result.get("success", false)):
		errors.append("baseball bat range-2 attack failed: %s" % blunt_result.get("reason", "unknown"))
	var blunt_attack_event: Dictionary = _last_attack_resolved_for_weapon(simulation.snapshot(), "1003")
	if absf(float(blunt_attack_event.get("base_damage", 0.0)) - 15.0) > 0.01:
		errors.append("baseball bat attack should use weapon base_damage 15")
	if not _array_or_empty(blunt_result.get("triggered_on_hit_effect_ids", [])).has("stun"):
		errors.append("baseball bat hit should expose stun on-hit effect")
	if not _array_or_empty(blunt_attack_event.get("triggered_on_hit_effect_ids", [])).has("stun"):
		errors.append("attack_resolved should expose triggered stun on-hit effect")
	if _array_or_empty(blunt_result.get("applied_on_hit_effects", [])).is_empty():
		errors.append("baseball bat hit should apply stun on-hit effect runtime")
	var stun_effect: Dictionary = _active_effect_by_id(blunt, "effect:stun")
	if stun_effect.is_empty():
		errors.append("baseball bat hit should add effect:stun to target active_effects")
	elif absf(float(stun_effect.get("duration_remaining", 0.0)) - 3.0) > 0.001:
		errors.append("stun on-hit effect should use effect duration 3")
	if not bool(blunt_result.get("critical", false)) and absf(float(blunt_result.get("damage", 0.0)) - 15.0) > 0.01:
		errors.append("non-critical baseball bat attack should deal weapon damage 15")
	if absf((before_ap - player.ap) - 3.0) > 0.01:
		errors.append("baseball bat attack should use attack_speed-derived AP cost 3")
	if not _has_attack_resolved_for_weapon(simulation.snapshot(), "1003"):
		errors.append("attack_resolved should include weapon item id")
	var second_blunt: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": blunt_target, "topology": topology})
	if not bool(second_blunt.get("success", false)):
		errors.append("second baseball bat hit should succeed for stun extend smoke: %s" % second_blunt.get("reason", "unknown"))
	stun_effect = _active_effect_by_id(blunt, "effect:stun")
	if not stun_effect.is_empty() and absf(float(stun_effect.get("duration_remaining", 0.0)) - 6.0) > 0.001:
		errors.append("stun on-hit effect should extend duration to 6 after second hit")

	player.equipment["main_hand"] = "1002"
	player.ap = 20.0
	var bleeding_target: int = _register_test_actor(simulation, "on_hit_bleeding_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 1,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 80.0)
	var bleeding_enemy: RefCounted = simulation.actor_registry.get_actor(bleeding_target)
	bleeding_enemy.hp = 80.0
	bleeding_enemy.max_hp = 80.0
	bleeding_enemy.defense = 0.0
	var bleeding_first: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": bleeding_target, "topology": topology})
	if not bool(bleeding_first.get("success", false)):
		errors.append("knife bleeding hit should succeed: %s" % bleeding_first.get("reason", "unknown"))
	var bleeding_effect: Dictionary = _active_effect_by_id(bleeding_enemy, "effect:bleeding")
	if bleeding_effect.is_empty():
		errors.append("knife hit should add effect:bleeding to target active_effects")
	elif int(bleeding_effect.get("stack_count", 0)) != 1 or absf(float(bleeding_effect.get("duration_remaining", 0.0)) - 15.0) > 0.001:
		errors.append("first bleeding on-hit effect should have stack 1 and duration 15")
	var bleeding_second: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": bleeding_target, "topology": topology})
	if not bool(bleeding_second.get("success", false)):
		errors.append("second knife bleeding hit should succeed: %s" % bleeding_second.get("reason", "unknown"))
	bleeding_effect = _active_effect_by_id(bleeding_enemy, "effect:bleeding")
	if int(bleeding_effect.get("stack_count", 0)) != 2:
		errors.append("bleeding intensity stack should increase to 2 after second hit")
	if _event_count(simulation.snapshot(), "on_hit_effect_applied") < 4:
		errors.append("on-hit effect runtime should emit on_hit_effect_applied events")

	player.equipment["main_hand"] = "1004"
	player.inventory["1009"] = 2
	player.weapon_ammo.erase("main_hand")
	player.ap = 20.0
	var pistol_target: int = _register_test_actor(simulation, "weapon_profile_pistol_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 8,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 40.0)
	var pistol_enemy: RefCounted = simulation.actor_registry.get_actor(pistol_target)
	pistol_enemy.hp = 40.0
	pistol_enemy.max_hp = 40.0
	pistol_enemy.defense = 0.0
	var pistol_result: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": pistol_target, "topology": topology})
	if not bool(pistol_result.get("success", false)):
		errors.append("pistol range attack failed: %s" % pistol_result.get("reason", "unknown"))
	if int(player.inventory.get("1009", 0)) != 1:
		errors.append("pistol attack should consume one pistol ammo")
	var pistol_attack_event: Dictionary = _last_attack_resolved_for_weapon(simulation.snapshot(), "1004")
	if absf(float(pistol_attack_event.get("base_damage", 0.0)) - 25.0) > 0.01:
		errors.append("pistol attack should expose weapon base_damage 25")
	if not _array_or_empty(pistol_result.get("triggered_on_hit_effect_ids", [])).has("headshot_bonus"):
		errors.append("pistol hit should expose headshot_bonus on-hit effect")
	if not _array_or_empty(pistol_result.get("applied_on_hit_effects", [])).is_empty():
		errors.append("placeholder headshot_bonus should not create active on-hit effect runtime")
	player.inventory["1009"] = 2
	player.weapon_ammo["main_hand"] = 1
	var magazine_target: int = _register_test_actor(simulation, "weapon_profile_magazine_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 7,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 40.0)
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
	var no_ammo_target: int = _register_test_actor(simulation, "weapon_profile_no_ammo_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 9,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 40.0)
	var no_ammo: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": no_ammo_target, "topology": topology})
	if no_ammo.get("reason", "") != "magazine_empty":
		errors.append("ranged weapon with empty tracked magazine should report magazine_empty")
	player.weapon_ammo.erase("main_hand")
	player.inventory.erase("1009")
	var inventory_no_ammo_target: int = _register_test_actor(simulation, "weapon_profile_inventory_no_ammo_target", "hostile", {
		"x": int(player_grid.get("x", 0)) + 10,
		"y": int(player_grid.get("y", 0)),
		"z": int(player_grid.get("z", 0)),
	}, 40.0)
	var inventory_no_ammo: Dictionary = simulation.submit_player_command({"kind": "attack", "target_actor_id": inventory_no_ammo_target, "topology": topology})
	if inventory_no_ammo.get("reason", "") != "ammo_insufficient":
		errors.append("ranged weapon without tracked magazine or inventory ammo should report ammo_insufficient")
	for actor_id in [blunt_target, bleeding_target, pistol_target, magazine_target, no_ammo_target, inventory_no_ammo_target]:
		if simulation.actor_registry.get_actor(actor_id) != null:
			simulation.actor_registry.unregister_actor(actor_id)
	player.active_effects = original_active_effects
	player.combat_attributes = original_attributes
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
		"combat_attributes": combat_attributes.duplicate(true),
		"xp_reward": int(combat.get("xp_reward", 0)),
		"loot": _array_or_empty(combat.get("loot", [])).duplicate(true),
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


func _targeted_skill_library(registry: RefCounted, targeting: Dictionary) -> Dictionary:
	var library: Dictionary = registry.get_library("skills").duplicate(true)
	var record: Dictionary = _dictionary_or_empty(library.get("adrenaline_rush", {})).duplicate(true)
	var data: Dictionary = _dictionary_or_empty(record.get("data", {})).duplicate(true)
	var activation: Dictionary = _dictionary_or_empty(data.get("activation", {})).duplicate(true)
	activation["targeting"] = targeting.duplicate(true)
	data["activation"] = activation
	record["data"] = data
	library["adrenaline_rush"] = record
	return library


func _force_combat_values(simulation: RefCounted, actor_id: int) -> void:
	var player: RefCounted = simulation.actor_registry.get_actor(1)
	var target: RefCounted = simulation.actor_registry.get_actor(actor_id)
	player.attack_power = 10.0
	player.combat_attributes["accuracy"] = 100.0
	target.hp = 5.0
	target.max_hp = 5.0
	target.defense = 0.0
	target.combat_attributes["evasion"] = 0.0


func _restore_player_turn(simulation: RefCounted, player: RefCounted) -> void:
	player.turn_open = true
	simulation.turn_state["phase"] = "player"
	simulation.turn_state["active_actor_id"] = player.actor_id


func _expect_turn_policy(errors: Array[String], result: Dictionary, expected_action: String, expected_auto_advanced: bool, context: String) -> void:
	var policy: Dictionary = _dictionary_or_empty(result.get("turn_policy", {}))
	if policy.is_empty():
		errors.append("%s should expose turn_policy" % context)
		return
	if str(policy.get("action_kind", "")) != expected_action:
		errors.append("%s turn_policy should expose action kind %s" % [context, expected_action])
	if bool(policy.get("success", false)) != bool(result.get("success", false)):
		errors.append("%s turn_policy success should mirror command result" % context)
	if not policy.has("ap_after_action") or not policy.has("affordable_ap_threshold"):
		errors.append("%s turn_policy should expose AP after action and affordable threshold" % context)
	if bool(policy.get("auto_advanced", false)) != expected_auto_advanced:
		errors.append("%s turn_policy auto_advanced should be %s" % [context, str(expected_auto_advanced)])
	var runtime_delta: Dictionary = _dictionary_or_empty(result.get("runtime_snapshot_delta", {}))
	var delta_policy: Dictionary = _dictionary_or_empty(runtime_delta.get("turn_policy", {}))
	if delta_policy.is_empty():
		errors.append("%s runtime delta should expose turn_policy" % context)
	elif str(delta_policy.get("action_kind", "")) != expected_action:
		errors.append("%s runtime delta turn_policy should mirror action kind" % context)


func _has_attack_resolved_for_weapon(snapshot: Dictionary, weapon_item_id: String) -> bool:
	return not _last_attack_resolved_for_weapon(snapshot, weapon_item_id).is_empty()


func _last_attack_resolved_for_weapon(snapshot: Dictionary, weapon_item_id: String) -> Dictionary:
	var events: Array = snapshot.get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = events[index]
		var payload: Dictionary = event_data.get("payload", {})
		if event_data.get("kind", "") == "attack_resolved" and str(payload.get("weapon_item_id", "")) == weapon_item_id:
			return payload
	return {}


func _active_effect_by_id(actor: RefCounted, effect_id: String) -> Dictionary:
	for effect in actor.active_effects:
		var effect_data: Dictionary = _dictionary_or_empty(effect)
		if str(effect_data.get("effect_id", "")) == effect_id:
			return effect_data
	return {}


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


func _corpse_by_source_actor(snapshot: Dictionary, source_actor_id: int) -> Dictionary:
	for corpse in _array_or_empty(snapshot.get("corpse_containers", [])):
		var corpse_data: Dictionary = _dictionary_or_empty(corpse)
		if int(corpse_data.get("source_actor_id", 0)) == source_actor_id:
			return corpse_data
	return {}


func _container_by_id(snapshot: Dictionary, container_id: String) -> Dictionary:
	for container in _array_or_empty(snapshot.get("container_sessions", [])):
		var container_data: Dictionary = _dictionary_or_empty(container)
		if str(container_data.get("container_id", "")) == container_id:
			return container_data
	return {}


func _entry_count(entries: Array, item_id: String) -> int:
	for entry in entries:
		var entry_data: Dictionary = _dictionary_or_empty(entry)
		if str(entry_data.get("item_id", "")) == item_id:
			return int(entry_data.get("count", 0))
	return 0


func _event_count(snapshot: Dictionary, kind: String) -> int:
	var count := 0
	for event in snapshot.get("events", []):
		var event_data: Dictionary = event
		if event_data.get("kind", "") == kind:
			count += 1
	return count


func _last_event_payload(snapshot: Dictionary, kind: String) -> Dictionary:
	var events: Array = snapshot.get("events", [])
	for index in range(events.size() - 1, -1, -1):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if str(event_data.get("kind", "")) == kind:
			return _dictionary_or_empty(event_data.get("payload", {}))
	return {}


func _event_payload_after(snapshot: Dictionary, kind: String, actor_id: int, start_index: int) -> Dictionary:
	var events: Array = _array_or_empty(snapshot.get("events", []))
	for index in range(max(0, start_index), events.size()):
		var event_data: Dictionary = _dictionary_or_empty(events[index])
		if str(event_data.get("kind", "")) != kind:
			continue
		var payload: Dictionary = _dictionary_or_empty(event_data.get("payload", {}))
		if int(payload.get("actor_id", 0)) == actor_id:
			return payload
	return {}


func _npc_result_for_actor(results: Array, actor_id: int) -> Dictionary:
	for result in results:
		var result_data: Dictionary = _dictionary_or_empty(result)
		if int(result_data.get("actor_id", 0)) == actor_id:
			return result_data
	return {}


func _expect_spatial_diagnostics(errors: Array[String], result: Dictionary, label: String, same_level: bool, range_ok: bool, min_range_ok: bool, line_of_sight: bool, line_of_sight_required: bool, spatial_failure: String) -> void:
	if not result.has("same_level") or bool(result.get("same_level", false)) != same_level:
		errors.append("%s should expose same_level=%s" % [label, str(same_level)])
	if not result.has("range_ok") or bool(result.get("range_ok", false)) != range_ok:
		errors.append("%s should expose range_ok=%s" % [label, str(range_ok)])
	if not result.has("min_range_ok") or bool(result.get("min_range_ok", false)) != min_range_ok:
		errors.append("%s should expose min_range_ok=%s" % [label, str(min_range_ok)])
	if not result.has("line_of_sight") or bool(result.get("line_of_sight", false)) != line_of_sight:
		errors.append("%s should expose line_of_sight=%s" % [label, str(line_of_sight)])
	if not result.has("line_of_sight_required") or bool(result.get("line_of_sight_required", false)) != line_of_sight_required:
		errors.append("%s should expose line_of_sight_required=%s" % [label, str(line_of_sight_required)])
	if str(result.get("spatial_failure", "")) != spatial_failure:
		errors.append("%s should expose spatial_failure=%s, got %s" % [label, spatial_failure, str(result.get("spatial_failure", ""))])


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _cells_include_grid(cells: Array, grid: Dictionary) -> bool:
	var gx: int = int(grid.get("x", 0))
	var gy: int = int(grid.get("y", 0))
	var gz: int = int(grid.get("z", 0))
	for cell in cells:
		var cell_data: Dictionary = _dictionary_or_empty(cell)
		if int(cell_data.get("x", 0)) == gx and int(cell_data.get("y", 0)) == gy and int(cell_data.get("z", 0)) == gz:
			return true
	return false


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
