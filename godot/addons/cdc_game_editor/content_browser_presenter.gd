@tool
extends RefCounted

const ContentRegistry = preload("res://scripts/data/content_registry.gd")
const ContentRecordValidator = preload("res://scripts/tools/content_record_validator.gd")
const EditorContentPresenter = preload("res://addons/cdc_game_editor/editor_content_presenter.gd")

const BROWSER_KINDS := ["item", "recipe", "character", "map"]


func supported_kinds() -> Array[String]:
	return BROWSER_KINDS.duplicate()


func rows_for_kind(kind: String, registry: ContentRegistry, filter_text: String = "") -> Array[Dictionary]:
	var presenter := EditorContentPresenter.new()
	var domain := presenter.domain_for_kind(kind)
	if domain.is_empty() or not BROWSER_KINDS.has(kind):
		return []

	var rows: Array[Dictionary] = []
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var normalized_filter := filter_text.strip_edges().to_lower()
	for id_value in registry.get_library(domain).keys():
		var id_string := str(id_value)
		var record: Dictionary = registry.get_library(domain).get(id_string, {})
		var data: Dictionary = _dictionary_or_empty(record.get("data", {}))
		var label := _label_for_record(domain, data)
		if not normalized_filter.is_empty():
			var haystack := "%s %s" % [id_string.to_lower(), label.to_lower()]
			if not haystack.contains(normalized_filter):
				continue
		var validation := validator.validate_record(domain, id_string, registry)
		rows.append({
			"kind": kind,
			"id": id_string,
			"label": label,
			"path": _repo_relative_path(str(record.get("path", ""))),
			"status": validation.get("status", "invalid"),
			"issue_count": _issue_count(validation.get("issues", [])),
		})
	rows.sort_custom(_sort_rows)
	return rows


func build_overview(registry: ContentRegistry) -> Dictionary:
	var output := {
		"kinds": {},
		"total_records": 0,
		"invalid_records": 0,
	}
	for kind in BROWSER_KINDS:
		var rows := rows_for_kind(kind, registry)
		var invalid_count := 0
		for row in rows:
			var row_data: Dictionary = row
			if str(row_data.get("status", "")) != "ok":
				invalid_count += 1
		output["kinds"][kind] = {
			"records": rows.size(),
			"invalid": invalid_count,
		}
		output["total_records"] = int(output["total_records"]) + rows.size()
		output["invalid_records"] = int(output["invalid_records"]) + invalid_count
	return output


func build_detail(kind: String, id_value: String, registry: ContentRegistry, repo_root: String) -> Dictionary:
	if not BROWSER_KINDS.has(kind):
		return {
			"ok": false,
			"message": "Unsupported browser kind %s." % kind,
			"text": "Supported browser kinds: %s." % ", ".join(BROWSER_KINDS),
		}

	var presenter := EditorContentPresenter.new()
	var selection := presenter.build_selection(kind, id_value, registry, repo_root)
	if not bool(selection.get("ok", false)):
		return {
			"ok": false,
			"message": selection.get("message", "Failed to select content."),
			"text": selection.get("message", "Failed to select content."),
		}

	var domain := presenter.domain_for_kind(kind)
	var validator: ContentRecordValidator = ContentRecordValidator.new()
	var validation := validator.validate_record(domain, str(selection.get("id", "")), registry)
	var sections: Array[String] = [
		str(selection.get("summary", "")),
		_validation_text(validation),
		str(selection.get("reference_summary", "")),
	]
	for field in ["edit_plan_summary", "edit_plan_checklist", "review_summary", "review_checklist"]:
		var text := str(selection.get(field, ""))
		if not text.is_empty():
			sections.append(text)
	return {
		"ok": true,
		"kind": kind,
		"id": selection.get("id", ""),
		"path": selection.get("path", ""),
		"status": validation.get("status", "invalid"),
		"text": "\n\n".join(sections),
	}


func _validation_text(validation: Dictionary) -> String:
	var lines: Array[String] = [
		"validation:",
		"status: %s" % validation.get("status", "invalid"),
		"issues: %d" % _issue_count(validation.get("issues", [])),
	]
	for issue in validation.get("issues", []):
		var issue_data: Dictionary = _dictionary_or_empty(issue)
		lines.append("- [%s] %s: %s (%s)" % [
			issue_data.get("severity", "error"),
			issue_data.get("code", "validation_error"),
			issue_data.get("message", ""),
			issue_data.get("field", "$"),
		])
	return "\n".join(lines)


func _label_for_record(domain: String, data: Dictionary) -> String:
	match domain:
		"items", "recipes":
			return str(data.get("name", ""))
		"characters":
			return str(_dictionary_or_empty(data.get("identity", {})).get("display_name", ""))
		"maps":
			return str(data.get("name", ""))
	return ""


func _sort_rows(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("id", "")) < str(right.get("id", ""))


func _issue_count(issues: Variant) -> int:
	if typeof(issues) != TYPE_ARRAY:
		return 0
	return (issues as Array).size()


func _repo_relative_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	var marker := "/data/"
	var index := normalized.find(marker)
	if index >= 0:
		return normalized.substr(index + 1)
	return normalized


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
