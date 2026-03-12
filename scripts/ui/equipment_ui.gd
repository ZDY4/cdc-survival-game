extends CanvasLayer
# EquipmentUI - 装备界面（统一装备系统）
const InputActions = preload("res://core/input_actions.gd")

@onready var equipment_panel = $EquipmentPanel
@onready var slots_container = $EquipmentPanel/VBoxContainer/SlotsContainer
@onready var inventory_list = $EquipmentPanel/VBoxContainer/InventoryList
@onready var stats_panel = $EquipmentPanel/VBoxContainer/StatsPanel
@onready var toggle_button = $ToggleButton

var selected_slot: String = ""
var selected_item_id: String = ""
var _equipment_system: Node = null

func _ready():
	toggle_button.pressed.connect(_on_toggle_pressed)
	equipment_panel.visible = false
	if GameState:
		GameState.equipment_system_ready.connect(_on_equipment_system_ready)
	_bind_equipment_system()

func _on_equipment_system_ready(_system: Node) -> void:
	_bind_equipment_system()

func _bind_equipment_system() -> void:
	var equip_system = GameState.get_equipment_system() if GameState else null
	if not equip_system or equip_system == _equipment_system:
		return
	_equipment_system = equip_system
	_equipment_system.item_equipped.connect(_on_equipment_changed)
	_equipment_system.item_unequipped.connect(_on_equipment_changed)
	_equipment_system.item_broken.connect(_on_equipment_broken)
	_equipment_system.durability_changed.connect(_on_equipment_damaged)
	_equipment_system.ammo_changed.connect(_on_ammo_changed)
	_setup_slots()

func _on_toggle_pressed():
	if equipment_panel.visible:
		equipment_panel.visible = false
	else:
		_bind_equipment_system()
		equipment_panel.visible = true
		_update_display()

func _setup_slots():
	if not _equipment_system:
		return
	for child in slots_container.get_children():
		child.queue_free()
	
	var slot_order = [
		"head", "body", "hands", "legs", "feet",
		"back", "main_hand", "off_hand",
		"accessory_1", "accessory_2"
	]
	
	for slot in slot_order:
		var button = Button.new()
		button.name = slot
		button.custom_minimum_size = Vector2(80, 80)
		
		var equipped = _equipment_system.get_equipped_data(slot)
		if equipped.is_empty():
			button.text = _equipment_system.SLOT_NAMES.get(slot, slot)
		else:
			var item_id = equipped.get("id", "")
			var name = equipped.get("name", ItemDatabase.get_item_name(item_id))
			var max_dur = ItemDatabase.get_max_durability(item_id)
			if max_dur > 0:
				var current = int(equipped.get("current_durability", max_dur))
				button.text = "%s\n(%d%%)" % [name, int(float(current) / max_dur * 100)]
				var durability_percent = float(current) / max_dur
				if durability_percent < 0.3:
					button.add_theme_color_override("font_color", Color.RED)
				elif durability_percent < 0.6:
					button.add_theme_color_override("font_color", Color.YELLOW)
			else:
				button.text = name
		
		button.pressed.connect(_on_slot_selected.bind(slot))
		slots_container.add_child(button)

func _update_display():
	_update_slots()
	_update_inventory()
	_update_stats()

func _update_slots():
	if not _equipment_system:
		return
	for child in slots_container.get_children():
		var slot = child.name
		var equipped = _equipment_system.get_equipped_data(slot)
		
		if equipped.is_empty():
			child.text = _equipment_system.SLOT_NAMES.get(slot, slot)
			child.remove_theme_color_override("font_color")
		else:
			var item_id = equipped.get("id", "")
			var name = equipped.get("name", ItemDatabase.get_item_name(item_id))
			var max_dur = ItemDatabase.get_max_durability(item_id)
			if max_dur > 0:
				var current = int(equipped.get("current_durability", max_dur))
				child.text = "%s\n(%d%%)" % [name, int(float(current) / max_dur * 100)]
				var durability_percent = float(current) / max_dur
				if durability_percent < 0.3:
					child.add_theme_color_override("font_color", Color.RED)
				elif durability_percent < 0.6:
					child.add_theme_color_override("font_color", Color.YELLOW)
				else:
					child.remove_theme_color_override("font_color")
			else:
				child.text = name
				child.remove_theme_color_override("font_color")

