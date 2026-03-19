extends Node
## GameplayTagsManager - Global hierarchical gameplay tag registry.

const DEFAULT_CONFIG_PATH: String = "res://config/gameplay_tags.ini"
const TAGS_SECTION_NAME: String = "GameplayTags"
const TAG_DECLARATION_KEY: String = "GameplayTagList"

signal registry_reloaded(tag_count: int, warning_count: int)
signal registry_changed()

var _explicit_tags: Dictionary = {}
var _all_tags: Dictionary = {}
var _parents_by_tag: Dictionary = {}
var _parse_warnings: Array[String] = []
var _loaded_config_path: String = DEFAULT_CONFIG_PATH
var _last_error: String = ""
var _tag_regex: RegEx = RegEx.new()

func _init() -> void:
	var compile_result: int = _tag_regex.compile("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)*$")
	if compile_result != OK:
		push_error("[GameplayTags] Failed to compile tag validation regex.")

func _ready() -> void:
	reload_tags()

func request_tag(tag_name: String, error_if_not_found: bool = true) -> StringName:
	var normalized: String = _normalize_tag_name(tag_name)
	if normalized.is_empty():
		_set_last_error("Tag cannot be empty.")
		if error_if_not_found:
			push_error("[GameplayTags] %s" % _last_error)
		return StringName()

	if not _is_valid_tag_format(normalized):
		_set_last_error("Tag '%s' has invalid format." % normalized)
		if error_if_not_found:
			push_error("[GameplayTags] %s" % _last_error)
		return StringName()

	var tag_name_id: StringName = StringName(normalized)
	if not _all_tags.has(tag_name_id):
		_set_last_error("Tag '%s' not found in registry." % normalized)
		if error_if_not_found:
			push_error("[GameplayTags] %s" % _last_error)
		return StringName()

	_last_error = ""
	return tag_name_id

func is_valid_tag(tag_name: StringName) -> bool:
	return _all_tags.has(tag_name)

func matches_tag(tag_a: StringName, tag_b: StringName, exact: bool = false) -> bool:
	var a_text: String = String(tag_a)
	var b_text: String = String(tag_b)
	if a_text.is_empty() or b_text.is_empty():
		return false
	if exact:
		return a_text == b_text
	return a_text == b_text or a_text.begins_with("%s." % b_text)

func make_container(tags: Array[StringName]) -> GameplayTagContainer:
	var container: GameplayTagContainer = GameplayTagContainer.new()
	for tag_name in tags:
		container.add_tag(tag_name)
	return container

func evaluate_query(container: GameplayTagContainer, query: GameplayTagQuery) -> bool:
	if container == null or query == null:
		return false
	return query.evaluate(container)

func reload_tags(config_path: String = "") -> bool:
	var target_path: String = _resolve_config_path(config_path)
	_loaded_config_path = target_path
	_last_error = ""
	_parse_warnings.clear()
	_explicit_tags.clear()

	if not FileAccess.file_exists(target_path):
		_set_last_error("Config file does not exist: %s" % target_path)
		push_warning("[GameplayTags] %s" % _last_error)
		_rebuild_hierarchy_cache()
		registry_reloaded.emit(_all_tags.size(), _parse_warnings.size())
		return false

	var file: FileAccess = FileAccess.open(target_path, FileAccess.READ)
	if file == null:
		_set_last_error("Failed to open config file: %s" % target_path)
		push_error("[GameplayTags] %s" % _last_error)
		_rebuild_hierarchy_cache()
		registry_reloaded.emit(_all_tags.size(), _parse_warnings.size())
		return false

	var in_tags_section: bool = false
	var line_index: int = 0
	while not file.eof_reached():
		line_index += 1
		var raw_line: String = file.get_line()
		var line: String = _strip_inline_comment(raw_line).strip_edges()
		if line.is_empty():
			continue

		if line.begins_with("[") and line.ends_with("]"):
			var section_name: String = line.substr(1, line.length() - 2).strip_edges()
			in_tags_section = section_name == TAGS_SECTION_NAME
			continue

		if not in_tags_section:
			continue

		var declaration: String = line.trim_prefix("+")
		if not declaration.begins_with("%s=" % TAG_DECLARATION_KEY):
			_parse_warnings.append("Line %d ignored: %s" % [line_index, line])
			continue

		var parsed_tag: String = _extract_tag_from_declaration(declaration)
		if parsed_tag.is_empty():
			_parse_warnings.append("Line %d ignored: empty tag declaration." % line_index)
			continue

		if not _is_valid_tag_format(parsed_tag):
			_parse_warnings.append("Line %d ignored: invalid tag '%s'." % [line_index, parsed_tag])
			continue

		_explicit_tags[StringName(parsed_tag)] = true

	_rebuild_hierarchy_cache()
	registry_reloaded.emit(_all_tags.size(), _parse_warnings.size())
	return true

