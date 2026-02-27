@tool
extends Control
## 物品编辑器
## 用于创建和管理游戏中的所有物品数据

signal item_saved(item_id: String)
signal item_loaded(item_id: String)
signal items_exported(path: String)

# 物品类型常量
const ITEM_TYPES = {
	"weapon": "武器",
	"armor": "护甲",
	"consumable": "消耗品",
	"material": "材料",
	"misc": "杂项"
}

const RARITY_LEVELS = {
	"common": "普通",
	"uncommon": " uncommon",
	"rare": "稀有",
	"epic": "史诗",
	"legendary": "传说"
}

const EQUIPMENT_SLOTS = {
	"head": "头部",
	"body": "身体",
	"hands": "手部",
	"legs": "腿部",
	"feet": "脚部",
	"back": "背部",
	"main_hand": "主手",
	"off_hand": "副手",
	"accessory_1": "饰品1",
	"accessory_2": "饰品2"
}

const WEAPON_SUBTYPES = {
	"unarmed": "徒手",
	"dagger": "匕首",
	"sword": "剑",
	"blunt": "钝器",
	"axe": "斧",
	"spear": "长矛",
	"polearm": "长柄",
	"bow": "弓",
	"gun": "枪械"
}

# 节点引用
@onready var _item_list: ItemList
@onready var _category_filter: OptionButton
@onready var _search_box: LineEdit
@onready var _property_panel: Control
@onready var _toolbar: HBoxContainer
@onready var _file_dialog: FileDialog
@onready var _status_bar: Label
@onready var _validation_panel: VBoxContainer

# 数据
var items: Dictionary = {}  # item_id -> item_data
var current_item_id: String = ""
var current_file_path: String = ""
var _validation_errors: Dictionary = {}

# 工具
var _undo_redo_helper: EditorUndoRedoHelper

# 编辑器插件引用
var editor_plugin: EditorPlugin = null:
	set(plugin):
		editor_plugin = plugin
		if plugin:
			_undo_redo_helper = EditorUndoRedoHelper.new(plugin)

func _ready():
	_setup_ui()
	_setup_file_dialog()
	_load_default_items()
	_update_item_list()

func _setup_ui():
	anchors_preset = Control.PRESET_FULL_RECT
	
	# 工具栏
	_toolbar = HBoxContainer.new()
	_toolbar.custom_minimum_size = Vector2(0, 45)
	add_child(_toolbar)
	_create_toolbar()
	
	# 主分割容器
	var main_split = HSplitContainer.new()
	main_split.position = Vector2(0, 50)
	main_split.size = Vector2(size.x, size.y - 70)
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_split)
	
	# 左侧面板：物品列表 + 过滤
	var left_panel = _create_left_panel()
	main_split.add_child(left_panel)
	
	# 右侧面板：属性编辑
	var right_panel = _create_right_panel()
	main_split.add_child(right_panel)
	
	main_split.split_offset = 280
	
	# 状态栏
	_status_bar = Label.new()
	_status_bar.position = Vector2(0, size.y - 20)
	_status_bar.size = Vector2(size.x, 20)
	_status_bar.text = "就绪 - 0 个物品"
	add_child(_status_bar)

func _create_toolbar():
	_add_toolbar_button("新建", _on_new_item, "新建物品 (Ctrl+N)")
	_add_toolbar_button("删除", _on_delete_item, "删除物品 (Delete)")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("撤销", _on_undo, "撤销 (Ctrl+Z)")
	_add_toolbar_button("重做", _on_redo, "重做 (Ctrl+Y)")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("保存", _on_save_items, "保存到文件 (Ctrl+S)")
	_add_toolbar_button("加载", _on_load_items, "从文件加载")
	_toolbar.add_child(VSeparator.new())
	_add_toolbar_button("验证", _on_validate_all, "验证所有物品")
	_add_toolbar_button("导出", _on_export_data, "导出数据")

func _add_toolbar_button(text: String, callback: Callable, tooltip: String = ""):
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.pressed.connect(callback)
	_toolbar.add_child(btn)

