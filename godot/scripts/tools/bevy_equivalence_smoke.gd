extends SceneTree

const GAME_ROOT_SCENE = preload("res://scenes/game/game_root.tscn")

const BEVY_SCENARIO := "WorldInteractionMenu"
const PICKUP_NODE_NAME := "MapObject_survivor_outpost_01_pickup_medkit"
const PICKUP_ITEM_ID := "1006"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_root: Node = GAME_ROOT_SCENE.instantiate()
	get_root().add_child(game_root)
	await process_frame

	# 迁移证据需要机器可读，方便 Commit 8 关闭 Bevy 前逐项审计旧 smoke 目标。
	var evidence: Dictionary = {
		"bevy_scenarios": {
			BEVY_SCENARIO: {
				"covered_by": ["PlayerInteraction", "Interaction", "UI"],
				"direct_assertions": [],
			},
		},
	}
	var errors: Array[String] = await _run_world_interaction_menu_checks(game_root, evidence)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("bevy_equivalence_smoke passed:")
	print(JSON.stringify(evidence, "\t"))
	quit(0)


func _run_world_interaction_menu_checks(game_root: Node, evidence: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if game_root.simulation == null:
		return ["game root did not initialize simulation"]
	if game_root.hud == null:
		return ["game root did not initialize HUD"]

	var pickup_node: Node = game_root.find_child(PICKUP_NODE_NAME, true, false)
	if pickup_node == null:
		return ["missing generated pickup node for Bevy equivalence smoke"]

	var selection: Dictionary = game_root.select_interaction_node(pickup_node)
	if not bool(selection.get("success", false)):
		errors.append("pickup node selection failed: %s" % selection.get("prompt", {}).get("reason", "unknown"))
	else:
		_append_assertion(evidence, "node_selection")

	var prompt: Dictionary = _dictionary_or_empty(selection.get("prompt", {}))
	if not bool(prompt.get("ok", false)):
		errors.append("pickup prompt was not queryable")
	if str(prompt.get("primary_option_id", "")) != "pickup":
		errors.append("pickup primary option should be 'pickup'")
	else:
		_append_assertion(evidence, "primary_pickup_option")

	var options: Array = prompt.get("options", [])
	if options.is_empty():
		errors.append("pickup prompt did not expose any option")
	else:
		var primary_option: Dictionary = _dictionary_or_empty(options[0])
		if primary_option.get("kind", "") != "pickup":
			errors.append("pickup primary option kind should be 'pickup'")
		if str(primary_option.get("item_id", "")) != PICKUP_ITEM_ID:
			errors.append("pickup primary option should reference item %s" % PICKUP_ITEM_ID)

	var hud_line: String = _hud_interaction_line(game_root)
	if not hud_line.contains("拾取"):
		errors.append("HUD interaction line did not show pickup prompt")
	else:
		_append_assertion(evidence, "hud_interaction_line")

	var pickup_result: Dictionary = game_root.execute_primary_interaction()
	if not bool(pickup_result.get("success", false)):
		errors.append("pickup primary interaction failed: %s" % pickup_result.get("reason", "unknown"))
	else:
		_append_assertion(evidence, "primary_pickup_execution")
	if int(_player_inventory(game_root).get(PICKUP_ITEM_ID, 0)) <= 0:
		errors.append("pickup primary interaction did not add item %s" % PICKUP_ITEM_ID)
	else:
		_append_assertion(evidence, "inventory_gain")

	await process_frame
	if game_root.find_child(PICKUP_NODE_NAME, true, false) != null:
		errors.append("consumed pickup node remained in generated scene")
	else:
		_append_assertion(evidence, "consumed_node_removed")
	return errors


func _append_assertion(evidence: Dictionary, assertion_id: String) -> void:
	var scenario: Dictionary = evidence.get("bevy_scenarios", {}).get(BEVY_SCENARIO, {})
	var assertions: Array = scenario.get("direct_assertions", [])
	if not assertions.has(assertion_id):
		assertions.append(assertion_id)
	scenario["direct_assertions"] = assertions


func _player_inventory(game_root: Node) -> Dictionary:
	for actor in game_root.simulation.snapshot().get("actors", []):
		var actor_data: Dictionary = _dictionary_or_empty(actor)
		if int(actor_data.get("actor_id", 0)) == 1:
			return actor_data.get("inventory", {})
	return {}


func _hud_interaction_line(game_root: Node) -> String:
	return game_root.hud.get_node("HudPanel/HudLines/InteractionLine").text


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
