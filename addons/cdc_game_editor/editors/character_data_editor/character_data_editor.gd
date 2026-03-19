@tool
extends Control
## CharacterDataEditor - Unified editor for character_data records.

signal character_saved(character_id: String)
signal character_loaded(character_id: String)

const CHARACTER_DIR: String = "res://data/characters"
const SKILLS_DIR: String = "res://data/skills"
const SKILL_TREES_DIR: String = "res://data/skill_trees"
const AI_GENERATE_PANEL_SCRIPT := preload("res://addons/cdc_game_editor/ai/ai_generate_panel.gd")

var editor_plugin: EditorPlugin = null

var characters: Dictionary = {}
var current_character_id: String = ""
var _dirty: bool = false
var _is_form_syncing: bool = false

var _character_list: ItemList
var _status_bar: Label
var _search_box: LineEdit
var _fields: Dictionary = {}

var _skill_definitions: Dictionary = {}
var _skill_trees: Dictionary = {}
var _skill_tree_checkbox_map: Dictionary = {}
var _skill_checkbox_map: Dictionary = {}
var _initial_skill_tree_container: VBoxContainer
var _initial_skill_groups_container: VBoxContainer
var _ai_panel: Window = null
var _ai_provider_override: Variant = null


func _ready() -> void:
	_load_skill_reference_data()
	_setup_ui()
	_load_characters_from_files()
	_update_character_list()


func _setup_ui() -> void:
	anchors_preset = PRESET_FULL_RECT

	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size = Vector2(0, 45)
	toolbar.set_anchors_preset(PRESET_TOP_WIDE)
	toolbar.offset_bottom = 45
	add_child(toolbar)

	var new_btn := Button.new()
	new_btn.text = "新建角色"
	new_btn.pressed.connect(_on_new_character)
	toolbar.add_child(new_btn)

	var delete_btn := Button.new()
	delete_btn.text = "删除"
	delete_btn.pressed.connect(_on_delete_character)
	toolbar.add_child(delete_btn)

	toolbar.add_child(VSeparator.new())

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(_on_save_characters)
	toolbar.add_child(save_btn)

	var reload_btn := Button.new()
	reload_btn.text = "重新加载"
	reload_btn.pressed.connect(_on_reload_characters)
	toolbar.add_child(reload_btn)

	var ai_btn := Button.new()
	ai_btn.text = "AI 生成"
	ai_btn.pressed.connect(_open_ai_panel)
	toolbar.add_child(ai_btn)

	var split := HSplitContainer.new()
	split.set_anchors_preset(PRESET_FULL_RECT)
	split.offset_top = 50
	split.offset_bottom = -20
	add_child(split)

	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(280, 0)
	split.add_child(left_panel)

	var title := Label.new()
	title.text = "Character 列表"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	left_panel.add_child(title)
	left_panel.add_child(HSeparator.new())

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "搜索角色..."
	_search_box.text_changed.connect(_on_search_changed)
	left_panel.add_child(_search_box)

	_character_list = ItemList.new()
	_character_list.size_flags_vertical = SIZE_EXPAND_FILL
	_character_list.item_selected.connect(_on_character_selected)
	left_panel.add_child(_character_list)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_child(right_scroll)

	var form := VBoxContainer.new()
	form.name = "Form"
	form.size_flags_horizontal = SIZE_EXPAND_FILL
	form.size_flags_vertical = SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	right_scroll.add_child(form)

	_add_string_field(form, "id", "ID")
	_add_string_field(form, "name", "名称")
	_add_multiline_field(form, "description", "描述")
	_add_number_field(form, "level", "等级", 1, 100, 1)
	_add_string_field(form, "identity.camp_id", "阵营ID")
	_add_string_field(form, "social.title", "称号")
	_add_string_field(form, "social.dialog_id", "对话ID")
	_add_string_field(form, "combat.behavior", "行为")
	_add_number_field(form, "combat.xp", "经验奖励", 0, 9999, 1)
	_add_number_field(form, "combat.stats.hp", "HP", 1, 9999, 1)
	_add_number_field(form, "combat.stats.damage", "伤害", 0, 999, 1)
	_add_number_field(form, "combat.stats.defense", "防御", 0, 999, 1)

	form.add_child(HSeparator.new())
	var tree_title := Label.new()
	tree_title.text = "初始技能树"
	tree_title.add_theme_font_size_override("font_size", 16)
	form.add_child(tree_title)

	_initial_skill_tree_container = VBoxContainer.new()
	_initial_skill_tree_container.add_theme_constant_override("separation", 6)
	form.add_child(_initial_skill_tree_container)

	form.add_child(HSeparator.new())
	var skill_title := Label.new()
	skill_title.text = "初始技能"
	skill_title.add_theme_font_size_override("font_size", 16)
	form.add_child(skill_title)

	_initial_skill_groups_container = VBoxContainer.new()
	_initial_skill_groups_container.add_theme_constant_override("separation", 10)
	form.add_child(_initial_skill_groups_container)

	_status_bar = Label.new()
	_status_bar.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_status_bar.offset_top = -20
	_status_bar.text = "就绪"
	add_child(_status_bar)

	_rebuild_skill_tree_selector()


