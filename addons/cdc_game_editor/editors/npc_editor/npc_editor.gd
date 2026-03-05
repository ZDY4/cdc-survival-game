@tool
extends Control
## NPC缂栬緫鍣?
## 鐢ㄤ簬鍒涘缓鍜岀紪杈慛PC鏁版嵁

signal npc_saved(npc_id: String)
signal npc_loaded(npc_id: String)

# NPC绫诲瀷閫夐」
const NPC_TYPES = {
	0: "Friendly",
	1: "Neutral",
	2: "Hostile",
	3: "Trader",
	4: "Quest Giver",
	5: "Recruitable"
}

const JSON_VALIDATOR = preload("res://addons/cdc_game_editor/utils/json_validator.gd")

# 鏁版嵁
var npcs: Dictionary = {}  # npc_id -> NPCData
var current_npc_id: String = ""
var current_file_path: String = ""

# 缂栬緫鍣ㄦ彃浠跺紩鐢?
var editor_plugin: EditorPlugin = null

# UI寮曠敤
var npc_list: ItemList
var property_panel: Control
var toolbar: HBoxContainer
var file_dialog: FileDialog
var status_bar: Label
var _stats_label: Label

func _ready():
	_setup_ui()
	_setup_file_dialog()
	_load_npcs_from_project_data()
	_update_npc_list()

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 宸ュ叿鏍?
	toolbar = HBoxContainer.new()
	toolbar.custom_minimum_size = Vector2(0, 45)
	toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_top = 0
	toolbar.offset_bottom = 45
	add_child(toolbar)
	
	var new_btn = Button.new()
	new_btn.text = "鏂板缓NPC"
	new_btn.pressed.connect(_on_new_npc)
	toolbar.add_child(new_btn)
	
	var delete_btn = Button.new()
	delete_btn.text = "鍒犻櫎"
	delete_btn.pressed.connect(_on_delete_npc)
	toolbar.add_child(delete_btn)
	
	toolbar.add_child(VSeparator.new())
	
	var save_btn = Button.new()
	save_btn.text = "淇濆瓨"
	save_btn.pressed.connect(_on_save_npcs)
	toolbar.add_child(save_btn)
	
	var load_btn = Button.new()
	load_btn.text = "鍔犺浇"
	load_btn.pressed.connect(_on_load_npcs)
	toolbar.add_child(load_btn)
	
	toolbar.add_child(VSeparator.new())
	
	var export_btn = Button.new()
	export_btn.text = "瀵煎嚭JSON"
	export_btn.pressed.connect(_on_export_json)
	toolbar.add_child(export_btn)
	
	# 涓诲垎鍓插鍣?
	var main_split = HSplitContainer.new()
	main_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_split.offset_top = 50
	main_split.offset_bottom = -20
	add_child(main_split)
	
	# 宸︿晶锛歂PC鍒楄〃
	var left_panel = _create_npc_list_panel()
	main_split.add_child(left_panel)
	
	# 鍙充晶锛氬睘鎬ч潰鏉?
	property_panel = preload("res://addons/cdc_game_editor/utils/property_panel.gd").new()
	property_panel.custom_minimum_size = Vector2(400, 0)
	property_panel.panel_title = "NPC灞炴€?
	property_panel.property_changed.connect(_on_property_changed)
	main_split.add_child(property_panel)
	
	main_split.split_offset = 250
	
	# 鐘舵€佹爮
	status_bar = Label.new()
	status_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_bar.offset_top = -20
	status_bar.offset_bottom = 0
	status_bar.offset_left = 0
	status_bar.offset_right = 0
	status_bar.text = "灏辩华"
	add_child(status_bar)

func _create_npc_list_panel() -> Control:
	var panel = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	
	var title = Label.new()
	title.text = "馃 NPC鍒楄〃"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)
	
	panel.add_child(HSeparator.new())
	
	# 鎼滅储妗?
	var search_box = LineEdit.new()
	search_box.placeholder_text = "鎼滅储NPC..."
	search_box.text_changed.connect(_on_search_changed)
	panel.add_child(search_box)
	
	# NPC鍒楄〃
	npc_list = ItemList.new()
	npc_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	npc_list.item_selected.connect(_on_npc_selected)
	panel.add_child(npc_list)
	
	# 缁熻
	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.text = "鎬昏: 0涓狽PC"
	panel.add_child(_stats_label)
	
	return panel

