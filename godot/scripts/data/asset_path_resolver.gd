extends RefCounted

const ContentPaths = preload("res://scripts/data/content_paths.gd")

const ASSETS_RESOURCE_ROOT := "res://assets/"
const BUILTIN_WEAPON_PREFIX := "builtin:weapon:"
const BUILTIN_ITEM_PREFIX := "builtin:item:"
const MEDIA_EXTENSIONS := {
	"jpeg": true,
	"jpg": true,
	"png": true,
	"svg": true,
	"webp": true,
}


static func resolve_model_asset(asset_id: String) -> Dictionary:
	var normalized := asset_id.strip_edges()
	if normalized.is_empty():
		return _invalid("", "missing_asset", "asset id is empty")
	if normalized.begins_with(BUILTIN_WEAPON_PREFIX):
		return _resolve_relative_gltf("preview_placeholders/placeholders/weapon_%s.gltf" % normalized.trim_prefix(BUILTIN_WEAPON_PREFIX), normalized)
	if normalized.begins_with(BUILTIN_ITEM_PREFIX):
		return _resolve_relative_gltf("preview_placeholders/placeholders/equipment_%s.gltf" % normalized.trim_prefix(BUILTIN_ITEM_PREFIX), normalized)
	return _resolve_relative_gltf(normalized, normalized)


static func resolve_equipment_visual_asset(visual_asset: String) -> Dictionary:
	return resolve_model_asset(visual_asset)


static func resolve_gltf_source_path(path: String) -> Dictionary:
	return _resolve_relative_gltf(path.strip_edges(), path.strip_edges())


static func resolve_media_asset(asset_id: String, fallback_key: String = "generic") -> Dictionary:
	var normalized := asset_id.replace("\\", "/").strip_edges()
	var fallback := fallback_key.strip_edges()
	if fallback.is_empty():
		fallback = _fallback_key_for_media_path(normalized)
	if normalized.is_empty():
		return _invalid_media("", "missing_asset", "media asset path is empty", fallback)
	if normalized.begins_with("assets/"):
		return _invalid_media(normalized, "legacy_root_asset_reference", "media asset still uses legacy root assets/ path", fallback)
	if normalized.begins_with("../assets/") or normalized.begins_with("godot/assets/"):
		return _invalid_media(normalized, "root_asset_reference", "media asset path must be relative to godot/assets or use res://assets", fallback)
	if normalized.begins_with("res://"):
		if not normalized.begins_with(ASSETS_RESOURCE_ROOT):
			return _invalid_media(normalized, "asset_outside_godot_assets", "media asset path must be under %s" % ASSETS_RESOURCE_ROOT, fallback)
		normalized = normalized.trim_prefix(ASSETS_RESOURCE_ROOT)
	if normalized.begins_with("/") or normalized.contains(":/"):
		return _invalid_media(normalized, "absolute_asset_path", "media asset path must not be absolute", fallback)
	normalized = normalized.trim_prefix("./").simplify_path()
	if normalized.begins_with("../"):
		return _invalid_media(normalized, "asset_path_escape", "media asset path must not escape godot/assets", fallback)
	var extension := normalized.get_extension().to_lower()
	if not MEDIA_EXTENSIONS.has(extension):
		return _invalid_media(normalized, "invalid_asset_format", "media asset path must reference an image file", fallback)
	var resource_path := "%s%s" % [ASSETS_RESOURCE_ROOT, normalized]
	var absolute_path := ContentPaths.assets_root().path_join(normalized).simplify_path()
	return {
		"ok": true,
		"source_id": asset_id,
		"relative_path": normalized,
		"resource_path": resource_path,
		"absolute_path": absolute_path,
		"exists": FileAccess.file_exists(absolute_path),
		"fallback_key": fallback,
		"legacy": false,
	}


static func relative_path_from_result(result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return str(result.get("relative_path", ""))
	return ""


static func resource_path_from_result(result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return str(result.get("resource_path", ""))
	return ""


static func absolute_path_from_result(result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return str(result.get("absolute_path", ""))
	return ""


static func _resolve_relative_gltf(path: String, source_id: String) -> Dictionary:
	var normalized := path.replace("\\", "/").strip_edges()
	if normalized.is_empty():
		return _invalid(source_id, "missing_asset", "asset path is empty")
	if normalized.begins_with("res://"):
		if not normalized.begins_with(ASSETS_RESOURCE_ROOT):
			return _invalid(source_id, "asset_outside_godot_assets", "asset path must be under %s" % ASSETS_RESOURCE_ROOT)
		normalized = normalized.trim_prefix(ASSETS_RESOURCE_ROOT)
	elif normalized.begins_with("assets/") or normalized.begins_with("../assets/") or normalized.begins_with("godot/assets/"):
		return _invalid(source_id, "root_asset_reference", "asset path must be relative to godot/assets or use res://assets")
	if normalized.begins_with("/") or normalized.contains(":/"):
		return _invalid(source_id, "absolute_asset_path", "asset path must not be absolute")
	normalized = normalized.trim_prefix("./").simplify_path()
	if normalized.begins_with("../"):
		return _invalid(source_id, "asset_path_escape", "asset path must not escape godot/assets")
	if not normalized.ends_with(".gltf"):
		return _invalid(source_id, "invalid_asset_format", "asset path must reference a .gltf file")
	var resource_path := "%s%s" % [ASSETS_RESOURCE_ROOT, normalized]
	var absolute_path := ContentPaths.assets_root().path_join(normalized).simplify_path()
	return {
		"ok": true,
		"source_id": source_id,
		"relative_path": normalized,
		"resource_path": resource_path,
		"absolute_path": absolute_path,
		"exists": FileAccess.file_exists(absolute_path),
	}


static func _invalid(source_id: String, reason: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"source_id": source_id,
		"reason": reason,
		"message": message,
		"relative_path": "",
		"resource_path": "",
		"absolute_path": "",
		"exists": false,
	}


static func _invalid_media(source_id: String, reason: String, message: String, fallback_key: String) -> Dictionary:
	var result := _invalid(source_id, reason, message)
	result["fallback_key"] = fallback_key
	result["legacy"] = reason == "legacy_root_asset_reference"
	return result


static func _fallback_key_for_media_path(path: String) -> String:
	var normalized := path.to_lower()
	if normalized.contains("/portraits/"):
		return "portrait"
	if normalized.contains("/ammo/"):
		return "ammo"
	if normalized.contains("/effects/"):
		return "effect"
	if normalized.contains("/weapons/"):
		return "weapon"
	if normalized.contains("/materials/"):
		return "material"
	if normalized.contains("/items/"):
		return "item"
	if normalized.contains("/locations/") or normalized.contains("/location_"):
		return "location"
	return "generic"