func _add_string_field(parent: VBoxContainer, key: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	var field := LineEdit.new()
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	field.text_changed.connect(_on_field_changed.bind(key))
	row.add_child(field)
	parent.add_child(row)
	_fields[key] = field


func _add_multiline_field(parent: VBoxContainer, key: String, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var field := TextEdit.new()
	field.custom_minimum_size = Vector2(0, 90)
	field.size_flags_horizontal = SIZE_EXPAND_FILL
	field.text_changed.connect(_on_text_field_changed.bind(key, field))
	parent.add_child(field)
	_fields[key] = field


func _add_number_field(
	parent: VBoxContainer,
	key: String,
	label_text: String,
	min_value: float,
	max_value: float,
	step: float
) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	var field := SpinBox.new()
	field.min_value = min_value
	field.max_value = max_value
	field.step = step
	field.value_changed.connect(_on_number_field_changed.bind(key))
	row.add_child(field)
	parent.add_child(row)
	_fields[key] = field


func _load_skill_reference_data() -> void:
	_skill_definitions = _load_directory_json(SKILLS_DIR)
	_skill_trees = _load_directory_json(SKILL_TREES_DIR)


func _load_directory_json(directory_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var path: String = "%s/%s" % [directory_path, file_name]
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				var item: Dictionary = (parsed as Dictionary).duplicate(true)
				var item_id: String = str(item.get("id", file_name.trim_suffix(".json")))
				item["id"] = item_id
				result[item_id] = item
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _load_characters_from_files() -> void:
	characters.clear()
	var dir := DirAccess.open(CHARACTER_DIR)
	if not dir:
		_update_status("角色目录不存在: %s" % CHARACTER_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir() or not file_name.ends_with(".json"):
			file_name = dir.get_next()
			continue
		var path: String = "%s/%s" % [CHARACTER_DIR, file_name]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			var record: Dictionary = _normalize_character_record(parsed as Dictionary)
			var record_id: String = str(record.get("id", file_name.trim_suffix(".json")))
			characters[record_id] = record
		file_name = dir.get_next()
	dir.list_dir_end()
	_dirty = false


func _normalize_character_record(record: Dictionary) -> Dictionary:
	var normalized: Dictionary = record.duplicate(true)
	normalized["skills"] = _normalize_skills_block(normalized.get("skills", {}))
	return normalized


func _normalize_skills_block(value: Variant) -> Dictionary:
	var result: Dictionary = {
		"initial_tree_ids": [],
		"initial_skills_by_tree": {}
	}
	if not (value is Dictionary):
		return result

	var source: Dictionary = value
	var initial_tree_ids: Array[String] = []
	var raw_tree_ids: Variant = source.get("initial_tree_ids", [])
	if raw_tree_ids is Array:
		for tree_id_variant in raw_tree_ids:
			var tree_id: String = str(tree_id_variant).strip_edges()
			if tree_id.is_empty() or initial_tree_ids.has(tree_id):
				continue
			initial_tree_ids.append(tree_id)
	result["initial_tree_ids"] = initial_tree_ids

	var initial_skills_by_tree: Dictionary = {}
	var raw_skills_by_tree: Variant = source.get("initial_skills_by_tree", {})
	if raw_skills_by_tree is Dictionary:
		var tree_map: Dictionary = raw_skills_by_tree
		for tree_id_variant in tree_map.keys():
			var tree_id: String = str(tree_id_variant)
			initial_skills_by_tree[tree_id] = _normalize_string_array(tree_map.get(tree_id_variant, []))
	result["initial_skills_by_tree"] = initial_skills_by_tree
	_sanitize_skills_block(result)
	return result


func _update_character_list(filter: String = "") -> void:
	_character_list.clear()
	var ids: Array = characters.keys()
	ids.sort()
	for character_id in ids:
		var record: Dictionary = characters[character_id]
		var display_text: String = "%s - %s" % [character_id, str(record.get("name", "Unnamed"))]
		if filter.is_empty() or display_text.to_lower().contains(filter.to_lower()):
			var index: int = _character_list.add_item(display_text)
			_character_list.set_item_metadata(index, character_id)


func _on_search_changed(text: String) -> void:
	_update_character_list(text)


func _on_character_selected(index: int) -> void:
	var character_id: String = str(_character_list.get_item_metadata(index))
	_select_character(character_id)


func _select_character(character_id: String) -> void:
	current_character_id = character_id
	var record: Dictionary = characters.get(character_id, {})
	_refresh_fields(record)


func _refresh_fields(record: Dictionary) -> void:
	_is_form_syncing = true
	for key in _fields.keys():
		var field: Control = _fields[key]
		var value: Variant = _get_nested_value(record, key)
		if field is LineEdit:
			(field as LineEdit).text = str(value)
		elif field is TextEdit:
			(field as TextEdit).text = str(value)
		elif field is SpinBox:
			(field as SpinBox).value = float(value)
	_rebuild_skill_tree_selector()
	_refresh_skill_sections(record)
	_is_form_syncing = false


func _refresh_skill_sections(record: Dictionary) -> void:
	var was_syncing: bool = _is_form_syncing
	_is_form_syncing = true
	var skills_block: Dictionary = _normalize_skills_block(record.get("skills", {}))
	_apply_tree_checkbox_state(skills_block)
	_rebuild_skill_groups(skills_block)
	_is_form_syncing = was_syncing


func _apply_tree_checkbox_state(skills_block: Dictionary) -> void:
	var selected_tree_ids: Array[String] = _normalize_string_array(skills_block.get("initial_tree_ids", []))
	for tree_id in _skill_tree_checkbox_map.keys():
		var checkbox := _skill_tree_checkbox_map[tree_id] as CheckBox
		if checkbox == null:
			continue
		checkbox.button_pressed = selected_tree_ids.has(str(tree_id))


func _rebuild_skill_tree_selector() -> void:
	_clear_container(_initial_skill_tree_container)
	_skill_tree_checkbox_map.clear()

	if _skill_trees.is_empty():
		var empty_label := Label.new()
		empty_label.text = "未找到技能树数据"
		_initial_skill_tree_container.add_child(empty_label)
		return

	var tree_ids: Array = _skill_trees.keys()
	tree_ids.sort()
	for tree_id_variant in tree_ids:
		var tree_id: String = str(tree_id_variant)
		var tree_definition: Dictionary = _skill_trees.get(tree_id, {})
		var checkbox := CheckBox.new()
		checkbox.text = "%s (%s)" % [str(tree_definition.get("name", tree_id)), tree_id]
		checkbox.toggled.connect(_on_initial_tree_toggled.bind(tree_id))
		_initial_skill_tree_container.add_child(checkbox)
		_skill_tree_checkbox_map[tree_id] = checkbox


func _rebuild_skill_groups(skills_block: Dictionary) -> void:
	_clear_container(_initial_skill_groups_container)
	_skill_checkbox_map.clear()

	var selected_tree_ids: Array[String] = _normalize_string_array(skills_block.get("initial_tree_ids", []))
	if selected_tree_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "勾选技能树后，这里会显示对应技能列表。"
		_initial_skill_groups_container.add_child(empty_label)
		return

	var selected_lookup: Dictionary = _build_global_selected_skill_lookup(skills_block)
	var skills_by_tree: Dictionary = skills_block.get("initial_skills_by_tree", {})
	for tree_id in selected_tree_ids:
		var tree_definition: Dictionary = _skill_trees.get(tree_id, {})
		if tree_definition.is_empty():
			continue

		var panel := PanelContainer.new()
		_initial_skill_groups_container.add_child(panel)

		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 6)
		panel.add_child(group)

		var header := Label.new()
		header.text = "%s (%s)" % [str(tree_definition.get("name", tree_id)), tree_id]
		header.add_theme_font_size_override("font_size", 15)
		group.add_child(header)

		var description_text: String = str(tree_definition.get("description", "")).strip_edges()
		if not description_text.is_empty():
			var description := Label.new()
			description.text = description_text
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			group.add_child(description)

		var selected_in_tree: Dictionary = {}
		for skill_id in _normalize_string_array(skills_by_tree.get(tree_id, [])):
			selected_in_tree[skill_id] = true

		for skill_id in _normalize_string_array(tree_definition.get("skills", [])):
			var skill_definition: Dictionary = _skill_definitions.get(skill_id, {})
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 2)
			group.add_child(row)

			var checkbox := CheckBox.new()
			var skill_name: String = str(skill_definition.get("name", skill_id))
			checkbox.text = "%s (%s)" % [skill_name, skill_id]
			checkbox.button_pressed = selected_in_tree.has(skill_id)
			checkbox.disabled = not checkbox.button_pressed and not _can_interact_with_skill(skill_id, selected_lookup)
			checkbox.toggled.connect(_on_initial_skill_toggled.bind(tree_id, skill_id))
			row.add_child(checkbox)
			_skill_checkbox_map[_make_skill_checkbox_key(tree_id, skill_id)] = checkbox

			var prerequisites: Array[String] = _normalize_string_array(skill_definition.get("prerequisites", []))
			var detail := Label.new()
			detail.modulate = Color(0.75, 0.75, 0.75, 1.0)
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if prerequisites.is_empty():
				detail.text = "无前置技能"
			else:
				detail.text = "前置: %s" % ", ".join(prerequisites)
			row.add_child(detail)


func _on_new_character() -> void:
	var character_id: String = "character_%d" % Time.get_ticks_msec()
	characters[character_id] = _create_default_character(character_id)
	_update_character_list()
	_select_character(character_id)
	_update_status("已创建角色: %s" % character_id)
	_dirty = true


func _create_default_character(character_id: String) -> Dictionary:
	return {
		"id": character_id,
		"name": "新角色",
		"description": "",
		"level": 1,
		"identity": {"camp_id": "neutral"},
		"visual": {
			"portrait_path": "",
			"avatar_path": "",
			"model_path": "",
			"placeholder": {
				"head_color": "#f2d6b2",
				"body_color": "#5d90e0",
				"leg_color": "#3c5c90"
			}
		},
		"combat": {
			"stats": {
				"hp": 50,
				"max_hp": 50,
				"damage": 5,
				"defense": 2,
				"speed": 5,
				"accuracy": 70,
				"crit_chance": 0.05,
				"crit_damage": 1.5,
				"evasion": 0.05
			},
			"ai": {
				"aggro_range": 6.0,
				"attack_range": 1.3,
				"wander_radius": 3.0,
				"leash_distance": 8.0,
				"decision_interval": 0.8,
				"attack_cooldown": 1.5
			},
			"behavior": "neutral",
			"loot": [],
			"xp": 10
		},
		"social": {
			"title": "",
			"dialog_id": "",
			"mood": {
				"friendliness": 50,
				"trust": 30,
				"fear": 0,
				"anger": 0
			}
		},
		"skills": {
			"initial_tree_ids": [],
			"initial_skills_by_tree": {}
		}
	}


func _on_delete_character() -> void:
	if current_character_id.is_empty():
		return
	characters.erase(current_character_id)
	current_character_id = ""
	_update_character_list()
	_refresh_fields({})
	_update_status("已删除角色")
	_dirty = true


func _on_save_characters() -> void:
	var validation_errors: Array[String] = get_validation_errors()
	if not validation_errors.is_empty():
		_update_status(validation_errors[0])
		return

	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CHARACTER_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CHARACTER_DIR))

	for character_id in characters.keys():
		var record: Dictionary = _normalize_character_record(characters[character_id])
		var final_id: String = str(record.get("id", character_id)).strip_edges()
		if final_id.is_empty():
			final_id = str(character_id)
			record["id"] = final_id
		var path: String = "%s/%s.json" % [CHARACTER_DIR, final_id]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(record, "\t", false))
			file.close()
			characters[final_id] = record

	_dirty = false
	_update_character_list(_search_box.text)
	_update_status("已保存 %d 个角色" % characters.size())
	character_saved.emit(current_character_id)