func _update_inventory():
	for child in inventory_list.get_children():
		child.queue_free()
	
	var equipment_list = InventoryModule.get_equipment()
	
	if equipment_list.size() == 0:
		var label = Label.new()
		label.text = "没有可装备物品"
		inventory_list.add_child(label)
		return
	
	for item in equipment_list:
		var item_id = item.get("id", "")
		var item_data = ItemDatabase.get_item(item_id)
		if item_data.is_empty():
			continue
		
		var hbox = HBoxContainer.new()
		
		# 名称
		var name_label = Label.new()
		var equipped_slot = _find_equipped_slot(item_id)
		var equipped_marker = "[装备] " if equipped_slot != "" else ""
		var max_dur = ItemDatabase.get_max_durability(item_id)
		var durability_text = ""
		if max_dur > 0:
			var current = _get_item_durability(item_id, max_dur)
			durability_text = " (%d%%)" % int(float(current) / max_dur * 100)
		
		name_label.text = equipped_marker + item_data.get("name", item_id) + durability_text
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)
		
		# 装备/卸下
		if equipped_slot == "":
			var equip_button = Button.new()
			equip_button.text = "装备"
			equip_button.pressed.connect(_on_equip_pressed.bind(item_id))
			hbox.add_child(equip_button)
		else:
			var unequip_button = Button.new()
			unequip_button.text = "卸下"
			unequip_button.pressed.connect(_on_unequip_pressed.bind(equipped_slot))
			hbox.add_child(unequip_button)
		
		# 修复
		if max_dur > 0:
			var repair_button = Button.new()
			repair_button.text = "修复"
			repair_button.pressed.connect(_on_repair_pressed.bind(item_id))
			hbox.add_child(repair_button)
		
		inventory_list.add_child(hbox)

func _update_stats():
	if not _equipment_system:
		return
	for child in stats_panel.get_children():
		child.queue_free()
	
	var title = Label.new()
	title.text = "属性总览"
	title.add_theme_font_size_override("font_size", 18)
	stats_panel.add_child(title)
	
	var main_hand = _equipment_system.get_equipped_data("main_hand")
	if main_hand && main_hand.size() > 0:
		var main_name = main_hand.get("name", ItemDatabase.get_item_name(main_hand.get("id", "")))
		var weapon_label = Label.new()
		weapon_label.text = "主手: %s" % main_name
		stats_panel.add_child(weapon_label)
		
		if main_hand.get("type") == "weapon":
			var weapon_data = main_hand.get("weapon_data", {})
			var ammo_type = str(weapon_data.get("ammo_type", ""))
			if ammo_type != "":
				var current = _equipment_system.get_ammo(ammo_type)
				var max_ammo = weapon_data.get("max_ammo", 0)
				var ammo_label = Label.new()
				ammo_label.text = "弹药: %d / %d" % [current, max_ammo]
				stats_panel.add_child(ammo_label)
	
	var stats = _equipment_system.get_total_stats()
	var stat_labels = {
		"defense": "防御力",
		"insulation": "保暖",
		"speed_bonus": "速度加成",
		"speed_penalty": "速度惩罚",
		"accuracy": "精准",
		"crit_chance": "暴击率",
		"max_hp": "生命加成",
		"inventory_slots": "背包加成",
		"radiation_resistance": "辐射抗性",
		"disease_resistance": "疾病抗性",
		"damage_reduction": "伤害减免",
		"carry_bonus": "负重加成",
		"ammo_capacity": "弹药容量"
	}
	
	for stat_name in stat_labels.keys():
		if stats.get(stat_name, 0) != 0:
			var label = Label.new()
			var value = stats[stat_name]
			if stat_name in ["crit_chance", "insulation", "speed_bonus", "speed_penalty",
				"radiation_resistance", "disease_resistance", "damage_reduction"]:
				value = "%.1f%%" % (value * 100)
			label.text = "  %s: %s" % [stat_labels[stat_name], str(value)]
			stats_panel.add_child(label)

