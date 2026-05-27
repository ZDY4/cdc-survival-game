extends RefCounted

var errors: Array[String] = []
var warnings: Array[String] = []


func add_error(path: String, content_id: String, field: String, message: String) -> void:
	errors.append(_format_issue("ERROR", path, content_id, field, message))


func add_warning(path: String, content_id: String, field: String, message: String) -> void:
	warnings.append(_format_issue("WARN", path, content_id, field, message))


func merge(other: RefCounted) -> void:
	errors.append_array(other.errors)
	warnings.append_array(other.warnings)


func has_errors() -> bool:
	return not errors.is_empty()


func _format_issue(level: String, path: String, content_id: String, field: String, message: String) -> String:
	var label := content_id
	if label.is_empty():
		label = "<unknown>"
	return "%s %s [%s] %s: %s" % [level, path, label, field, message]
