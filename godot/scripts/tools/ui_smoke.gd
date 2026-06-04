extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const CoreRuntimeBootstrap = preload("res://scripts/core/runtime/runtime_bootstrap.gd")
const WorldSnapshotBuilder = preload("res://scripts/world/world_snapshot_builder.gd")
const HudSnapshot = preload("res://scripts/ui/snapshots/hud_snapshot.gd")
const HUD_SCENE = preload("res://scenes/ui/hud.tscn")


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
	var world_result: Dictionary = WorldSnapshotBuilder.new(registry).build_from_runtime_snapshot(simulation.snapshot())
	var pickup_prompt: Dictionary = simulation.query_interaction_options(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	var pickup_result: Dictionary = simulation.execute_interaction(1, {
		"target_type": "map_object",
		"target_id": "survivor_outpost_01_pickup_medkit",
	})
	if not bool(pickup_result.get("success", false)):
		printerr("ui smoke setup pickup failed")
		quit(1)
		return

	var snapshot: Dictionary = HudSnapshot.new().build(simulation.snapshot(), world_result, pickup_prompt)
	var hud: Control = HUD_SCENE.instantiate()
	get_root().add_child(hud)
	hud.apply_snapshot(snapshot)

	var errors := _validate_hud(hud, snapshot)
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("ui_smoke passed:")
	print(JSON.stringify({
		"world_line": hud.get_node("HudPanel/HudLines/WorldLine").text,
		"inventory_line": hud.get_node("HudPanel/HudLines/InventoryLine").text,
		"quest_line": hud.get_node("HudPanel/HudLines/QuestLine").text,
		"interaction_line": hud.get_node("HudPanel/HudLines/InteractionLine").text,
	}, "\t"))
	quit(0)


func _validate_hud(hud: Control, snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if hud.get_node_or_null("HudPanel/HudLines/WorldLine") == null:
		errors.append("missing world line")
	if not hud.get_node("HudPanel/HudLines/WorldLine").text.contains(str(snapshot.get("world", {}).get("map_id", ""))):
		errors.append("world line missing map id")
	if not hud.get_node("HudPanel/HudLines/InventoryLine").text.contains("1006"):
		errors.append("inventory line missing picked item")
	if hud.get_node_or_null("HudPanel/HudLines/QuestLine") == null:
		errors.append("missing quest line")
	elif not hud.get_node("HudPanel/HudLines/QuestLine").text.contains("Quest none"):
		errors.append("quest line should show empty tracked quest state")
	if hud.get_node_or_null("HudPanel/HudLines/HotbarDock") == null:
		errors.append("missing hotbar dock")
	else:
		var hotbar_dock: Node = hud.get_node("HudPanel/HudLines/HotbarDock")
		if hotbar_dock.get_child_count() != 10:
			errors.append("hotbar dock should expose ten slots")
		var first_slot: Node = hotbar_dock.get_node_or_null("HotbarSlot_slot_1")
		if not (first_slot is Button) or not str((first_slot as Button).text).contains("1:-"):
			errors.append("empty hotbar slot should show key and empty marker")
		if first_slot is Button and not str((first_slot as Button).tooltip_text).contains("空"):
			errors.append("empty hotbar slot should expose empty tooltip")
	if not hud.get_node("HudPanel/HudLines/InteractionLine").text.contains("拾取"):
		errors.append("interaction line missing pickup option")
	if typeof(snapshot.get("hotbar", [])) != TYPE_ARRAY or snapshot.get("hotbar", []).size() != 10:
		errors.append("HUD snapshot should expose ten hotbar slots")
	if not snapshot.has("tracked_quest") or bool(snapshot.get("tracked_quest", {}).get("active", true)):
		errors.append("HUD snapshot should expose inactive tracked quest by default")
	var interaction: Dictionary = snapshot.get("interaction", {})
	if str(interaction.get("target_kind", "")) != "pickup":
		errors.append("HUD snapshot should expose interaction target_kind")
	if str(interaction.get("primary_option_kind", "")) != "pickup":
		errors.append("HUD snapshot should expose primary_option_kind")
	if str(interaction.get("action_label", "")) != "拾取":
		errors.append("HUD snapshot should expose action_label")
	if absf(float(interaction.get("ap_cost", -1.0)) - 1.0) > 0.001:
		errors.append("HUD snapshot should expose ap_cost")
	if typeof(interaction.get("disabled_options", [])) != TYPE_ARRAY:
		errors.append("HUD snapshot should expose disabled_options")
	return errors