func _on_reload_characters() -> void:
	_load_skill_reference_data()
	_load_characters_from_files()
	_rebuild_skill_tree_selector()
	_update_character_list(_search_box.text)
	if not current_character_id.is_empty() and characters.has(current_character_id):
		_select_character(current_character_id)
	_update_status("已重新加载角色数据")
	character_loaded.emit(current_character_id)


func _on_field_changed(value: String, key: String) -> void:
	_apply_field_change(key, value)


func _on_text_field_changed(key: String, control: TextEdit) -> void:
	_apply_field_change(key, control.text)


func _on_number_field_changed(value: float, key: String) -> void:
	_apply_field_change(key, int(value))


func _apply_field_change(key: String, value: Variant) -> void:
	if _is_form_syncing:
		return
	if current_character_id.is_empty() or not characters.has(current_character_id):
		return
	var record: Dictionary = characters[current_character_id]
	_set_nested_value(record, key, value)

	if key == "id":
		var new_id: String = str(value).strip_edges()
		if not new_id.is_empty() and new_id != current_character_id and not characters.has(new_id):
			characters.erase(current_character_id)
			record["id"] = new_id
			characters[new_id] = record
			current_character_id = new_id

	characters[current_character_id] = record
	_dirty = true
	_update_character_list(_search_box.text)


