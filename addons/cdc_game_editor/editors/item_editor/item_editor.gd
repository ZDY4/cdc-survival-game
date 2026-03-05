@tool
extends Control
## 鐗╁搧缂栬緫鍣?
## 鐢ㄤ簬鍒涘缓鍜岀鐞嗘父鎴忎腑鐨勬墍鏈夌墿鍝佹暟鎹?

signal item_saved(item_id: String)
signal item_loaded(item_id: String)
signal items_exported(path: String)

# 鐗╁搧绫诲瀷甯搁噺
const ITEM_TYPES = {
	"weapon": "姝﹀櫒",
	"armor": "鎶ょ敳",
	"consumable": "娑堣€楀搧",
	"material": "鏉愭枡",
	"misc": "鏉傞」"
}

const RARITY_LEVELS = {
	"common": "鏅€?,
	"uncommon": " uncommon",
	"rare": "绋€鏈?,
	"epic": "鍙茶瘲",
	"legendary": "浼犺"
}

const EQUIPMENT_SLOTS = {
	"head": "澶撮儴",
	"body": "韬綋",
	"hands": "鎵嬮儴",
	"legs": "鑵块儴",
	"feet": "鑴氶儴",
	"back": "鑳岄儴",
	"main_hand": "涓绘墜",
	"off_hand": "鍓墜",
	"accessory_1": "楗板搧1",
	"accessory_2": "楗板搧2"
}

const WEAPON_SUBTYPES = {
	"unarmed": "寰掓墜",
	"dagger": "鍖曢",
	"sword": "鍓?,
	"blunt": "閽濆櫒",
	"axe": "鏂?,
	"spear": "闀跨煕",
	"polearm": "闀挎焺",
	"bow": "寮?,
	"gun": "鏋"
}

const JSON_VALIDATOR = preload("res://addons/cdc_game_editor/utils/json_validator.gd")

# 鑺傜偣寮曠敤
@onready var _item_list: ItemList
@onready var _category_filter: OptionButton
@onready var _search_box: LineEdit
@onready var _property_panel: Control
@onready var _toolbar: HBoxContainer
@onready var _file_dialog: FileDialog
@onready var _status_bar: Label
@onready var _validation_panel: VBoxContainer
@onready var _stats_label: Label

# 鏁版嵁
var items: Dictionary = {}  # item_id -> item_data
var current_item_id: String = ""
var current_file_path: String = ""
var _validation_errors: Dictionary = {}

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
	_load_items_from_project_data()
	if items.is_empty():
		_load_default_items()
	_update_item_list()
	_update_stats()

func _load_items_from_project_data() -> void:
	var preferred_paths: Array[String] = [
		"res://data/json/items.json",
		"res://data/items.json"
	]
	var has_candidate_file := false
	for path in preferred_paths:
		if not FileAccess.file_exists(path):
			continue
		has_candidate_file = true
		if _load_from_file(path):
			return

	if has_candidate_file:
		_update_status("[JSON] project_data | No valid item JSON file found in project data paths")

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 宸ュ叿鏍?
	_toolbar = HBoxContainer.new()
	_toolbar.custom_minimum_size = Vector2(0, 45)
	_toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toolbar.offset_top = 0
	_toolbar.offset_bottom = 45
	add_child(_toolbar)
	_create_toolbar()
	
	# 涓诲垎鍓插鍣?
	var main_split = HSplitContainer.new()
	main_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_split.offset_top = 50
	main_split.offset_bottom = -20
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_split)
	
	# 宸︿晶闈㈡澘锛氱墿鍝佸垪琛?+ 杩囨护
	var left_panel = _create_left_panel()
	main_split.add_child(left_panel)
	
	# 鍙充晶闈㈡澘锛氬睘鎬х紪杈?
	var right_panel = _create_right_panel()
	main_split.add_child(right_panel)
	
	main_split.split_offset = 280
	
	# 鐘舵€佹爮
	_status_bar = Label.new()
	_status_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_bar.offset_top = -20
	_status_bar.offset_bottom = 0
	_status_bar.offset_left = 0
	_status_bar.offset_right = 0
	_status_bar.text = "灏辩华 - 0 涓墿鍝?
	add_child(_status_bar)

