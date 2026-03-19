@tool
extends RefCounted

var host_editor: Object = null
var editor_plugin: EditorPlugin = null
var repository: RefCounted = null
var context_builder: RefCounted = null
var data_type: String = ""


func setup(
	target_host_editor: Object,
	target_editor_plugin: EditorPlugin,
	target_repository: RefCounted,
	target_context_builder: RefCounted,
	target_data_type: String
) -> void:
	host_editor = target_host_editor
	editor_plugin = target_editor_plugin
	repository = target_repository
	context_builder = target_context_builder
	data_type = target_data_type


func build_context(request: Dictionary) -> Dictionary:
	var seed_context: Dictionary = {}
	if host_editor != null and host_editor.has_method("build_ai_seed_context"):
		var built: Variant = host_editor.call("build_ai_seed_context")
		if built is Dictionary:
			seed_context = (built as Dictionary).duplicate(true)
	var max_records := preload("res://addons/cdc_game_editor/ai/ai_settings.gd").get_max_context_records(editor_plugin)
	return context_builder.build_context(data_type, request, seed_context, max_records)


func validate_draft(draft: Dictionary) -> Array[String]:
	if host_editor == null or not host_editor.has_method("get_ai_validation_errors"):
		return []
	var errors := host_editor.call("get_ai_validation_errors", draft)
	return errors if errors is Array else []


func apply_draft(draft: Dictionary) -> bool:
	if host_editor == null or not host_editor.has_method("apply_ai_draft"):
		return false
	return bool(host_editor.call("apply_ai_draft", draft))


func get_generation_rules() -> Array[String]:
	return []


func summarize_record_changes(before: Dictionary, after: Dictionary) -> Dictionary:
	return _build_diff_summary(before, after, [])


func _build_diff_summary(before: Dictionary, after: Dictionary, custom_summary_lines: Array[String]) -> Dictionary:
	var diff := {
		"added_paths": [],
		"changed_paths": [],
		"removed_paths": []
	}
	_collect_diff_paths(before, after, "", diff)

	var summary_lines: Array[String] = []
	summary_lines.append_array(_dedupe_string_array(custom_summary_lines))
	if diff["added_paths"].size() > 0:
		summary_lines.append("新增字段 %d 个" % diff["added_paths"].size())
	if diff["changed_paths"].size() > 0:
		summary_lines.append("修改字段 %d 个" % diff["changed_paths"].size())
	if diff["removed_paths"].size() > 0:
		summary_lines.append("删除字段 %d 个" % diff["removed_paths"].size())
	if summary_lines.is_empty():
		summary_lines.append("草稿与当前记录没有结构差异")

	var risk_level := "low"
	if diff["removed_paths"].size() > 0 or _has_primary_id_change(before, after):
		risk_level = "high"
	elif diff["added_paths"].size() > 0 or diff["changed_paths"].size() > 0:
		risk_level = "medium"

	return {
		"summary_lines": _dedupe_string_array(summary_lines),
		"added_paths": _dedupe_string_array(diff["added_paths"]),
		"changed_paths": _dedupe_string_array(diff["changed_paths"]),
		"removed_paths": _dedupe_string_array(diff["removed_paths"]),
		"risk_level": risk_level
	}


func _collect_diff_paths(before_value: Variant, after_value: Variant, path: String, diff: Dictionary) -> void:
	if before_value is Dictionary and after_value is Dictionary:
		var before_dict := before_value as Dictionary
		var after_dict := after_value as Dictionary
		var all_keys: Array[String] = []
		for key in before_dict.keys():
			all_keys.append(str(key))
		for key in after_dict.keys():
			var key_text := str(key)
			if not all_keys.has(key_text):
				all_keys.append(key_text)
		all_keys.sort()

		for key_text in all_keys:
			var child_path := _append_path(path, key_text)
			var in_before := before_dict.has(key_text)
			var in_after := after_dict.has(key_text)
			if not in_before and in_after:
				diff["added_paths"].append(child_path)
				continue
			if in_before and not in_after:
				diff["removed_paths"].append(child_path)
				continue
			_collect_diff_paths(before_dict.get(key_text), after_dict.get(key_text), child_path, diff)
		return

	if before_value is Array and after_value is Array:
		var before_array := before_value as Array
		var after_array := after_value as Array
		var max_size := maxi(before_array.size(), after_array.size())
		for index in range(max_size):
			var child_path := "%s[%d]" % [path if not path.is_empty() else "root", index]
			var has_before := index < before_array.size()
			var has_after := index < after_array.size()
			if not has_before and has_after:
				diff["added_paths"].append(child_path)
				continue
			if has_before and not has_after:
				diff["removed_paths"].append(child_path)
				continue
			_collect_diff_paths(before_array[index], after_array[index], child_path, diff)
		return

	if not _variant_equals(before_value, after_value):
		diff["changed_paths"].append(path if not path.is_empty() else "root")


func _append_path(parent_path: String, child_key: String) -> String:
	if parent_path.is_empty():
		return child_key
	return "%s.%s" % [parent_path, child_key]


func _variant_equals(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		return JSON.stringify(left) == JSON.stringify(right)
	if left is Array and right is Array:
		return JSON.stringify(left) == JSON.stringify(right)
	return left == right


func _dedupe_string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value).strip_edges()
		if text.is_empty() or result.has(text):
			continue
		result.append(text)
	return result


func _has_any_paths(diff_summary: Dictionary, prefixes: Array[String]) -> bool:
	var all_paths: Array[String] = []
	for key in ["added_paths", "changed_paths", "removed_paths"]:
		for value in diff_summary.get(key, []):
			all_paths.append(str(value))
	for path in all_paths:
		for prefix in prefixes:
			if path == prefix or path.begins_with("%s." % prefix) or path.begins_with("%s[" % prefix):
				return true
	return false


func _has_primary_id_change(before: Dictionary, after: Dictionary) -> bool:
	for key in ["id", "dialog_id", "quest_id"]:
		var before_id := str(before.get(key, "")).strip_edges()
		var after_id := str(after.get(key, "")).strip_edges()
		if before_id.is_empty() or after_id.is_empty():
			continue
		if before_id != after_id:
			return true
	return false
