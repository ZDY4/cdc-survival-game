@tool
extends EditorInspectorPlugin

const SINGLE_TAG_MARKER: String = "gameplay_tag"
const TAG_ARRAY_MARKER: String = "gameplay_tags"
const EDITOR_PROPERTY_SCRIPT := preload("res://addons/gameplay_tags/editor/gameplay_tag_editor_property.gd")

var _editor_plugin: EditorPlugin = null

func _init(editor_plugin: EditorPlugin = null) -> void:
	_editor_plugin = editor_plugin

func _can_handle(_object: Object) -> bool:
	return true

func _parse_property(
	_object: Object,
	type: int,
	name: String,
	_hint_type: int,
	hint_string: String,
	usage_flags: int,
	_wide: bool
) -> bool:
	if (usage_flags & PROPERTY_USAGE_EDITOR) == 0:
		return false

	var property_mode: String = _resolve_property_mode(type, hint_string)
	if property_mode.is_empty():
		return false

	var editor_property: EditorProperty = EDITOR_PROPERTY_SCRIPT.new()
	editor_property.setup(name, property_mode, _editor_plugin)
	add_property_editor(name, editor_property)
	return true

func _resolve_property_mode(type: int, hint_string: String) -> String:
	var marker: String = _extract_marker(hint_string)
	if marker == SINGLE_TAG_MARKER and (type == TYPE_STRING_NAME or type == TYPE_STRING):
		return SINGLE_TAG_MARKER
	if marker == TAG_ARRAY_MARKER and type == TYPE_ARRAY:
		return TAG_ARRAY_MARKER
	return ""

func _extract_marker(hint_string: String) -> String:
	var normalized_hint: String = hint_string.strip_edges()
	if normalized_hint.is_empty():
		return ""

	var comma_index: int = normalized_hint.find(",")
	if comma_index >= 0:
		normalized_hint = normalized_hint.substr(0, comma_index).strip_edges()
	return normalized_hint
