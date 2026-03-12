@tool
extends Control
## SkillEditor - CDC 插件内技能编辑器（纯脚本 UI）

const SKILLS_DIR: String = "res://data/skills"
const SKILL_TREES_DIR: String = "res://data/skill_trees"

var editor_plugin: EditorPlugin = null

var _skill_list: ItemList
var _new_skill_button: Button
var _delete_skill_button: Button

var _skill_id_input: LineEdit
var _skill_name_input: LineEdit
var _icon_input: LineEdit
var _skill_tree_id_input: LineEdit
var _max_level_input: SpinBox
var _prerequisites_input: LineEdit
var _attr_requirements_input: LineEdit
var _description_input: TextEdit
var _gameplay_effect_input: TextEdit

var _tree_selector: OptionButton
var _new_tree_button: Button
var _delete_tree_button: Button
var _tree_id_input: LineEdit
var _tree_name_input: LineEdit
var _tree_description_input: TextEdit
var _tree_skills_input: LineEdit
var _tree_links_input: TextEdit

var _save_button: Button
var _reload_button: Button
var _status_label: Label

var _skills: Dictionary = {}
var _trees: Dictionary = {}
var _selected_skill_id: String = ""
var _selected_tree_id: String = ""
var _deleted_skill_ids: Array[String] = []
var _deleted_tree_ids: Array[String] = []
var _dirty_tree_ids: Array[String] = []
var _validation_errors: Array = []
var _has_unsaved_changes: bool = false
var _is_form_syncing: bool = false


func _ready() -> void:
	_build_ui()
	_connect_signals()
	_reload_all()


func has_unsaved_changes() -> bool:
	return _has_unsaved_changes


func get_validation_errors() -> Array:
	_rebuild_validation_errors()
	return _validation_errors.duplicate()


func _build_ui() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.custom_minimum_size = Vector2(0, 42)
	root.add_child(toolbar)

	_save_button = Button.new()
	_save_button.text = "保存"
	toolbar.add_child(_save_button)

	_reload_button = Button.new()
	_reload_button.text = "重新加载"
	toolbar.add_child(_reload_button)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_status_label = Label.new()
	_status_label.text = "就绪"
	toolbar.add_child(_status_label)

	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 280
	root.add_child(split)

	var left_panel: VBoxContainer = VBoxContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_panel)

	var skill_title: Label = Label.new()
	skill_title.text = "技能列表"
	skill_title.add_theme_font_size_override("font_size", 16)
	left_panel.add_child(skill_title)

	_skill_list = ItemList.new()
	_skill_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(_skill_list)

	var skill_buttons: HBoxContainer = HBoxContainer.new()
	left_panel.add_child(skill_buttons)

	_new_skill_button = Button.new()
	_new_skill_button.text = "新增技能"
	_new_skill_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_buttons.add_child(_new_skill_button)

	_delete_skill_button = Button.new()
	_delete_skill_button.text = "删除技能"
	_delete_skill_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_buttons.add_child(_delete_skill_button)

	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_scroll)

	var right_vbox: VBoxContainer = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.custom_minimum_size = Vector2(800, 700)
	right_vbox.add_theme_constant_override("separation", 10)
	right_scroll.add_child(right_vbox)

	var skill_section_title: Label = Label.new()
	skill_section_title.text = "技能配置"
	skill_section_title.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(skill_section_title)

	var skill_grid: GridContainer = GridContainer.new()
	skill_grid.columns = 2
	skill_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(skill_grid)

	_skill_id_input = _add_line_field(skill_grid, "技能ID")
	_skill_name_input = _add_line_field(skill_grid, "名字")
	_icon_input = _add_line_field(skill_grid, "图标路径")
	_skill_tree_id_input = _add_line_field(skill_grid, "技能树ID")
	_max_level_input = _add_spin_field(skill_grid, "最大等级", 1, 50, 1)
	_prerequisites_input = _add_line_field(skill_grid, "前置技能(逗号)")
	_attr_requirements_input = _add_line_field(skill_grid, "属性要求(strength:6)")

	right_vbox.add_child(_make_label("描述"))
	_description_input = TextEdit.new()
	_description_input.custom_minimum_size = Vector2(0, 100)
	_description_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_description_input)

	right_vbox.add_child(_make_label("GameplayEffect(JSON)"))
	_gameplay_effect_input = TextEdit.new()
	_gameplay_effect_input.custom_minimum_size = Vector2(0, 140)
	_gameplay_effect_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_gameplay_effect_input)

	right_vbox.add_child(HSeparator.new())

	var tree_section_title: Label = Label.new()
	tree_section_title.text = "技能树配置"
	tree_section_title.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(tree_section_title)

	var tree_toolbar: HBoxContainer = HBoxContainer.new()
	right_vbox.add_child(tree_toolbar)

	_tree_selector = OptionButton.new()
	_tree_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_toolbar.add_child(_tree_selector)

	_new_tree_button = Button.new()
	_new_tree_button.text = "新增技能树"
	tree_toolbar.add_child(_new_tree_button)

	_delete_tree_button = Button.new()
	_delete_tree_button.text = "删除技能树"
	tree_toolbar.add_child(_delete_tree_button)

	var tree_grid: GridContainer = GridContainer.new()
	tree_grid.columns = 2
	tree_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(tree_grid)

	_tree_id_input = _add_line_field(tree_grid, "技能树ID")
	_tree_name_input = _add_line_field(tree_grid, "名字")
	_tree_skills_input = _add_line_field(tree_grid, "技能ID列表(逗号)")

	right_vbox.add_child(_make_label("技能树描述"))
	_tree_description_input = TextEdit.new()
	_tree_description_input.custom_minimum_size = Vector2(0, 100)
	_tree_description_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_tree_description_input)

	right_vbox.add_child(_make_label("连线(每行: from -> to)"))
	_tree_links_input = TextEdit.new()
	_tree_links_input.custom_minimum_size = Vector2(0, 120)
	_tree_links_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_tree_links_input)