func _setup_file_dialog():
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.json; JSON鏂囦欢")
	add_child(file_dialog)

func _load_npcs_from_project_data():
	var data_manager = get_node_or_null("/root/DataManager")
	if data_manager and data_manager.has_method("get_all_npcs"):
		var data: Variant = data_manager.get_all_npcs()
		if data is Dictionary and not data.is_empty():
			_apply_npc_dictionary(data)
			print("[NPCEditor] Loaded %d NPCs from DataManager" % npcs.size())
			return
		elif not (data is Dictionary):
			push_warning("[NPCEditor] Invalid NPC data from DataManager: expected Dictionary")

	var file_data: Dictionary = _load_json_dictionary([
		"res://data/json/npcs.json",
		"res://data/npcs.json"
	])
	if not file_data.is_empty():
		_apply_npc_dictionary(file_data)
		current_file_path = "res://data/json/npcs.json" if FileAccess.file_exists("res://data/json/npcs.json") else "res://data/npcs.json"
		print("[NPCEditor] Loaded %d NPCs from %s" % [npcs.size(), current_file_path])

func _load_json_dictionary(paths: Array[String]) -> Dictionary:
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var validation := JSON_VALIDATOR.validate_file(path, {
			"root_type": JSON_VALIDATOR.TYPE_DICTIONARY,
			"wrapper_key": "npcs",
			"wrapper_type": JSON_VALIDATOR.TYPE_DICTIONARY,
			"entry_type": JSON_VALIDATOR.TYPE_DICTIONARY,
			"entry_label": "npc"
		})
		if bool(validation.get("ok", false)):
			var loaded_npcs: Variant = validation.get("data", {})
			if loaded_npcs is Dictionary:
				return loaded_npcs
			push_warning("[JSON] %s | Invalid validator result: data must be Dictionary" % path)
			continue
		push_warning(str(validation.get("message", "[JSON] Unknown validation error")))
	return {}

func _apply_npc_dictionary(data: Dictionary) -> void:
	npcs.clear()
	var npc_data_class: Script = load("res://modules/npc/npc_data.gd")
	for npc_id in data.keys():
		var raw_npc: Variant = data[npc_id]
		if raw_npc is Object:
			npcs[npc_id] = raw_npc
			continue
		if raw_npc is Dictionary and npc_data_class:
			var npc_data: Variant = npc_data_class.new()
			if npc_data is Object and npc_data.has_method("deserialize"):
				npc_data.deserialize(raw_npc)
				npcs[npc_id] = npc_data
				continue
		if raw_npc is Dictionary:
			npcs[npc_id] = raw_npc.duplicate(true)

func _update_npc_list(filter: String = ""):
	npc_list.clear()
	
	var sorted_npcs = npcs.keys()
	sorted_npcs.sort()
	
	for npc_id in sorted_npcs:
		var npc = npcs[npc_id]
		var npc_type = int(npc.get("npc_type", 0))
		var npc_name = str(npc.get("name", npc_id))
		var display_text = "%s - %s (%s)" % [npc_id, npc_name, NPC_TYPES.get(npc_type, "鏈煡")]
		
		if filter.is_empty() or display_text.to_lower().contains(filter.to_lower()):
			var idx = npc_list.add_item(display_text)
			npc_list.set_item_metadata(idx, npc_id)
		
			# 鏍规嵁绫诲瀷璁剧疆棰滆壊 (3=TRADER, 2=HOSTILE, 4=QUEST_GIVER)
			match npc_type:
				3:  # TRADER
					npc_list.set_item_custom_fg_color(idx, Color.GOLD)
				2:  # HOSTILE
					npc_list.set_item_custom_fg_color(idx, Color.RED)
				4:  # QUEST_GIVER
					npc_list.set_item_custom_fg_color(idx, Color.CYAN)
	
	if _stats_label:
		_stats_label.text = "鎬昏: %d涓狽PC" % npcs.size()