func save_registry(config_path: String = "") -> bool:
	var target_path: String = _resolve_config_path(config_path)
	var absolute_dir: String = ProjectSettings.globalize_path(target_path).get_base_dir()
	var mkdir_result: int = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_result != OK:
		_set_last_error("Failed to create directory for config: %s" % absolute_dir)
		push_error("[GameplayTags] %s" % _last_error)
		return false

	var file: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_set_last_error("Failed to open config file for writing: %s" % target_path)
		push_error("[GameplayTags] %s" % _last_error)
		return false

	file.store_line("; Gameplay Tags registry")
	file.store_line("[GameplayTags]")
	var sorted_tags: Array[StringName] = get_explicit_tags()
	for tag_name in sorted_tags:
		file.store_line("+GameplayTagList=\"%s\"" % String(tag_name))

	_loaded_config_path = target_path
	_last_error = ""
	return true

func add_explicit_tag(tag_name: String) -> bool:
	var normalized: String = _normalize_tag_name(tag_name)
	if normalized.is_empty():
		_set_last_error("Tag cannot be empty.")
		return false
	if not _is_valid_tag_format(normalized):
		_set_last_error("Tag '%s' has invalid format." % normalized)
		return false

	var tag_key: StringName = StringName(normalized)
	if _explicit_tags.has(tag_key):
		_set_last_error("Tag '%s' already exists." % normalized)
		return false

	_explicit_tags[tag_key] = true
	_rebuild_hierarchy_cache()
	_last_error = ""
	registry_changed.emit()
	return true

func remove_explicit_tag(tag_name: StringName, include_children: bool = false) -> bool:
	var target: String = _normalize_tag_name(String(tag_name))
	if target.is_empty():
		_set_last_error("Tag cannot be empty.")
		return false

	var removed_any: bool = false
	var target_key: StringName = StringName(target)

	if include_children:
		for explicit_tag in _explicit_tags.keys().duplicate():
			var explicit_text: String = String(explicit_tag)
			if explicit_text == target or explicit_text.begins_with("%s." % target):
				_explicit_tags.erase(explicit_tag)
				removed_any = true
	else:
		if _explicit_tags.has(target_key):
			_explicit_tags.erase(target_key)
			removed_any = true

	if not removed_any:
		_set_last_error("Tag '%s' was not found in explicit registry." % target)
		return false

	_rebuild_hierarchy_cache()
	_last_error = ""
	registry_changed.emit()
	return true

func rename_tag(old_tag: StringName, new_tag: String, include_children: bool = true) -> bool:
	var old_normalized: String = _normalize_tag_name(String(old_tag))
	var new_normalized: String = _normalize_tag_name(new_tag)

	if old_normalized.is_empty() or new_normalized.is_empty():
		_set_last_error("Both old and new tag names are required.")
		return false
	if not _is_valid_tag_format(new_normalized):
		_set_last_error("Tag '%s' has invalid format." % new_normalized)
		return false

	var replaced_tags: Array[String] = []
	var retained_tags: Array[String] = []
	for explicit_tag in _explicit_tags.keys():
		var explicit_text: String = String(explicit_tag)
		var is_target: bool = explicit_text == old_normalized
		var is_child: bool = explicit_text.begins_with("%s." % old_normalized)
		if is_target or (include_children and is_child):
			replaced_tags.append(explicit_text)
		else:
			retained_tags.append(explicit_text)

	if replaced_tags.is_empty():
		_set_last_error("Tag '%s' not found for rename." % old_normalized)
		return false

	var retained_lookup: Dictionary = {}
	for retained_tag in retained_tags:
		retained_lookup[retained_tag] = true

	var renamed_tags: Array[String] = []
	var renamed_lookup: Dictionary = {}
	for source_tag in replaced_tags:
		var suffix: String = source_tag.substr(old_normalized.length())
		var candidate: String = "%s%s" % [new_normalized, suffix]
		if retained_lookup.has(candidate):
			_set_last_error("Rename conflict: '%s' already exists." % candidate)
			return false
		if renamed_lookup.has(candidate):
			_set_last_error("Rename conflict: duplicate generated tag '%s'." % candidate)
			return false
		if not _is_valid_tag_format(candidate):
			_set_last_error("Rename generated invalid tag '%s'." % candidate)
			return false
		renamed_lookup[candidate] = true
		renamed_tags.append(candidate)

	_explicit_tags.clear()
	for retained_tag in retained_tags:
		_explicit_tags[StringName(retained_tag)] = true
	for renamed_tag in renamed_tags:
		_explicit_tags[StringName(renamed_tag)] = true

	_rebuild_hierarchy_cache()
	_last_error = ""
	registry_changed.emit()
	return true