func _connect_signals() -> void:
	_skill_list.item_selected.connect(_on_skill_selected)
	_new_skill_button.pressed.connect(_on_new_skill_pressed)
	_delete_skill_button.pressed.connect(_on_delete_skill_pressed)
	_tree_selector.item_selected.connect(_on_tree_selected)
	_new_tree_button.pressed.connect(_on_new_tree_pressed)
	_delete_tree_button.pressed.connect(_on_delete_tree_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_reload_button.pressed.connect(_reload_all)

	_skill_id_input.text_changed.connect(func(_t: String): _mark_dirty())
	_skill_name_input.text_changed.connect(func(_t: String): _mark_dirty())
	_icon_input.text_changed.connect(func(_t: String): _mark_dirty())
	_skill_tree_id_input.text_changed.connect(func(_t: String): _mark_dirty())
	_max_level_input.value_changed.connect(func(_v: float): _mark_dirty())
	_prerequisites_input.text_changed.connect(func(_t: String): _mark_dirty())
	_attr_requirements_input.text_changed.connect(func(_t: String): _mark_dirty())
	_description_input.text_changed.connect(_mark_dirty)
	_gameplay_effect_input.text_changed.connect(_mark_dirty)
	_tree_id_input.text_changed.connect(func(_t: String): _mark_dirty())
	_tree_name_input.text_changed.connect(func(_t: String): _mark_dirty())
	_tree_skills_input.text_changed.connect(func(_t: String): _mark_dirty())
	_tree_description_input.text_changed.connect(_mark_dirty)
	_tree_links_input.text_changed.connect(_mark_dirty)


func _reload_all() -> void:
	_skills = _load_directory_json(SKILLS_DIR)
	_trees = _load_directory_json(SKILL_TREES_DIR)
	_deleted_skill_ids.clear()
	_deleted_tree_ids.clear()
	_dirty_tree_ids.clear()
	_refresh_skill_list()
	_refresh_tree_selector()
	_select_first_skill()
	_select_first_tree()
	_has_unsaved_changes = false
	_rebuild_validation_errors()
	_set_status("已加载技能 %d 个，技能树 %d 个" % [_skills.size(), _trees.size()])


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
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				file.close()
				if parsed is Dictionary:
					var item: Dictionary = parsed
					var item_id: String = str(item.get("id", file_name.trim_suffix(".json")))
					item.erase("id")
					result[item_id] = item
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _refresh_skill_list() -> void:
	_skill_list.clear()
	var ids: Array = _skills.keys()
	ids.sort()
	for id in ids:
		_skill_list.add_item(str(id))


func _refresh_tree_selector() -> void:
	_tree_selector.clear()
	var ids: Array = _trees.keys()
	ids.sort()
	for id in ids:
		_tree_selector.add_item(str(id))


func _select_first_skill() -> void:
	if _skill_list.get_item_count() == 0:
		_selected_skill_id = ""
		_clear_skill_form()
		return
	_skill_list.select(0)
	_on_skill_selected(0)


func _select_first_tree() -> void:
	if _tree_selector.get_item_count() == 0:
		_selected_tree_id = ""
		_clear_tree_form()
		return
	_tree_selector.select(0)
	_on_tree_selected(0)


func _on_skill_selected(index: int) -> void:
	var skill_id: String = _skill_list.get_item_text(index)
	_selected_skill_id = skill_id
	_fill_skill_form(skill_id)


func _fill_skill_form(skill_id: String) -> void:
	var skill: Dictionary = _skills.get(skill_id, {})
	_is_form_syncing = true
	_skill_id_input.text = skill_id
	_skill_name_input.text = str(skill.get("name", ""))
	_icon_input.text = str(skill.get("icon", ""))
	_description_input.text = str(skill.get("description", ""))
	_skill_tree_id_input.text = str(skill.get("tree_id", ""))
	_max_level_input.value = float(int(skill.get("max_level", 1)))
	_prerequisites_input.text = _join_string_array(skill.get("prerequisites", []))
	_attr_requirements_input.text = _format_attr_requirements(skill.get("attribute_requirements", {}))
	_gameplay_effect_input.text = JSON.stringify(skill.get("gameplay_effect", {}), "\t")
	_is_form_syncing = false


func _clear_skill_form() -> void:
	_is_form_syncing = true
	_skill_id_input.text = ""
	_skill_name_input.text = ""
	_icon_input.text = ""
	_description_input.text = ""
	_skill_tree_id_input.text = ""
	_max_level_input.value = 1.0
	_prerequisites_input.text = ""
	_attr_requirements_input.text = ""
	_gameplay_effect_input.text = "{}"
	_is_form_syncing = false


func _on_tree_selected(index: int) -> void:
	var tree_id: String = _tree_selector.get_item_text(index)
	_selected_tree_id = tree_id
	_fill_tree_form(tree_id)


func _fill_tree_form(tree_id: String) -> void:
	var tree: Dictionary = _trees.get(tree_id, {})
	_is_form_syncing = true
	_tree_id_input.text = tree_id
	_tree_name_input.text = str(tree.get("name", tree_id))
	_tree_description_input.text = str(tree.get("description", ""))
	_tree_skills_input.text = _join_string_array(tree.get("skills", []))
	_tree_links_input.text = _format_links(tree.get("links", []))
	_is_form_syncing = false


func _clear_tree_form() -> void:
	_is_form_syncing = true
	_tree_id_input.text = ""
	_tree_name_input.text = ""
	_tree_description_input.text = ""
	_tree_skills_input.text = ""
	_tree_links_input.text = ""
	_is_form_syncing = false


func _on_new_skill_pressed() -> void:
	var new_id: String = _generate_unique_id(_skills, "new_skill")
	_skills[new_id] = {
		"name": "新技能",
		"icon": "",
		"description": "",
		"tree_id": "combat",
		"max_level": 1,
		"prerequisites": [],
		"attribute_requirements": {},
		"gameplay_effect": {"modifiers": {"new_bonus": {"per_level": 0.1}}}
	}
	_refresh_skill_list()
	var index: int = _find_item_list_index(_skill_list, new_id)
	if index >= 0:
		_skill_list.select(index)
		_on_skill_selected(index)
	_mark_dirty()
	_set_status("已创建技能: %s" % new_id)


func _on_delete_skill_pressed() -> void:
	if _selected_skill_id.is_empty():
		return
	var deleted_id: String = _selected_skill_id
	_deleted_skill_ids.append(deleted_id)
	_skills.erase(deleted_id)
	_remove_skill_from_trees(deleted_id)
	_refresh_skill_list()
	_select_first_skill()
	_mark_dirty()
	_set_status("已删除技能: %s" % deleted_id)


func _on_new_tree_pressed() -> void:
	var new_id: String = _generate_unique_id(_trees, "new_tree")
	_trees[new_id] = {"name": "新技能树", "description": "", "skills": [], "links": [], "layout": {}}
	_refresh_tree_selector()
	var index: int = _find_option_index(_tree_selector, new_id)
	if index >= 0:
		_tree_selector.select(index)
		_on_tree_selected(index)
	_mark_dirty()
	_set_status("已创建技能树: %s" % new_id)


func _on_delete_tree_pressed() -> void:
	if _selected_tree_id.is_empty():
		return
	var deleted_id: String = _selected_tree_id
	_deleted_tree_ids.append(deleted_id)
	_trees.erase(deleted_id)
	_refresh_tree_selector()
	_select_first_tree()
	_mark_dirty()
	_set_status("已删除技能树: %s" % deleted_id)


func _on_save_pressed() -> void:
	if not _save_current_forms():
		return
	if not _flush_deleted_files():
		_set_status("保存失败: 删除旧文件失败")
		return
	if not _save_selected_files():
		_set_status("保存失败: 写入文件失败")
		return

	_dirty_tree_ids.clear()
	_has_unsaved_changes = false
	_rebuild_validation_errors()
	if _validation_errors.is_empty():
		_set_status("保存成功")
	else:
		_set_status("已保存，但有 %d 个校验警告" % _validation_errors.size())


func _save_current_forms() -> bool:
	if not _selected_skill_id.is_empty():
		var old_skill_id: String = _selected_skill_id
		var new_skill_id: String = _skill_id_input.text.strip_edges()
		if new_skill_id.is_empty():
			_set_status("技能ID不能为空")
			return false
		if new_skill_id != old_skill_id and _skills.has(new_skill_id):
			_set_status("技能ID重复: %s" % new_skill_id)
			return false

		var gameplay_effect: Variant = JSON.parse_string(_gameplay_effect_input.text)
		if gameplay_effect == null or not (gameplay_effect is Dictionary):
			_set_status("GameplayEffect 必须是合法JSON对象")
			return false

		var skill_data: Dictionary = {
			"name": _skill_name_input.text.strip_edges(),
			"icon": _icon_input.text.strip_edges(),
			"description": _description_input.text.strip_edges(),
			"tree_id": _skill_tree_id_input.text.strip_edges(),
			"max_level": int(_max_level_input.value),
			"prerequisites": _parse_csv(_prerequisites_input.text),
			"attribute_requirements": _parse_attr_requirements(_attr_requirements_input.text),
			"gameplay_effect": gameplay_effect
		}
		_skills.erase(old_skill_id)
		_skills[new_skill_id] = skill_data
		_selected_skill_id = new_skill_id
		if new_skill_id != old_skill_id:
			_deleted_skill_ids.append(old_skill_id)
			_replace_skill_id_in_trees(old_skill_id, new_skill_id)

	if not _selected_tree_id.is_empty():
		var old_tree_id: String = _selected_tree_id
		var new_tree_id: String = _tree_id_input.text.strip_edges()
		if new_tree_id.is_empty():
			_set_status("技能树ID不能为空")
			return false
		if new_tree_id != old_tree_id and _trees.has(new_tree_id):
			_set_status("技能树ID重复: %s" % new_tree_id)
			return false

		var tree_data: Dictionary = _trees.get(old_tree_id, {}).duplicate(true)
		tree_data["name"] = _tree_name_input.text.strip_edges()
		tree_data["description"] = _tree_description_input.text.strip_edges()
		tree_data["skills"] = _parse_csv(_tree_skills_input.text)
		tree_data["links"] = _parse_links(_tree_links_input.text)
		if not tree_data.has("layout"):
			tree_data["layout"] = {}

		_trees.erase(old_tree_id)
		_trees[new_tree_id] = tree_data
		_selected_tree_id = new_tree_id
		if not _dirty_tree_ids.has(new_tree_id):
			_dirty_tree_ids.append(new_tree_id)
		if new_tree_id != old_tree_id:
			_deleted_tree_ids.append(old_tree_id)

	_refresh_skill_list()
	_refresh_tree_selector()
	return true


func _flush_deleted_files() -> bool:
	for skill_id in _deleted_skill_ids:
		if not _delete_file("%s/%s.json" % [SKILLS_DIR, skill_id]):
			return false
	_deleted_skill_ids.clear()

	for tree_id in _deleted_tree_ids:
		if not _delete_file("%s/%s.json" % [SKILL_TREES_DIR, tree_id]):
			return false
	_deleted_tree_ids.clear()
	return true


func _save_selected_files() -> bool:
	if not _selected_skill_id.is_empty() and _skills.has(_selected_skill_id):
		if not _write_item_file(SKILLS_DIR, _selected_skill_id, _skills.get(_selected_skill_id, {})):
			return false
	if not _selected_tree_id.is_empty() and _trees.has(_selected_tree_id):
		if not _write_item_file(SKILL_TREES_DIR, _selected_tree_id, _trees.get(_selected_tree_id, {})):
			return false
	for tree_id in _dirty_tree_ids:
		if tree_id == _selected_tree_id:
			continue
		if _trees.has(tree_id):
			if not _write_item_file(SKILL_TREES_DIR, tree_id, _trees.get(tree_id, {})):
				return false
	return true


func _write_item_file(directory_path: String, item_id: String, item_data: Dictionary) -> bool:
	if not _ensure_directory(directory_path):
		return false

	var payload: Dictionary = item_data.duplicate(true)
	payload["id"] = item_id
	var path: String = "%s/%s.json" % [directory_path, item_id]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func _ensure_directory(directory_path: String) -> bool:
	if DirAccess.open(directory_path) != null:
		return true
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory_path)) == OK


