extends SceneTree

const MapReviewDock = preload("res://addons/cdc_game_editor/map_preview_dock.gd")

var target_map_id := "survivor_outpost_01"


func _init() -> void:
	target_map_id = _target_map_id()
	_run.call_deferred()


func _run() -> void:
	var errors := await _run_checks()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("map_review_smoke passed:")
	print({
		"covered_map": target_map_id,
	})
	quit(0)


func _run_checks() -> Array[String]:
	var errors: Array[String] = []
	var dock: MapReviewDock = MapReviewDock.new()
	get_root().add_child(dock)
	await process_frame

	var result := dock.select_map(target_map_id)
	if not bool(result.get("ok", false)):
		errors.append("map review select_map failed: %s" % result)
		_cleanup(dock)
		return errors

	if str(result.get("scene_path", "")) != dock.scene_path_for_map(target_map_id):
		errors.append("map review should expose the Godot scene path for %s" % target_map_id)
	if not bool(result.get("scene_exists", false)):
		errors.append("map review should find the Godot scene for %s" % target_map_id)

	if dock.preview_root == null:
		errors.append("map review should create a preview root")
	elif dock.preview_root.get_node_or_null("GeneratedWorld") == null:
		errors.append("map review should render GeneratedWorld")

	var counts: Dictionary = result.get("counts", {})
	if int(counts.get("ground", 0)) != 1:
		errors.append("map review should render one ground mesh")
	if int(counts.get("objects", 0)) <= 0:
		errors.append("map review should render map object markers")
	if int(counts.get("cameras", 0)) <= 0:
		errors.append("map review should render a camera")

	if dock.detail == null or not dock.detail.text.contains("map_review_checks:"):
		errors.append("map review should show review checklist text")
	if dock.detail == null or not dock.detail.text.contains("scene_path:"):
		errors.append("map review should show the scene path")
	if dock.status_label == null or not dock.status_label.text.contains(target_map_id):
		errors.append("map review status should include selected map id")
	if dock.open_scene_button == null or dock.open_scene_button.disabled:
		errors.append("map review should enable Open Scene for existing map scenes")

	_cleanup(dock)
	return errors


func _cleanup(dock: MapReviewDock) -> void:
	dock.queue_free()
	await process_frame


func _target_map_id() -> String:
	var args := _tool_args()
	if args.size() >= 2 and args[0] == "map":
		return args[1]
	return "survivor_outpost_01"


func _tool_args() -> Array[String]:
	var raw := OS.get_cmdline_user_args()
	if raw.is_empty():
		raw = OS.get_cmdline_args()
	for i in range(raw.size()):
		if str(raw[i]) == "map":
			var output: Array[String] = []
			for j in range(i, raw.size()):
				output.append(str(raw[j]))
			return output
	return []