func _create_left_panel() -> Control:
	var panel = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	
	# 标题
	var title = Label.new()
	title.text = "📦 物品列表"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)
	
	panel.add_child(HSeparator.new())
	
	# 分类过滤
	var filter_row = HBoxContainer.new()
	panel.add_child(filter_row)
	
	var filter_label = Label.new()
	filter_label.text = "分类:"
	filter_row.add_child(filter_label)
	
	_category_filter = OptionButton.new()
	_category_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_filter.add_item("全部", 0)
	_category_filter.set_item_metadata(0, "")
	var idx = 1
	for type_key in ITEM_TYPES:
		_category_filter.add_item(ITEM_TYPES[type_key], idx)
		_category_filter.set_item_metadata(idx, type_key)
		idx += 1
	_category_filter.item_selected.connect(_on_category_changed)
	filter_row.add_child(_category_filter)
	
	# 搜索框
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "🔍 搜索物品..."
	_search_box.text_changed.connect(_on_search_changed)
	panel.add_child(_search_box)
	
	# 物品列表
	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.item_selected.connect(_on_item_selected)
	panel.add_child(_item_list)
	
	# 统计信息
	var stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.text = "总计: 0 | 武器: 0 | 护甲: 0 | 消耗品: 0"
	stats_label.add_theme_color_override("font_color", Color.GRAY)
	panel.add_child(stats_label)
	
	return panel

func _create_right_panel() -> Control:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(400, 0)
	
	# 属性面板
	_property_panel = preload("res://addons/cdc_game_editor/utils/property_panel.gd").new()
	_property_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_property_panel.panel_title = "物品属性"
	_property_panel.property_changed.connect(_on_property_changed)
	container.add_child(_property_panel)
	
	# 验证错误面板
	_validation_panel = VBoxContainer.new()
	_validation_panel.visible = false
	container.add_child(_validation_panel)
	
	var validation_title = Label.new()
	validation_title.text = "⚠️ 验证问题"
	validation_title.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
	_validation_panel.add_child(validation_title)
	_validation_panel.add_child(HSeparator.new())
	
	return container

func _setup_file_dialog():
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json; JSON 文件")
	_file_dialog.add_filter("*.items; 物品数据文件")
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

# 默认物品数据
func _load_default_items():
	# 如果还没有物品，加载一些默认示例
	if items.is_empty():
		items = {
			"fist": {
				"id": "fist",
				"name": "拳头",
				"description": "最基础的攻击方式",
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

# 物品管理
func _on_new_item():
	var item_id = "item_%d" % Time.get_ticks_msec()
	var item_data = {
		"id": item_id,
		"name": "新物品",
		"description": "物品描述",
		"type": "misc",
		"rarity": "common",
		"weight": 0.0,
		"durability": 100,
		"max_durability": 100,
		"required_level": 0,
		"special_effects": []
	}
	
	# 撤销/重做
	if _undo_redo_helper:
		_undo_redo_helper.create_method_action(
			"创建物品",
			self, "_add_item",
			[item_id, item_data],
			[item_id]
		)
	
	_add_item(item_id, item_data)
	_select_item(item_id)
	_update_status("创建了新物品: %s" % item_id)

func _add_item(item_id: String, item_data: Dictionary):
	items[item_id] = item_data
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
	
	var old_data = items[current_item_id].duplicate(true)
	
	# 撤销/重做
	if _undo_redo_helper:
		_undo_redo_helper.create_method_action(
			"删除物品",
			self, "_add_item",
			[current_item_id],
			[current_item_id, old_data]
		)
	
	_remove_item(current_item_id)
	_update_status("删除了物品: %s" % current_item_id)

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
		var item_name = item.get("name", "未命名")
		
		# 分类过滤
		if not category_filter.is_empty() and item_type != category_filter:
			continue
		
		# 搜索过滤
		var display_text = "%s - %s" % [item_id, item_name]
		if not filter_text.is_empty():
			if not display_text.to_lower().contains(filter_text.to_lower()):
				continue
		
		var idx = _item_list.add_item(display_text)
		_item_list.set_item_metadata(idx, item_id)
		
		# 根据稀有度设置颜色
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
	
	var stats_label = get_node_or_null("StatsLabel")
	if stats_label:
		stats_label.text = "总计: %d | 武器: %d | 护甲: %d | 消耗品: %d | 材料: %d" % [
			total, weapons, armors, consumables, materials
		]

func _on_category_changed(index: int):
	var category = _category_filter.get_item_metadata(index)
	_update_item_list(_search_box.text, category)

func _on_search_changed(text: String):
	var category = _category_filter.get_item_metadata(_category_filter.selected)
	_update_item_list(text, category)

# 属性面板
func _update_property_panel(item: Dictionary):
	_property_panel.clear()
	
	if item.is_empty():
		return
	
	# 基础信息
	_property_panel.add_string_property("id", "物品ID:", item.get("id", ""), false, "唯一标识符")
	_property_panel.add_string_property("name", "显示名称:", item.get("name", ""), false, "物品名称")
	_property_panel.add_string_property("description", "描述:", item.get("description", ""), true, "物品描述...")
	
	_property_panel.add_separator()
	
	# 类型和稀有度
	_property_panel.add_enum_property("type", "物品类型:", ITEM_TYPES, item.get("type", "misc"))
	_property_panel.add_enum_property("rarity", "稀有度:", RARITY_LEVELS, item.get("rarity", "common"))
	
	_property_panel.add_separator()
	
	# 基础属性
	_property_panel.add_number_property("weight", "重量:", item.get("weight", 0.0), 0.0, 1000.0, 0.1, true)
	_property_panel.add_number_property("durability", "当前耐久:", item.get("durability", 100), -1, 9999, 1, false)
	_property_panel.add_number_property("max_durability", "最大耐久:", item.get("max_durability", 100), 1, 9999, 1, false)
	_property_panel.add_number_property("required_level", "需求等级:", item.get("required_level", 0), 0, 100, 1, false)
	
	_property_panel.add_separator()
	
	# 根据类型显示特定属性
	var item_type = item.get("type", "")
	match item_type:
		"weapon":
			_property_panel.add_enum_property("slot", "装备槽位:", EQUIPMENT_SLOTS, item.get("slot", "main_hand"))
			_property_panel.add_enum_property("subtype", "武器类型:", WEAPON_SUBTYPES, item.get("subtype", "unarmed"))
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_weapon_data_editor(item))
		
		"armor":
			_property_panel.add_enum_property("slot", "装备槽位:", EQUIPMENT_SLOTS, item.get("slot", "body"))
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_armor_data_editor(item))
		
		"consumable":
			_property_panel.add_separator()
			_property_panel.add_custom_control(_create_consumable_editor(item))
	
	_property_panel.add_separator()
	
	# 特殊效果
	_property_panel.add_custom_control(_create_effects_editor(item))

