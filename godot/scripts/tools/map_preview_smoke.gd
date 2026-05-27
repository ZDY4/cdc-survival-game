extends SceneTree

const MapPreviewDock = preload("res://addons/cdc_game_editor/map_preview_dock.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")


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
	_expect_object_editing(errors, dock)

	_cleanup(dock)
	return errors


func _expect_object_editing(errors: Array[String], dock: MapPreviewDock) -> void:
	dock.registry = _registry_with_temp_record(dock.registry, "survivor_outpost_01")
	var result := dock.select_map("survivor_outpost_01")
	if not bool(result.get("ok", false)):
		errors.append("map preview temp select_map failed: %s" % result)
		return
	dock.selected_object_id = "survivor_outpost_01_gatehouse"
	dock._refresh_object_form(dock._map_object_data(dock.selected_map_id, dock.selected_object_id))
	if dock.object_inputs.is_empty():
		errors.append("map preview should build object edit inputs")
		return

	var anchor_x: SpinBox = dock.object_inputs.get("anchor.x", null)
	var blocks_movement: CheckBox = dock.object_inputs.get("blocks_movement", null)
	if anchor_x == null:
		errors.append("map preview object form missing anchor.x editor")
		return
	if blocks_movement == null:
		errors.append("map preview object form missing blocks_movement editor")
		return
	anchor_x.value = 21
	blocks_movement.button_pressed = true
	var patch := dock.build_object_patch_from_inputs()
	if typeof(patch.get("anchor.x")) != TYPE_INT:
		errors.append("map preview object patch should preserve int values")
	if typeof(patch.get("blocks_movement")) != TYPE_BOOL:
		errors.append("map preview object patch should preserve bool values")

	var dry_run := dock.apply_object_patch(patch, true, {"allow_external_path": true})
	if not bool(dry_run.get("ok", false)):
		errors.append("map preview object dry run failed: %s" % dry_run)

	var saved := dock.apply_object_patch(patch, false, {"allow_external_path": true})
	if not bool(saved.get("ok", false)):
		errors.append("map preview object save failed: %s" % saved)
		return
	var raw := FileAccess.get_file_as_string(str(saved.get("path", "")))
	if not raw.contains("\"x\": 21"):
		errors.append("map preview object save should write updated x coordinate")


func _cleanup(dock: MapPreviewDock) -> void:
	dock.queue_free()
	await process_frame


func _registry_with_temp_record(registry: ContentRegistry, map_id: String) -> ContentRegistry:
	var copy: ContentRegistry = ContentRegistry.new()
	copy.libraries = registry.libraries.duplicate(true)
	copy.files_by_domain = registry.files_by_domain.duplicate(true)
	copy.bootstrap_config = registry.bootstrap_config.duplicate(true)
	copy.data_root = registry.data_root
	var record: Dictionary = registry.get_library("maps").get(map_id, {}).duplicate(true)
	var data: Dictionary = record.get("data", {}).duplicate(true)
	var temp_dir := ProjectSettings.globalize_path("user://map_preview_smoke").simplify_path()
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var temp_path := temp_dir.path_join("maps_%s.json" % map_id)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  ") + "\n")
	record["path"] = temp_path
	record["data"] = data
	var library: Dictionary = copy.libraries.get("maps", {}).duplicate(true)
	library[map_id] = record
	copy.libraries["maps"] = library
	return copy
