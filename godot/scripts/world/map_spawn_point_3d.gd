@tool
class_name MapSpawnPoint3D
extends Marker3D

const GROUP_NAME := "map_scene_object"

@export var object_id: String = ""
@export var character_id: String = ""
@export var spawn_id: String = ""
@export var spawn_radius: float = 1.0
@export var auto_spawn: bool = true
@export var respawn_enabled: bool = true
@export var respawn_delay: float = 24.0
@export_multiline var props_json: String = "{}"


func _enter_tree() -> void:
	add_to_group(GROUP_NAME)


func _ready() -> void:
	_ensure_editor_marker()


func to_object_definition() -> Dictionary:
	return {
		"object_id": object_id,
		"kind": "ai_spawn",
		"anchor": {
			"x": int(round(position.x)),
			"y": int(round(position.y)),
			"z": int(round(position.z)),
		},
		"footprint": {"width": 1, "height": 1},
		"rotation": "north",
		"blocks_movement": false,
		"blocks_sight": false,
		"props": _props_dictionary(),
	}


func _props_dictionary() -> Dictionary:
	var props := _json_dictionary(props_json, "props_json")
	var spawn := _dictionary_or_empty(props.get("ai_spawn", {})).duplicate(true)
	if not character_id.strip_edges().is_empty():
		spawn["character_id"] = character_id
	if not spawn_id.strip_edges().is_empty():
		spawn["spawn_id"] = spawn_id
	spawn["spawn_radius"] = spawn_radius
	spawn["auto_spawn"] = auto_spawn
	spawn["respawn_enabled"] = respawn_enabled
	spawn["respawn_delay"] = respawn_delay
	props["ai_spawn"] = spawn
	return props


func _json_dictionary(raw_json: String, field_name: String) -> Dictionary:
	var raw := raw_json.strip_edges()
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	push_warning("地图刷怪点 %s 的 %s 不是合法 Dictionary" % [object_id, field_name])
	return {}


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _ensure_editor_marker() -> void:
	if not Engine.is_editor_hint():
		return
	if get_node_or_null("SpawnPreview") != null:
		return
	var mesh := SphereMesh.new()
	mesh.radius = max(0.12, spawn_radius * 0.12)
	mesh.height = max(0.24, spawn_radius * 0.24)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.82, 0.18, 0.12, 0.68)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var preview := MeshInstance3D.new()
	preview.name = "SpawnPreview"
	preview.mesh = mesh
	preview.material_override = material
	add_child(preview)
	if owner != null:
		preview.owner = owner