func _create_toolbar():
	_add_toolbar_button("鏂板缓", _on_new_item, "鏂板缓鐗╁搧 (Ctrl+N)")
	_add_toolbar_button("鍒犻櫎", _on_delete_item, "鍒犻櫎鐗╁搧 (Delete)")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("鎾ら攢", _on_undo, "鎾ら攢 (Ctrl+Z)")
	_add_toolbar_button("閲嶅仛", _on_redo, "閲嶅仛 (Ctrl+Y)")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("淇濆瓨", _on_save_items, "淇濆瓨鍒版枃浠?(Ctrl+S)")
	_add_toolbar_button("鍔犺浇", _on_load_items, "浠庢枃浠跺姞杞?)
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("楠岃瘉", _on_validate_all, "楠岃瘉鎵€鏈夌墿鍝?)
	_add_toolbar_button("瀵煎嚭", _on_export_data, "瀵煎嚭鏁版嵁")

func _add_toolbar_button(text: String, callback: Callable, tooltip: String = ""):
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.pressed.connect(callback)
	_toolbar.add_child(btn)

func _create_left_panel() -> Control:
	var panel = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	
	# 鏍囬
	var title = Label.new()
	title.text = "馃摝 鐗╁搧鍒楄〃"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)
	
	panel.add_child(HSeparator.new())
	
	# 鍒嗙被杩囨护
	var filter_row = HBoxContainer.new()
	panel.add_child(filter_row)
	
	var filter_label = Label.new()
	filter_label.text = "鍒嗙被:"
	filter_row.add_child(filter_label)
	
	_category_filter = OptionButton.new()
	_category_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_filter.add_item("鍏ㄩ儴", 0)
	_category_filter.set_item_metadata(0, "")
	var idx = 1
	for type_key in ITEM_TYPES:
		_category_filter.add_item(ITEM_TYPES[type_key], idx)
		_category_filter.set_item_metadata(idx, type_key)
		idx += 1
	_category_filter.item_selected.connect(_on_category_changed)
	filter_row.add_child(_category_filter)
	
	# 鎼滅储妗?
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "馃攳 鎼滅储鐗╁搧..."
	_search_box.text_changed.connect(_on_search_changed)
	panel.add_child(_search_box)
	
	# 鐗╁搧鍒楄〃
	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.item_selected.connect(_on_item_selected)
	panel.add_child(_item_list)
	
	# 缁熻淇℃伅
	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.text = "鎬昏: 0 | 姝﹀櫒: 0 | 鎶ょ敳: 0 | 娑堣€楀搧: 0"
	_stats_label.add_theme_color_override("font_color", Color.GRAY)
	panel.add_child(_stats_label)
	
	return panel

func _create_right_panel() -> Control:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(400, 0)
	
	# 灞炴€ч潰鏉?
	_property_panel = preload("res://addons/cdc_game_editor/utils/property_panel.gd").new()
	_property_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_property_panel.panel_title = "鐗╁搧灞炴€?
	_property_panel.property_changed.connect(_on_property_changed)
	container.add_child(_property_panel)
	
	# 楠岃瘉閿欒闈㈡澘
	_validation_panel = VBoxContainer.new()
	_validation_panel.visible = false
	container.add_child(_validation_panel)
	
	var validation_title = Label.new()
	validation_title.text = "鈿狅笍 楠岃瘉闂"
	validation_title.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
	_validation_panel.add_child(validation_title)
	_validation_panel.add_child(HSeparator.new())
	
	return container

func _setup_file_dialog():
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON 鏂囦欢")
	_file_dialog.add_filter("*.items; 鐗╁搧鏁版嵁鏂囦欢")
	add_child(_file_dialog)

func _input(event: InputEvent):
	if not visible:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_DELETE:
				_on_delete_item()
			KEY_N when event.ctrl_pressed:
				_on_new_item()
			KEY_S when event.ctrl_pressed:
				_on_save_items()
			KEY_Z when event.ctrl_pressed and not event.shift_pressed:
				_on_undo()
			KEY_Y when event.ctrl_pressed:
				_on_redo()

# 榛樿鐗╁搧鏁版嵁
func _load_default_items():
	# 濡傛灉杩樻病鏈夌墿鍝侊紝鍔犺浇涓€浜涢粯璁ょず渚?
	if items.is_empty():
		items = {
			"fist": {
				"id": "fist",
				"name": "鎷冲ご",
				"description": "鏈€鍩虹鐨勬敾鍑绘柟寮?,
				"type": "weapon",
				"slot": "main_hand",
				"subtype": "unarmed",
				"rarity": "common",
				"weight": 0.0,
				"durability": -1,
				"max_durability": -1,
				"weapon_data": {
					"damage": 5,
					"attack_speed": 1.0,
					"range": 1,
					"stamina_cost": 2,
					"crit_chance": 0.05,
					"crit_multiplier": 1.5
				},
				"special_effects": [],
				"required_level": 0
			}
		}

# 鐗╁搧绠＄悊
func _on_new_item():
	var item_id = "item_%d" % Time.get_ticks_msec()
	var item_data = {
		"id": item_id,
		"name": "鏂扮墿鍝?,
		"description": "鐗╁搧鎻忚堪",
		"type": "misc",
		"rarity": "common",
		"weight": 0.0,
		"durability": 100,
		"max_durability": 100,
		"required_level": 0,
		"special_effects": []
	}
	var item_snapshot = item_data.duplicate(true)
	
	# 鎾ら攢/閲嶅仛
	if _undo_redo_helper:
		_undo_redo_helper.create_action("鍒涘缓鐗╁搧")
		_undo_redo_helper.add_undo_method(self, "_remove_item", item_id)
		_undo_redo_helper.add_redo_method(self, "_add_item", item_id, item_snapshot)
		_undo_redo_helper.commit_action()
	
	_add_item(item_id, item_data)
	_select_item(item_id)
	_update_status("鍒涘缓浜嗘柊鐗╁搧: %s" % item_id)

func _add_item(item_id: String, item_data: Dictionary):
	items[item_id] = item_data.duplicate(true)
	_update_item_list()
	_update_stats()

func _remove_item(item_id: String) -> Dictionary:
	if items.has(item_id):
		var old_data = items[item_id].duplicate(true)
		items.erase(item_id)
		_validation_errors.erase(item_id)
		
		if current_item_id == item_id:
			current_item_id = ""
			_property_panel.clear()
		
		_update_item_list()
		_update_stats()
		_update_validation_panel()
		return old_data
	return {}

func _on_delete_item():
	if current_item_id.is_empty():
		return
	
	var item_id = current_item_id
	var old_data = items[item_id].duplicate(true)
	
	# 鎾ら攢/閲嶅仛
	if _undo_redo_helper:
		_undo_redo_helper.create_action("鍒犻櫎鐗╁搧")
		_undo_redo_helper.add_undo_method(self, "_add_item", item_id, old_data)
		_undo_redo_helper.add_redo_method(self, "_remove_item", item_id)
		_undo_redo_helper.commit_action()
	
	_remove_item(item_id)
	_update_status("鍒犻櫎浜嗙墿鍝? %s" % item_id)

func _on_item_selected(index: int):
	var item_id = _item_list.get_item_metadata(index)
	_select_item(item_id)

func _select_item(item_id: String):
	current_item_id = item_id
	var item = items.get(item_id)
	if item:
		_update_property_panel(item)
		_update_validation_panel()

func _update_item_list(filter_text: String = "", category_filter: String = ""):
	_item_list.clear()
	
	var sorted_items = items.keys()
	sorted_items.sort()
	
	for item_id in sorted_items:
		var item = items[item_id]
		var item_type = item.get("type", "misc")
		var item_name = item.get("name", "鏈懡鍚?)
		
		# 鍒嗙被杩囨护
		if not category_filter.is_empty() and item_type != category_filter:
			continue
		
		# 鎼滅储杩囨护
		var display_text = "%s - %s" % [item_id, item_name]
		if not filter_text.is_empty():
			if not display_text.to_lower().contains(filter_text.to_lower()):
				continue
		
		var idx = _item_list.add_item(display_text)
		_item_list.set_item_metadata(idx, item_id)
		
		# 鏍规嵁绋€鏈夊害璁剧疆棰滆壊
		var rarity = item.get("rarity", "common")
		var color = _get_rarity_color(rarity)
		_item_list.set_item_custom_fg_color(idx, color)

func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color.WHITE
		"uncommon": return Color.LIME
		"rare": return Color.CYAN
		"epic": return Color.MAGENTA
		"legendary": return Color.GOLD
		_: return Color.WHITE

func _update_stats():
	var total = items.size()
	var weapons = 0
	var armors = 0
	var consumables = 0
	var materials = 0
	
	for item_id in items:
		var item = items[item_id]
		match item.get("type", ""):
			"weapon": weapons += 1
			"armor": armors += 1
			"consumable": consumables += 1
			"material": materials += 1
	
	if _stats_label and is_instance_valid(_stats_label):
		_stats_label.text = "鎬昏: %d | 姝﹀櫒: %d | 鎶ょ敳: %d | 娑堣€楀搧: %d | 鏉愭枡: %d" % [
			total, weapons, armors, consumables, materials
		]

func _on_category_changed(index: int):
	var category = _category_filter.get_item_metadata(index)
	_update_item_list(_search_box.text, category)

func _on_search_changed(text: String):
	var category = _category_filter.get_item_metadata(_category_filter.selected)
	_update_item_list(text, category)

# 灞炴€ч潰鏉?
func _update_property_panel(item: Dictionary):
	_property_panel.clear()
	
	if item.is_empty():
		return
	
	# 鍩虹淇℃伅
	_property_panel.add_string_property("id", "鐗╁搧ID:", item.get("id", ""), false, "鍞竴鏍囪瘑绗?)
	_property_panel.add_string_property("name", "鏄剧ず鍚嶇О:", item.get("name", ""), false, "鐗╁搧鍚嶇О")
	_property_panel.add_string_property("description", "鎻忚堪:", item.get("description", ""), true, "鐗╁搧鎻忚堪...")
	
	_property_panel.add_separator()
	
	# 绫诲瀷鍜岀█鏈夊害
	_property_panel.add_enum_property("type", "鐗╁搧绫诲瀷:", ITEM_TYPES, item.get("type", "misc"))
	_property_panel.add_enum_property("rarity", "绋€鏈夊害:", RARITY_LEVELS, item.get("rarity", "common"))
	
	_property_panel.add_separator()
	
	# 鍩虹灞炴€?
	_property_panel.add_number_property("weight", "閲嶉噺:", item.get("weight", 0.0), 0.0, 1000.0, 0.1, true)
	_property_panel.add_number_property("durability", "褰撳墠鑰愪箙:", item.get("durability", 100), -1, 9999, 1, false)
	_property_panel.add_number_property("max_durability", "鏈€澶ц€愪箙:", item.get("max_durability", 100), 1, 9999, 1, false)
	_property_panel.add_number_property("required_level", "闇€姹傜瓑绾?", item.get("required_level", 0), 0, 100, 1, false)
	
	_property_panel.add_separator()
	
	# 鏍规嵁绫诲瀷鏄剧ず鐗瑰畾灞炴€?
	var item_type = item.get("type", "")
	match item_type:
		"weapon":
			_property_panel.add_enum_property("slot", "瑁呭妲戒綅:", EQUIPMENT_SLOTS, item.get("slot", "main_hand"))
			_property_panel.add_enum_property("subtype", "姝﹀櫒绫诲瀷:", WEAPON_SUBTYPES, item.get("subtype", "unarmed"))
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_weapon_data_editor(item))
		
		"armor":
			_property_panel.add_enum_property("slot", "瑁呭妲戒綅:", EQUIPMENT_SLOTS, item.get("slot", "body"))
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_armor_data_editor(item))
		
		"consumable":
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_consumable_editor(item))
	
	_property_panel.add_separator()
	
	# 鐗规畩鏁堟灉
	_property_panel.add_custom_control(_create_effects_editor(item))