func _on_slot_selected(slot: String):
	selected_slot = slot
	if not _equipment_system:
		return
	var equipped = _equipment_system.get_equipped_data(slot)
	
	if not equipped.is_empty():
		var item_id = equipped.get("id", "")
		var item_data = ItemDatabase.get_item(item_id)
		var info_text = "%s\n%s\n\n属性:" % [item_data.get("name", item_id), item_data.get("description", "")]
		
		var bonuses = item_data.get("attributes_bonus", {})
		for stat_name in bonuses.keys():
			info_text += "\n  %s: %s" % [stat_name, str(bonuses[stat_name])]
		
		DialogModule.show_dialog(info_text, "装备信息", "")

func _on_equip_pressed(item_id: String):
	if not _equipment_system:
		return
	var target_slot = _get_target_slot(item_id)
	if target_slot.is_empty():
		DialogModule.show_dialog("无法装备此物品", "错误", "")
		return
	
	if _equipment_system.equip(item_id, target_slot):
		_update_display()
	else:
		DialogModule.show_dialog("无法装备此物品", "错误", "")

func _on_unequip_pressed(slot: String):
	if _equipment_system:
		_equipment_system.unequip(slot)
	_update_display()

func _on_repair_pressed(item_id: String):
	if _equipment_system and _equipment_system.repair_item(item_id):
		_update_display()
		DialogModule.show_dialog("修复成功！", "装备", "")
	else:
		DialogModule.show_dialog("材料不足，无法修复", "装备", "")

func _on_equipment_changed():
	if equipment_panel.visible:
		_update_display()

func _on_equipment_damaged(_slot: String, _durability_percent: float):
	if equipment_panel.visible:
		_update_slots()

func _on_equipment_broken(_slot: String, _item_id: String):
	if equipment_panel.visible:
		_update_display()

func _on_ammo_changed(_ammo_type: String, _current: int, _max_ammo: int):
	if equipment_panel.visible:
		_update_stats()

func _find_equipped_slot(item_id: String) -> String:
	if not _equipment_system:
		return ""
	var resolved = ItemDatabase.resolve_item_id(item_id)
	var slots = ["head", "body", "hands", "legs", "feet", "back", "main_hand", "off_hand", "accessory_1", "accessory_2"]
	for slot in slots:
		var equipped_id = _equipment_system.get_equipped(slot)
		if ItemDatabase.resolve_item_id(str(equipped_id)) == resolved:
			return slot
	return ""

func _get_item_durability(item_id: String, fallback: int) -> int:
	var resolved = ItemDatabase.resolve_item_id(item_id)
	var equipped = _equipment_system.get_equipped_data(_find_equipped_slot(resolved)) if _equipment_system else {}
	if equipped && equipped.has("current_durability"):
		return int(equipped.current_durability)
	return fallback

func _get_target_slot(item_id: String) -> String:
	if not _equipment_system:
		return ""
	var slot = ItemDatabase.get_equip_slot(item_id)
	if slot == "accessory":
		if _equipment_system.get_equipped("accessory_1") == "" or not _equipment_system.get_equipped("accessory_1"):
			return "accessory_1"
		if _equipment_system.get_equipped("accessory_2") == "" or not _equipment_system.get_equipped("accessory_2"):
			return "accessory_2"
		return "accessory_1"
	return slot

func _input(event):
	if event.is_action_pressed(InputActions.ACTION_MENU_INVENTORY):
		_on_toggle_pressed()