func _on_initial_tree_toggled(enabled: bool, tree_id: String) -> void:
	if _is_form_syncing:
		return
	var record: Dictionary = _get_current_record()
	if record.is_empty():
		return

	var skills_block: Dictionary = _normalize_skills_block(record.get("skills", {}))
	var selected_tree_ids: Array[String] = _normalize_string_array(skills_block.get("initial_tree_ids", []))
	var initial_skills_by_tree: Dictionary = skills_block.get("initial_skills_by_tree", {})
	if enabled:
		if not selected_tree_ids.has(tree_id):
			selected_tree_ids.append(tree_id)
		if not initial_skills_by_tree.has(tree_id):
			initial_skills_by_tree[tree_id] = []
	else:
		selected_tree_ids.erase(tree_id)
		initial_skills_by_tree.erase(tree_id)

	skills_block["initial_tree_ids"] = selected_tree_ids
	skills_block["initial_skills_by_tree"] = initial_skills_by_tree
	_sanitize_skills_block(skills_block)
	_commit_skills_block(record, skills_block)


func _on_initial_skill_toggled(enabled: bool, tree_id: String, skill_id: String) -> void:
	if _is_form_syncing:
		return
	var record: Dictionary = _get_current_record()
	if record.is_empty():
		return

	var skills_block: Dictionary = _normalize_skills_block(record.get("skills", {}))
	var initial_skills_by_tree: Dictionary = skills_block.get("initial_skills_by_tree", {})
	var selected_in_tree: Array[String] = _normalize_string_array(initial_skills_by_tree.get(tree_id, []))
	if enabled:
		if not selected_in_tree.has(skill_id):
			selected_in_tree.append(skill_id)
	else:
		selected_in_tree.erase(skill_id)

	initial_skills_by_tree[tree_id] = _sort_skill_ids_for_tree(tree_id, selected_in_tree)
	skills_block["initial_skills_by_tree"] = initial_skills_by_tree
	_sanitize_skills_block(skills_block)
	_commit_skills_block(record, skills_block)