func get_explicit_tags() -> Array[StringName]:
	var sorted_text: Array[String] = []
	for tag_name in _explicit_tags.keys():
		sorted_text.append(String(tag_name))
	sorted_text.sort()
	var result: Array[StringName] = []
	for tag_text in sorted_text:
		result.append(StringName(tag_text))
	return result

func get_all_tags() -> Array[StringName]:
	var sorted_text: Array[String] = []
	for tag_name in _all_tags.keys():
		sorted_text.append(String(tag_name))
	sorted_text.sort()
	var result: Array[StringName] = []
	for tag_text in sorted_text:
		result.append(StringName(tag_text))
	return result

func get_parents(tag_name: StringName) -> Array[StringName]:
	if not _parents_by_tag.has(tag_name):
		return []
	var parents: Array[StringName] = []
	for parent_tag in _parents_by_tag[tag_name]:
		parents.append(parent_tag)
	return parents

func get_parse_warnings() -> Array[String]:
	return _parse_warnings.duplicate()

func get_loaded_config_path() -> String:
	return _loaded_config_path

func get_default_config_path() -> String:
	return DEFAULT_CONFIG_PATH

func validate_registry() -> Array[String]:
	var issues: Array[String] = []
	for explicit_tag in _explicit_tags.keys():
		var tag_text: String = String(explicit_tag)
		var normalized: String = _normalize_tag_name(tag_text)
		if normalized.is_empty():
			issues.append("Encountered an empty explicit tag entry.")
			continue
		if normalized != tag_text:
			issues.append("Tag '%s' should be normalized to '%s'." % [tag_text, normalized])
			continue
		if not _is_valid_tag_format(tag_text):
			issues.append("Tag '%s' has an invalid format." % tag_text)
	return issues

func get_last_error() -> String:
	return _last_error

func _resolve_config_path(config_path: String) -> String:
	var normalized_path: String = config_path.strip_edges()
	if normalized_path.is_empty():
		if _loaded_config_path.strip_edges().is_empty():
			return DEFAULT_CONFIG_PATH
		return _loaded_config_path
	return normalized_path

func _extract_tag_from_declaration(declaration: String) -> String:
	var separator_index: int = declaration.find("=")
	if separator_index < 0:
		return ""
	var value: String = declaration.substr(separator_index + 1).strip_edges()
	if value.begins_with("\"") and value.ends_with("\"") and value.length() >= 2:
		value = value.substr(1, value.length() - 2)
	return _normalize_tag_name(value)

func _normalize_tag_name(tag_name: String) -> String:
	var normalized: String = tag_name.strip_edges()
	while normalized.contains(".."):
		normalized = normalized.replace("..", ".")
	if normalized.begins_with("."):
		normalized = normalized.substr(1)
	if normalized.ends_with(".") and normalized.length() > 0:
		normalized = normalized.substr(0, normalized.length() - 1)
	return normalized

func _strip_inline_comment(line: String) -> String:
	var inside_quotes: bool = false
	for char_index in range(line.length()):
		var character: String = line.substr(char_index, 1)
		if character == "\"":
			inside_quotes = not inside_quotes
			continue
		if not inside_quotes and (character == "#" or character == ";"):
			return line.substr(0, char_index)
	return line

func _is_valid_tag_format(tag_name: String) -> bool:
	if tag_name.is_empty():
		return false
	var regex_result: RegExMatch = _tag_regex.search(tag_name)
	return regex_result != null

func _rebuild_hierarchy_cache() -> void:
	_all_tags.clear()
	_parents_by_tag.clear()

	for explicit_tag in _explicit_tags.keys():
		var explicit_text: String = String(explicit_tag)
		var segments: PackedStringArray = explicit_text.split(".", false)
		var prefix: String = ""
		for segment in segments:
			prefix = segment if prefix.is_empty() else "%s.%s" % [prefix, segment]
			_all_tags[StringName(prefix)] = true

	for tag_name in _all_tags.keys():
		var tag_text: String = String(tag_name)
		var parents: Array[StringName] = []
		var cursor: String = tag_text
		while cursor.contains("."):
			var split_index: int = cursor.rfind(".")
			cursor = cursor.substr(0, split_index)
			parents.append(StringName(cursor))
		_parents_by_tag[tag_name] = parents

func _set_last_error(message: String) -> void:
	_last_error = message