func _delete_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func _remove_skill_from_trees(skill_id: String) -> void:
	for tree_id in _trees.keys():
		var tree: Dictionary = _trees.get(tree_id, {}).duplicate(true)
		var skills: Array[String] = _parse_csv(_join_string_array(tree.get("skills", [])))
		skills.erase(skill_id)
		tree["skills"] = skills

		var links: Array[Dictionary] = _parse_links(_format_links(tree.get("links", [])))
		var filtered_links: Array[Dictionary] = []
		for link in links:
			if str(link.get("from", "")) == skill_id:
				continue
			if str(link.get("to", "")) == skill_id:
				continue
			filtered_links.append(link)
		tree["links"] = filtered_links

		var layout: Dictionary = tree.get("layout", {})
		if layout is Dictionary and layout.has(skill_id):
			layout.erase(skill_id)
			tree["layout"] = layout

		_trees[tree_id] = tree
		if not _dirty_tree_ids.has(tree_id):
			_dirty_tree_ids.append(tree_id)


func _replace_skill_id_in_trees(old_id: String, new_id: String) -> void:
	for tree_id in _trees.keys():
		var tree: Dictionary = _trees.get(tree_id, {}).duplicate(true)

		var skills: Array[String] = _parse_csv(_join_string_array(tree.get("skills", [])))
		for i in range(skills.size()):
			if skills[i] == old_id:
				skills[i] = new_id
		tree["skills"] = skills

		var links: Array[Dictionary] = _parse_links(_format_links(tree.get("links", [])))
		for link in links:
			if str(link.get("from", "")) == old_id:
				link["from"] = new_id
			if str(link.get("to", "")) == old_id:
				link["to"] = new_id
		tree["links"] = links

		var layout: Dictionary = tree.get("layout", {})
		if layout is Dictionary and layout.has(old_id):
			layout[new_id] = layout.get(old_id, {})
			layout.erase(old_id)
			tree["layout"] = layout

		_trees[tree_id] = tree
		if not _dirty_tree_ids.has(tree_id):
			_dirty_tree_ids.append(tree_id)