func _create_weapon_data_editor(item: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "鈿旓笍 姝﹀櫒灞炴€?
	label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.4))
	container.add_child(label)
	
	var weapon_data = item.get("weapon_data", {})
	
	var grid = GridContainer.new()
	grid.columns = 2
	container.add_child(grid)
	
	_add_number_field(grid, "浼ゅ:", weapon_data.get("damage", 0), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.damage = int(v)
	)
	
	_add_number_field(grid, "鏀诲嚮閫熷害:", weapon_data.get("attack_speed", 1.0), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.attack_speed = float(v)
	, true)
	
	_add_number_field(grid, "鏀诲嚮鑼冨洿:", weapon_data.get("range", 1), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.range = int(v)
	)
	
	_add_number_field(grid, "鑰愬姏娑堣€?", weapon_data.get("stamina_cost", 0), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.stamina_cost = int(v)
	)
	
	_add_number_field(grid, "鏆村嚮鐜?%):", weapon_data.get("crit_chance", 0.05) * 100, func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.crit_chance = float(v) / 100.0
	, true)
	
	_add_number_field(grid, "鏆村嚮鍊嶆暟:", weapon_data.get("crit_multiplier", 1.5), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.crit_multiplier = float(v)
	, true)
	
	return container

func _create_armor_data_editor(item: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "馃洝锔?鎶ょ敳灞炴€?
	label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8))
	container.add_child(label)
	
	var armor_data = item.get("armor_data", {})
	
	var grid = GridContainer.new()
	grid.columns = 2
	container.add_child(grid)
	
	_add_number_field(grid, "闃插尽鍔?", armor_data.get("defense", 0), func(v): 
		if not item.has("armor_data"): item["armor_data"] = {}
		item.armor_data.defense = int(v)
	)
	
	_add_number_field(grid, "浼ゅ鍑忓厤(%):", armor_data.get("damage_reduction", 0.0) * 100, func(v): 
		if not item.has("armor_data"): item["armor_data"] = {}
		item.armor_data.damage_reduction = float(v) / 100.0
	, true)
	
	return container

