extends CanvasLayer
# EquipmentUI - 装备界面

@onready var equipment_panel = $EquipmentPanel
@onready var slots_container = $EquipmentPanel/VBoxContainer/SlotsContainer
@onready var inventory_list = $EquipmentPanel/VBoxContainer/InventoryList
@onready var stats_panel = $EquipmentPanel/VBoxContainer/StatsPanel
@onready var toggle_button = $ToggleButton

var selected_slot: String = ""
var selected_equipment: String = ""

func _ready():
	toggle_button.pressed.connect(_on_toggle_pressed)
	equipment_panel.visible = false
	
	# 订阅事件
	EquipmentSystem.equipment_equipped.connect(_on_equipment_changed)
	EquipmentSystem.equipment_unequipped.connect(_on_equipment_changed)
	EquipmentSystem.equipment_damaged.connect(_on_equipment_damaged)
	EquipmentSystem.equipment_broken.connect(_on_equipment_broken)
	
	_setup_slots()

func _on_toggle_pressed():
	if equipment_panel.visible:
		equipment_panel.visible = false
	else:
		equipment_panel.visible = true
		_update_display()

func _setup_slots(level: int = 1):
	# 清除现有
	for child in slots_container.get_children():
		child.queue_free()
	
	# 创建装备槽位
	var slot_order = ["head", "body", "hands", "legs", "feet", "back", "accessory_1", "accessory_2"]
	
	for slot in slot_order:
		var button = Button.new()
		button.name = slot
		button.custom_minimum_size = Vector2(80, 80)
		
		var equipped = EquipmentSystem.get_equipped_in_slot(slot)
		if equipped.is_empty():
			button.text = EquipmentSystem.SLOT_NAMES[slot]
		else:
			button.text = equipped.name + "\n(%d%%)" % (equipped.durability * 100 / equipped.max_durability)
			# 根据耐久度显示颜色
			var durability_percent = float(equipped.durability) / equipped.max_durability
			if durability_percent < 0.3:
				button.add_theme_color_override("font_color", Color.RED)
			elif durability_percent < 0.6:
				button.add_theme_color_override("font_color", Color.YELLOW)
		
		button.pressed.connect(_on_slot_selected.bind(slot))
		slots_container.add_child(button)

func _update_display(level: int = 1):
	_update_slots()
	_update_inventory()
	_update_stats()

func _update_slots(level: int = 1):
	for child in slots_container.get_children():
		var slot = child.name
		var equipped = EquipmentSystem.get_equipped_in_slot(slot)
		
		if equipped.is_empty():
			child.text = EquipmentSystem.SLOT_NAMES[slot]
			child.remove_theme_color_override("font_color")
		else:
			var durability_percent = float(equipped.durability) / equipped.max_durability
			child.text = equipped.name + "\n(%d%%)" % int(durability_percent * 100)
			
			if durability_percent < 0.3:
				child.add_theme_color_override("font_color", Color.RED)
			elif durability_percent < 0.6:
				child.add_theme_color_override("font_color", Color.YELLOW)
			else:
				child.remove_theme_color_override("font_color")

func _update_inventory(level: int = 1):
	for child in inventory_list.get_children():
		child.queue_free()
	
	var equipment_list = EquipmentSystem.get_equipment_inventory()
	
	if equipment_list.size() == 0:
		var label = Label.new()
		label.text = "没有装备"
		inventory_list.add_child(label)
		return
	
	for item in equipment_list:
		var hbox = HBoxContainer.new()
		
		# 装备名称
		var name_label = Label.new()
		var equipped_marker = "[装备] " if item.is_equipped else ""
		var durability_text = ""
		if item.max_durability > 0:
			durability_text = " (%d%%)" % int(float(item.durability) / item.max_durability * 100)
		
		name_label.text = equipped_marker + item.name + durability_text
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)
		
		# 装备按钮
		if not item.is_equipped:
			var equip_button = Button.new()
			equip_button.text = "装备"
			equip_button.pressed.connect(_on_equip_pressed.bind(item.id))
			hbox.add_child(equip_button)
		else:
			# 找到装备的槽位并显示卸下按钮
			for slot in EquipmentSystem.equipped_items.keys():
				if EquipmentSystem.equipped_items[slot] != null:
					if EquipmentSystem.equipped_items[slot].id == item.id:
						var unequip_button = Button.new()
						unequip_button.text = "卸下"
						unequip_button.pressed.connect(_on_unequip_pressed.bind(slot))
						hbox.add_child(unequip_button)
						break
		
		# 修复按钮
		if item.durability < item.max_durability && item.max_durability > 0:
			var repair_button = Button.new()
			repair_button.text = "修复"
			repair_button.pressed.connect(_on_repair_pressed.bind(item.id))
			hbox.add_child(repair_button)
		
		inventory_list.add_child(hbox)

func _update_stats(level: int = 1):
	for child in stats_panel.get_children():
		child.queue_free()
	
	var stats = EquipmentSystem.get_total_stats()
	
	var title = Label.new()
	title.text = "属性总览"
	title.add_theme_font_size_override("font_size", 18)
	stats_panel.add_child(title)
	
	# 显示各项属性
	var stat_labels = {
		"defense": "防御力",
		"insulation": "保暖",
		"speed_bonus": "速度加成",
		"accuracy": "精准",
		"crit_chance": "暴击率",
		"max_hp": "生命加成",
		"inventory_slots": "背包加成",
		"radiation_resistance": "辐射抗性",
		"disease_resistance": "疾病抗性"
	}
	
	for stat_name in stat_labels.keys():
		if stats[stat_name] != 0:
			var label = Label.new()
			var value = stats[stat_name]
			if stat_name == "crit_chance":
				value = "%.1f%%" % (value * 100)
			elif stat_name in ["insulation", "speed_bonus", "radiation_resistance", "disease_resistance"]:
				value = "%.0f%%" % (value * 100)
			
			label.text = "  %s: %s" % [stat_labels[stat_name], str(value)]
			stats_panel.add_child(label)

func _on_slot_selected(level: int = 1):
	selected_slot = slot
	var equipped = EquipmentSystem.get_equipped_in_slot(slot)
	
	if not equipped.is_empty():
		var item_data = EquipmentSystem.EQUIPMENT[equipped.id]
		var info_text = "%s\n%s\n\n属性:" % [equipped.name, item_data.description]
		
		for stat_name in equipped.stats.keys():
			info_text += "\n  %s: %s" % [stat_name, str(equipped.stats[stat_name])]
		
		DialogModule.show_dialog(info_text, "装备信息", "")

func _on_equip_pressed(level: int = 1):
	if EquipmentSystem.equip(item_id):
		_update_display()
	else:
		DialogModule.show_dialog("无法装备此物品", "错误", "")

func _on_unequip_pressed(level: int = 1):
	EquipmentSystem.unequip(slot)
	_update_display()

func _on_repair_pressed(level: int = 1):
	if EquipmentSystem.repair_equipment(item_id):
		_update_display()
		DialogModule.show_dialog("装备修复成功！", "装备", "")
	else:
		DialogModule.show_dialog("材料不足，无法修复", "装备", "")

func _on_equipment_changed():
	if equipment_panel.visible:
		_update_display()

func _on_equipment_damaged(level: int = 1):
	if equipment_panel.visible:
		_update_slots()

func _on_equipment_broken():
	if equipment_panel.visible:
		_update_display()

func _input():
	if event is InputEventKey:
		if event.pressed && event.keycode == KEY_E:
			_on_toggle_pressed()