func _rebuild_validation_errors() -> void:
	_validation_errors.clear()

	for skill_id in _skills.keys():
		var skill: Dictionary = _skills.get(skill_id, {})
		if str(skill.get("name", "")).strip_edges().is_empty():
			_validation_errors.append("skill[%s]: name 不能为空" % skill_id)
		if str(skill.get("tree_id", "")).strip_edges().is_empty():
			_validation_errors.append("skill[%s]: tree_id 不能为空" % skill_id)
		if int(skill.get("max_level", 0)) <= 0:
			_validation_errors.append("skill[%s]: max_level 必须 > 0" % skill_id)
		var gameplay_effect: Variant = skill.get("gameplay_effect", {})
		if not (gameplay_effect is Dictionary) or gameplay_effect.is_empty():
			_validation_errors.append("skill[%s]: gameplay_effect 不能为空" % skill_id)

		var prerequisites: Array[String] = _parse_csv(_join_string_array(skill.get("prerequisites", [])))
		for prerequisite in prerequisites:
			if not _skills.has(prerequisite):
				_validation_errors.append("skill[%s]: prerequisite 不存在 -> %s" % [skill_id, prerequisite])

	for tree_id in _trees.keys():
		var tree: Dictionary = _trees.get(tree_id, {})
		var tree_skills: Array[String] = _parse_csv(_join_string_array(tree.get("skills", [])))
		for skill_id in tree_skills:
			if not _skills.has(skill_id):
				_validation_errors.append("tree[%s]: skill 不存在 -> %s" % [tree_id, skill_id])