func _commit_skills_block(record: Dictionary, skills_block: Dictionary) -> void:
	record["skills"] = skills_block.duplicate(true)
	characters[current_character_id] = record
	_dirty = true
	_refresh_skill_sections(record)
	_update_character_list(_search_box.text)


func _get_current_record() -> Dictionary:
	if current_character_id.is_empty() or not characters.has(current_character_id):
		return {}
	return characters[current_character_id]


func _sanitize_skills_block(skills_block: Dictionary) -> void:
	var tree_ids: Array[String] = []
	for tree_id in _normalize_string_array(skills_block.get("initial_tree_ids", [])):
		if _skill_trees.has(tree_id) and not tree_ids.has(tree_id):
			tree_ids.append(tree_id)
	skills_block["initial_tree_ids"] = tree_ids

	var skills_by_tree: Dictionary = {}
	var raw_skills_by_tree: Variant = skills_block.get("initial_skills_by_tree", {})
	if raw_skills_by_tree is Dictionary:
		skills_by_tree = (raw_skills_by_tree as Dictionary).duplicate(true)

	for tree_id in tree_ids:
		skills_by_tree[tree_id] = _sort_skill_ids_for_tree(tree_id, _normalize_string_array(skills_by_tree.get(tree_id, [])))
	for tree_id in skills_by_tree.keys():
		if not tree_ids.has(str(tree_id)):
			skills_by_tree.erase(tree_id)

	var changed: bool = true
	while changed:
		changed = false
		var selected_lookup: Dictionary = _build_global_selected_skill_lookup({
			"initial_tree_ids": tree_ids,
			"initial_skills_by_tree": skills_by_tree
		})
		for tree_id in tree_ids:
			var ordered: Array[String] = _sort_skill_ids_for_tree(tree_id, _normalize_string_array(skills_by_tree.get(tree_id, [])))
			var filtered: Array[String] = []
			for skill_id in ordered:
				if _can_interact_with_skill(skill_id, selected_lookup):
					filtered.append(skill_id)
				else:
					changed = true
			skills_by_tree[tree_id] = filtered
	skills_block["initial_skills_by_tree"] = skills_by_tree