func _create_weapon_data_editor(item: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "⚔️ 武器属性"
	label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.4))
	container.add_child(label)
	
	var weapon_data = item.get("weapon_data", {})
	
	var grid = GridContainer.new()
	grid.columns = 2
	container.add_child(grid)
	
	_add_number_field(grid, "伤害:", weapon_data.get("damage", 0), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.damage = int(v)
	)
	
	_add_number_field(grid, "攻击速度:", weapon_data.get("attack_speed", 1.0), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.attack_speed = float(v)
	, true)
	
	_add_number_field(grid, "攻击范围:", weapon_data.get("range", 1), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.range = int(v)
	)
	
	_add_number_field(grid, "耐力消耗:", weapon_data.get("stamina_cost", 0), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.stamina_cost = int(v)
	)
	
	_add_number_field(grid, "暴击率(%):", weapon_data.get("crit_chance", 0.05) * 100, func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.crit_chance = float(v) / 100.0
	, true)
	
	_add_number_field(grid, "暴击倍数:", weapon_data.get("crit_multiplier", 1.5), func(v): 
		if not item.has("weapon_data"): item["weapon_data"] = {}
		item.weapon_data.crit_multiplier = float(v)
	, true)
	
	return container

func _create_armor_data_editor(item: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "🛡️ 护甲属性"
	label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8))
	container.add_child(label)
	
	var armor_data = item.get("armor_data", {})
	
	var grid = GridContainer.new()
	grid.columns = 2
	container.add_child(grid)
	
	_add_number_field(grid, "防御力:", armor_data.get("defense", 0), func(v): 
		if not item.has("armor_data"): item["armor_data"] = {}
		item.armor_data.defense = int(v)
	)
	
	_add_number_field(grid, "伤害减免(%):", armor_data.get("damage_reduction", 0.0) * 100, func(v): 
		if not item.has("armor_data"): item["armor_data"] = {}
		item.armor_data.damage_reduction = float(v) / 100.0
	, true)
	
	return container

func _create_consumable_editor(item: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "🧪 消耗品效果"
	label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.6))
	container.add_child(label)
	
	var consumable_data = item.get("consumable_data", {})
	
	var grid = GridContainer.new()
	grid.columns = 2
	container.add_child(grid)
	
	_add_number_field(grid, "生命值恢复:", consumable_data.get("hp_restore", 0), func(v): 
		if not item.has("consumable_data"): item["consumable_data"] = {}
		item.consumable_data.hp_restore = int(v)
	)
	
	_add_number_field(grid, "耐力恢复:", consumable_data.get("stamina_restore", 0), func(v): 
		if not item.has("consumable_data"): item["consumable_data"] = {}
		item.consumable_data.stamina_restore = int(v)
	)
	
	_add_number_field(grid, "持续时间(秒):", consumable_data.get("duration", 0), func(v): 
		if not item.has("consumable_data"): item["consumable_data"] = {}
		item.consumable_data.duration = int(v)
	)
	
	return container