func _mark_dirty() -> void:
	if _is_form_syncing:
		return
	_has_unsaved_changes = true


func _set_status(message: String) -> void:
	if _status_label:
		_status_label.text = message
	print("[SkillEditor] %s" % message)

func focus_record(record_id: String) -> bool:
	var target_id: String = record_id.strip_edges()
	if target_id.is_empty():
		return false

	_reload_all()
	if not _skills.has(target_id):
		_set_status("未找到技能: %s" % target_id)
		return false

	var item_index: int = _find_item_list_index(_skill_list, target_id)
	if item_index < 0:
		_set_status("未找到技能: %s" % target_id)
		return false

	_skill_list.select(item_index)
	_on_skill_selected(item_index)
	_skill_list.ensure_current_is_visible()
	_set_status("已定位技能: %s" % target_id)
	return true


func _generate_unique_id(container: Dictionary, base_id: String) -> String:
	var index: int = 1
	var candidate: String = "%s_%d" % [base_id, index]
	while container.has(candidate):
		index += 1
		candidate = "%s_%d" % [base_id, index]
	return candidate


func _find_option_index(button: OptionButton, text: String) -> int:
	for i in range(button.get_item_count()):
		if button.get_item_text(i) == text:
			return i
	return -1


func _find_item_list_index(list: ItemList, text: String) -> int:
	for i in range(list.get_item_count()):
		if list.get_item_text(i) == text:
			return i
	return -1


