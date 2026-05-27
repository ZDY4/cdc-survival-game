extends SceneTree

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const MapEditService = preload("res://scripts/data/map_edit_service.gd")


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("map_edit_service_smoke passed:")
	print({
		"covered_domains": ["map_object"],
	})
	quit(0)


func _run() -> Array[String]:
	var errors: Array[String] = []
	var registry: ContentRegistry = ContentRegistry.new()
	var result := registry.load_all()
	if result.has_errors():
		for error in result.errors:
			errors.append(str(error))
		return errors

	var service: MapEditService = MapEditService.new()
	_expect_field_types(errors, service)
	_expect_map_object_patch(errors, service, registry)
	return errors


func _expect_field_types(errors: Array[String], service: MapEditService) -> void:
	var patch := service.normalize_map_object_patch({
		"anchor.x": "21",
		"footprint.width": "8",
		"blocks_movement": "true",
		"rotation": "east",
	})
	if typeof(patch.get("anchor.x")) != TYPE_INT:
		errors.append("anchor.x should normalize to int")
	if typeof(patch.get("footprint.width")) != TYPE_INT:
		errors.append("footprint.width should normalize to int")
	if typeof(patch.get("blocks_movement")) != TYPE_BOOL:
		errors.append("blocks_movement should normalize to bool")
	if typeof(patch.get("rotation")) != TYPE_STRING:
		errors.append("rotation should normalize to string")


func _expect_map_object_patch(errors: Array[String], service: MapEditService, registry: ContentRegistry) -> void:
	var isolated := _registry_with_temp_record(registry, "survivor_outpost_01")
	var report := service.save_map_object_patch(
		"survivor_outpost_01",
		"survivor_outpost_01_gatehouse",
		{
			"anchor.x": "21",
			"anchor.z": "32",
			"blocks_movement": "true",
		},
		isolated,
		{"allow_external_path": true}
	)
	if not bool(report.get("ok", false)):
		errors.append("map object patch failed: %s" % report)
		return
	var raw := FileAccess.get_file_as_string(str(report.get("path", "")))
	if not raw.contains("\"x\": 21"):
		errors.append("map object patch should write normalized x coordinate")
	if not raw.contains("\"blocks_movement\": true"):
		errors.append("map object patch should write normalized bool value")

	var invalid := service.save_map_object_patch(
		"survivor_outpost_01",
		"survivor_outpost_01_gatehouse",
		{"anchor.x": -1},
		isolated,
		{"allow_external_path": true}
	)
	if bool(invalid.get("ok", false)):
		errors.append("invalid map object patch should fail validation")


func _registry_with_temp_record(registry: ContentRegistry, map_id: String) -> ContentRegistry:
	var copy: ContentRegistry = ContentRegistry.new()
	copy.libraries = registry.libraries.duplicate(true)
	copy.files_by_domain = registry.files_by_domain.duplicate(true)
	copy.bootstrap_config = registry.bootstrap_config.duplicate(true)
	copy.data_root = registry.data_root
	var record: Dictionary = registry.get_library("maps").get(map_id, {}).duplicate(true)
	var data: Dictionary = record.get("data", {}).duplicate(true)
	var temp_dir := ProjectSettings.globalize_path("user://map_edit_service_smoke").simplify_path()
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
