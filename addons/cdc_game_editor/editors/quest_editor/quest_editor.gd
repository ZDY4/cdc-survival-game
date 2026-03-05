@tool
extends Control
## 浠诲姟缂栬緫鍣?
## 闆嗘垚鎾ら攢/閲嶅仛銆佹暟鎹獙璇併€佹敼杩涚殑灞炴€х紪杈戠瓑鍔熻兘

signal quest_saved(quest_id: String)
signal quest_loaded(quest_id: String)
signal validation_errors_found(errors: Array[String])

# 甯搁噺
const OBJECTIVE_TYPES = {
	"collect": "鏀堕泦鐗╁搧",
	"kill": "鍑昏触鏁屼汉",
	"location": "鍒拌揪鍦扮偣",
	"talk": "涓嶯PC瀵硅瘽",
	"custom": "鑷畾涔夋潯浠?
}

const QUEST_STATUS_COLORS = {
	"valid": Color(0.2, 0.8, 0.2),
	"warning": Color(0.9, 0.6, 0.2),
	"error": Color(0.9, 0.2, 0.2)
}

const JSON_VALIDATOR = preload("res://addons/cdc_game_editor/utils/json_validator.gd")

# 鑺傜偣寮曠敤
@onready var _quest_list: ItemList
@onready var _property_panel: Control
@onready var _toolbar: HBoxContainer
@onready var _file_dialog: FileDialog
@onready var _status_bar: Label
@onready var _search_box: LineEdit
@onready var _validation_panel: VBoxContainer

# 鏁版嵁
var quests: Dictionary = {}  # quest_id -> quest_data
var current_quest_id: String = ""
var current_file_path: String = ""
var _validation_errors: Dictionary = {}  # quest_id -> Array[String]

# 宸ュ叿
var _undo_redo_helper: RefCounted

# 缂栬緫鍣ㄦ彃浠跺紩鐢?
var editor_plugin: EditorPlugin = null:
	set(plugin):
		editor_plugin = plugin
		if plugin:
			_undo_redo_helper = load("res://addons/cdc_game_editor/utils/undo_redo_helper.gd").new(plugin)

func _ready():
	_setup_ui()
	_setup_file_dialog()
	_load_quests_from_project_data()
	_update_quest_list()

func _load_quests_from_project_data() -> void:
	var preferred_paths: Array[String] = [
		"res://data/json/quests.json",
		"res://data/quests.json"
	]
	var has_candidate_file := false
	for path in preferred_paths:
		if not FileAccess.file_exists(path):
			continue
		has_candidate_file = true
		if _load_from_file(path):
			return

	if has_candidate_file:
		_update_status("[JSON] project_data | No valid quest JSON file found in project data paths")

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 鍒涘缓宸ュ叿鏍?
	_toolbar = HBoxContainer.new()
	_toolbar.custom_minimum_size = Vector2(0, 45)
	_toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toolbar.offset_top = 0
	_toolbar.offset_bottom = 45
	add_child(_toolbar)
	_create_toolbar()
	
	# 鍒涘缓涓诲垎鍓插鍣?
	var main_split = HSplitContainer.new()
	main_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_split.offset_top = 50
	main_split.offset_bottom = -20
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_split)
	
	# 宸︿晶锛氫换鍔″垪琛?
	var left_panel = _create_quest_list_panel()
	main_split.add_child(left_panel)
	
	# 鍙充晶锛氬睘鎬ч潰鏉垮拰楠岃瘉闈㈡澘
	var right_container = VBoxContainer.new()
	right_container.custom_minimum_size = Vector2(350, 0)
	right_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_child(right_container)
	
	# 鎼滅储妗?
	var search_container = HBoxContainer.new()
	search_container.custom_minimum_size = Vector2(0, 30)
	right_container.add_child(search_container)
	
	var search_label = Label.new()
	search_label.text = "馃攳"
	search_container.add_child(search_label)
	
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "鎼滅储浠诲姟..."
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.text_changed.connect(_on_search_changed)
	search_container.add_child(_search_box)
	
	var clear_btn = Button.new()
	clear_btn.text = "娓呴櫎"
	clear_btn.pressed.connect(func(): _search_box.clear(); _on_search_changed(""))
	search_container.add_child(clear_btn)
	
	# 灞炴€ч潰鏉?
	_property_panel = preload("res://addons/cdc_game_editor/utils/property_panel.gd").new()
	_property_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_property_panel.panel_title = "浠诲姟灞炴€?
	_property_panel.property_changed.connect(_on_property_changed)
	right_container.add_child(_property_panel)
	
	# 楠岃瘉閿欒闈㈡澘
	_validation_panel = VBoxContainer.new()
	_validation_panel.visible = false
	right_container.add_child(_validation_panel)
	
	var validation_title = Label.new()
	validation_title.text = "鈿狅笍 楠岃瘉闂"
	validation_title.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
	_validation_panel.add_child(validation_title)
	_validation_panel.add_child(HSeparator.new())
	
	main_split.split_offset = 250
	
	# 鐘舵€佹爮
	_status_bar = Label.new()
	_status_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_bar.offset_top = -20
	_status_bar.offset_bottom = 0
	_status_bar.offset_left = 0
	_status_bar.offset_right = 0
	_status_bar.text = "灏辩华 - 0 涓换鍔?
	add_child(_status_bar)

