extends SceneTree

const MapPreviewDock = preload("res://addons/cdc_game_editor/map_preview_dock.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors := await _run_checks()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("map_preview_smoke passed:")
	print({
		"covered_map": "survivor_outpost_01",
	})
	quit(0)


func _run_checks() -> Array[String]:
	var errors: Array[String] = []
	var dock: MapPreviewDock = MapPreviewDock.new()
	get_root().add_child(dock)
	await process_frame

	var result := dock.select_map("survivor_outpost_01")
	if not bool(result.get("ok", false)):
		errors.append("map preview select_map failed: %s" % result)
		_cleanup(dock)
		return errors

	if dock.preview_root == null:
		errors.append("map preview should create a preview root")
	elif dock.preview_root.get_node_or_null("GeneratedWorld") == null:
		errors.append("map preview should render GeneratedWorld")

	var counts: Dictionary = result.get("counts", {})
	if int(counts.get("ground", 0)) != 1:
		errors.append("map preview should render one ground mesh")
	if int(counts.get("objects", 0)) <= 0:
		errors.append("map preview should render map object markers")
	if int(counts.get("cameras", 0)) <= 0:
		errors.append("map preview should render a camera")

	if dock.detail == null or not dock.detail.text.contains("map_review_checks:"):
		errors.append("map preview should show review checklist text")
	if dock.status_label == null or not dock.status_label.text.contains("survivor_outpost_01"):
		errors.append("map preview status should include selected map id")

	_cleanup(dock)
	return errors


func _cleanup(dock: MapPreviewDock) -> void:
	dock.queue_free()
	await process_frame
