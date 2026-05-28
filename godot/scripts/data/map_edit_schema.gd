extends RefCounted

# 地图编辑白名单只描述迁移期可安全写回的字段，地图内容结构仍由 data/ 与校验器约束。
const MAP_OBJECT_FIELD_TYPES := {
	"anchor.x": "int",
	"anchor.y": "int",
	"anchor.z": "int",
	"footprint.width": "int",
	"footprint.height": "int",
	"rotation": "string",
	"blocks_movement": "bool",
	"blocks_sight": "bool",
}

const ENTRY_POINT_FIELD_TYPES := {
	"grid.x": "int",
	"grid.y": "int",
	"grid.z": "int",
	"facing": "string",
}


func map_object_editable_fields() -> Array[String]:
	return _sorted_keys(MAP_OBJECT_FIELD_TYPES)


func map_object_field_type(field_path: String) -> String:
	return str(MAP_OBJECT_FIELD_TYPES.get(field_path, "string"))


func can_edit_map_object_field(field_path: String) -> bool:
	return MAP_OBJECT_FIELD_TYPES.has(field_path)


func normalize_map_object_patch(raw_patch: Dictionary) -> Dictionary:
	return _normalize_patch(raw_patch, MAP_OBJECT_FIELD_TYPES)


func entry_point_editable_fields() -> Array[String]:
	return _sorted_keys(ENTRY_POINT_FIELD_TYPES)


func entry_point_field_type(field_path: String) -> String:
	return str(ENTRY_POINT_FIELD_TYPES.get(field_path, "string"))


func can_edit_entry_point_field(field_path: String) -> bool:
	return ENTRY_POINT_FIELD_TYPES.has(field_path)


func normalize_entry_point_patch(raw_patch: Dictionary) -> Dictionary:
	return _normalize_patch(raw_patch, ENTRY_POINT_FIELD_TYPES)


func _normalize_patch(raw_patch: Dictionary, field_types: Dictionary) -> Dictionary:
	var patch: Dictionary = {}
	for field in raw_patch.keys():
		var field_path := str(field)
		patch[field_path] = _coerce_value(raw_patch[field], str(field_types.get(field_path, "string")))
	return patch


func _coerce_value(value: Variant, value_type: String) -> Variant:
	match value_type:
		"int":
			return int(value)
		"float":
			return float(value)
		"bool":
			if typeof(value) == TYPE_BOOL:
				return value
			var text := str(value).strip_edges().to_lower()
			return ["true", "1", "yes", "on"].has(text)
		_:
			return str(value)


func _sorted_keys(value: Dictionary) -> Array[String]:
	var fields: Array[String] = []
	for field in value.keys():
		fields.append(str(field))
	fields.sort()
	return fields
