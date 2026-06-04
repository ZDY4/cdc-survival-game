extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const WorldSceneRenderer = preload("res://scripts/world/world_scene_renderer.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var registry := ContentRegistry.new()
	var load_result := registry.load_all()
	if load_result.has_errors():
		for error in load_result.errors:
			printerr(error)
		quit(1)
		return

	var runtime_snapshot: Dictionary = CoreRuntimeBootstrap.new(registry).build_new_game_runtime().get("snapshot", {})
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	if not bool(world_result.get("ok", false)):
		printerr(world_result.get("error", "world build failed"))
		quit(1)
		return

	var root := Node3D.new()
	root.name = "SceneSmokeRoot"
	root.name = "SceneSmokeRoot"
	root.add_to_group("scene_smoke_root")
	root.set_meta("world_result", world_result)
	get_root().add_child(root)
	await process_frame

	var counts: Dictionary = WorldSceneRenderer.new().render_world(root, world_result)
	await process_frame
	var errors := _validate_scene(root, world_result, counts, registry)
	errors.append_array(_validate_door_state_visuals())
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("scene_smoke passed:")
	print(JSON.stringify(counts, "\t"))
	quit(0)


func _validate_scene(root: Node3D, world_result: Dictionary, counts: Dictionary, registry: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	if root.get_node_or_null("GeneratedWorld") == null:
		errors.append("missing GeneratedWorld root")
	if int(counts.get("ground", 0)) != 1:
		errors.append("expected one ground mesh")
	if int(counts.get("objects", 0)) <= 0:
		errors.append("expected object marker meshes")
	if int(counts.get("actors", 0)) != 3:
		errors.append("expected 3 actor markers")
	_validate_actor_model_assets(root, errors)
	_validate_actor_status_markers(root, world_result, errors)
	if int(counts.get("colliders", 0)) <= int(counts.get("actors", 0)):
		errors.append("expected pickable colliders for ground, actors and objects")
	if _interaction_target_node_count(root) <= 0:
		errors.append("expected interaction target metadata on generated nodes")
	_validate_declared_map_visual_assets(root, counts, errors)
	_validate_all_map_scene_visual_assets(counts, errors)
	_validate_imported_gltf_assets(counts, errors)
	if int(counts.get("lights", 0)) <= 0:
		errors.append("expected light")
	if int(counts.get("cameras", 0)) <= 0:
		errors.append("expected camera")
	else:
		_validate_player_camera_focus(root, errors)
	_validate_runtime_map_object_fallbacks(root, errors)
	_validate_synthetic_actor_side_badges(errors)
	_validate_quest_actor_markers(registry, errors)
	_validate_corpse_world_markers(errors)
	_validate_equipment_attach_points(errors)
	_validate_combat_feedback_markers(registry, errors)
	_validate_actor_facing_markers(registry, errors)
	return errors


func _validate_player_camera_focus(root: Node3D, errors: Array[String]) -> void:
	var player: Node3D = root.find_child("Actor_player_1", true, false) as Node3D
	if player == null:
		errors.append("missing player actor marker")
		return
	if player.position.distance_to(Vector3(24.0, 0.58, 39.0)) > 0.1:
		errors.append("player actor should spawn near default_entry on survivor_outpost_01")
	var camera: Camera3D = root.find_child("WorldCamera", true, false) as Camera3D
	if camera == null:
		errors.append("missing WorldCamera")
		return
	if not camera.current:
		errors.append("WorldCamera should be the current startup camera")
	var focus: Variant = camera.get_meta("focus_position", Vector3.ZERO)
	if typeof(focus) != TYPE_VECTOR3 or (focus as Vector3).distance_to(Vector3(24.0, 0.5, 39.0)) > 0.1:
		errors.append("WorldCamera should focus the player/default entry at startup")
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		errors.append("WorldCamera should use the legacy Bevy perspective projection")
	if absf(camera.fov - 30.0) > 0.01:
		errors.append("WorldCamera should use the legacy Bevy 30 degree fov")
	if camera.is_position_behind(player.global_position):
		errors.append("WorldCamera should face the startup player marker")
	var projected := camera.unproject_position(player.global_position)
	if projected.x < 0.0 or projected.y < 0.0 or projected.x > 1440.0 or projected.y > 900.0:
		errors.append("startup player marker should be inside the default camera viewport")


func _validate_door_state_visuals() -> Array[String]:
	var errors: Array[String] = []
	var closed_root := Node3D.new()
	closed_root.name = "SceneSmokeDoorClosedRoot"
	get_root().add_child(closed_root)
	WorldSceneRenderer.new().render_world(closed_root, _door_visual_world(false, false), {"load_map_visuals": false})
	var closed_visual: MeshInstance3D = closed_root.find_child("DoorStateVisual", true, false) as MeshInstance3D
	if closed_visual == null:
		errors.append("closed door should render DoorStateVisual")
	else:
		if str(closed_visual.get_meta("door_visual_state", "")) != "closed":
			errors.append("closed door visual should expose closed state")
		if bool(closed_visual.get_meta("door_is_open", true)):
			errors.append("closed door visual should expose door_is_open false")
		if absf(closed_visual.rotation_degrees.y) > 0.01:
			errors.append("closed door visual should keep closed yaw")
	closed_root.queue_free()

	var open_root := Node3D.new()
	open_root.name = "SceneSmokeDoorOpenRoot"
	get_root().add_child(open_root)
	WorldSceneRenderer.new().render_world(open_root, _door_visual_world(true, false), {"load_map_visuals": false})
	var open_visual: MeshInstance3D = open_root.find_child("DoorStateVisual", true, false) as MeshInstance3D
	if open_visual == null:
		errors.append("open door should render DoorStateVisual")
	else:
		if str(open_visual.get_meta("door_visual_state", "")) != "open":
			errors.append("open door visual should expose open state")
		if not bool(open_visual.get_meta("door_is_open", false)):
			errors.append("open door visual should expose door_is_open true")
		if absf(open_visual.rotation_degrees.y) < 45.0:
			errors.append("open door visual should rotate away from closed pose")
	open_root.queue_free()

	var locked_root := Node3D.new()
	locked_root.name = "SceneSmokeDoorLockedRoot"
	get_root().add_child(locked_root)
	WorldSceneRenderer.new().render_world(locked_root, _door_visual_world(false, true), {"load_map_visuals": false})
	var locked_visual: MeshInstance3D = locked_root.find_child("DoorStateVisual", true, false) as MeshInstance3D
	if locked_visual == null:
		errors.append("locked door should render DoorStateVisual")
	else:
		if str(locked_visual.get_meta("door_visual_state", "")) != "locked":
			errors.append("locked door visual should expose locked state")
		if not bool(locked_visual.get_meta("door_locked", false)):
			errors.append("locked door visual should expose door_locked true")
	locked_root.queue_free()
	return errors


func _door_visual_world(is_open: bool, locked: bool) -> Dictionary:
	var grid := {"x": 1, "y": 0, "z": 1}
	var door := {
		"door_id": "scene_smoke_door",
		"object_id": "scene_smoke_door",
		"display_name": "Scene Smoke Door",
		"anchor": grid,
		"cells": [grid],
		"is_open": is_open,
		"locked": locked,
		"blocks_movement": not is_open,
		"blocks_sight": not is_open,
		"blocks_sight_when_closed": true,
	}
	var target := {
		"target_id": "scene_smoke_door",
		"target_type": "map_object",
		"display_name": "Scene Smoke Door",
		"kind": "door",
		"anchor": grid,
		"cells": [grid],
		"door": door,
	}
	return {
		"map": {
			"map_id": "scene_smoke_door_map",
			"size": {"width": 3, "height": 3},
			"entry_points": {"default_entry": {"x": 0, "y": 0, "z": 0}},
			"interactive_objects": [{
				"object_id": "scene_smoke_door",
				"kind": "interactive",
				"anchor": grid,
				"footprint": {"width": 1, "height": 1},
			}],
			"trigger_objects": [],
			"pickup_objects": [],
			"interaction_targets": {"scene_smoke_door": target},
			"door_objects": [door],
		},
		"actors": [],
		"corpses": [],
	}


func _validate_actor_model_assets(root: Node3D, errors: Array[String]) -> void:
	var player: Node = root.find_child("Actor_player_1", true, false)
	if player == null:
		return
	var actor_model: Node = player.find_child("ActorModel", true, false)
	if actor_model == null:
		errors.append("player actor should instantiate its appearance glTF model")
	elif str(actor_model.get_meta("model_asset", "")) != "preview_placeholders/characters/humanoid_mannequin.gltf":
		errors.append("player actor model should come from default_humanoid appearance asset")
	if player.find_child("ActorFallbackMesh", true, false) != null:
		errors.append("player actor should not use fallback capsule mesh when appearance model exists")
	if player.find_child("PlayerRuntimeMarker", true, false) == null:
		errors.append("player actor should include a visible runtime marker")
	_validate_player_equipment_models(player, errors)


func _validate_player_equipment_models(player: Node, errors: Array[String]) -> void:
	for slot_id in ["main_hand", "body", "legs", "feet"]:
		var model: Node = player.find_child("EquipmentModel_%s" % slot_id, true, false)
		if model == null:
			errors.append("player actor should instantiate equipment model for %s" % slot_id)
			continue
		if str(model.get_meta("slot_id", "")) != slot_id:
			errors.append("equipment model %s should expose slot_id metadata" % slot_id)
		if str(model.get_meta("attach_target", "")) == "":
			errors.append("equipment model %s should expose attach_target metadata" % slot_id)
		if not model.has_meta("attach_offset") or not model.has_meta("attach_rotation_degrees") or not model.has_meta("attach_scale"):
			errors.append("equipment model %s should expose attachment transform metadata" % slot_id)
	var main_hand: Node = player.find_child("EquipmentModel_main_hand", true, false)
	if main_hand != null and str(main_hand.get_meta("model_asset", "")) != "preview_placeholders/placeholders/weapon_dagger.gltf":
		errors.append("main_hand equipment model should use dagger glTF")
	if main_hand != null:
		if str(main_hand.get_meta("attach_target", "")) != "main_hand":
			errors.append("main_hand equipment model should attach to main_hand")
		var rotation: Vector3 = main_hand.get_meta("attach_rotation_degrees", Vector3.ZERO)
		if absf(rotation.z) < 1.0:
			errors.append("main_hand weapon should expose hand-held rotation")


func _validate_actor_status_markers(root: Node3D, world_result: Dictionary, errors: Array[String]) -> void:
	var actors: Array = _array_or_empty(world_result.get("actors", []))
	for actor in actors:
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		var actor_id := int(actor_data.get("actor_id", 0))
		var definition_id := str(actor_data.get("definition_id", ""))
		var actor_node: Node = root.find_child("Actor_%s_%d" % [definition_id, actor_id], true, false)
		if actor_node == null:
			errors.append("actor %s/%d should render status marker parent" % [definition_id, actor_id])
			continue
		var label: Label3D = actor_node.find_child("ActorNameLabel", true, false) as Label3D
		if label == null:
			errors.append("actor %d should render ActorNameLabel" % actor_id)
		else:
			if int(label.get_meta("actor_id", 0)) != actor_id:
				errors.append("actor %d label should expose actor_id metadata" % actor_id)
			if label.text.strip_edges().is_empty():
				errors.append("actor %d label should show a display name" % actor_id)
		_validate_actor_resource_bar(actor_node, actor_data, "health", _expected_health_ratio(actor_data), errors)
		_validate_actor_resource_bar(actor_node, actor_data, "ap", _expected_ap_ratio(actor_data), errors)
		var badge: MeshInstance3D = actor_node.find_child("ActorSideBadge", true, false) as MeshInstance3D
		if badge == null:
			errors.append("actor %d should render ActorSideBadge" % actor_id)
		else:
			var side := str(actor_data.get("side", ""))
			if int(badge.get_meta("actor_id", 0)) != actor_id:
				errors.append("actor %d side badge should expose actor_id metadata" % actor_id)
			if str(badge.get_meta("side", "")) != side:
				errors.append("actor %d side badge should expose side metadata" % actor_id)


func _validate_actor_resource_bar(actor_node: Node, actor_data: Dictionary, resource_id: String, expected_ratio: float, errors: Array[String]) -> void:
	var actor_id := int(actor_data.get("actor_id", 0))
	var bar: Node = actor_node.find_child("Actor%sBar" % resource_id.capitalize(), true, false)
	if bar == null:
		errors.append("actor %d should render %s resource bar" % [actor_id, resource_id])
		return
	if int(bar.get_meta("actor_id", 0)) != actor_id:
		errors.append("actor %d %s bar should expose actor_id metadata" % [actor_id, resource_id])
	if str(bar.get_meta("resource_id", "")) != resource_id:
		errors.append("actor %d %s bar should expose resource_id metadata" % [actor_id, resource_id])
	var ratio := float(bar.get_meta("ratio", -1.0))
	if absf(ratio - expected_ratio) > 0.001:
		errors.append("actor %d %s bar ratio %.3f should match snapshot %.3f" % [actor_id, resource_id, ratio, expected_ratio])
	if bar.find_child("ActorBarFill", true, false) == null:
		errors.append("actor %d %s bar should render fill segment" % [actor_id, resource_id])
	if bar.find_child("ActorBarMissing", true, false) == null:
		errors.append("actor %d %s bar should render missing segment" % [actor_id, resource_id])


func _expected_health_ratio(actor_data: Dictionary) -> float:
	var combat: Dictionary = _dictionary_or_empty(actor_data.get("combat", {}))
	var max_hp: float = max(1.0, float(combat.get("max_hp", actor_data.get("max_hp", 1.0))))
	var hp: float = clampf(float(combat.get("hp", actor_data.get("hp", max_hp))), 0.0, max_hp)
	return hp / max_hp


func _expected_ap_ratio(actor_data: Dictionary) -> float:
	var combat: Dictionary = _dictionary_or_empty(actor_data.get("combat", {}))
	var attributes: Dictionary = _dictionary_or_empty(combat.get("attributes", {}))
	var max_ap: float = max(1.0, float(attributes.get("turn_ap_max", attributes.get("ap_max", 6.0))))
	return clampf(float(actor_data.get("ap", 0.0)) / max_ap, 0.0, 1.0)


func _validate_synthetic_actor_side_badges(errors: Array[String]) -> void:
	var synthetic_root := Node3D.new()
	synthetic_root.name = "SceneSmokeActorSideRoot"
	get_root().add_child(synthetic_root)
	WorldSceneRenderer.new().render_world(synthetic_root, {
		"map": {
			"map_id": "scene_smoke_actor_side_map",
			"size": {"width": 2, "height": 2},
			"entry_points": {"default_entry": {"x": 0, "y": 0, "z": 0}},
			"interactive_objects": [],
			"trigger_objects": [],
			"pickup_objects": [],
			"interaction_targets": {},
		},
		"actors": [{
			"actor_id": 9101,
			"definition_id": "scene_smoke_hostile",
			"display_name": "Scene Smoke Hostile",
			"kind": "npc",
			"side": "hostile",
			"grid_position": {"x": 1, "y": 0, "z": 1},
			"ap": 3.0,
			"combat": {
				"hp": 4.0,
				"max_hp": 8.0,
				"attributes": {"turn_ap_max": 6.0},
				"active_effects": [{
					"effect_id": "passive_skill_combat",
					"source": "skill",
					"skill_id": "combat",
					"category": "passive",
					"level": 1,
					"is_infinite": true,
					"modifiers": {"damage_bonus": 0.04},
				}, {
					"effect_id": "skill_adrenaline_rush",
					"source": "skill",
					"skill_id": "adrenaline_rush",
					"category": "buff",
					"level": 1,
					"duration_remaining": 8.0,
					"modifiers": {"damage_bonus": 0.25},
				}],
			},
		}],
		"corpses": [],
	}, {"load_map_visuals": false})
	var actor_node: Node = synthetic_root.find_child("Actor_scene_smoke_hostile_9101", true, false)
	if actor_node == null:
		errors.append("synthetic hostile actor should render")
	else:
		var badge: MeshInstance3D = actor_node.find_child("ActorSideBadge", true, false) as MeshInstance3D
		if badge == null:
			errors.append("synthetic hostile actor should render side badge")
		elif str(badge.get_meta("side", "")) != "hostile":
			errors.append("synthetic hostile actor side badge should expose hostile side")
		var health_bar: Node = actor_node.find_child("ActorHealthBar", true, false)
		if health_bar == null or absf(float(health_bar.get_meta("ratio", -1.0)) - 0.5) > 0.001:
			errors.append("synthetic hostile actor health bar should expose half hp ratio")
		var ap_bar: Node = actor_node.find_child("ActorApBar", true, false)
		if ap_bar == null or absf(float(ap_bar.get_meta("ratio", -1.0)) - 0.5) > 0.001:
			errors.append("synthetic hostile actor AP bar should expose half ap ratio")
		_validate_actor_status_effect_icons(actor_node, errors)
	synthetic_root.queue_free()


func _validate_actor_status_effect_icons(actor_node: Node, errors: Array[String]) -> void:
	var container: Node = actor_node.find_child("ActorStatusEffectIcons", true, false)
	if container == null:
		errors.append("actor with active effects should render ActorStatusEffectIcons")
		return
	if int(container.get_meta("effect_count", 0)) != 2:
		errors.append("status effect container should expose total effect_count")
	if int(container.get_meta("visible_effect_count", 0)) != 2:
		errors.append("status effect container should expose visible_effect_count")
	var passive: Node = _status_effect_icon_by_effect_id(container, "passive_skill_combat")
	if passive == null:
		errors.append("status effect icons should include passive_skill_combat")
	else:
		if str(passive.get_meta("category", "")) != "passive":
			errors.append("passive status effect icon should expose category")
		if not bool(passive.get_meta("is_infinite", false)):
			errors.append("passive status effect icon should expose infinite duration")
		var modifiers: Dictionary = _dictionary_or_empty(passive.get_meta("modifiers", {}))
		if absf(float(modifiers.get("damage_bonus", 0.0)) - 0.04) > 0.001:
			errors.append("passive status effect icon should expose modifiers")
	var buff: Node = _status_effect_icon_by_effect_id(container, "skill_adrenaline_rush")
	if buff == null:
		errors.append("status effect icons should include skill_adrenaline_rush")
	else:
		if str(buff.get_meta("category", "")) != "buff":
			errors.append("buff status effect icon should expose category")
		if absf(float(buff.get_meta("duration_remaining", 0.0)) - 8.0) > 0.001:
			errors.append("buff status effect icon should expose duration")
	if container.find_child("ActorStatusEffectLabel_0", true, false) == null:
		errors.append("status effect icons should render compact labels")


func _status_effect_icon_by_effect_id(root: Node, effect_id: String) -> Node:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if str(node.get_meta("effect_id", "")) == effect_id and node.name.begins_with("ActorStatusEffectIcon"):
			return node
		for child in node.get_children():
			pending.append(child)
	return null


func _validate_quest_actor_markers(registry: RefCounted, errors: Array[String]) -> void:
	var runtime_snapshot := _quest_marker_runtime_snapshot()
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(runtime_snapshot)
	if not bool(world_result.get("ok", false)):
		errors.append("quest actor marker smoke failed to build world snapshot: %s" % world_result.get("error", "unknown"))
		return
	var doctor_actor := _actor_by_definition(_array_or_empty(world_result.get("actors", [])), "doctor_chen")
	if doctor_actor.is_empty():
		errors.append("quest actor marker smoke should include doctor_chen actor")
		return
	var doctor_marker: Dictionary = _quest_marker_by_kind(_array_or_empty(doctor_actor.get("quest_markers", [])), "quest_turn_in")
	_validate_quest_marker_data(doctor_marker, "doctor_chen", "quest_turn_in", "find_medicine", "ready", "doctor_chen_find_medicine_turn_in", errors)
	var trader_actor := _actor_by_definition(_array_or_empty(world_result.get("actors", [])), "trader_lao_wang")
	if trader_actor.is_empty():
		errors.append("quest actor marker smoke should include trader_lao_wang actor")
		return
	var trader_marker: Dictionary = _quest_marker_by_kind(_array_or_empty(trader_actor.get("quest_markers", [])), "quest_offer")
	_validate_quest_marker_data(trader_marker, "trader_lao_wang", "quest_offer", "tutorial_survive", "available", "trader_lao_wang_intro", errors)

	var root := Node3D.new()
	root.name = "SceneSmokeQuestMarkerRoot"
	get_root().add_child(root)
	WorldSceneRenderer.new().render_world(root, world_result, {"load_map_visuals": false})
	_validate_rendered_quest_marker(root, "Actor_doctor_chen_9102", "doctor_chen", "quest_turn_in", "find_medicine", "ready", "doctor_chen_find_medicine_turn_in", "!", errors)
	_validate_rendered_quest_marker(root, "Actor_trader_lao_wang_9103", "trader_lao_wang", "quest_offer", "tutorial_survive", "available", "trader_lao_wang_intro", "!", errors)
	root.queue_free()


func _validate_quest_marker_data(marker: Dictionary, actor_label: String, expected_kind: String, expected_quest_id: String, expected_status: String, expected_dialogue_id: String, errors: Array[String]) -> void:
	if marker.is_empty():
		errors.append("%s should expose %s marker from dialogue rules" % [actor_label, expected_kind])
		return
	if str(marker.get("kind", "")) != expected_kind:
		errors.append("%s quest marker should expose kind %s" % [actor_label, expected_kind])
	if str(marker.get("quest_id", "")) != expected_quest_id:
		errors.append("%s quest marker should target %s" % [actor_label, expected_quest_id])
	if str(marker.get("status", "")) != expected_status:
		errors.append("%s quest marker should expose status %s" % [actor_label, expected_status])
	if str(marker.get("source_dialogue_id", "")) != expected_dialogue_id:
		errors.append("%s quest marker should expose dialogue source %s" % [actor_label, expected_dialogue_id])


func _validate_rendered_quest_marker(root: Node, node_name: String, actor_label: String, expected_kind: String, expected_quest_id: String, expected_status: String, expected_dialogue_id: String, expected_label: String, errors: Array[String]) -> void:
	var actor_node: Node = root.find_child(node_name, true, false)
	if actor_node == null:
		errors.append("%s quest marker actor should render" % actor_label)
	else:
		var icon: MeshInstance3D = actor_node.find_child("ActorQuestMarker", true, false) as MeshInstance3D
		if icon == null:
			errors.append("%s should render ActorQuestMarker" % actor_label)
		else:
			if str(icon.get_meta("marker_kind", "")) != expected_kind:
				errors.append("%s ActorQuestMarker should expose marker kind" % actor_label)
			if str(icon.get_meta("quest_id", "")) != expected_quest_id:
				errors.append("%s ActorQuestMarker should expose quest_id metadata" % actor_label)
			if str(icon.get_meta("marker_status", "")) != expected_status:
				errors.append("%s ActorQuestMarker should expose marker status metadata" % actor_label)
			if str(icon.get_meta("source_dialogue_id", "")) != expected_dialogue_id:
				errors.append("%s ActorQuestMarker should expose source dialogue metadata" % actor_label)
		var label: Label3D = actor_node.find_child("ActorQuestMarkerLabel", true, false) as Label3D
		if label == null:
			errors.append("%s should render ActorQuestMarkerLabel" % actor_label)
		elif label.text != expected_label:
			errors.append("%s quest marker label should use %s" % [actor_label, expected_label])


func _quest_marker_runtime_snapshot() -> Dictionary:
	return {
		"active_map_id": "survivor_outpost_01",
		"door_states": [],
		"consumed_interaction_targets": [],
		"corpse_containers": [],
		"active_quests": [{
			"quest_id": "find_medicine",
			"current_node_id": "step_1",
			"completed_objectives": {"step_1": 1},
		}],
		"completed_quests": ["zombie_hunter"],
		"actors": [{
			"actor_id": 9101,
			"definition_id": "player",
			"display_name": "Player",
			"kind": "player",
			"side": "player",
			"map_id": "survivor_outpost_01",
			"grid_position": {"x": 1, "y": 0, "z": 1},
			"ap": 6.0,
			"combat": {"hp": 10.0, "max_hp": 10.0, "attributes": {"turn_ap_max": 6.0}},
		}, {
			"actor_id": 9102,
			"definition_id": "doctor_chen",
			"display_name": "陈医生",
			"kind": "npc",
			"side": "friendly",
			"map_id": "survivor_outpost_01",
			"grid_position": {"x": 2, "y": 0, "z": 1},
			"ap": 3.0,
			"combat": {"hp": 8.0, "max_hp": 8.0, "attributes": {"turn_ap_max": 6.0}},
		}, {
			"actor_id": 9103,
			"definition_id": "trader_lao_wang",
			"display_name": "老王",
			"kind": "npc",
			"side": "friendly",
			"map_id": "survivor_outpost_01",
			"grid_position": {"x": 3, "y": 0, "z": 1},
			"ap": 3.0,
			"combat": {"hp": 8.0, "max_hp": 8.0, "attributes": {"turn_ap_max": 6.0}},
		}],
	}


func _quest_marker_by_kind(markers: Array, marker_kind: String) -> Dictionary:
	for marker in markers:
		var marker_data: Dictionary = _dictionary_or_empty(marker)
		if str(marker_data.get("kind", "")) == marker_kind:
			return marker_data
	return {}


func _actor_by_definition(actors: Array, definition_id: String) -> Dictionary:
	for actor in actors:
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if str(actor_data.get("definition_id", "")) == definition_id:
			return actor_data
	return {}


func _validate_corpse_world_markers(errors: Array[String]) -> void:
	var root := Node3D.new()
	root.name = "SceneSmokeCorpseRoot"
	get_root().add_child(root)
	WorldSceneRenderer.new().render_world(root, _corpse_world(), {"load_map_visuals": false})
	var corpse_node: Node = root.find_child("Corpse_scene_smoke_corpse", true, false)
	if corpse_node == null:
		errors.append("synthetic corpse should render Corpse_* world node")
	else:
		if str(corpse_node.get_meta("corpse_container_id", "")) != "scene_smoke_corpse":
			errors.append("corpse node should expose corpse_container_id metadata")
		if int(corpse_node.get_meta("source_actor_id", 0)) != 9201:
			errors.append("corpse node should expose source_actor_id metadata")
		if int(corpse_node.get_meta("loot_count", 0)) != 2:
			errors.append("corpse node should expose loot_count metadata")
		if int(corpse_node.get_meta("money", 0)) != 17:
			errors.append("corpse node should expose money metadata")
		var label: Label3D = corpse_node.find_child("CorpseNameLabel", true, false) as Label3D
		if label == null:
			errors.append("corpse node should render CorpseNameLabel")
		elif not label.text.contains("Scene Smoke Corpse"):
			errors.append("corpse label should show display name")
		var badge: MeshInstance3D = corpse_node.find_child("CorpseContainerBadge", true, false) as MeshInstance3D
		if badge == null:
			errors.append("corpse node should render CorpseContainerBadge")
		else:
			if str(badge.get_meta("target_kind", "")) != "container":
				errors.append("corpse badge should expose container target kind")
			if int(badge.get_meta("loot_count", 0)) != 2:
				errors.append("corpse badge should mirror loot_count metadata")
		if corpse_node.find_child("PickableBody", true, false) == null:
			errors.append("corpse node should remain pickable after visual markers")
	root.queue_free()


func _corpse_world() -> Dictionary:
	return {
		"map": {
			"map_id": "scene_smoke_corpse_map",
			"size": {"width": 3, "height": 3},
			"entry_points": {"default_entry": {"x": 0, "y": 0, "z": 0}},
			"interactive_objects": [],
			"trigger_objects": [],
			"pickup_objects": [],
			"interaction_targets": {},
		},
		"actors": [],
		"corpses": [{
			"container_id": "scene_smoke_corpse",
			"display_name": "Scene Smoke Corpse",
			"source_actor_id": 9201,
			"source_actor_definition_id": "scene_smoke_zombie",
			"source_actor_kind": "enemy",
			"defeated_by_actor_id": 1,
			"map_id": "scene_smoke_corpse_map",
			"grid_position": {"x": 1, "y": 0, "z": 1},
			"inventory": [
				{"item_id": "1006", "count": 2},
				{"item_id": "1009", "count": 9},
			],
			"money": 17,
		}],
	}


func _validate_equipment_attach_points(errors: Array[String]) -> void:
	var root := Node3D.new()
	root.name = "SceneSmokeEquipmentAttachRoot"
	get_root().add_child(root)
	WorldSceneRenderer.new().render_world(root, _equipment_attach_world(), {"load_map_visuals": false})
	var actor_node: Node = root.find_child("Actor_scene_smoke_equipment_9301", true, false)
	if actor_node == null:
		errors.append("equipment attach smoke actor should render")
	else:
		for attach_target in ["head", "hands", "back", "accessory", "off_hand"]:
			var model: Node = actor_node.find_child("EquipmentModel_%s" % attach_target, true, false)
			if model == null:
				errors.append("equipment attach smoke should render %s model" % attach_target)
				continue
			if str(model.get_meta("attach_target", "")) != attach_target:
				errors.append("%s equipment should expose attach_target metadata" % attach_target)
			if not model.has_meta("attach_offset") or not model.has_meta("attach_rotation_degrees") or not model.has_meta("attach_scale"):
				errors.append("%s equipment should expose transform metadata" % attach_target)
		var off_hand: Node = actor_node.find_child("EquipmentModel_off_hand", true, false)
		if off_hand != null:
			var off_rotation: Vector3 = off_hand.get_meta("attach_rotation_degrees", Vector3.ZERO)
			if off_rotation.z <= 0.0:
				errors.append("off_hand equipment should mirror hand-held rotation")
		var back: Node = actor_node.find_child("EquipmentModel_back", true, false)
		if back != null:
			var back_offset: Vector3 = back.get_meta("attach_offset", Vector3.ZERO)
			if back_offset.z <= 0.0:
				errors.append("back equipment should attach behind actor")
	root.queue_free()


func _equipment_attach_world() -> Dictionary:
	var visuals: Array[Dictionary] = []
	for attach_target in ["head", "hands", "back", "accessory", "off_hand"]:
		visuals.append({
			"slot_id": attach_target,
			"item_id": "scene_smoke_%s" % attach_target,
			"visual_asset": "builtin:item:body",
			"model_asset": "preview_placeholders/placeholders/equipment_body.gltf",
			"attach_target": attach_target,
			"presentation_mode": "attach",
		})
	return {
		"map": {
			"map_id": "scene_smoke_equipment_map",
			"size": {"width": 3, "height": 3},
			"entry_points": {"default_entry": {"x": 0, "y": 0, "z": 0}},
			"interactive_objects": [],
			"trigger_objects": [],
			"pickup_objects": [],
			"interaction_targets": {},
		},
		"actors": [{
			"actor_id": 9301,
			"definition_id": "scene_smoke_equipment",
			"display_name": "Equipment Attach Smoke",
			"kind": "npc",
			"side": "friendly",
			"grid_position": {"x": 1, "y": 0, "z": 1},
			"equipment_visuals": visuals,
			"ap": 3.0,
			"combat": {"hp": 8.0, "max_hp": 8.0, "attributes": {"turn_ap_max": 6.0}},
		}],
		"corpses": [],
	}


func _validate_combat_feedback_markers(registry: RefCounted, errors: Array[String]) -> void:
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(_combat_feedback_runtime_snapshot())
	if not bool(world_result.get("ok", false)):
		errors.append("combat feedback smoke failed to build world snapshot: %s" % world_result.get("error", "unknown"))
		return
	var actors: Array = _array_or_empty(world_result.get("actors", []))
	var by_id: Dictionary = {}
	for actor in actors:
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		by_id[int(actor_data.get("actor_id", 0))] = actor_data
	if str(_dictionary_or_empty(by_id.get(9402, {})).get("combat_feedback", {}).get("feedback_kind", "")) != "critical":
		errors.append("world snapshot should derive latest critical feedback for target actor")
	if str(_dictionary_or_empty(by_id.get(9403, {})).get("combat_feedback", {}).get("feedback_kind", "")) != "miss":
		errors.append("world snapshot should derive miss feedback for target actor")
	if str(_dictionary_or_empty(by_id.get(9404, {})).get("combat_feedback", {}).get("feedback_kind", "")) != "blocked":
		errors.append("world snapshot should derive blocked feedback for target actor")
	if str(_dictionary_or_empty(by_id.get(9405, {})).get("combat_feedback", {}).get("feedback_kind", "")) != "defeated":
		errors.append("world snapshot should derive defeated feedback for target actor")

	var root := Node3D.new()
	root.name = "SceneSmokeCombatFeedbackRoot"
	get_root().add_child(root)
	WorldSceneRenderer.new().render_world(root, world_result, {"load_map_visuals": false})
	_validate_combat_feedback_actor(root, 9402, "critical", "CRIT -7", 7.0, errors)
	_validate_combat_feedback_actor(root, 9403, "miss", "MISS", 0.0, errors)
	_validate_combat_feedback_actor(root, 9404, "blocked", "BLOCK", 0.0, errors)
	_validate_combat_feedback_actor(root, 9405, "defeated", "-12 KO", 12.0, errors)
	root.queue_free()


func _validate_combat_feedback_actor(root: Node, actor_id: int, expected_kind: String, expected_text: String, expected_damage: float, errors: Array[String]) -> void:
	var actor_node: Node = root.find_child("Actor_scene_smoke_feedback_%d" % actor_id, true, false)
	if actor_node == null:
		errors.append("combat feedback actor %d should render" % actor_id)
		return
	var label: Label3D = actor_node.find_child("ActorCombatFeedback", true, false) as Label3D
	if label == null:
		errors.append("combat feedback actor %d should render ActorCombatFeedback" % actor_id)
	else:
		if str(label.get_meta("feedback_kind", "")) != expected_kind:
			errors.append("combat feedback actor %d should expose %s feedback kind" % [actor_id, expected_kind])
		if label.text != expected_text:
			errors.append("combat feedback actor %d label should show %s, got %s" % [actor_id, expected_text, label.text])
		if absf(float(label.get_meta("damage", -1.0)) - expected_damage) > 0.001:
			errors.append("combat feedback actor %d should expose damage metadata" % actor_id)
		if int(label.get_meta("target_actor_id", 0)) != actor_id:
			errors.append("combat feedback actor %d should expose target actor id" % actor_id)
	var marker: MeshInstance3D = actor_node.find_child("ActorCombatFeedbackMarker", true, false) as MeshInstance3D
	if marker == null:
		errors.append("combat feedback actor %d should render ActorCombatFeedbackMarker" % actor_id)
	elif str(marker.get_meta("feedback_kind", "")) != expected_kind:
		errors.append("combat feedback marker actor %d should expose %s feedback kind" % [actor_id, expected_kind])


func _combat_feedback_runtime_snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor_id in [9401, 9402, 9403, 9404, 9405]:
		actors.append({
			"actor_id": actor_id,
			"definition_id": "scene_smoke_feedback",
			"display_name": "Combat Feedback %d" % actor_id,
			"kind": "player" if actor_id == 9401 else "npc",
			"side": "player" if actor_id == 9401 else "hostile",
			"map_id": "survivor_outpost_01",
			"grid_position": {"x": 2 + actor_id - 9401, "y": 0, "z": 2},
			"ap": 3.0,
			"combat": {"hp": 10.0, "max_hp": 12.0, "attributes": {"turn_ap_max": 6.0}},
		})
	return {
		"active_map_id": "survivor_outpost_01",
		"actors": actors,
		"events": [{
			"kind": "attack_resolved",
			"payload": {
				"actor_id": 9401,
				"target_actor_id": 9402,
				"damage": 3.0,
				"target_hp": 9.0,
				"critical": false,
				"hit_kind": "hit",
				"defeated": false,
				"hit_chance": 0.85,
				"weapon_item_id": "1003",
			},
		}, {
			"kind": "attack_resolved",
			"payload": {
				"actor_id": 9401,
				"target_actor_id": 9402,
				"damage": 7.0,
				"target_hp": 2.0,
				"critical": true,
				"hit_kind": "hit",
				"defeated": false,
				"hit_chance": 0.85,
				"weapon_item_id": "1003",
			},
		}, {
			"kind": "attack_resolved",
			"payload": {
				"actor_id": 9401,
				"target_actor_id": 9403,
				"damage": 0.0,
				"target_hp": 10.0,
				"critical": false,
				"hit_kind": "miss",
				"defeated": false,
				"hit_chance": 0.25,
				"weapon_item_id": "1004",
			},
		}, {
			"kind": "attack_resolved",
			"payload": {
				"actor_id": 9401,
				"target_actor_id": 9404,
				"damage": 0.0,
				"target_hp": 10.0,
				"critical": false,
				"hit_kind": "blocked",
				"defeated": false,
				"hit_chance": 0.9,
				"weapon_item_id": "1003",
			},
		}, {
			"kind": "attack_resolved",
			"payload": {
				"actor_id": 9401,
				"target_actor_id": 9405,
				"damage": 12.0,
				"target_hp": 0.0,
				"critical": false,
				"hit_kind": "hit",
				"defeated": true,
				"hit_chance": 0.9,
				"weapon_item_id": "1003",
			},
		}],
		"corpse_containers": [],
		"consumed_interaction_targets": [],
		"door_states": [],
		"active_quests": [],
		"completed_quests": [],
	}


func _validate_actor_facing_markers(registry: RefCounted, errors: Array[String]) -> void:
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(_actor_facing_runtime_snapshot())
	if not bool(world_result.get("ok", false)):
		errors.append("actor facing smoke failed to build world snapshot: %s" % world_result.get("error", "unknown"))
		return
	var moved_actor: Dictionary = _actor_by_id(_array_or_empty(world_result.get("actors", [])), 9501)
	if str(moved_actor.get("facing_direction", "")) != "east" or absf(float(moved_actor.get("facing_yaw_degrees", -1.0)) - 90.0) > 0.001:
		errors.append("moved actor should face east from actor_moved event")
	var attacker_actor: Dictionary = _actor_by_id(_array_or_empty(world_result.get("actors", [])), 9502)
	if str(attacker_actor.get("facing_direction", "")) != "north" or absf(float(attacker_actor.get("facing_yaw_degrees", -1.0))) > 0.001:
		errors.append("attacking actor should face north from attack_resolved event")
	var root := Node3D.new()
	root.name = "SceneSmokeActorFacingRoot"
	get_root().add_child(root)
	WorldSceneRenderer.new().render_world(root, world_result, {"load_map_visuals": false})
	_validate_actor_facing_node(root, 9501, "east", 90.0, "movement", errors)
	_validate_actor_facing_node(root, 9502, "north", 0.0, "attack", errors)
	root.queue_free()


func _validate_actor_facing_node(root: Node, actor_id: int, expected_direction: String, expected_yaw: float, expected_source: String, errors: Array[String]) -> void:
	var actor_node: Node3D = root.find_child("Actor_scene_smoke_facing_%d" % actor_id, true, false) as Node3D
	if actor_node == null:
		errors.append("actor facing smoke actor %d should render" % actor_id)
		return
	if str(actor_node.get_meta("facing_direction", "")) != expected_direction:
		errors.append("actor %d should expose facing direction %s" % [actor_id, expected_direction])
	if str(actor_node.get_meta("facing_source", "")) != expected_source:
		errors.append("actor %d should expose facing source %s" % [actor_id, expected_source])
	if absf(float(actor_node.get_meta("facing_yaw_degrees", -1.0)) - expected_yaw) > 0.001:
		errors.append("actor %d should expose facing yaw %.1f" % [actor_id, expected_yaw])
	if absf(actor_node.rotation_degrees.y - expected_yaw) > 0.001:
		errors.append("actor %d node should rotate to facing yaw %.1f" % [actor_id, expected_yaw])


func _actor_facing_runtime_snapshot() -> Dictionary:
	return {
		"active_map_id": "survivor_outpost_01",
		"actors": [{
			"actor_id": 9501,
			"definition_id": "scene_smoke_facing",
			"display_name": "Facing Move Smoke",
			"kind": "npc",
			"side": "friendly",
			"map_id": "survivor_outpost_01",
			"grid_position": {"x": 5, "y": 0, "z": 5},
			"ap": 3.0,
			"combat": {"hp": 10.0, "max_hp": 10.0, "attributes": {"turn_ap_max": 6.0}},
		}, {
			"actor_id": 9502,
			"definition_id": "scene_smoke_facing",
			"display_name": "Facing Attack Smoke",
			"kind": "npc",
			"side": "friendly",
			"map_id": "survivor_outpost_01",
			"grid_position": {"x": 8, "y": 0, "z": 8},
			"ap": 3.0,
			"combat": {"hp": 10.0, "max_hp": 10.0, "attributes": {"turn_ap_max": 6.0}},
		}, {
			"actor_id": 9503,
			"definition_id": "scene_smoke_facing",
			"display_name": "Facing Target Smoke",
			"kind": "npc",
			"side": "hostile",
			"map_id": "survivor_outpost_01",
			"grid_position": {"x": 8, "y": 0, "z": 6},
			"ap": 3.0,
			"combat": {"hp": 10.0, "max_hp": 10.0, "attributes": {"turn_ap_max": 6.0}},
		}],
		"events": [{
			"kind": "actor_moved",
			"payload": {
				"actor_id": 9501,
				"from": {"x": 4, "y": 0, "z": 5},
				"to": {"x": 5, "y": 0, "z": 5},
				"steps": 1,
			},
		}, {
			"kind": "attack_resolved",
			"payload": {
				"actor_id": 9502,
				"target_actor_id": 9503,
				"damage": 1.0,
				"target_hp": 9.0,
				"critical": false,
				"hit_kind": "hit",
				"defeated": false,
			},
		}],
		"corpse_containers": [],
		"consumed_interaction_targets": [],
		"door_states": [],
		"active_quests": [],
		"completed_quests": [],
	}


func _actor_by_id(actors: Array, actor_id: int) -> Dictionary:
	for actor in actors:
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == actor_id:
			return actor_data
	return {}


func _validate_declared_map_visual_assets(root: Node3D, counts: Dictionary, errors: Array[String]) -> void:
	var visual_root: Node = root.find_child("MapSceneVisuals", true, false)
	if visual_root == null:
		errors.append("scene smoke should instantiate MapSceneVisuals")
		return
	var stats := _declared_visual_stats(visual_root, "runtime MapSceneVisuals", errors)
	var declared_count := int(stats.get("declared", 0))
	var instantiated_count := int(stats.get("instantiated", 0))
	counts["declared_map_visuals"] = declared_count
	counts["instantiated_map_visuals"] = instantiated_count
	if declared_count <= 0:
		errors.append("scene smoke expected at least one map object with declared visual props")
	if instantiated_count != declared_count:
		errors.append("scene smoke visual instancing mismatch %d/%d" % [instantiated_count, declared_count])


func _validate_all_map_scene_visual_assets(counts: Dictionary, errors: Array[String]) -> void:
	var dir := DirAccess.open("res://scenes/maps")
	if dir == null:
		errors.append("scene smoke cannot open res://scenes/maps")
		return
	var map_count := 0
	var declared_total := 0
	var instantiated_total := 0
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir() or not file_name.ends_with(".tscn"):
			continue
		map_count += 1
		var scene_path := "res://scenes/maps/%s" % file_name
		var packed: PackedScene = load(scene_path)
		if packed == null:
			errors.append("map scene visual smoke failed to load %s" % scene_path)
			continue
		var scene_root: Node = packed.instantiate()
		if scene_root == null:
			errors.append("map scene visual smoke failed to instantiate %s" % scene_path)
			continue
		var stats := _declared_visual_stats(scene_root, file_name, errors)
		declared_total += int(stats.get("declared", 0))
		instantiated_total += int(stats.get("instantiated", 0))
		scene_root.free()
	dir.list_dir_end()
	counts["map_scene_count"] = map_count
	counts["all_map_declared_visuals"] = declared_total
	counts["all_map_instantiated_visuals"] = instantiated_total
	if map_count <= 0:
		errors.append("scene smoke expected at least one map scene")
	if declared_total <= 0:
		errors.append("scene smoke expected declared visual props across map scenes")
	if instantiated_total != declared_total:
		errors.append("all map scene visual instancing mismatch %d/%d" % [instantiated_total, declared_total])


func _validate_runtime_map_object_fallbacks(root: Node3D, errors: Array[String]) -> void:
	var visual_backed_marker: Node = root.find_child("MapObject_survivor_outpost_01_pickup_medkit", true, false)
	if visual_backed_marker != null and _map_object_fallback_count(visual_backed_marker) != 0:
		errors.append("runtime map object with real scene visual should not add duplicate fallback visual")
	if _map_object_fallback_count(root) <= 0:
		errors.append("runtime map objects without real scene visuals should expose fallback visuals")
	var fallback_root := Node3D.new()
	fallback_root.name = "SceneSmokeMapObjectFallbackRoot"
	get_root().add_child(fallback_root)
	WorldSceneRenderer.new().render_world(fallback_root, _fallback_visual_world(), {"load_map_visuals": false})
	var categories := {}
	var pending: Array[Node] = [fallback_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node.name != "MapObjectFallbackVisual":
			continue
		categories[str(node.get_meta("fallback_category", ""))] = true
	for category in ["pickup", "container", "trigger"]:
		if not bool(categories.get(category, false)):
			errors.append("generated map object fallback should include %s visual" % category)
	fallback_root.queue_free()


func _map_object_fallback_count(root: Node) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.name == "MapObjectFallbackVisual":
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


func _fallback_visual_world() -> Dictionary:
	var pickup_grid := {"x": 1, "y": 0, "z": 1}
	var container_grid := {"x": 2, "y": 0, "z": 1}
	var trigger_grid := {"x": 3, "y": 0, "z": 1}
	return {
		"map": {
			"map_id": "scene_smoke_fallback_map",
			"size": {"width": 5, "height": 4},
			"entry_points": {"default_entry": {"x": 0, "y": 0, "z": 0}},
			"interactive_objects": [{
				"object_id": "scene_smoke_container",
				"kind": "interactive",
				"anchor": container_grid,
				"footprint": {"width": 1, "height": 1},
			}],
			"trigger_objects": [{
				"object_id": "scene_smoke_trigger",
				"kind": "trigger",
				"anchor": trigger_grid,
				"footprint": {"width": 1, "height": 1},
			}],
			"pickup_objects": [{
				"object_id": "scene_smoke_pickup",
				"kind": "pickup",
				"anchor": pickup_grid,
				"footprint": {"width": 1, "height": 1},
			}],
			"interaction_targets": {
				"scene_smoke_container": {
					"target_id": "scene_smoke_container",
					"target_type": "map_object",
					"display_name": "Fallback Container",
					"kind": "container",
					"anchor": container_grid,
					"cells": [container_grid],
				},
				"scene_smoke_trigger": {
					"target_id": "scene_smoke_trigger",
					"target_type": "map_object",
					"display_name": "Fallback Trigger",
					"kind": "enter_subscene",
					"anchor": trigger_grid,
					"cells": [trigger_grid],
				},
				"scene_smoke_pickup": {
					"target_id": "scene_smoke_pickup",
					"target_type": "map_object",
					"display_name": "Fallback Pickup",
					"kind": "pickup",
					"anchor": pickup_grid,
					"cells": [pickup_grid],
				},
			},
		},
		"actors": [],
		"corpses": [],
	}


func _declared_visual_stats(root: Node, label: String, errors: Array[String]) -> Dictionary:
	var declared_count := 0
	var instantiated_count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if not node.has_method("to_object_definition"):
			continue
		var definition: Dictionary = node.call("to_object_definition")
		var props: Dictionary = _dictionary_or_empty(definition.get("props", {}))
		var visual_props: Dictionary = _dictionary_or_empty(props.get("visual", {}))
		if visual_props.is_empty():
			continue
		declared_count += 1
		var object_id := str(definition.get("object_id", ""))
		var visuals_container: Node = node.get_node_or_null("Visuals")
		if visuals_container == null:
			errors.append("%s object %s declares visual props but has no Visuals node" % [label, object_id])
			continue
		if visuals_container.get_child_count() <= 0:
			errors.append("%s object %s declares visual props but instantiated no visual children" % [label, object_id])
			continue
		instantiated_count += 1
	return {
		"declared": declared_count,
		"instantiated": instantiated_count,
	}


func _validate_imported_gltf_assets(counts: Dictionary, errors: Array[String]) -> void:
	var asset_paths: Array[String] = []
	_collect_gltf_assets("res://assets", asset_paths, errors)
	asset_paths.sort()
	var mesh_total := 0
	var material_total := 0
	var zero_bounds: Array[String] = []
	for asset_path in asset_paths:
		if not ResourceLoader.exists(asset_path):
			errors.append("gltf asset missing imported resource: %s" % asset_path)
			continue
		var packed: PackedScene = load(asset_path)
		if packed == null:
			errors.append("gltf asset failed to load as PackedScene: %s" % asset_path)
			continue
		var instance: Node = packed.instantiate()
		if instance == null:
			errors.append("gltf asset failed to instantiate: %s" % asset_path)
			continue
		var stats := _gltf_instance_stats(instance)
		var mesh_count := int(stats.get("mesh_count", 0))
		var material_count := int(stats.get("material_count", 0))
		mesh_total += mesh_count
		material_total += material_count
		if mesh_count <= 0:
			errors.append("gltf asset should contain at least one mesh: %s" % asset_path)
		var bounds: AABB = stats.get("bounds", AABB())
		if bounds.size.length() <= 0.001:
			zero_bounds.append(asset_path)
		instance.free()
	for asset_path in zero_bounds:
		errors.append("gltf asset should have non-zero visual bounds: %s" % asset_path)
	counts["gltf_asset_count"] = asset_paths.size()
	counts["gltf_mesh_count"] = mesh_total
	counts["gltf_material_count"] = material_total
	if asset_paths.is_empty():
		errors.append("scene smoke expected glTF assets under res://assets")


func _collect_gltf_assets(root_path: String, output: Array[String], errors: Array[String]) -> void:
	var dir := DirAccess.open(root_path)
	if dir == null:
		errors.append("cannot open asset directory %s" % root_path)
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		var path := "%s/%s" % [root_path, entry]
		if dir.current_is_dir():
			_collect_gltf_assets(path, output, errors)
		elif entry.ends_with(".gltf") or entry.ends_with(".glb"):
			output.append(path)
	dir.list_dir_end()


func _gltf_instance_stats(root: Node) -> Dictionary:
	var mesh_count := 0
	var material_count := 0
	var has_bounds := false
	var bounds := AABB()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		mesh_count += 1
		var mesh_bounds := mesh_node.get_aabb()
		bounds = mesh_bounds if not has_bounds else bounds.merge(mesh_bounds)
		has_bounds = true
		for surface_index in range(mesh_node.mesh.get_surface_count()):
			if mesh_node.mesh.surface_get_material(surface_index) != null:
				material_count += 1
		if mesh_node.material_override != null:
			material_count += 1
	return {
		"mesh_count": mesh_count,
		"material_count": material_count,
		"bounds": bounds,
	}


func _interaction_target_node_count(root: Node) -> int:
	var count: int = 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.has_meta("interaction_target"):
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