func _create_effects_editor(item: Dictionary) -> Control:
	var container = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "✨ 特殊效果"
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
		del_btn.text = "×"
		del_btn.pressed.connect(func(): _remove_effect(item, i, list))
		row.add_child(del_btn)
		
		list.add_child(row)
	
	var add_btn = Button.new()
	add_btn.text = "+ 添加效果"
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
	# 重新创建效果列表UI
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
		del_btn.text = "×"
		del_btn.pressed.connect(func(): _remove_effect(item, i, list))
		row.add_child(del_btn)
		
		list.add_child(row)

# 属性变更
func _on_property_changed(property_name: String, new_value: Variant, old_value: Variant):
	if current_item_id.is_empty():
		return
	
	var item = items[current_item_id]
	
	# ID变更特殊处理
	if property_name == "id":
		if new_value != current_item_id and not new_value.is_empty():
			if _undo_redo_helper:
				_undo_redo_helper.create_method_action(
					"修改物品ID",
					self, "_change_item_id",
					[current_item_id, new_value],
					[new_value, current_item_id]
				)
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

# 验证
func _validate_item(item_id: String) -> bool:
	var item = items.get(item_id)
	if not item:
		return false
	
	var errors: Array[String] = []
	
	if item_id.is_empty():
		errors.append("物品ID不能为空")
	
	if item.get("name", "").is_empty():
		errors.append("物品名称不能为空")
	
	if item.get("weight", 0.0) < 0:
		errors.append("重量不能为负数")
	
	_validation_errors[item_id] = errors
	return errors.is_empty()

func _on_validate_all():
	var error_count = 0
	for item_id in items:
		if not _validate_item(item_id):
			error_count += _validation_errors[item_id].size()
	
	_update_validation_panel()
	
	if error_count == 0:
		_update_status("✓ 所有物品验证通过")
	else:
		_update_status("⚠️ 发现 %d 个问题" % error_count)

func _update_validation_panel():
	if current_item_id.is_empty():
		_validation_panel.visible = false
		return
	
	var errors = _validation_errors.get(current_item_id, [])
	
	if errors.is_empty():
		_validation_panel.visible = false
		return
	
	_validation_panel.visible = true
	
	# 清除旧的错误显示
	while _validation_panel.get_child_count() > 2:
		_validation_panel.remove_child(_validation_panel.get_child(2))
	
	for error in errors:
		var label = Label.new()
		label.text = "• %s" % error
		label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_validation_panel.add_child(label)

# 文件操作
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
	
	var data = {
		"version": "1.0",
		"export_time": Time.get_datetime_string_from_system(),
		"items": items
	}
	
	var json = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json)
		file.close()
		item_saved.emit(current_item_id)
		_update_status("✓ 已保存: %s" % path)
	else:
		_update_status("❌ 无法保存文件")

func _on_load_items():
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.file_selected.connect(_load_from_file, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _load_from_file(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		_update_status("❌ 无法打开文件")
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		_update_status("❌ JSON解析错误")
		return
	
	var data = json.data
	if not data is Dictionary or not data.has("items"):
		_update_status("❌ 无效的文件格式")
		return
	
	items = data.items
	current_file_path = path
	current_item_id = ""
	_validation_errors.clear()
	
	_update_item_list()
	_update_stats()
	_property_panel.clear()
	item_loaded.emit(current_item_id)
	_update_status("✓ 已加载: %s" % path)

func _on_export_data():
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "item_data.gd"
	_file_dialog.file_selected.connect(_export_to_gdscript, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered(Vector2(800, 600))

func _export_to_gdscript(path: String):
	var lines: Array[String] = []
	lines.append("# 自动生成的物品数据")
	lines.append("# 生成时间: %s" % Time.get_datetime_string_from_system())
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
		_update_status("✓ 已导出GDScript")

# 撤销/重做
func _on_undo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().undo()
		_update_status("撤销")
		_update_item_list()
		_update_stats()

func _on_redo():
	if editor_plugin and editor_plugin.get_undo_redo():
		editor_plugin.get_undo_redo().redo()
		_update_status("重做")
		_update_item_list()
		_update_stats()

func _update_status(message: String):
	_status_bar.text = "%s - 共 %d 个物品" % [message, items.size()]
	print("物品编辑器: %s" % message)

# 公共方法
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