func _create_consumable_editor(item: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "馃И 娑堣€楀搧鏁堟灉"
	label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.6))
	container.add_child(label)
	
	var consumable_data = item.get("consumable_data", {})
	
	var grid = GridContainer.new()
	grid.columns = 2
	container.add_child(grid)
	
	_add_number_field(grid, "鐢熷懡鍊兼仮澶?", consumable_data.get("hp_restore", 0), func(v): 
		if not item.has("consumable_data"): item["consumable_data"] = {}
		item.consumable_data.hp_restore = int(v)
	)
	
	_add_number_field(grid, "鑰愬姏鎭㈠:", consumable_data.get("stamina_restore", 0), func(v): 
		if not item.has("consumable_data"): item["consumable_data"] = {}
		item.consumable_data.stamina_restore = int(v)
	)
	
	_add_number_field(grid, "鎸佺画鏃堕棿(绉?:", consumable_data.get("duration", 0), func(v): 
		if not item.has("consumable_data"): item["consumable_data"] = {}
		item.consumable_data.duration = int(v)
	)
	
	return container

func _create_effects_editor(item: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "鉁?鐗规畩鏁堟灉"
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	container.add_child(label)
	
	var effects = item.get("special_effects", [])
	
	var list = VBoxContainer.new()
	list.name = "EffectsList"
	container.add_child(list)
	
	for i in range(effects.size()):
		var row = HBoxContainer.new()
		
		var effect_edit = LineEdit.new()
		effect_edit.text = effects[i]
		effect_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		effect_edit.text_changed.connect(func(v): effects[i] = v)
		row.add_child(effect_edit)
		
		var del_btn = Button.new()
		del_btn.text = "脳"
		del_btn.pressed.connect(func(): _remove_effect(item, i, list))
		row.add_child(del_btn)
		
		list.add_child(row)
	
	var add_btn = Button.new()
	add_btn.text = "+ 娣诲姞鏁堟灉"
	add_btn.pressed.connect(func(): _add_effect(item, list))
	container.add_child(add_btn)
	
	return container

func _add_number_field(parent: Control, label: String, value: float, callback: Callable, is_float: bool = false):
	var lbl = Label.new()
	lbl.text = label
	parent.add_child(lbl)
	
	var spin = SpinBox.new()
	spin.value = value
	spin.allow_greater = true
	if is_float:
		spin.step = 0.1
		spin.value_changed.connect(callback)
	else:
		spin.step = 1
		spin.value_changed.connect(func(v): callback.call(int(v)))
	parent.add_child(spin)

func _add_effect(item: Dictionary, list: VBoxContainer):
	if not item.has("special_effects"):
		item.special_effects = []
	item.special_effects.append("")
	_refresh_effects_list(list, item)

func _remove_effect(item: Dictionary, index: int, list: VBoxContainer):
	if item.has("special_effects") and index < item.special_effects.size():
		item.special_effects.remove_at(index)
		_refresh_effects_list(list, item)

func _refresh_effects_list(list: VBoxContainer, item: Dictionary):
	# 閲嶆柊鍒涘缓鏁堟灉鍒楄〃UI
	for child in list.get_children():
		child.queue_free()
	
	var effects = item.get("special_effects", [])
	for i in range(effects.size()):
		var row = HBoxContainer.new()
		
		var effect_edit = LineEdit.new()
		effect_edit.text = effects[i]
		effect_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		effect_edit.text_changed.connect(func(v): effects[i] = v)
		row.add_child(effect_edit)
		
		var del_btn = Button.new()
		del_btn.text = "脳"
		del_btn.pressed.connect(func(): _remove_effect(item, i, list))
		row.add_child(del_btn)
		
		list.add_child(row)

# 灞炴€у彉鏇?
func _on_property_changed(property_name: String, new_value: Variant, old_value: Variant):
	if current_item_id.is_empty():
		return
	
	var item = items[current_item_id]
	
	# ID鍙樻洿鐗规畩澶勭悊
	if property_name == "id":
		if new_value != current_item_id and not new_value.is_empty():
			if _undo_redo_helper:
				_undo_redo_helper.create_action("淇敼鐗╁搧ID")
				_undo_redo_helper.add_undo_method(self, "_change_item_id", new_value, current_item_id)
				_undo_redo_helper.add_redo_method(self, "_change_item_id", current_item_id, new_value)
				_undo_redo_helper.commit_action()
			_change_item_id(current_item_id, new_value)
			return
	else:
		item[property_name] = new_value
	
	_validate_item(current_item_id)
	_update_item_list(_search_box.text, _category_filter.get_item_metadata(_category_filter.selected))

func _change_item_id(old_id: String, new_id: String):
	if items.has(old_id) and not items.has(new_id):
		var data = items[old_id]
		data.id = new_id
		items.erase(old_id)
		items[new_id] = data
		
		if _validation_errors.has(old_id):
			_validation_errors[new_id] = _validation_errors[old_id]
			_validation_errors.erase(old_id)
		
		current_item_id = new_id
		_update_item_list()
		_update_stats()
		_select_item(new_id)

# 楠岃瘉
func _validate_item(item_id: String) -> bool:
	var item = items.get(item_id)
	if not item:
		return false
	
	var errors: Array[String] = []
	
	if item_id.is_empty():
		errors.append("鐗╁搧ID涓嶈兘涓虹┖")
	
	if item.get("name", "").is_empty():
		errors.append("鐗╁搧鍚嶇О涓嶈兘涓虹┖")
	
	if item.get("weight", 0.0) < 0:
		errors.append("閲嶉噺涓嶈兘涓鸿礋鏁?)
	
	_validation_errors[item_id] = errors
	return errors.is_empty()

func _on_validate_all():
	var error_count = 0
	for item_id in items:
		if not _validate_item(item_id):
			error_count += _validation_errors[item_id].size()
	
	_update_validation_panel()
	
	if error_count == 0:
		_update_status("鉁?鎵€鏈夌墿鍝侀獙璇侀€氳繃")
	else:
		_update_status("鈿狅笍 鍙戠幇 %d 涓棶棰? % error_count)

func _update_validation_panel():
	if current_item_id.is_empty():
		_validation_panel.visible = false
		return
	
	var errors = _validation_errors.get(current_item_id, [])
	
	if errors.is_empty():
		_validation_panel.visible = false
		return
	
	_validation_panel.visible = true
	
	# 娓呴櫎鏃х殑閿欒鏄剧ず
	while _validation_panel.get_child_count() > 2:
		_validation_panel.remove_child(_validation_panel.get_child(2))
	
	for error in errors:
		var label = Label.new()
		label.text = "鈥?%s" % error
		label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_validation_panel.add_child(label)

# 鏂囦欢鎿嶄綔
func _on_save_items():
	if current_file_path.is_empty():
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.current_file = "items.json"
		_file_dialog.file_selected.connect(_save_to_file, CONNECT_ONE_SHOT)
		_file_dialog.popup_centered(Vector2(800, 600))
	else:
		_save_to_file(current_file_path)

func _save_to_file(path: String):
	current_file_path = path
	var json = JSON.stringify(items, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		item_saved.emit(current_item_id)
		_update_status("鉁?宸蹭繚瀛? %s" % path)
	else:
		_update_status("鉂?鏃犳硶淇濆瓨鏂囦欢")

func _on_load_items():
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.file_selected.connect(_load_from_file, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _load_from_file(path: String) -> bool:
	var validation := JSON_VALIDATOR.validate_file(path, {
		"root_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"wrapper_key": "items",
		"wrapper_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_label": "item"
	})
	if not bool(validation.get("ok", false)):
		_update_status(str(validation.get("message", "[JSON] Unknown validation error")))
		return false

	var loaded_items: Variant = validation.get("data", {})
	if not (loaded_items is Dictionary):
		_update_status("[JSON] %s | Invalid validator result: data must be Dictionary" % path)
		return false
	items = loaded_items

	current_file_path = path
	current_item_id = ""
	_validation_errors.clear()
	
	_update_item_list()
	_update_stats()
	_property_panel.clear()
	item_loaded.emit(current_item_id)
	_update_status("Loaded: %s" % path)
	return true

func _on_export_data():
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "item_data.gd"
	_file_dialog.file_selected.connect(_export_to_gdscript, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _export_to_gdscript(path: String):
	var lines: Array[String] = []
	lines.append("# 鑷姩鐢熸垚鐨勭墿鍝佹暟鎹?)
	lines.append("# 鐢熸垚鏃堕棿: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("const ITEMS = {")
	
	var item_keys = items.keys()
	for i in range(item_keys.size()):
		var item_id = item_keys[i]
		var item = items[item_id]
		
		lines.append('\t"%s": {' % item_id)
		lines.append('\t\t"id": "%s",' % item_id)
		lines.append('\t\t"name": "%s",' % item.get("name", ""))
		lines.append('\t\t"description": "%s",' % item.get("description", ""))
		lines.append('\t\t"type": "%s",' % item.get("type", ""))
		lines.append('\t\t"rarity": "%s",' % item.get("rarity", ""))
		lines.append('\t\t"weight": %s,' % item.get("weight", 0))
		lines.append('\t\t"durability": %d,' % item.get("durability", 100))
		lines.append('\t\t"max_durability": %d,' % item.get("max_durability", 100))
		lines.append('\t\t"required_level": %d' % item.get("required_level", 0))
		lines.append('\t},')
	
	lines.append('}')
	lines.append("")
	lines.append("static func get_item(item_id: String):")
	lines.append("\treturn ITEMS.get(item_id, null)")
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines))
		file.close()
		items_exported.emit(path)
		_update_status("鉁?宸插鍑篏DScript")

# 鎾ら攢/閲嶅仛
func _on_undo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().undo()
		_update_status("鎾ら攢")
		_update_item_list()
		_update_stats()

func _on_redo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().redo()
		_update_status("閲嶅仛")
		_update_item_list()
		_update_stats()

func _update_status(message: String):
	_status_bar.text = "%s - 鍏?%d 涓墿鍝? % [message, items.size()]
	print("鐗╁搧缂栬緫鍣? %s" % message)

# 鍏叡鏂规硶
func get_current_item_id() -> String:
	return current_item_id

func get_items_count() -> int:
	return items.size()

func get_items_by_type(item_type: String) -> Dictionary:
	var result = {}
	for item_id in items:
		var item = items[item_id]
		if item.get("type", "") == item_type:
			result[item_id] = item
	return result

