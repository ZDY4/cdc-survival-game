extends CanvasLayer
# WeaponUI - 武器界面

@onready var weapon_panel = $WeaponPanel
@onready var weapon_list = $WeaponPanel/VBoxContainer/WeaponList
@onready var current_weapon_label = $WeaponPanel/VBoxContainer/CurrentWeapon
@onready var ammo_label = $WeaponPanel/VBoxContainer/AmmoLabel
@onready var toggle_button = $ToggleButton

var is_visible = false

func _ready():
	toggle_button.pressed.connect(_on_toggle_pressed)
	weapon_panel.visible = false
	
	# 订阅武器事件
	WeaponSystem.weapon_equipped.connect(_on_weapon_equipped)
	WeaponSystem.ammo_changed.connect(_on_ammo_changed)
	WeaponSystem.weapon_broken.connect(_on_weapon_broken)
	
	_update_display()

func _on_toggle_pressed():
	if is_visible:
		_hide_panel()
	else:
		_show_panel()

func _show_panel():
	is_visible = true
	weapon_panel.visible = true
	_update_weapon_list()
	_update_current_weapon()

func _hide_panel():
	is_visible = false
	weapon_panel.visible = false

func _update_display(level: int = 1):
	_update_current_weapon()
	_update_ammo_display()

func _update_current_weapon(weapon: Dictionary = {}):
	var weapon = WeaponSystem.get_equipped_weapon()
	current_weapon_label.text = "当前武器: %s" % weapon.name
	
	if weapon.type == "ranged":
		var ammo_type = weapon.get("ammo_type", "")
		if ammo_type != "":
			var current = WeaponSystem.get_ammo_count(ammo_type)
			ammo_label.text = "弹药: %d / %d" % [current, weapon.max_ammo]
		else:
			ammo_label.text = ""
	else:
		var durability_text = ""
		if weapon.durability > 0:
			durability_text = " (耐久: %d/%d)" % [weapon.durability, weapon.max_durability]
		ammo_label.text = durability_text

func _update_ammo_display():
	_update_current_weapon()

func _update_weapon_list(weapon: Dictionary = {}):
	# 清除列表
	for child in weapon_list.get_children():
		child.queue_free()
	
	# 添加可用武器
	for weapon_data in WeaponSystem.weapon_inventory:
		var weapon_id = weapon_data.id
		var weapon_template = WeaponSystem.WEAPONS[weapon_id]
		
		var hbox = HBoxContainer.new()
		
		# 武器名称
		var name_label = Label.new()
		var durability_percent = float(weapon_data.durability) / weapon_template.max_durability
		var durability_indicator = ""
		if durability_percent < 0.3:
			durability_indicator = " [破损]"
		name_label.text = weapon_template.name + durability_indicator
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)
		
		# 装备按钮
		if weapon_id != WeaponSystem.equipped_weapon:
			var equip_button = Button.new()
			equip_button.text = "装备"
			equip_button.pressed.connect(_on_equip_weapon.bind(weapon_id))
			hbox.add_child(equip_button)
		
		# 修复按钮
		if weapon_data.durability < weapon_template.max_durability:
			var repair_button = Button.new()
			repair_button.text = "修复"
			repair_button.pressed.connect(_on_repair_weapon.bind(weapon_id))
			hbox.add_child(repair_button)
		
		weapon_list.add_child(hbox)

func _on_equip_weapon(weapon: Dictionary = {}):
	WeaponSystem.equip_weapon(weapon_id)
	_update_weapon_list()
	_update_current_weapon()

func _on_repair_weapon(weapon: Dictionary = {}):
	if WeaponSystem.repair_weapon(weapon_id):
		_update_weapon_list()
		DialogModule.show_dialog("武器修复成功！", "武器", "")
	else:
		DialogModule.show_dialog("材料不足，无法修复。", "武器", "")

func _on_weapon_equipped():
	_update_current_weapon()
	if is_visible:
		_update_weapon_list()

func _on_ammo_changed():
	_update_ammo_display()

func _on_weapon_broken():
	DialogModule.show_dialog("你的武器损坏了！", "武器", "")
	if is_visible:
		_update_weapon_list()

func _input():
	if event is InputEventKey:
		if event.pressed && event.keycode == KEY_W:
			_on_toggle_pressed()