func get_data() -> Dictionary:
	# 杞崲
	var data = {}
	for npc_id in npcs:
		var npc: Variant = npcs[npc_id]
		if npc is Object and npc.has_method("serialize"):
			data[npc_id] = npc.serialize()
		elif npc is Dictionary:
			data[npc_id] = npc.duplicate(true)
		else:
			data[npc_id] = npc
	return data

func _on_search_changed(text: String):
	_update_npc_list(text)

func _on_new_npc():
	var npc_id = "npc_%d" % Time.get_ticks_msec()
	var NPCDataClass = load("res://modules/npc/npc_data.gd")
	if not NPCDataClass:
		_update_status("鉂?鏃犳硶鍔犺浇 NPCData 绫?)
		return
	
	var npc_data = NPCDataClass.new()
	npc_data.id = npc_id
	npc_data.name = "鏂癗PC"
	npc_data.description = "NPC鎻忚堪"
	npc_data.npc_type = 0  # Type.FRIENDLY = 0
	npc_data.default_location = "safehouse"
	npc_data.current_location = "safehouse"
	
	npcs[npc_id] = npc_data
	_update_npc_list()
	_select_npc(npc_id)
	_update_status("鍒涘缓浜嗘柊NPC: %s" % npc_id)

func _on_delete_npc():
	if current_npc_id.is_empty():
		return
	
	npcs.erase(current_npc_id)
	current_npc_id = ""
	_update_npc_list()
	property_panel.clear()
	_update_status("鍒犻櫎浜哊PC")

func _on_npc_selected(index: int):
	var npc_id = npc_list.get_item_metadata(index)
	_select_npc(npc_id)

func _select_npc(npc_id: String):
	current_npc_id = npc_id
	var npc = npcs.get(npc_id)
	if npc:
		_update_property_panel(npc)

func _update_property_panel(npc):
	property_panel.clear()
	
	if not npc:
		return
	
	# 鍩虹淇℃伅 - 浣跨敤 get() 瀹夊叏璁块棶
	property_panel.add_string_property("id", "NPC ID:", npc.get("id", ""), false, "鍞竴鏍囪瘑绗?)
	property_panel.add_string_property("name", "鍚嶇О:", npc.get("name", ""), false, "鏄剧ず鍚嶇О")
	property_panel.add_string_property("title", "绉板彿:", npc.get("title", ""), false, "濡傦細搴熷湡鍟嗕汉")
	property_panel.add_string_property("description", "鎻忚堪:", npc.get("description", ""), true, "璇︾粏鎻忚堪...")
	
	property_panel.add_separator()
	
	# 绫诲瀷
	var type_dict = {}
	for key in NPC_TYPES:
		type_dict[str(key)] = NPC_TYPES[key]
	property_panel.add_enum_property("npc_type", "NPC绫诲瀷:", type_dict, str(npc.get("npc_type", 0)))
	
	# 绛夌骇
	property_panel.add_number_property("level", "绛夌骇:", npc.get("level", 1), 1, 100, 1, false)
	
	property_panel.add_separator()
	
	# 灞炴€?
	property_panel.add_section_label("馃搳 灞炴€?)
	var attributes = npc.get("attributes", {})
	property_panel.add_number_property("attr_strength", "鍔涢噺:", attributes.get("strength", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_perception", "鎰熺煡:", attributes.get("perception", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_endurance", "浣撹川:", attributes.get("endurance", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_charisma", "榄呭姏:", attributes.get("charisma", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_intelligence", "鏅哄姏:", attributes.get("intelligence", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_agility", "鏁忔嵎:", attributes.get("agility", 10), 1, 20, 1, false)
	property_panel.add_number_property("attr_luck", "骞歌繍:", attributes.get("luck", 10), 1, 20, 1, false)
	
	property_panel.add_separator()
	
	# 鎯呯华
	property_panel.add_section_label("馃槉 鍒濆鎯呯华")
	var mood = npc.get("mood", {})
	property_panel.add_number_property("mood_friendliness", "鍙嬪ソ搴?", mood.get("friendliness", 0), 0, 100, 5, false)
	property_panel.add_number_property("mood_trust", "淇′换搴?", mood.get("trust", 0), 0, 100, 5, false)
	property_panel.add_number_property("mood_fear", "鎭愭儳搴?", mood.get("fear", 0), 0, 100, 5, false)
	property_panel.add_number_property("mood_anger", "鎰ゆ€掑害:", mood.get("anger", 0), 0, 100, 5, false)
	
	property_panel.add_separator()
	
	# 鑳藉姏
	property_panel.add_section_label("鈿?鑳藉姏")
	# 浣跨敤鑷畾涔夋帶浠舵樉绀哄竷灏斿€?
	property_panel.add_custom_control(_create_bool_checkbox("can_trade", "鍙互浜ゆ槗", npc.get("can_trade", false)))
	property_panel.add_custom_control(_create_bool_checkbox("can_recruit", "鍙互鎷涘嫙", npc.get("can_recruit", false)))
	property_panel.add_custom_control(_create_bool_checkbox("can_give_quest", "鍙互鍙戝竷浠诲姟", npc.get("can_give_quest", false)))
	property_panel.add_custom_control(_create_bool_checkbox("can_heal", "鍙互娌荤枟", npc.get("can_heal", false)))
	
	property_panel.add_separator()
	
	# 浣嶇疆
	property_panel.add_string_property("default_location", "榛樿浣嶇疆:", npc.get("default_location", "safehouse"), false, "濡傦細safehouse")
	
	property_panel.add_separator()
	
	# 澶栬
	property_panel.add_section_label("馃帹 澶栬")
	property_panel.add_string_property("portrait_path", "榛樿绔嬬粯:", npc.get("portrait_path", ""), false, "res://assets/portraits/...")
	
	property_panel.add_separator()
	
	# 琛ㄦ儏绔嬬粯
	property_panel.add_section_label("馃槉 琛ㄦ儏绔嬬粯锛堝彲閫夛級")
	var expression_paths = npc.get("expression_paths", {})
	property_panel.add_string_property("expr_normal", "姝ｅ父:", expression_paths.get("normal", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_happy", "寮€蹇?", expression_paths.get("happy", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_angry", "鎰ゆ€?", expression_paths.get("angry", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_sad", "鎮蹭激:", expression_paths.get("sad", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_fear", "鎭愭儳:", expression_paths.get("fear", ""), false, "res://assets/portraits/...")
	property_panel.add_string_property("expr_surprised", "鎯婅:", expression_paths.get("surprised", ""), false, "res://assets/portraits/...")

func _create_bool_checkbox(property_name: String, label: String, value: bool) -> Control:
	var hbox = HBoxContainer.new()
	
	var lbl = Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	
	var checkbox = CheckBox.new()
	checkbox.button_pressed = value
	checkbox.toggled.connect(func(v): _on_bool_property_changed(property_name, v))
	hbox.add_child(checkbox)
	
	return hbox

func _on_property_changed(property_name: String, new_value: Variant, old_value: Variant):
	if current_npc_id.is_empty():
		return
	
	var npc: Object = npcs[current_npc_id]
	if not npc:
		return
	
	var attributes: Dictionary = npc.get("attributes", {})
	var mood: Dictionary = npc.get("mood", {})
	var expression_paths: Dictionary = npc.get("expression_paths", {})
	
	match property_name:
		"id":
			if new_value != current_npc_id and not new_value.is_empty() and not npcs.has(new_value):
				npcs.erase(current_npc_id)
				npc.set("id", new_value)
				npcs[new_value] = npc
				current_npc_id = new_value
				_update_npc_list()
		"name":
			npc.set("name", new_value)
		"title":
			npc.set("title", new_value)
		"description":
			npc.set("description", new_value)
		"npc_type":
			npc.set("npc_type", int(new_value))
		"level":
			npc.set("level", int(new_value))
		"default_location":
			npc.set("default_location", new_value)
			npc.set("current_location", new_value)
		"portrait_path":
			npc.set("portrait_path", new_value)
		"expr_normal":
			expression_paths["normal"] = new_value
		"expr_happy":
			expression_paths["happy"] = new_value
		"expr_angry":
			expression_paths["angry"] = new_value
		"expr_sad":
			expression_paths["sad"] = new_value
		"expr_fear":
			expression_paths["fear"] = new_value
		"expr_surprised":
			expression_paths["surprised"] = new_value
		"attr_strength":
			attributes["strength"] = int(new_value)
		"attr_perception":
			attributes["perception"] = int(new_value)
		"attr_endurance":
			attributes["endurance"] = int(new_value)
		"attr_charisma":
			attributes["charisma"] = int(new_value)
		"attr_intelligence":
			attributes["intelligence"] = int(new_value)
		"attr_agility":
			attributes["agility"] = int(new_value)
		"attr_luck":
			attributes["luck"] = int(new_value)
		"mood_friendliness":
			mood["friendliness"] = int(new_value)
		"mood_trust":
			mood["trust"] = int(new_value)
		"mood_fear":
			mood["fear"] = int(new_value)
		"mood_anger":
			mood["anger"] = int(new_value)
	
	npc.set("attributes", attributes)
	npc.set("mood", mood)
	npc.set("expression_paths", expression_paths)

func _on_bool_property_changed(property_name: String, value: bool):
	if current_npc_id.is_empty():
		return
	
	var npc: Object = npcs[current_npc_id]
	if not npc:
		return
	
	match property_name:
		"can_trade":
			npc.set("can_trade", value)
		"can_recruit":
			npc.set("can_recruit", value)
		"can_give_quest":
			npc.set("can_give_quest", value)
		"can_heal":
			npc.set("can_heal", value)

func _on_save_npcs():
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = "npcs.json"
	file_dialog.file_selected.connect(_save_to_file, CONNECT_ONE_SHOT)
	file_dialog.popup_centered(Vector2(800, 600))

func _save_to_file(path: String):
	var data = {}
	for npc_id in npcs:
		var npc = npcs[npc_id]
		if npc is Object and npc.has_method("serialize"):
			data[npc_id] = npc.serialize()
		elif npc is Dictionary:
			data[npc_id] = npc.duplicate(true)
		else:
			data[npc_id] = npc
	
	var json = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		npc_saved.emit(current_npc_id)
		_update_status("鉁?宸蹭繚瀛? %s (%d涓狽PC)" % [path, npcs.size()])
	else:
		_update_status("鉂?淇濆瓨澶辫触")

func _on_load_npcs():
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.file_selected.connect(_load_from_file, CONNECT_ONE_SHOT)
	file_dialog.popup_centered(Vector2(800, 600))

func _load_from_file(path: String):
	var validation := JSON_VALIDATOR.validate_file(path, {
		"root_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"wrapper_key": "npcs",
		"wrapper_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_type": JSON_VALIDATOR.TYPE_DICTIONARY,
		"entry_label": "npc"
	})
	if not bool(validation.get("ok", false)):
		_update_status(str(validation.get("message", "[JSON] Unknown validation error")))
		return

	var loaded_npcs: Variant = validation.get("data", {})
	if not (loaded_npcs is Dictionary):
		_update_status("[JSON] %s | Invalid validator result: data must be Dictionary" % path)
		return
	var data: Dictionary = loaded_npcs

	_apply_npc_dictionary(data)
	current_file_path = path
	current_npc_id = ""
	
	_update_npc_list()
	property_panel.clear()
	npc_loaded.emit(current_npc_id)
	_update_status("Loaded: %s (%d NPCs)" % [path, npcs.size()])

func _on_export_json():
	_on_save_npcs()

func _update_status(message: String):
	status_bar.text = message
	print("[NPCEditor] %s" % message)

# 鍏叡鏂规硶
func get_current_npc_id() -> String:
	return current_npc_id

func get_npcs_count() -> int:
	return npcs.size()

func has_unsaved_changes() -> bool:
	return npcs.size() > 0