func _parse_csv(text: String) -> Array[String]:
	var result: Array[String] = []
	for token in text.split(",", false):
		var value: String = token.strip_edges()
		if not value.is_empty():
			result.append(value)
	return result


func _join_string_array(value: Variant) -> String:
	if not (value is Array):
		return ""
	var items: Array[String] = []
	for entry in value:
		items.append(str(entry))
	return ",".join(items)


func _parse_attr_requirements(text: String) -> Dictionary:
	var result: Dictionary = {}
	for token in text.split(",", false):
		var entry: String = token.strip_edges()
		if entry.is_empty():
			continue
		var separator: int = entry.find(":")
		if separator <= 0:
			continue
		var key: String = entry.substr(0, separator).strip_edges()
		var value_text: String = entry.substr(separator + 1).strip_edges()
		result[key] = int(value_text)
	return result


func _format_attr_requirements(value: Variant) -> String:
	if not (value is Dictionary):
		return ""
	var source: Dictionary = value
	var parts: Array[String] = []
	for key in source.keys():
		parts.append("%s:%d" % [str(key), int(source.get(key, 0))])
	parts.sort()
	return ",".join(parts)


func _parse_links(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line in text.split("\n", false):
		var entry: String = line.strip_edges()
		if entry.is_empty():
			continue
		var arrow: int = entry.find("->")
		if arrow <= 0:
			continue
		var from_id: String = entry.substr(0, arrow).strip_edges()
		var to_id: String = entry.substr(arrow + 2).strip_edges()
		if from_id.is_empty() or to_id.is_empty():
			continue
		result.append({"from": from_id, "to": to_id})
	return result


func _format_links(value: Variant) -> String:
	if not (value is Array):
		return ""
	var lines: Array[String] = []
	for link in value:
		if link is Dictionary:
			var item: Dictionary = link
			lines.append("%s -> %s" % [str(item.get("from", "")), str(item.get("to", ""))])
	return "\n".join(lines)


func _add_line_field(grid: GridContainer, label_text: String) -> LineEdit:
	grid.add_child(_make_label(label_text))
	var line: LineEdit = LineEdit.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(line)
	return line


func _add_spin_field(grid: GridContainer, label_text: String, min_v: float, max_v: float, step_v: float) -> SpinBox:
	grid.add_child(_make_label(label_text))
	var spin: SpinBox = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step_v
	spin.value = min_v
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(spin)
	return spin


func _make_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label