func _sort_skill_ids_for_tree(tree_id: String, skill_ids: Array[String]) -> Array[String]:
	var tree_definition: Dictionary = _skill_trees.get(tree_id, {})
	var ordered_ids: Array[String] = []
	var selected_lookup: Dictionary = {}
	for skill_id in skill_ids:
		selected_lookup[skill_id] = true
	for skill_id in _normalize_string_array(tree_definition.get("skills", [])):
		if selected_lookup.has(skill_id):
			ordered_ids.append(skill_id)
	return ordered_ids


func _build_global_selected_skill_lookup(skills_block: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var tree_ids: Array[String] = _normalize_string_array(skills_block.get("initial_tree_ids", []))
	var skills_by_tree: Dictionary = skills_block.get("initial_skills_by_tree", {})
	for tree_id in tree_ids:
		for skill_id in _normalize_string_array(skills_by_tree.get(tree_id, [])):
			result[skill_id] = true
	return result


func _can_interact_with_skill(skill_id: String, selected_lookup: Dictionary) -> bool:
	var skill_definition: Dictionary = _skill_definitions.get(skill_id, {})
	if skill_definition.is_empty():
		return false
	for prerequisite_id in _normalize_string_array(skill_definition.get("prerequisites", [])):
		if not selected_lookup.has(prerequisite_id):
			return false
	return true


func _make_skill_checkbox_key(tree_id: String, skill_id: String) -> String:
	return "%s::%s" % [tree_id, skill_id]


func _set_nested_value(target: Dictionary, path: String, value: Variant) -> void:
	var keys: PackedStringArray = path.split(".")
	if keys.is_empty():
		return
	var current: Dictionary = target
	for i in range(keys.size() - 1):
		var key: String = keys[i]
		if not current.has(key) or not (current[key] is Dictionary):
			current[key] = {}
		current = current[key]
	current[keys[keys.size() - 1]] = value


func _get_nested_value(target: Dictionary, path: String) -> Variant:
	var keys: PackedStringArray = path.split(".")
	var current: Variant = target
	for key in keys:
		if not (current is Dictionary):
			return ""
		var dict: Dictionary = current
		if not dict.has(key):
			return ""
		current = dict[key]
	return current


func _normalize_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			var text: String = str(item).strip_edges()
			if not text.is_empty() and not result.has(text):
				result.append(text)
	return result


func _clear_container(container: Control) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.free()


func _update_status(message: String) -> void:
	if _status_bar:
		_status_bar.text = message


func has_unsaved_changes() -> bool:
	return _dirty


func get_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	for character_id_variant in characters.keys():
		var character_id: String = str(character_id_variant)
		var record: Dictionary = _normalize_character_record(characters[character_id_variant])
		errors.append_array(_get_character_validation_errors_for_record(character_id, record))
	return errors


func focus_record(record_id: String) -> bool:
	if not characters.has(record_id):
		return false
	_select_character(record_id)
	for i in range(_character_list.item_count):
		if str(_character_list.get_item_metadata(i)) == record_id:
			_character_list.select(i)
			break
	return true


func set_ai_provider_override(provider: Variant) -> void:
	_ai_provider_override = provider
	if _ai_panel and is_instance_valid(_ai_panel):
		_ai_panel.set_provider_override(provider)


func build_ai_seed_context() -> Dictionary:
	return {
		"target_id": current_character_id,
		"current_record": _get_current_record().duplicate(true)
	}


func get_ai_validation_errors(draft: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var record := draft.get("record", {})
	if not (record is Dictionary):
		errors.append("record 必须是 Dictionary")
		return errors

	var record_id := str(record.get("id", "")).strip_edges()
	var operation := str(draft.get("operation", "")).strip_edges()
	var target_id := str(draft.get("target_id", "")).strip_edges()
	if record_id.is_empty():
		errors.append("角色 ID 不能为空")
		return errors
	if operation == "create" and characters.has(record_id):
		errors.append("新建模式下不能复用已有角色 ID: %s" % record_id)
	if operation == "revise" and not target_id.is_empty() and record_id != target_id:
		errors.append("调整模式下 record.id 必须保持为当前角色 ID")

	errors.append_array(_get_character_validation_errors_for_record(record_id, _normalize_character_record(record)))
	return errors


func apply_ai_draft(draft: Dictionary) -> bool:
	var errors := get_ai_validation_errors(draft)
	if not errors.is_empty():
		_update_status(errors[0])
		return false

	var record: Dictionary = _normalize_character_record((draft.get("record", {}) as Dictionary).duplicate(true))
	var record_id := str(record.get("id", "")).strip_edges()
	var existing: Dictionary = characters.get(record_id, {}).duplicate(true)
	if not existing.is_empty():
		record = _deep_merge_dictionary(existing, record)
		record = _normalize_character_record(record)
	characters[record_id] = record
	current_character_id = record_id
	_dirty = true
	_update_character_list(_search_box.text)
	_select_character(record_id)
	_update_status("AI 草稿已应用到角色: %s" % record_id)
	return true


func _open_ai_panel() -> void:
	if _ai_panel == null or not is_instance_valid(_ai_panel):
		_ai_panel = AI_GENERATE_PANEL_SCRIPT.new()
		_ai_panel.editor_plugin = editor_plugin
		add_child(_ai_panel)
	_ai_panel.configure(self, editor_plugin, "character", _ai_provider_override)
	_ai_panel.open_panel()


func _get_character_validation_errors_for_record(character_id: String, record: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var skills_block: Dictionary = record.get("skills", {})
	var tree_ids: Array[String] = _normalize_string_array(skills_block.get("initial_tree_ids", []))
	var skills_by_tree: Dictionary = skills_block.get("initial_skills_by_tree", {})
	var selected_lookup: Dictionary = _build_global_selected_skill_lookup(skills_block)

	for tree_id in tree_ids:
		if not _skill_trees.has(tree_id):
			errors.append("character[%s]: 初始技能树不存在 -> %s" % [character_id, tree_id])
			continue
		var tree_definition: Dictionary = _skill_trees.get(tree_id, {})
		var tree_skill_lookup: Dictionary = {}
		for tree_skill_id in _normalize_string_array(tree_definition.get("skills", [])):
			tree_skill_lookup[tree_skill_id] = true
		for skill_id in _normalize_string_array(skills_by_tree.get(tree_id, [])):
			if not tree_skill_lookup.has(skill_id):
				errors.append("character[%s]: 技能 %s 不属于技能树 %s" % [character_id, skill_id, tree_id])
				continue
			var skill_definition: Dictionary = _skill_definitions.get(skill_id, {})
			if skill_definition.is_empty():
				errors.append("character[%s]: 技能不存在 -> %s" % [character_id, skill_id])
				continue
			for prerequisite_id in _normalize_string_array(skill_definition.get("prerequisites", [])):
				if not selected_lookup.has(prerequisite_id):
					errors.append(
						"character[%s]: 技能 %s 缺少前置技能 %s" % [character_id, skill_id, prerequisite_id]
					)
	return errors


func _deep_merge_dictionary(base: Dictionary, override_data: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate(true)
	for key in override_data.keys():
		var incoming: Variant = override_data[key]
		if merged.has(key) and merged[key] is Dictionary and incoming is Dictionary:
			merged[key] = _deep_merge_dictionary(merged[key], incoming)
		else:
			merged[key] = incoming
	return merged