func _create_toolbar():
	_add_toolbar_button("鏂板缓", _on_new_quest, "鏂板缓浠诲姟 (Ctrl+N)")
	_add_toolbar_button("鍒犻櫎", _on_delete_quest, "鍒犻櫎閫変腑浠诲姟 (Delete)")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("鎾ら攢", _on_undo, "鎾ら攢 (Ctrl+Z)")
	_add_toolbar_button("閲嶅仛", _on_redo, "閲嶅仛 (Ctrl+Y)")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("淇濆瓨", _on_save_quests, "淇濆瓨鍒版枃浠?(Ctrl+S)")
	_add_toolbar_button("鍔犺浇", _on_load_quests, "浠庢枃浠跺姞杞?)
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("楠岃瘉", _on_validate_all, "楠岃瘉鎵€鏈変换鍔?)
	_add_toolbar_button("瀵煎嚭GD", _on_export_gdscript, "瀵煎嚭涓篏DScript")

func _add_toolbar_button(text: String, callback: Callable, tooltip: String = ""):
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.pressed.connect(callback)
	_toolbar.add_child(btn)

func _create_quest_list_panel() -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	
	# 鏍囬
	var title = Label.new()
	title.text = "浠诲姟鍒楄〃"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	# 浠诲姟鍒楄〃
	_quest_list = ItemList.new()
	_quest_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_quest_list.item_selected.connect(_on_quest_selected)
	vbox.add_child(_quest_list)
	
	return panel

func _setup_file_dialog():
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON 鏂囦欢")
	_file_dialog.add_filter("*.quest; 浠诲姟鏂囦欢")
	add_child(_file_dialog)

func _input(event: InputEvent):
	if not visible:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_DELETE:
				_on_delete_quest()
			KEY_N when event.ctrl_pressed:
				_on_new_quest()
			KEY_S when event.ctrl_pressed:
				_on_save_quests()
			KEY_Z when event.ctrl_pressed and not event.shift_pressed:
				_on_undo()
			KEY_Y when event.ctrl_pressed:
				_on_redo()

# 浠诲姟绠＄悊
func _on_new_quest():
	var quest_id = "quest_%d" % Time.get_ticks_msec()
	var quest_data = {
		"quest_id": quest_id,
		"title": "鏂颁换鍔?,
		"description": "浠诲姟鎻忚堪",
		"objectives": [],
		"rewards": {
			"items": [],
			"experience": 0
		},
		"prerequisites": [],
		"time_limit": -1,
		"_status": "draft"
	}
	var quest_snapshot = quest_data.duplicate(true)
	
	# 鎾ら攢/閲嶅仛
	if _undo_redo_helper:
		_undo_redo_helper.create_action("鍒涘缓浠诲姟")
		_undo_redo_helper.add_undo_method(self, "_remove_quest", quest_id)
		_undo_redo_helper.add_redo_method(self, "_add_quest", quest_id, quest_snapshot)
		_undo_redo_helper.commit_action()
	
	_add_quest(quest_id, quest_data)
	_select_quest(quest_id)
	_update_status("鍒涘缓浜嗘柊浠诲姟: %s" % quest_id)

func _add_quest(quest_id: String, quest_data: Dictionary):
	quests[quest_id] = quest_data.duplicate(true)
	_update_quest_list()
	_validate_quest(quest_id)

func _remove_quest(quest_id: String):
	if quests.has(quest_id):
		var old_data = quests[quest_id].duplicate(true)
		quests.erase(quest_id)
		_validation_errors.erase(quest_id)
		
		if current_quest_id == quest_id:
			current_quest_id = ""
			_property_panel.clear()
		
		_update_quest_list()
		_update_validation_panel()
		return old_data
	return null

func _on_delete_quest():
	if current_quest_id.is_empty():
		return
	
	var quest_id = current_quest_id
	var old_data = quests[quest_id].duplicate(true)
	
	# 鎾ら攢/閲嶅仛
	if _undo_redo_helper:
		_undo_redo_helper.create_action("鍒犻櫎浠诲姟")
		_undo_redo_helper.add_undo_method(self, "_add_quest", quest_id, old_data)
		_undo_redo_helper.add_redo_method(self, "_remove_quest", quest_id)
		_undo_redo_helper.commit_action()
	
	_remove_quest(quest_id)
	_update_status("鍒犻櫎浜嗕换鍔? %s" % quest_id)

func _on_quest_selected(index: int):
	var quest_id = _quest_list.get_item_metadata(index)
	_select_quest(quest_id)

func _select_quest(quest_id: String):
	current_quest_id = quest_id
	var quest = quests.get(quest_id)
	if quest:
		_update_property_panel(quest)
		_update_validation_panel()

func _update_quest_list(filter: String = ""):
	_quest_list.clear()
	
	var sorted_quests = quests.keys()
	sorted_quests.sort()
	
	for quest_id in sorted_quests:
		var quest = quests[quest_id]
		var display_text = "%s - %s" % [quest_id, quest.get("title", "鏈懡鍚?)]
		
		if filter.is_empty() or display_text.to_lower().contains(filter.to_lower()):
			var idx = _quest_list.add_item(display_text)
			_quest_list.set_item_metadata(idx, quest_id)
			
			# 鏍规嵁楠岃瘉鐘舵€佽缃鑹?
			if _validation_errors.has(quest_id) and not _validation_errors[quest_id].is_empty():
				_quest_list.set_item_custom_fg_color(idx, QUEST_STATUS_COLORS.error)
	
	_update_status("鍏?%d 涓换鍔? % quests.size())

func _on_search_changed(text: String):
	_update_quest_list(text)

# 灞炴€ч潰鏉?
func _update_property_panel(quest: Dictionary):
	_property_panel.clear()
	
	if quest.is_empty():
		return
	
	# ID锛堝彲缂栬緫锛屼絾闇€瑕佺壒娈婂鐞嗭級
	_property_panel.add_string_property("quest_id", "浠诲姟ID:", quest.get("quest_id", ""), false, "鍞竴鏍囪瘑绗?)
	
	# 鏍囬鍜屾弿杩?
	_property_panel.add_string_property("title", "浠诲姟鏍囬:", quest.get("title", ""), false, "鏄剧ず鍚嶇О")
	_property_panel.add_string_property("description", "浠诲姟鎻忚堪:", quest.get("description", ""), true, "璇︾粏鎻忚堪...")
	
	_property_panel.add_separator()
	
	# 缁忛獙鍊煎鍔?
	var rewards = quest.get("rewards", {})
	_property_panel.add_number_property("experience", "缁忛獙鍊煎鍔?", 
		rewards.get("experience", 0), 0, 999999, 10, false)
	
	# 鏃堕棿闄愬埗
	_property_panel.add_number_property("time_limit", "鏃堕棿闄愬埗(绉?:", 
		quest.get("time_limit", -1), -1, 999999, 1, false)
	
	_property_panel.add_separator()
	
	# 鑷畾涔夋帶浠讹細鐩爣鍒楄〃
	_property_panel.add_custom_control(_create_objectives_editor(quest))
	
	_property_panel.add_separator()
	
	# 鑷畾涔夋帶浠讹細濂栧姳鐗╁搧鍒楄〃
	_property_panel.add_custom_control(_create_rewards_editor(quest))
	
	_property_panel.add_separator()
	
	# 鑷畾涔夋帶浠讹細鍓嶇疆浠诲姟
	_property_panel.add_custom_control(_create_prerequisites_editor(quest))

func _create_objectives_editor(quest: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "馃搵 浠诲姟鐩爣 (%d涓?" % quest.objectives.size()
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(label)
	
	var list_container = VBoxContainer.new()
	list_container.name = "ObjectivesList"
	container.add_child(list_container)
	
	_refresh_objectives_list(list_container, quest)
	
	var add_btn = Button.new()
	add_btn.text = "+ 娣诲姞鐩爣"
	add_btn.pressed.connect(func(): _add_objective(quest, list_container))
	container.add_child(add_btn)
	
	return container

func _refresh_objectives_list(container: VBoxContainer, quest: Dictionary):
	for child in container.get_children():
		child.queue_free()
	
	var objectives = quest.get("objectives", [])
	for i in range(objectives.size()):
		var obj = objectives[i]
		var row = _create_objective_row(quest, i, obj, container)
		container.add_child(row)

func _create_objective_row(quest: Dictionary, index: int, obj: Dictionary, list_container: VBoxContainer) -> Control:
	var panel = PanelContainer.new()
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	# 绫诲瀷鍜岀洰鏍?
	var top_row = HBoxContainer.new()
	vbox.add_child(top_row)
	
	var type_option = OptionButton.new()
	for key in OBJECTIVE_TYPES:
		type_option.add_item(OBJECTIVE_TYPES[key], type_option.item_count)
		type_option.set_item_metadata(type_option.item_count - 1, key)
		if key == obj.get("type", "collect"):
			type_option.selected = type_option.item_count - 1
	
	type_option.item_selected.connect(func(i):
		var type_key = type_option.get_item_metadata(i)
		_on_objective_field_changed(quest, index, "type", type_key)
	)
	top_row.add_child(type_option)
	
	var target_edit = LineEdit.new()
	target_edit.text = obj.get("target", "")
	target_edit.placeholder_text = "鐩爣ID"
	target_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_edit.text_changed.connect(func(v): _on_objective_field_changed(quest, index, "target", v))
	top_row.add_child(target_edit)
	
	var count_spin = SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 999
	count_spin.value = obj.get("count", 1)
	count_spin.value_changed.connect(func(v): _on_objective_field_changed(quest, index, "count", int(v)))
	top_row.add_child(count_spin)
	
	# 鎻忚堪
	var desc_row = HBoxContainer.new()
	vbox.add_child(desc_row)
	
	var desc_edit = LineEdit.new()
	desc_edit.text = obj.get("description", "")
	desc_edit.placeholder_text = "鐩爣鎻忚堪"
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.text_changed.connect(func(v): _on_objective_field_changed(quest, index, "description", v))
	desc_row.add_child(desc_edit)
	
	var del_btn = Button.new()
	del_btn.text = "脳"
	del_btn.tooltip_text = "鍒犻櫎鐩爣"
	del_btn.pressed.connect(func(): _remove_objective(quest, index, list_container))
	desc_row.add_child(del_btn)
	
	return panel

func _on_objective_field_changed(quest: Dictionary, index: int, field: String, value: Variant):
	if index < quest.objectives.size():
		quest.objectives[index][field] = value
		_validate_quest(quest.quest_id)

func _add_objective(quest: Dictionary, list_container: VBoxContainer):
	var new_objective = {
		"type": "collect",
		"target": "",
		"count": 1,
		"description": "鏂扮洰鏍?
	}
	var quest_id = str(quest.get("quest_id", ""))
	var insert_index = quest.objectives.size()
	
	# 鎾ら攢/閲嶅仛
	if _undo_redo_helper and not quest_id.is_empty():
		_undo_redo_helper.create_action("娣诲姞鐩爣")
		_undo_redo_helper.add_undo_method(self, "_remove_objective_at", quest_id, insert_index)
		_undo_redo_helper.add_redo_method(self, "_insert_objective_at", quest_id, insert_index, new_objective)
		_undo_redo_helper.commit_action()
	
	quest.objectives.append(new_objective)
	_refresh_objectives_list(list_container, quest)
	_validate_quest(quest.quest_id)

func _remove_objective(quest: Dictionary, index: int, list_container: VBoxContainer):
	if index < quest.objectives.size():
		var old_obj = quest.objectives[index].duplicate(true)
		var quest_id = str(quest.get("quest_id", ""))
		
		# 鎾ら攢/閲嶅仛
		if _undo_redo_helper and not quest_id.is_empty():
			_undo_redo_helper.create_action("鍒犻櫎鐩爣")
			_undo_redo_helper.add_undo_method(self, "_insert_objective_at", quest_id, index, old_obj)
			_undo_redo_helper.add_redo_method(self, "_remove_objective_at", quest_id, index)
			_undo_redo_helper.commit_action()
		
		quest.objectives.remove_at(index)
		_refresh_objectives_list(list_container, quest)
		_validate_quest(quest.quest_id)

func _remove_objective_at(quest_id: String, index: int):
	var quest = quests.get(quest_id, {})
	if quest and index >= 0 and index < quest.objectives.size():
		quest.objectives.remove_at(index)
		_validate_quest(quest_id)
		if current_quest_id == quest_id:
			_update_property_panel(quest)
		_update_quest_list(_search_box.text)
		_update_validation_panel()

func _insert_objective_at(quest_id: String, index: int, obj: Dictionary):
	var quest = quests.get(quest_id, {})
	if not quest:
		return
	var target_index: int = clampi(index, 0, quest.objectives.size())
	quest.objectives.insert(target_index, obj.duplicate(true))
	_validate_quest(quest_id)
	if current_quest_id == quest_id:
		_update_property_panel(quest)
	_update_quest_list(_search_box.text)
	_update_validation_panel()

func _create_rewards_editor(quest: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "馃巵 鐗╁搧濂栧姳"
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(label)
	
	var rewards = quest.get("rewards", {})
	var items = rewards.get("items", [])
	
	var list = VBoxContainer.new()
	list.name = "RewardsList"
	container.add_child(list)
	
	for i in range(items.size()):
		var row = _create_reward_row(quest, i, items[i], list)
		list.add_child(row)
	
	var add_btn = Button.new()
	add_btn.text = "+ 娣诲姞鐗╁搧"
	add_btn.pressed.connect(func(): _add_reward_item(quest, list))
	container.add_child(add_btn)
	
	return container

func _create_reward_row(quest: Dictionary, index: int, item: Dictionary, list: VBoxContainer) -> Control:
	var row = HBoxContainer.new()
	
	var id_edit = LineEdit.new()
	id_edit.text = item.get("id", "")
	id_edit.placeholder_text = "鐗╁搧ID"
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_edit.text_changed.connect(func(v):
		quest.rewards.items[index].id = v
	)
	row.add_child(id_edit)
	
	var count_spin = SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 999
	count_spin.value = item.get("count", 1)
	count_spin.value_changed.connect(func(v):
		quest.rewards.items[index].count = int(v)
	)
	row.add_child(count_spin)
	
	var del_btn = Button.new()
	del_btn.text = "脳"
	del_btn.pressed.connect(func(): _remove_reward_item(quest, index, list))
	row.add_child(del_btn)
	
	return row

func _add_reward_item(quest: Dictionary, list: VBoxContainer):
	quest.rewards.items.append({"id": "", "count": 1})
	_refresh_rewards_list(list, quest)

func _remove_reward_item(quest: Dictionary, index: int, list: VBoxContainer):
	if index < quest.rewards.items.size():
		quest.rewards.items.remove_at(index)
		_refresh_rewards_list(list, quest)

func _refresh_rewards_list(list: VBoxContainer, quest: Dictionary):
	for child in list.get_children():
		child.queue_free()
	
	var items = quest.get("rewards", {}).get("items", [])
	for i in range(items.size()):
		var row = _create_reward_row(quest, i, items[i], list)
		list.add_child(row)

func _create_prerequisites_editor(quest: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "馃敆 鍓嶇疆浠诲姟"
	label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(label)
	
	var prereq_list = VBoxContainer.new()
	prereq_list.name = "PrereqList"
	container.add_child(prereq_list)
	
	_refresh_prereq_list(prereq_list, quest)
	
	var add_btn = Button.new()
	add_btn.text = "+ 娣诲姞鍓嶇疆浠诲姟"
	add_btn.pressed.connect(func(): _show_prereq_selector(quest, prereq_list))
	container.add_child(add_btn)
	
	return container

func _refresh_prereq_list(list: VBoxContainer, quest: Dictionary):
	for child in list.get_children():
		child.queue_free()
	
	for prereq_id in quest.get("prerequisites", []):
		var row = HBoxContainer.new()
		
		var id_label = Label.new()
		id_label.text = prereq_id
		id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(id_label)
		
		var del_btn = Button.new()
		del_btn.text = "脳"
		del_btn.pressed.connect(func(): _remove_prereq(quest, prereq_id, list))
		row.add_child(del_btn)
		
		list.add_child(row)

func _show_prereq_selector(quest: Dictionary, list: VBoxContainer):
	var popup = PopupPanel.new()
	popup.size = Vector2(400, 300)
	
	var vbox = VBoxContainer.new()
	popup.add_child(vbox)
	
	var title = Label.new()
	title.text = "閫夋嫨鍓嶇疆浠诲姟"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var item_list = ItemList.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(item_list)
	
	for quest_id in quests:
		if quest_id != quest.quest_id and not quest.prerequisites.has(quest_id):
			var q = quests[quest_id]
			var idx = item_list.add_item("%s - %s" % [quest_id, q.get("title", "")])
			item_list.set_item_metadata(idx, quest_id)
	
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)
	
	var confirm_btn = Button.new()
	confirm_btn.text = "纭"
	confirm_btn.pressed.connect(func():
		var selected = item_list.get_selected_items()
		if selected.size() > 0:
			var prereq_id = item_list.get_item_metadata(selected[0])
			_add_prereq(quest, prereq_id, list)
		popup.queue_free()
	)
	btn_box.add_child(confirm_btn)
	
	add_child(popup)
	popup.popup_centered()

func _add_prereq(quest: Dictionary, prereq_id: String, list: VBoxContainer):
	if not quest.prerequisites.has(prereq_id):
		quest.prerequisites.append(prereq_id)
		_refresh_prereq_list(list, quest)
		_validate_quest(quest.quest_id)

func _remove_prereq(quest: Dictionary, prereq_id: String, list: VBoxContainer):
	quest.prerequisites.erase(prereq_id)
	_refresh_prereq_list(list, quest)
	_validate_quest(quest.quest_id)

# 灞炴€у彉鏇?
func _on_property_changed(property_name: String, new_value: Variant, old_value: Variant):
	if current_quest_id.is_empty():
		return
	
	var quest = quests[current_quest_id]
	
	# 鐗规畩澶勭悊宓屽灞炴€?
	if property_name == "experience":
		quest.rewards.experience = int(new_value)
	elif property_name == "time_limit":
		quest.time_limit = int(new_value)
	elif property_name == "quest_id":
		# ID鍙樻洿闇€瑕佺壒娈婂鐞?
		if new_value != current_quest_id and not new_value.is_empty():
			if _undo_redo_helper:
				_undo_redo_helper.create_action("淇敼浠诲姟ID")
				_undo_redo_helper.add_undo_method(self, "_change_quest_id", new_value, current_quest_id)
				_undo_redo_helper.add_redo_method(self, "_change_quest_id", current_quest_id, new_value)
				_undo_redo_helper.commit_action()
			_change_quest_id(current_quest_id, new_value)
			return
	else:
		quest[property_name] = new_value
	
	_validate_quest(current_quest_id)
	_update_quest_list()

func _change_quest_id(old_id: String, new_id: String):
	if quests.has(old_id) and not quests.has(new_id):
		var data = quests[old_id]
		data.quest_id = new_id
		quests.erase(old_id)
		quests[new_id] = data
		
		if _validation_errors.has(old_id):
			_validation_errors[new_id] = _validation_errors[old_id]
			_validation_errors.erase(old_id)
		
		current_quest_id = new_id
		_update_quest_list()
		_select_quest(new_id)

# 楠岃瘉
func _validate_quest(quest_id: String) -> bool:
	var quest = quests.get(quest_id)
	if not quest:
		return false
	
	var errors: Array[String] = []
	
	# 妫€鏌D
	if quest_id.is_empty():
		errors.append("浠诲姟ID涓嶈兘涓虹┖")
	
	# 妫€鏌ユ爣棰?
	if quest.get("title", "").is_empty():
		errors.append("浠诲姟鏍囬涓嶈兘涓虹┖")
	
	# 妫€鏌ョ洰鏍?
	var objectives = quest.get("objectives", [])
	if objectives.is_empty():
		errors.append("鑷冲皯闇€瑕佽缃竴涓洰鏍?)
	
	for i in range(objectives.size()):
		var obj = objectives[i]
		if obj.get("target", "").is_empty():
			errors.append("鐩爣 #%d 缂哄皯鐩爣ID" % (i + 1))
	
	# 妫€鏌ュ墠缃换鍔?
	for prereq in quest.get("prerequisites", []):
		if not quests.has(prereq):
			errors.append("鍓嶇疆浠诲姟 '%s' 涓嶅瓨鍦? % prereq)
	
	_validation_errors[quest_id] = errors
	return errors.is_empty()

func _validate_all():
	var all_errors: Array[String] = []
	
	for quest_id in quests:
		if not _validate_quest(quest_id):
			for error in _validation_errors[quest_id]:
				all_errors.append("%s: %s" % [quest_id, error])
	
	validation_errors_found.emit(all_errors)
	return all_errors

func _on_validate_all():
	var errors = _validate_all()
	_update_validation_panel()
	
	if errors.is_empty():
		_update_status("鉁?鎵€鏈変换鍔￠獙璇侀€氳繃")
	else:
		_update_status("鈿狅笍 鍙戠幇 %d 涓棶棰? % errors.size())

func _update_validation_panel():
	if current_quest_id.is_empty():
		_validation_panel.visible = false
		return
	
	var errors = _validation_errors.get(current_quest_id, [])
	
	if errors.is_empty():
		_validation_panel.visible = false
		return
	
	_validation_panel.visible = true
	
	# 娓呴櫎鏃х殑閿欒鏄剧ず锛堜繚鐣欐爣棰樺拰鍒嗛殧绗︼級
	while _validation_panel.get_child_count() > 2:
		_validation_panel.remove_child(_validation_panel.get_child(2))
	
	for error in errors:
		var label = Label.new()
		label.text = "鈥?%s" % error
		label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_validation_panel.add_child(label)

# 鏂囦欢鎿嶄綔
func _on_save_quests():
	if current_file_path.is_empty():
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.current_file = "quests.json"
		_file_dialog.file_selected.connect(_save_to_file, CONNECT_ONE_SHOT)
		_file_dialog.popup_centered(Vector2(800, 600))
	else:
		_save_to_file(current_file_path)

func _save_to_file(path: String):
	current_file_path = path
	var json = JSON.stringify(quests, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		quest_saved.emit(current_quest_id)
		_update_status("鉁?宸蹭繚瀛? %s" % path)
	else:
		_update_status("鉂?鏃犳硶淇濆瓨鏂囦欢")

func _on_load_quests():
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.file_selected.connect(_load_from_file, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _load_from_file(path: String) -> bool:
	var validation := JSON_VALIDATOR.validate_file(path, {
		"root_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"wrapper_key": "quests",
		"wrapper_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_label": "quest"
	})
	if not bool(validation.get("ok", false)):
		_update_status(str(validation.get("message", "[JSON] Unknown validation error")))
		return false

	var loaded_quests: Variant = validation.get("data", {})
	if not (loaded_quests is Dictionary):
		_update_status("[JSON] %s | Invalid validator result: data must be Dictionary" % path)
		return false
	quests = loaded_quests

	current_file_path = path
	current_quest_id = ""
	_validation_errors.clear()
	
	# Validate all quests after load.
	for quest_id in quests:
		_validate_quest(quest_id)
	
	_update_quest_list()
	_property_panel.clear()
	quest_loaded.emit(current_quest_id)
	_update_status("Loaded: %s" % path)
	return true

func _on_export_gdscript():
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "quest_data.gd"
	_file_dialog.file_selected.connect(func(path):
		var output = _build_gdscript()
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(output)
			file.close()
			_update_status("鉁?宸插鍑篏DScript")
	, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _build_gdscript() -> String:
	var lines: Array[String] = []
	lines.append("# 鑷姩鐢熸垚鐨勪换鍔℃暟鎹?)
	lines.append("# 鐢熸垚鏃堕棿: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("const QUESTS = {")
	
	var quest_keys = quests.keys()
	for i in range(quest_keys.size()):
		var quest_id = quest_keys[i]
		var quest = quests[quest_id]
		
		lines.append('\t"%s": {' % quest_id)
		lines.append('\t\t"quest_id": "%s",' % quest_id)
		lines.append('\t\t"title": "%s",' % quest.get("title", ""))
		lines.append('\t\t"description": "%s",' % quest.get("description", ""))
		
		# 鐩爣
		lines.append('\t\t"objectives": [')
		for obj in quest.get("objectives", []):
			lines.append('\t\t\t{')
			lines.append('\t\t\t\t"type": "%s",' % obj.get("type", ""))
			lines.append('\t\t\t\t"target": "%s",' % obj.get("target", ""))
			lines.append('\t\t\t\t"count": %d,' % obj.get("count", 1))
			lines.append('\t\t\t\t"description": "%s"' % obj.get("description", ""))
			lines.append('\t\t\t},')
		lines.append('\t\t],')
		
		# 濂栧姳
		lines.append('\t\t"rewards": {')
		lines.append('\t\t\t"items": [')
		for item in quest.get("rewards", {}).get("items", []):
			lines.append('\t\t\t\t{"id": "%s", "count": %d},' % [item.get("id", ""), item.get("count", 1)])
		lines.append('\t\t\t],')
		lines.append('\t\t\t"experience": %d' % quest.get("rewards", {}).get("experience", 0))
		lines.append('\t\t},')
		
		# 鍓嶇疆浠诲姟
		lines.append('\t\t"prerequisites": %s,' % str(quest.get("prerequisites", [])))
		lines.append('\t\t"time_limit": %d' % quest.get("time_limit", -1))
		lines.append('\t},')
	
	lines.append('}')
	lines.append("")
	lines.append("static func get_quest(quest_id: String):")
	lines.append("\treturn QUESTS.get(quest_id, null)")
	
	return "\n".join(lines)

# 鎾ら攢/閲嶅仛
func _on_undo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().undo()
		_update_status("鎾ら攢")
		_update_quest_list()
		_update_validation_panel()

func _on_redo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().redo()
		_update_status("閲嶅仛")
		_update_quest_list()
		_update_validation_panel()

func _update_status(message: String):
	_status_bar.text = "%s - 鍏?%d 涓换鍔? % [message, quests.size()]
	print("浠诲姟缂栬緫鍣? %s" % message)

# 鍏叡鏂规硶
func get_current_quest_id() -> String:
	return current_quest_id

func get_quests_count() -> int:
	return quests.size()

func get_validation_errors() -> Dictionary:
	return _validation_errors

