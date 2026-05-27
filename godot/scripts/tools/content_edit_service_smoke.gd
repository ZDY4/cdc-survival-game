extends SceneTree

const ContentEditService = preload("res://scripts/data/content_edit_service.gd")
const ContentRegistry = preload("res://scripts/data/content_registry.gd")


func _init() -> void:
	var errors := _run()
	if not errors.is_empty():
		for error in errors:
			printerr(error)
		quit(1)
		return

	print("content_edit_service_smoke passed:")
	print({
		"covered_domains": ["item", "recipe", "character", "map"],
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

	var service: ContentEditService = ContentEditService.new()
	_expect_editable_fields(errors, service)
	_expect_field_types(errors, service)
	_expect_patch(errors, service, registry, "items", "1006", {"name": "绷带 smoke"})
	_expect_patch(errors, service, registry, "recipes", "recipe_first_aid_kit", {"craft_time": 31.0})
	_expect_patch(errors, service, registry, "characters", "zombie_walker", {"identity.display_name": "行尸 smoke"})
	_expect_patch(errors, service, registry, "maps", "survivor_outpost_01", {"name": "survivor outpost smoke"})
	_expect_invalid_patch(errors, service, registry)
	return errors


func _expect_editable_fields(errors: Array[String], service: ContentEditService) -> void:
	for domain in ["items", "recipes", "characters", "maps"]:
		if service.editable_fields(domain).is_empty():
			errors.append("content edit service has no editable fields for %s" % domain)


func _expect_field_types(errors: Array[String], service: ContentEditService) -> void:
	var patch := service.normalize_patch("recipes", {
		"craft_time": "31.5",
		"experience_reward": "17",
		"is_default_unlocked": "true",
	})
	if typeof(patch.get("craft_time")) != TYPE_FLOAT:
		errors.append("craft_time should normalize to float")
	if typeof(patch.get("experience_reward")) != TYPE_INT:
		errors.append("experience_reward should normalize to int")
	if typeof(patch.get("is_default_unlocked")) != TYPE_BOOL:
		errors.append("is_default_unlocked should normalize to bool")


func _expect_patch(errors: Array[String], service: ContentEditService, registry: ContentRegistry, domain: String, id_value: String, patch: Dictionary) -> void:
	var isolated := _registry_with_temp_record(registry, domain, id_value)
	var report := service.save_patch(domain, id_value, patch, isolated, {"allow_external_path": true})
	if not bool(report.get("ok", false)):
		errors.append("patch failed for %s %s: %s" % [domain, id_value, report])
		return
	if not bool(report.get("changed", false)):
		errors.append("patch should report changed for %s %s" % [domain, id_value])
	var path := str(report.get("path", ""))
	var raw := FileAccess.get_file_as_string(path)
	for field in patch.keys():
		if not raw.contains(str(patch[field])):
			errors.append("patched file %s does not contain value for %s" % [path, field])


func _expect_invalid_patch(errors: Array[String], service: ContentEditService, registry: ContentRegistry) -> void:
	var isolated := _registry_with_temp_record(registry, "recipes", "recipe_first_aid_kit")
	var report := service.save_patch("recipes", "recipe_first_aid_kit", {"craft_time": -1.0}, isolated, {"allow_external_path": true})
	if bool(report.get("ok", false)):
		errors.append("invalid patch should fail validation")
	if str(report.get("code", "")) != "validation_failed":
		errors.append("invalid patch should return validation_failed, got %s" % report)
	var persisted := FileAccess.get_file_as_string(str(isolated.get_library("recipes")["recipe_first_aid_kit"].get("path", "")))
	if persisted.contains("-1"):
		errors.append("invalid patch should not be written to disk")


func _registry_with_temp_record(registry: ContentRegistry, domain: String, id_value: String) -> ContentRegistry:
	var copy: ContentRegistry = ContentRegistry.new()
	copy.libraries = registry.libraries.duplicate(true)
	copy.files_by_domain = registry.files_by_domain.duplicate(true)
	copy.bootstrap_config = registry.bootstrap_config.duplicate(true)
	copy.data_root = registry.data_root
	var record: Dictionary = registry.get_library(domain).get(id_value, {}).duplicate(true)
	var data: Dictionary = record.get("data", {}).duplicate(true)
	var temp_dir := ProjectSettings.globalize_path("user://content_edit_service_smoke").simplify_path()
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var temp_path := temp_dir.path_join("%s_%s.json" % [domain, id_value])
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  ") + "\n")
	record["path"] = temp_path
	record["data"] = data
	var library: Dictionary = copy.libraries.get(domain, {}).duplicate(true)
	library[id_value] = record
	copy.libraries[domain] = library
	return copy
